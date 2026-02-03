#!/bin/bash
# CNKI 检索爬取一体化脚本
# 用法: cnki-search.sh <keyword> [count] [output_dir]
# 功能: 一步完成打开浏览器、检索、爬取数据
# 特性: 支持异常检测（验证码/弹窗）并自动重试一次

# 不使用 set -e，手动处理错误

# 自动定位项目根目录（从脚本目录向上查找）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 脚本位于 .claude/skills/cnki-search-agent-browser/scripts/
# 需要向上4级到达项目根目录
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# 导入异常检测工具函数
source "$SCRIPT_DIR/cnki-utils.sh"

# 主检索逻辑函数（封装后支持重试）
main_search() {
    KEYWORD=$1
    TARGET_COUNT=${2:-100}
    OUTPUT_DIR=${3:-"$PROJECT_ROOT/outputs"}
    SESSION="cnki"
    BASE_OPTS="--session $SESSION --headed"
    TIMESTAMP=$(date +%Y%m%d)

    echo "🔍 CNKI 检索爬取工具"
    echo "===================="
    echo "关键词: $KEYWORD"
    echo "目标数量: $TARGET_COUNT 篇"
    echo "输出目录: $OUTPUT_DIR"
    echo ""

    # 清理可能存在的同名会话（避免残留会话导致启动失败）
    npx agent-browser --session $SESSION close 2>/dev/null || true

    # 步骤1：打开浏览器
    echo "📖 步骤1: 打开CNKI..."
    npx agent-browser --session $SESSION --headed open https://chn.oversea.cnki.net
    if [ $? -ne 0 ]; then
        echo "❌ 打开浏览器失败"
        return 1
    fi
    echo "✓ 浏览器已启动"

    # 异常检测：打开浏览器后检测验证码/弹窗
    if ERROR_TYPE=$(detect_exception "$BASE_OPTS"); then
        handle_exception "$SESSION" "$ERROR_TYPE" "$OUTPUT_DIR"
    fi

    # 步骤2：获取元素ref
    echo "📖 步骤2: 获取页面元素..."
    sleep 2
    SNAPSHOT=$(npx agent-browser --session $SESSION --headed snapshot -i)
    SEARCH_REF=$(echo "$SNAPSHOT" | grep 'textbox.*中文文献' | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')
    BUTTON_REF=$(echo "$SNAPSHOT" | grep 'button.*检索' | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')

    if [ -z "$SEARCH_REF" ] || [ -z "$BUTTON_REF" ]; then
        echo "❌ 无法找到搜索框或检索按钮"
        return 1
    fi
    echo "✓ 搜索框: @$SEARCH_REF, 检索按钮: @$BUTTON_REF"

    # 步骤3：输入关键词并检索
    echo "📖 步骤3: 执行检索..."
    npx agent-browser --session $SESSION --headed fill "$SEARCH_REF" "$KEYWORD" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ 输入关键词失败"
        return 1
    fi
    npx agent-browser --session $SESSION --headed click "$BUTTON_REF" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ 点击检索按钮失败"
        return 1
    fi
    echo "✓ 已提交检索"

    # 步骤4：等待并检测检索是否成功（使用智能等待 + 兜底机制 + 异常检测）
    echo "📖 步骤4: 等待检索结果..."

    SUCCESS=0

    # 方法1：使用智能等待（首选，更高效）
    if npx agent-browser $BASE_OPTS wait --text "共找到" --timeout 15000 2>/dev/null; then
        SUCCESS=1
    else
        # 异常检测：等待超时时检查是否出现验证码/弹窗
        if ERROR_TYPE=$(detect_exception "$BASE_OPTS"); then
            handle_exception "$SESSION" "$ERROR_TYPE" "$OUTPUT_DIR"
        fi

        # 方法2：备选文本等待
        if npx agent-browser $BASE_OPTS wait --text "总库" --timeout 5000 2>/dev/null; then
            SUCCESS=1
        else
            # 方法3：兜底机制 - 使用原始轮询方式（适应各种情况）
            echo "   智能等待超时，使用备选检测方式..."
            RETRY=0
            while [ $RETRY -lt 3 ]; do
                sleep 3

                # 异常检测：轮询过程中检测异常
                if ERROR_TYPE=$(detect_exception "$BASE_OPTS"); then
                    handle_exception "$SESSION" "$ERROR_TYPE" "$OUTPUT_DIR"
                fi

                SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i)
                if echo "$SNAPSHOT" | grep -q "共找到\|总库\|找到"; then
                    SUCCESS=1
                    break
                fi
                RETRY=$((RETRY + 1))
                echo "   备选检测中... ($((RETRY))/3)"
            done
        fi
    fi

    if [ $SUCCESS -eq 0 ]; then
        echo "❌ 检索失败或超时，未检测到结果页面"
        return 1
    fi

    # 提取结果数量（优先使用 eval，失败则从 snapshot 解析）
    RESULT_COUNT=$(npx agent-browser $BASE_OPTS eval 'document.querySelector(".pagerTitleCell em")?.textContent || "0"' 2>/dev/null | tr -d '"' || echo "?")
    if [ "$RESULT_COUNT" = "0" ] || [ "$RESULT_COUNT" = "?" ]; then
        # 兜底：从快照中解析结果数量
        SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i)
        RESULT_COUNT=$(echo "$SNAPSHOT" | grep -Eo '总库 [0-9]+' | head -1 | grep -Eo '[0-9]+' || echo "?")
    fi
    echo "✓ 检索成功！共找到约 $RESULT_COUNT 篇相关文献"

    # 步骤5：调用爬虫脚本
    echo "📖 步骤5: 开始爬取数据..."
    echo ""

    # 调用爬虫脚本（首次检索，使用默认参数）
    bash "$SCRIPT_DIR/cnki-crawl.sh" "$SESSION" "$OUTPUT_DIR" "$KEYWORD" --count "$TARGET_COUNT"

    # 读取状态文件获取爬取结果
    STATE_FILE="$OUTPUT_DIR/.cnki_state.json"
    if [ -f "$STATE_FILE" ]; then
        ACTUAL_COUNT=$(jq -r '.total_collected // 0' "$STATE_FILE")
    else
        ACTUAL_COUNT=$TARGET_COUNT
    fi

    # 输出总结报告
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 爬取总结报告"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "检索关键词: $KEYWORD"
    echo "相关文献总数: 约 $RESULT_COUNT 篇"
    echo "本次爬取: $ACTUAL_COUNT 篇"
    echo "未爬取: $((RESULT_COUNT - ACTUAL_COUNT)) 篇"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    return 0
}

# ============ 主入口：支持异常自动重试 ============
RETRY_COUNT=0
MAX_RETRY=1

while [ $RETRY_COUNT -le $MAX_RETRY ]; do
    # 执行主检索逻辑
    main_search "$@"
    EXIT_CODE=$?

    # 检查是否需要重试（退出码 42 为异常重试信号）
    if [ $EXIT_CODE -eq 42 ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -le $MAX_RETRY ]; then
            echo "🔄 正在进行第 $RETRY_COUNT 次重试..."
            echo ""
            sleep 3
            continue
        fi
    fi

    # 非 42 退出码，直接退出
    exit $EXIT_CODE
done
