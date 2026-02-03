#!/bin/bash
# CNKI 检索爬取一体化脚本
# 用法: cnki-search.sh <keyword> [count] [output_dir]
# 功能: 一步完成打开浏览器、检索、爬取数据

# 不使用 set -e，手动处理错误

KEYWORD=$1
TARGET_COUNT=${2:-100}
OUTPUT_DIR=${3:-"./outputs"}
SESSION="cnki"
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
    exit 1
fi
echo "✓ 浏览器已启动"

# 步骤2：获取元素ref
echo "📖 步骤2: 获取页面元素..."
sleep 2
SNAPSHOT=$(npx agent-browser --session $SESSION --headed snapshot -i)
SEARCH_REF=$(echo "$SNAPSHOT" | grep 'textbox.*中文文献' | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')
BUTTON_REF=$(echo "$SNAPSHOT" | grep 'button.*检索' | head -1 | sed -n 's/.*\[ref=\(.*\)\].*/\1/p')

if [ -z "$SEARCH_REF" ] || [ -z "$BUTTON_REF" ]; then
    echo "❌ 无法找到搜索框或检索按钮"
    exit 1
fi
echo "✓ 搜索框: @$SEARCH_REF, 检索按钮: @$BUTTON_REF"

# 步骤3：输入关键词并检索
echo "📖 步骤3: 执行检索..."
npx agent-browser --session $SESSION --headed fill "$SEARCH_REF" "$KEYWORD" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ 输入关键词失败"
    exit 1
fi
npx agent-browser --session $SESSION --headed click "$BUTTON_REF" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ 点击检索按钮失败"
    exit 1
fi
echo "✓ 已提交检索"

# 步骤4：等待并检测检索是否成功
echo "📖 步骤4: 等待检索结果..."
sleep 5

# 检测检索成功标志（最多重试3次）
# 使用 sleep + snapshot 循环检测，不依赖 networkidle
RETRY=0
SUCCESS=0
while [ $RETRY -lt 3 ]; do
    sleep 3
    SNAPSHOT=$(npx agent-browser --session $SESSION --headed snapshot -i)
    if echo "$SNAPSHOT" | grep -q "共找到\|总库"; then
        SUCCESS=1
        break
    fi
    RETRY=$((RETRY + 1))
    echo "   等待结果加载... ($((RETRY))/3)"
done

if [ $SUCCESS -eq 0 ]; then
    echo "❌ 检索失败或超时，未检测到结果页面"
    exit 1
fi

# 提取结果数量
RESULT_COUNT=$(echo "$SNAPSHOT" | grep -Eo '总库 [0-9]+' | head -1 | grep -Eo '[0-9]+' || echo "?")
echo "✓ 检索成功！共找到约 $RESULT_COUNT 篇相关文献"

# 步骤5：调用爬虫脚本
echo "📖 步骤5: 开始爬取数据..."
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 调用爬虫脚本
bash "$SCRIPT_DIR/cnki-crawl.sh" "$SESSION" "$OUTPUT_DIR" "$KEYWORD" "$TARGET_COUNT"

# 获取实际爬取数量
ACTUAL_COUNT=$(cat "$OUTPUT_DIR/.cnki_last_count" 2>/dev/null || echo "$TARGET_COUNT")

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
