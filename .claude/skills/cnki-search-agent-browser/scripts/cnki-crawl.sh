#!/bin/bash
# CNKI 结果爬取脚本（检索后调用）
# 用法: cnki-crawl.sh <session> <output_dir> <keyword> [count] [offset]
# 功能: 自动设置每页50条、自动翻页、提取指定数量的论文
#   offset: 起始序号，用于从中断位置继续爬取

# 不使用 set -e，手动处理错误

SESSION=$1
OUTPUT_DIR=$2
KEYWORD=${3:-"检索"}
TARGET_COUNT=${4:-100}
OFFSET=${5:-0}  # 起始序号，默认0

TIMESTAMP=$(date +%Y%m%d)
BASE_OPTS="--session $SESSION --headed"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 输出文件路径（关键词中的空格替换为下划线）
SAFE_KEYWORD=$(echo "$KEYWORD" | sed 's/ /_/g')
MD_FILE="$OUTPUT_DIR/${SAFE_KEYWORD}-${TIMESTAMP}.md"
JSON_FILE="$OUTPUT_DIR/${SAFE_KEYWORD}-${TIMESTAMP}.json"

# 如果 offset 为 0，初始化文件；否则追加到现有文件
if [ "$OFFSET" -eq 0 ]; then
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
    echo "📌 从第 $((OFFSET + 1)) 篇继续爬取（已有 $EXISTING_COUNT 篇）"
fi

# 步骤1：自动设置每页显示50条
echo "⚙️  正在设置每页显示50条..."
# CNKI 使用 radio input，snapshot -i 不会显示 label 元素
# 需要使用 eval 直接点击 input[value="50"]
# 先检查当前是否已经是50
PER_PAGE=$(npx agent-browser $BASE_OPTS eval 'document.querySelector("label.on")?.textContent.trim() || ""' 2>/dev/null || echo "")
if [ "$PER_PAGE" = "50" ]; then
    echo "✓ 已是每页50条"
else
    # 点击 value="50" 的 radio
    npx agent-browser $BASE_OPTS eval 'document.querySelector("input[value=\\"50\\"]")?.click()' > /dev/null 2>&1 || true
    sleep 2
    # 验证是否设置成功
    PER_PAGE=$(npx agent-browser $BASE_OPTS eval 'document.querySelector("label.on")?.textContent.trim() || ""' 2>/dev/null || echo "")
    if [ "$PER_PAGE" = "50" ]; then
        echo "✓ 已设置每页50条"
    else
        echo "⚠️  设置失败，使用默认设置"
    fi
fi

# 步骤2：爬取数据
TOTAL_COLLECTED=0
PAGE_NUM=1

while [ $TOTAL_COLLECTED -lt $TARGET_COUNT ]; do
    echo "📄 正在爬取第 $PAGE_NUM 页..."

    # 提取当前页结果（单行格式，使用正确的选择器）
    PAGE_DATA=$(npx agent-browser $BASE_OPTS eval '[...document.querySelectorAll(`tbody tr`)].map((r,i)=>({title:r.querySelector(`.name a`)?.textContent?.trim(),author:[...r.querySelectorAll(`td:nth-child(3) a`)].map(a=>a.textContent.trim()).join(`; `),source:r.querySelector(`td:nth-child(4) a`)?.textContent?.trim(),date:r.querySelector(`td:nth-child(5)`)?.textContent?.trim()})).filter(x=>x.title)' || echo '[]')

    # 统计当前页条数
    PAGE_COUNT=$(echo "$PAGE_DATA" | jq 'length' 2>/dev/null || echo "0")

    if [ "$PAGE_COUNT" -eq 0 ]; then
        echo "⚠️  当前页无数据，可能已到最后一页"
        break
    fi

    # 计算需要从当前页提取的数量
    NEEDED=$((TARGET_COUNT - TOTAL_COLLECTED))
    if [ $NEEDED -lt $PAGE_COUNT ]; then
        # 只取需要的数量
        PAGE_DATA=$(echo "$PAGE_DATA" | jq ".[0:$NEEDED]")
        PAGE_COUNT=$NEEDED
    fi

    # 追加到 JSON 文件
    if [ -n "$PAGE_DATA" ] && [ "$PAGE_DATA" != "[]" ]; then
        CURRENT=$(cat "$JSON_FILE")
        echo "$CURRENT" | jq --argjson new "$PAGE_DATA" '. + $new' > "$JSON_FILE.tmp" 2>/dev/null || echo "$CURRENT" > "$JSON_FILE.tmp"
        mv "$JSON_FILE.tmp" "$JSON_FILE"
    fi

    # 写入 Markdown 表格内容（使用 offset 作为起始序号）
    echo "$PAGE_DATA" | jq -r '.[] | "| \(.idx // "") | \(.title | gsub("\\|"; "\\|")) | \(.author) | \(.source) | \(.date) |"' \
        | awk -v start=$((OFFSET + TOTAL_COLLECTED + 1)) '{print "| " start++ " " substr($0, 3)}' >> "$MD_FILE" 2>/dev/null || true

    TOTAL_COLLECTED=$((TOTAL_COLLECTED + PAGE_COUNT))
    echo "   已收集 $((OFFSET + TOTAL_COLLECTED))/$(($OFFSET + $TARGET_COUNT)) 篇"

    # 检查是否已达到目标数量
    if [ $TOTAL_COLLECTED -ge $TARGET_COUNT ]; then
        echo "✅ 已达到目标数量 $TARGET_COUNT 篇"
        break
    fi

    # 步骤3：自动获取下一页按钮ref
    NEXT_PAGE_REF=$(npx agent-browser $BASE_OPTS snapshot -i | grep "下一页" | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')

    if [ -z "$NEXT_PAGE_REF" ]; then
        echo "⚠️  未找到下一页按钮，可能已到最后一页"
        break
    fi

    # 点击下一页
    echo "   正在翻页..."
    npx agent-browser $BASE_OPTS click "$NEXT_PAGE_REF" > /dev/null 2>&1 || true
    # 使用 sleep 替代 networkidle，避免超时问题
    sleep 3

    PAGE_NUM=$((PAGE_NUM + 1))

    # 安全限制：最多爬取10页
    if [ $PAGE_NUM -gt 10 ]; then
        echo "⚠️  已达到最大页数限制(10页)"
        break
    fi
done

# 更新 Markdown 头部信息（仅在首次爬取时更新）
if [ "$OFFSET" -eq 0 ]; then
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

# 输出已爬取数量（供调用方使用）
echo "$ACTUAL_COUNT" > "$OUTPUT_DIR/.cnki_last_count"
