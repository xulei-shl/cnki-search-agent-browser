#!/bin/bash
# CNKI 高级检索脚本
# 用法: cnki-adv-search.sh <keyword> [options]
# 功能: 支持时间范围和来源类别过滤的高级检索
#
# 参数说明:
#   keyword        检索关键词
#   -s, --start    起始年份 (可选)
#   -e, --end      结束年份 (可选)
#   -c, --core     核心期刊标识 (传任意值表示只检索核心期刊)
#   -n, --count    爬取数量 (默认100)
#   -o, --output   输出目录 (默认outputs)
#
# 示例:
#   # 简单高级检索 (仅关键词)
#   cnki-adv-search.sh "人工智能"
#
#   # 按时间范围检索
#   cnki-adv-search.sh "人工智能" -s 2020 -e 2024
#
#   # 仅检索核心期刊
#   cnki-adv-search.sh "人工智能" -c
#
#   # 组合条件: 2020-2024年的核心期刊
#   cnki-adv-search.sh "人工智能" -s 2020 -e 2024 -c -n 50

# 解析参数
KEYWORD=""
START_YEAR=""
END_YEAR=""
IS_CORE=""
TARGET_COUNT=100
OUTPUT_DIR="./outputs"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--start)
            START_YEAR="$2"
            shift 2
            ;;
        -e|--end)
            END_YEAR="$2"
            shift 2
            ;;
        -c|--core)
            IS_CORE="yes"
            shift
            ;;
        -n|--count)
            TARGET_COUNT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            if [ -z "$KEYWORD" ]; then
                KEYWORD="$1"
            fi
            shift
            ;;
    esac
done

# 验证必填参数
if [ -z "$KEYWORD" ]; then
    echo "❌ 错误: 缺少检索关键词"
    echo ""
    echo "用法: cnki-adv-search.sh <keyword> [options]"
    echo ""
    echo "参数说明:"
    echo "  keyword        检索关键词 (必填)"
    echo "  -s, --start    起始年份 (可选)"
    echo "  -e, --end      结束年份 (可选)"
    echo "  -c, --core     核心期刊标识 (传任意值表示只检索核心期刊)"
    echo "  -n, --count    爬取数量 (默认100)"
    echo "  -o, --output   输出目录 (默认outputs)"
    echo ""
    echo "示例:"
    echo "  cnki-adv-search.sh \"人工智能\""
    echo "  cnki-adv-search.sh \"人工智能\" -s 2020 -e 2024"
    echo "  cnki-adv-search.sh \"人工智能\" -c"
    echo "  cnki-adv-search.sh \"人工智能\" -s 2020 -e 2024 -c -n 50"
    exit 1
fi

SESSION="cnki-adv"
BASE_OPTS="--session $SESSION --headed"
TIMESTAMP=$(date +%Y%m%d)

echo "🔍 CNKI 高级检索工具"
echo "===================="
echo "关键词: $KEYWORD"
if [ -n "$START_YEAR" ]; then
    echo "起始年份: $START_YEAR"
fi
if [ -n "$END_YEAR" ]; then
    echo "结束年份: $END_YEAR"
fi
if [ -n "$IS_CORE" ]; then
    echo "来源类别: 核心期刊"
fi
echo "目标数量: $TARGET_COUNT 篇"
echo "输出目录: $OUTPUT_DIR"
echo ""

# 清理可能存在的同名会话（避免残留会话导致启动失败）
npx agent-browser --session $SESSION close 2>/dev/null || true

# 步骤1：打开CNKI主站（避免直接打开高级检索页面触发反爬）
echo "📖 步骤1: 打开CNKI主站..."
npx agent-browser $BASE_OPTS open "https://chn.oversea.cnki.net" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ 打开浏览器失败"
    exit 1
fi
echo "✓ 浏览器已启动"
sleep 3

# 步骤1.5：在新tab中打开高级检索页面
echo "📖 步骤2: 在新tab中打开高级检索页面..."
npx agent-browser $BASE_OPTS tab new > /dev/null 2>&1
npx agent-browser $BASE_OPTS open "https://kns.cnki.net/kns8s/AdvSearch?classid=YSTT4HG0" > /dev/null 2>&1
sleep 3
echo "✓ 高级检索页面已打开"

# 步骤3：获取页面元素ref
echo "📖 步骤3: 获取页面元素..."
SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i)

