#!/bin/bash
# CNKI 结果爬取脚本（检索后调用）
# 用法: cnki-crawl.sh <session> <output_dir> <keyword> --target-page <页码> --skip-in-page <条数> --count <数量>
# 功能: 跳转到指定页、跳过指定条数、提取指定数量的论文
# 特性: 支持异常检测（验证码/弹窗），检测到异常返回 42 触发重试
#
# 参数说明:
#   --target-page: 目标页码（从1开始），如未指定则从当前页开始
#   --skip-in-page: 当前页内需要跳过的条数（用于同一页续爬），默认0
#   --count: 本次要爬取的数量，默认100
#   --start-idx: 输出文件的起始序号，默认1

# 不使用 set -e，手动处理错误

# 自动定位项目根目录（从脚本目录向上查找）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# 导入异常检测工具函数
source "$SCRIPT_DIR/cnki-utils.sh"

SESSION=$1
OUTPUT_DIR=$2

# 如果输出目录是相对路径，则转换为基于项目根目录的绝对路径
if [[ "$OUTPUT_DIR" != /* ]] && [[ "$OUTPUT_DIR" != .* ]]; then
    OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_DIR"
fi
KEYWORD=${3:-"检索"}

# 解析命名参数
TARGET_PAGE=""
SKIP_IN_PAGE=0
TARGET_COUNT=100
START_IDX=1

shift 3
while [[ $# -gt 0 ]]; do
    case $1 in
        --target-page)
            TARGET_PAGE="$2"
            shift 2
            ;;
        --skip-in-page)
            SKIP_IN_PAGE="$2"
            shift 2
            ;;
        --count)
            TARGET_COUNT="$2"
            shift 2
            ;;
        --start-idx)
            START_IDX="$2"
            shift 2
            ;;
        *)
            echo "❌ 未知参数: $1"
            echo "用法: cnki-crawl.sh <session> <output_dir> <keyword> --target-page <页码> --skip-in-page <条数> --count <数量> [--start-idx <序号>]"
            exit 1
            ;;
    esac
done

TIMESTAMP=$(date +%Y%m%d)
BASE_OPTS="--session $SESSION --headed"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 输出文件路径（关键词中的空格替换为下划线）
SAFE_KEYWORD=$(echo "$KEYWORD" | sed 's/ /_/g')
MD_FILE="$OUTPUT_DIR/${SAFE_KEYWORD}-${TIMESTAMP}.md"
JSON_FILE="$OUTPUT_DIR/${SAFE_KEYWORD}-${TIMESTAMP}.json"

# 初始化或追加模式判断
if [ "$START_IDX" -eq 1 ]; then
    # 初始化 JSON 数组
    echo "[]" > "$JSON_FILE"

    # 写入 Markdown 头部
    cat > "$MD_FILE" << EOF
# CNKI 检索结果：$KEYWORD

**检索日期**: $(date '+%Y-%m-%d')
**检索关键词**: $KEYWORD

EOF

    # Markdown 表格头部
    echo "" >> "$MD_FILE"
    echo "| 序号 | 标题 | 作者 | 来源 | 发表时间 |" >> "$MD_FILE"
    echo "|------|------|------|------|----------|" >> "$MD_FILE"
else
    # 追加模式：读取现有数据
    EXISTING_COUNT=$(jq 'length' "$JSON_FILE" 2>/dev/null || echo "0")
    echo "📌 从第 $START_IDX 篇继续爬取（已有 $EXISTING_COUNT 篇）"
fi

# 步骤1：自动设置每页显示50条（使用智能等待 + 兜底机制）
echo "⚙️  正在设置每页显示50条..."
# 先检查当前是否已经是50
PER_PAGE=$(npx agent-browser $BASE_OPTS eval 'document.querySelector("label.on")?.textContent.trim() || ""' 2>/dev/null || echo "")
if [ "$PER_PAGE" = "50" ]; then
    echo "✓ 已是每页50条"
else
    # 点击 value="50" 的 radio
    npx agent-browser $BASE_OPTS eval 'document.querySelector("input[value=\\"50\\"]")?.click()' > /dev/null 2>&1 || true

    # 等待设置生效（带兜底机制）
    # 方法1：智能等待（首选）
    if ! npx agent-browser $BASE_OPTS wait --fn 'document.querySelector("label.on")?.textContent.trim() === "50"' --timeout 3000 2>/dev/null; then
        # 方法2：兜底 - 使用固定等待
        sleep 2
    fi

    # 验证是否设置成功
    PER_PAGE=$(npx agent-browser $BASE_OPTS eval 'document.querySelector("label.on")?.textContent.trim() || ""' 2>/dev/null || echo "")
    if [ "$PER_PAGE" = "50" ]; then
        echo "✓ 已设置每页50条"
    else
        echo "⚠️  设置失败，使用默认设置"
    fi
fi

# 步骤2：跳转到目标页面（如果指定了 target-page）
if [ -n "$TARGET_PAGE" ]; then
    # 获取当前页码
    CURRENT_PAGE=$(npx agent-browser $BASE_OPTS eval 'document.querySelector(".pagerTitleCell .curr")?.textContent.trim() || "1"' 2>/dev/null || echo "1")

    echo "📍 跳转页面：当前第 $CURRENT_PAGE 页，目标第 $TARGET_PAGE 页"

    # 如果当前页小于目标页，需要翻页
    if [ "$CURRENT_PAGE" -lt "$TARGET_PAGE" ]; then
        PAGES_TO_JUMP=$((TARGET_PAGE - CURRENT_PAGE))
        echo "   需要跳转 $PAGES_TO_JUMP 页..."

        for ((i=1; i<=PAGES_TO_JUMP; i++)); do
            echo "   正在跳转到第 $((CURRENT_PAGE + i)) 页..."

            # 获取下一页按钮ref
            NEXT_PAGE_REF=$(npx agent-browser $BASE_OPTS snapshot -i | grep "下一页" | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')

            if [ -z "$NEXT_PAGE_REF" ]; then
                echo "   ⚠️  未找到下一页按钮，无法继续跳转"
                break
            fi

            # 点击下一页
            npx agent-browser $BASE_OPTS click "$NEXT_PAGE_REF" > /dev/null 2>&1 || true

            # 等待页面加载
            if ! npx agent-browser $BASE_OPTS wait --fn 'document.querySelector("tbody tr")?.textContent?.trim() !== ""' --timeout 5000 2>/dev/null; then
                sleep 2
            fi

            # 异常检测
            if ERROR_TYPE=$(detect_exception "$BASE_OPTS"); then
                echo "   ⚠️  跳转时检测到异常: $ERROR_TYPE"
                handle_exception "$SESSION" "$ERROR_TYPE" "$OUTPUT_DIR"
            fi
        done

        # 验证是否跳转成功
        CURRENT_PAGE=$(npx agent-browser $BASE_OPTS eval 'document.querySelector(".pagerTitleCell .curr")?.textContent.trim() || "1"' 2>/dev/null || echo "1")
        echo "   ✓ 当前已到达第 $CURRENT_PAGE 页"
    fi
fi

# 步骤3：爬取数据
TOTAL_COLLECTED=0
PAGE_NUM=1

while [ $TOTAL_COLLECTED -lt $TARGET_COUNT ]; do
    echo "📄 正在爬取第 $PAGE_NUM 页..."

    # 异常检测：每页爬取前检测验证码/弹窗
    if ERROR_TYPE=$(detect_exception "$BASE_OPTS"); then
        echo "⚠️  在第 $PAGE_NUM 页爬取前检测到异常: $ERROR_TYPE"
        handle_exception "$SESSION" "$ERROR_TYPE" "$OUTPUT_DIR"
    fi

    # 提取当前页结果
    PAGE_DATA=$(npx agent-browser $BASE_OPTS eval '[...document.querySelectorAll(`tbody tr`)].map((r,i)=>({title:r.querySelector(`.name a`)?.textContent?.trim(),author:[...r.querySelectorAll(`td:nth-child(3) a`)].map(a=>a.textContent.trim()).join(`; `),source:r.querySelector(`td:nth-child(4) a`)?.textContent?.trim(),date:r.querySelector(`td:nth-child(5)`)?.textContent?.trim()})).filter(x=>x.title)' || echo '[]')

    # 统计当前页条数
    PAGE_COUNT=$(echo "$PAGE_DATA" | jq 'length' 2>/dev/null || echo "0")

    if [ "$PAGE_COUNT" -eq 0 ]; then
        echo "⚠️  当前页无数据，可能已到最后一页"
        break
    fi

    # 【执行层】跳过页内指定条数（由 Skill 层计算传入）
    if [ $SKIP_IN_PAGE -gt 0 ]; then
        echo "   当前页前 $SKIP_IN_PAGE 条已爬取，跳过..."
        PAGE_DATA=$(echo "$PAGE_DATA" | jq ".[$SKIP_IN_PAGE:]")
        PAGE_COUNT=$(echo "$PAGE_DATA" | jq 'length' 2>/dev/null || echo "0")
        # 跳过后，后续页不再需要跳过
        SKIP_IN_PAGE=0
    fi

    # 计算需要从当前页提取的数量
    NEEDED=$((TARGET_COUNT - TOTAL_COLLECTED))
    # 确保不超过当前页剩余条数
    if [ $NEEDED -gt $PAGE_COUNT ]; then
        NEEDED=$PAGE_COUNT
    fi
    # 只取需要的数量
    if [ $NEEDED -lt $PAGE_COUNT ]; then
        PAGE_DATA=$(echo "$PAGE_DATA" | jq ".[0:$NEEDED]")
        PAGE_COUNT=$NEEDED
    fi

    # 追加到 JSON 文件
    if [ -n "$PAGE_DATA" ] && [ "$PAGE_DATA" != "[]" ]; then
        CURRENT=$(cat "$JSON_FILE")
        echo "$CURRENT" | jq --argjson new "$PAGE_DATA" '. + $new' > "$JSON_FILE.tmp" 2>/dev/null || echo "$CURRENT" > "$JSON_FILE.tmp"
        mv "$JSON_FILE.tmp" "$JSON_FILE"
    fi

    # 写入 Markdown 表格内容（使用 START_IDX 作为起始序号）
    echo "$PAGE_DATA" | jq -r '.[] | "| \(.idx // "") | \(.title | gsub("\\|"; "\\|")) | \(.author) | \(.source) | \(.date) |"' \
        | awk -v start=$((START_IDX + TOTAL_COLLECTED)) '{print "| " start++ " " substr($0, 3)}' >> "$MD_FILE" 2>/dev/null || true

    TOTAL_COLLECTED=$((TOTAL_COLLECTED + PAGE_COUNT))
    echo "   已收集 $((START_IDX + TOTAL_COLLECTED - 1)) 篇"

    # 检查是否已达到目标数量
    if [ $TOTAL_COLLECTED -ge $TARGET_COUNT ]; then
        echo "✅ 已达到目标数量 $TARGET_COUNT 篇"
        break
    fi

    # 步骤4：自动获取下一页按钮ref
    NEXT_PAGE_REF=$(npx agent-browser $BASE_OPTS snapshot -i | grep "下一页" | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')

    if [ -z "$NEXT_PAGE_REF" ]; then
        echo "⚠️  未找到下一页按钮，可能已到最后一页"
        break
    fi

    # 点击下一页
    echo "   正在翻页..."
    npx agent-browser $BASE_OPTS click "$NEXT_PAGE_REF" > /dev/null 2>&1 || true

    # 使用智能等待，检测新内容是否加载完成（带兜底机制）
    # 方法1：智能等待（首选）
    if ! npx agent-browser $BASE_OPTS wait --fn 'document.querySelector("tbody tr")?.textContent?.trim() !== ""' --timeout 5000 2>/dev/null; then
        # 方法2：兜底 - 使用固定等待
        sleep 2
    fi

    # 异常检测：翻页后检测验证码/弹窗（常见触发点）
    if ERROR_TYPE=$(detect_exception "$BASE_OPTS"); then
        echo "⚠️  在第 $PAGE_NUM 页翻页后检测到异常: $ERROR_TYPE"
        handle_exception "$SESSION" "$ERROR_TYPE" "$OUTPUT_DIR"
    fi

    PAGE_NUM=$((PAGE_NUM + 1))

    # 安全限制：最多爬取10页
    if [ $PAGE_NUM -gt 10 ]; then
        echo "⚠️  已达到最大页数限制(10页)"
        break
    fi
done

# 更新 Markdown 头部信息（仅在首次爬取时更新）
if [ "$START_IDX" -eq 1 ]; then
    # 获取实际爬取数量（JSON 文件中的条目数）
    ACTUAL_COUNT=$(jq 'length' "$JSON_FILE" 2>/dev/null || echo "$TOTAL_COLLECTED")

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/\*\*检索关键词\*\*: $KEYWORD/**文献数量**: ${ACTUAL_COUNT}篇 | **检索关键词**: $KEYWORD | **爬取页数**: ${PAGE_NUM}页/" "$MD_FILE"
    else
        # Linux
        sed -i "s/\*\*检索关键词\*\*: $KEYWORD/**文献数量**: ${ACTUAL_COUNT}篇 | **检索关键词**: $KEYWORD | **爬取页数**: ${PAGE_NUM}页/" "$MD_FILE"
    fi

    echo ""
    echo "✅ 爬取完成！"
    echo "   - Markdown: $MD_FILE"
    echo "   - JSON: $JSON_FILE"
    echo "   - 共 ${ACTUAL_COUNT} 篇文献"
else
    # 追加模式：返回累计爬取数量
    ACTUAL_COUNT=$(jq 'length' "$JSON_FILE" 2>/dev/null || echo "$TOTAL_COLLECTED")
    echo ""
    echo "✅ 追加爬取完成！"
    echo "   - 累计爬取: ${ACTUAL_COUNT} 篇"
fi

# 输出状态文件（供 Skill 层读取，计算下次爬取参数）
STATE_FILE="$OUTPUT_DIR/.cnki_state.json"

# 获取当前页码（用于状态输出）
CURRENT_PAGE=$(npx agent-browser $BASE_OPTS eval 'document.querySelector(".pagerTitleCell .curr")?.textContent.trim() || "1"' 2>/dev/null || echo "1")

# 确定每页实际显示条数
if [ "$PER_PAGE" = "50" ]; then
    ITEMS_PER_PAGE=50
else
    ITEMS_PER_PAGE=20
fi

# 输出 JSON 格式状态文件
cat > "$STATE_FILE" << EOF
{
  "keyword": "$KEYWORD",
  "total_collected": $ACTUAL_COUNT,
  "current_page": $CURRENT_PAGE,
  "items_per_page": $ITEMS_PER_PAGE,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "   - 状态文件: $STATE_FILE"

# 注册清理函数，在脚本退出时保留状态文件（不删除）
# 状态文件将被 Skill 层读取用于计算下次爬取参数
trap "rm -f '$OUTPUT_DIR/.cnki_last_count' 2>/dev/null || true" EXIT