# 查找第一行的输入框 (主题/关键词输入框)
# 注意：snapshot 中 textbox 不显示 placeholder，需通过 nth 或直接获取第一个
INPUT_REF=$(echo "$SNAPSHOT" | grep 'textbox \[ref=' | head -1 | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')

if [ -z "$INPUT_REF" ]; then
    echo "❌ 无法找到输入框"
    echo "   调试信息："
    echo "$SNAPSHOT" | grep textbox | head -5
    exit 1
fi
echo "✓ 输入框: @$INPUT_REF"

# 步骤4：输入关键词
echo "📖 步骤4: 输入关键词..."
npx agent-browser $BASE_OPTS fill "$INPUT_REF" "$KEYWORD" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ 输入关键词失败"
    exit 1
fi
echo "✓ 已输入关键词"

# 步骤5：设置时间范围（如果指定）
if [ -n "$START_YEAR" ] || [ -n "$END_YEAR" ]; then
    echo "📖 步骤5: 设置时间范围..."

    # 重新获取快照
    sleep 1
    SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i)

    # 查找时间范围相关的输入框
    # 快照格式: textbox "起始年" [ref=e32]
    if [ -n "$START_YEAR" ]; then
        START_YEAR_REF=$(echo "$SNAPSHOT" | grep 'textbox "起始年"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
        if [ -n "$START_YEAR_REF" ]; then
            npx agent-browser $BASE_OPTS fill "$START_YEAR_REF" "$START_YEAR" > /dev/null 2>&1
            echo "✓ 已设置起始年份: $START_YEAR"
        else
            echo "⚠️  未找到起始年输入框"
        fi
    fi

    if [ -n "$END_YEAR" ]; then
        END_YEAR_REF=$(echo "$SNAPSHOT" | grep 'textbox "结束年"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
        if [ -n "$END_YEAR_REF" ]; then
            npx agent-browser $BASE_OPTS fill "$END_YEAR_REF" "$END_YEAR" > /dev/null 2>&1
            echo "✓ 已设置结束年份: $END_YEAR"
        else
            echo "⚠️  未找到结束年输入框"
        fi
    fi
fi

# 步骤6：设置来源类别（如果指定核心期刊）
if [ -n "$IS_CORE" ]; then
    echo "📖 步骤6: 设置来源类别为核心期刊..."

    sleep 1
    SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i)

    # 根据HTML结构，需要勾选以下复选框：
    # - SCI来源期刊 (key="SI", value="Y")
    # - EI来源期刊 (key="EI", value="Y")
    # - 北大核心 (key="HX", value="Y")
    # - CSSCI (key="CSI", value="Y")
    # - CSCD (key="CSD", value="Y")
    # - WJCI (key="LYBSM", value="P12")
    # - AMI (key="AMI", value="P13")

    # 取消"全部期刊"勾选
    ALL_JOURNALS_REF=$(echo "$SNAPSHOT" | grep 'checkbox.*name="all"' | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')
    if [ -n "$ALL_JOURNALS_REF" ]; then
        npx agent-browser $BASE_OPTS click "$ALL_JOURNALS_REF" > /dev/null 2>&1
        echo "✓ 已取消'全部期刊'勾选"
        sleep 1
    fi

    # 重新获取快照
    SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i)

    # 勾选各核心期刊复选框
    # 注意：使用显示名称匹配，格式如：checkbox "SCI来源期刊" [ref=e37]
    CORE_CHECKED=0

    # SCI来源期刊
    SCI_REF=$(echo "$SNAPSHOT" | grep 'checkbox "SCI来源期刊"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
    if [ -n "$SCI_REF" ]; then
        npx agent-browser $BASE_OPTS click "$SCI_REF" > /dev/null 2>&1 && CORE_CHECKED=$((CORE_CHECKED + 1))
    fi

    # EI来源期刊
    EI_REF=$(echo "$SNAPSHOT" | grep 'checkbox "EI来源期刊"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
    if [ -n "$EI_REF" ]; then
        npx agent-browser $BASE_OPTS click "$EI_REF" > /dev/null 2>&1 && CORE_CHECKED=$((CORE_CHECKED + 1))
    fi

    # 北大核心
    HX_REF=$(echo "$SNAPSHOT" | grep 'checkbox "北大核心"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
    if [ -n "$HX_REF" ]; then
        npx agent-browser $BASE_OPTS click "$HX_REF" > /dev/null 2>&1 && CORE_CHECKED=$((CORE_CHECKED + 1))
    fi

    # CSSCI
    CSSCI_REF=$(echo "$SNAPSHOT" | grep 'checkbox "CSSCI"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
    if [ -n "$CSSCI_REF" ]; then
        npx agent-browser $BASE_OPTS click "$CSSCI_REF" > /dev/null 2>&1 && CORE_CHECKED=$((CORE_CHECKED + 1))
    fi

    # CSCD
    CSCD_REF=$(echo "$SNAPSHOT" | grep 'checkbox "CSCD"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
    if [ -n "$CSCD_REF" ]; then
        npx agent-browser $BASE_OPTS click "$CSCD_REF" > /dev/null 2>&1 && CORE_CHECKED=$((CORE_CHECKED + 1))
    fi

    # WJCI
    WJCI_REF=$(echo "$SNAPSHOT" | grep 'checkbox "WJCI"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
    if [ -n "$WJCI_REF" ]; then
        npx agent-browser $BASE_OPTS click "$WJCI_REF" > /dev/null 2>&1 && CORE_CHECKED=$((CORE_CHECKED + 1))
    fi

    # AMI
    AMI_REF=$(echo "$SNAPSHOT" | grep 'checkbox "AMI"' | sed -n 's/.*\[ref=\([^]]*\)\].*/\1/p')
    if [ -n "$AMI_REF" ]; then
        npx agent-browser $BASE_OPTS click "$AMI_REF" > /dev/null 2>&1 && CORE_CHECKED=$((CORE_CHECKED + 1))
    fi

    echo "✓ 已勾选 $CORE_CHECKED 个核心期刊选项"
fi

# 步骤7：点击检索按钮
echo "📖 步骤7: 执行检索..."
sleep 1
SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i)
SEARCH_BUTTON_REF=$(echo "$SNAPSHOT" | grep 'button.*检索' | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')

if [ -z "$SEARCH_BUTTON_REF" ]; then
    echo "❌ 无法找到检索按钮"
    exit 1
fi

npx agent-browser $BASE_OPTS click "$SEARCH_BUTTON_REF" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ 点击检索按钮失败"
    exit 1
fi
echo "✓ 已提交检索"

# 步骤8：等待并检测检索是否成功
echo "📖 步骤8: 等待检索结果..."
sleep 5

# 检测检索成功标志（最多重试3次）
RETRY=0
SUCCESS=0
while [ $RETRY -lt 3 ]; do
    sleep 3
    SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i)
    if echo "$SNAPSHOT" | grep -q "共找到\|总库\|找到"; then
        SUCCESS=1
        break
    fi
    RETRY=$((RETRY + 1))
    echo "   等待结果加载... ($((RETRY))/3)"
done

if [ $SUCCESS -eq 0 ]; then
    echo "❌ 检索失败或超时，未检测到结果页面"
    npx agent-browser $BASE_OPTS screenshot error.png
    echo "   已保存错误截图: error.png"
    exit 1
fi

# 提取结果数量
# 使用 eval 直接从 DOM 中获取结果数量
# HTML 结构: <em>39</em> inside .pagerTitleCell
RESULT_COUNT=$(npx agent-browser $BASE_OPTS eval 'document.querySelector(".pagerTitleCell em")?.textContent || "0"' 2>/dev/null | tr -d '"' || echo "?")
if [ "$RESULT_COUNT" = "0" ] || [ -z "$RESULT_COUNT" ]; then
    RESULT_COUNT="?"
fi
echo "✓ 检索成功！共找到约 $RESULT_COUNT 篇相关文献"

# 步骤9：调用爬虫脚本
echo "📖 步骤9: 开始爬取数据..."
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 调用爬虫脚本（复用现有的爬虫逻辑）
bash "$SCRIPT_DIR/cnki-crawl.sh" "$SESSION" "$OUTPUT_DIR" "$KEYWORD" "$TARGET_COUNT"

# 获取实际爬取数量
ACTUAL_COUNT=$(cat "$OUTPUT_DIR/.cnki_last_count" 2>/dev/null || echo "$TARGET_COUNT")

# 输出总结报告
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 高级检索爬取总结报告"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "检索关键词: $KEYWORD"
[ -n "$START_YEAR" ] && echo "起始年份: $START_YEAR"
[ -n "$END_YEAR" ] && echo "结束年份: $END_YEAR"
[ -n "$IS_CORE" ] && echo "来源类别: 核心期刊"
echo "相关文献总数: 约 $RESULT_COUNT 篇"
echo "本次爬取: $ACTUAL_COUNT 篇"
# 仅当 RESULT_COUNT 为数字时计算未爬取数量
if [[ "$RESULT_COUNT" =~ ^[0-9]+$ ]]; then
    echo "未爬取: $((RESULT_COUNT - ACTUAL_COUNT)) 篇"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
