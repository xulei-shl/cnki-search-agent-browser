# CNKI 手动操作参考文档

> **说明**：本文档保留用于**调试和故障排查**。日常使用请优先参考主文档中的[脚本化批量爬取方案]({baseDir}/.claude/skills/cnki/SKILL.md#26-脚本化批量爬取推荐)。

## 适用场景

- 需要调试特定页面元素
- 脚本执行失败需要手动排查
- 需要验证页面结构变化
- 学习 CNKI 页面交互机制

## 手动翻页操作

> **重要**：翻页操作必须使用 `snapshot + click` 方式，使用 JavaScript `eval` 点击往往无效。

### 基本翻页步骤

```bash
# 步骤 1：使用 snapshot 获取翻页按钮的 ref
npx agent-browser --session cnki --headed snapshot -i | grep '"2"'  # 查找页码2
# 输出示例：- link "2" [ref=e270]

# 步骤 2：使用 click 命令点击（不要用 eval）
npx agent-browser --session cnki --headed click @e270

# 步骤 3：等待新页面加载
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000

# 步骤 4：提取结果
npx agent-browser --session cnki --headed eval "..."
```

### 常见错误

```bash
# ❌ 错误：使用 JavaScript 点击往往无效，返回旧页面内容
npx agent-browser --session cnki --headed eval "document.querySelector('.pagesnums').click()"

# ✅ 正确：使用 snapshot + click
npx agent-browser --session cnki --headed snapshot -i | grep '"2"'
npx agent-browser --session cnki --headed click @e270
```

### 点击下一页按钮

```bash
# 获取下一页按钮 ref
npx agent-browser --session cnki --headed snapshot -i | grep "下一页"
# 输出示例：- link "下一页" [ref=e100]

# 点击下一页
npx agent-browser --session cnki --headed click @e100
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000
```

### 跳转到指定页码

```bash
# 跳转到第5页
npx agent-browser --session cnki --headed snapshot -i | grep '"5"'
# 输出示例：- link "5" [ref=e275]
npx agent-browser --session cnki --headed click @e275
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000
```

## 手动结果提取

### 标准提取格式

> **推荐格式**（简单可靠，避免编码问题）：
> 使用简短属性名（t/a/s/d）和链式调用，避免复杂函数表达式。

```javascript
[...document.querySelectorAll('tbody tr')].map(r=>({
  t:r.querySelector('.name a')?.textContent?.trim(),
  a:r.querySelector('td:nth-child(3)')?.textContent?.trim(),
  s:r.querySelector('td:nth-child(4)')?.textContent?.trim(),
  d:r.querySelector('td:nth-child(5)')?.textContent?.trim()
}))
```

**属性说明**：
- `t` = title（标题）
- `a` = author（作者）
- `s` = source（来源）
- `d` = date（日期）

### 其他提取示例

**仅提取标题**：
```javascript
[...document.querySelectorAll('.name a')].map(a=>a.textContent.trim())
```

**去重提取（处理重复条目）**：
```javascript
(() => {
  const results = [];
  const seen = new Set();
  document.querySelectorAll('tbody tr').forEach(row => {
    const titleEl = row.querySelector('.name a');
    if (titleEl) {
      const title = titleEl.textContent.trim();
      if (!seen.has(title)) {
        seen.add(title);
        results.push({
          title,
          author: row.querySelector('td:nth-child(3)')?.textContent?.trim() || '',
          source: row.querySelector('td:nth-child(4)')?.textContent?.trim() || '',
          date: row.querySelector('td:nth-child(5)')?.textContent?.trim() || ''
        });
      }
    }
  });
  return results;
})()
```

**提取前10条结果**：
```javascript
[...document.querySelectorAll('tbody tr')].slice(0,10).map(r=>({
  title:r.querySelector('.name a')?.textContent?.trim(),
  author:r.querySelector('td:nth-child(3)')?.textContent?.trim()
}))
```

## 手动保存到 Markdown

### 基础保存方式

```bash
# 创建输出目录
mkdir -p {baseDir}/outputs

# 设置输出文件名
OUTPUT_FILE="{baseDir}/outputs/检索关键词-$(date +%Y%m%d).md"

# 写入 Markdown 头部
echo "# CNKI 检索结果：检索关键词" > "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**检索日期**: $(date +%Y-%m-%d)" >> "$OUTPUT_FILE"
echo "**检索关键词**: 检索关键词" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "## 第1页" >> "$OUTPUT_FILE"

# 提取结果并追加到文件
npx agent-browser --session cnki --headed eval "
  [...document.querySelectorAll('tbody tr')].map((r,i)=>(
    \`\${i+1}. \${r.querySelector('.name a')?.textContent}\`
  })).join('\\n')
" >> "$OUTPUT_FILE"
```

### 带表格格式保存

```bash
OUTPUT_FILE="{baseDir}/outputs/检索关键词-$(date +%Y%m%d).md"

# 写入 Markdown 头部和表格
cat > "$OUTPUT_FILE" << EOF
# CNKI 检索结果：检索关键词

**检索日期**: $(date +%Y-%m-%d)
**检索关键词**: 检索关键词

| 序号 | 标题 | 作者 | 来源 | 发表时间 |
|------|------|------|------|----------|
EOF

# 提取并追加结果
npx agent-browser --session cnki --headed eval "
  [...document.querySelectorAll('tbody tr')].map((r, i) => {
    const title = r.querySelector('.name a')?.textContent?.trim() || 'N/A';
    const author = r.querySelector('td:nth-child(3)')?.textContent?.trim() || 'N/A';
    const source = r.querySelector('td:nth-child(4)')?.textContent?.trim() || 'N/A';
    const date = r.querySelector('td:nth-child(5)')?.textContent?.trim() || 'N/A';
    return \`| \${i+1} | \${title} | \${author} | \${source} | \${date} |\`;
  }).join('\\n')
" >> "$OUTPUT_FILE"
```

### 多页保存示例

```bash
OUTPUT_FILE="{baseDir}/outputs/检索关键词-$(date +%Y%m%d).md"

# 初始化文件
echo "# CNKI 检索结果" > "$OUTPUT_FILE"
echo "**检索日期**: $(date +%Y-%m-%d)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# 循环爬取3页
for page in {1..3}; do
    echo "## 第${page}页" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # 提取当前页
    npx agent-browser --session cnki --headed eval "..." >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # 翻页（如果不是最后一页）
    if [ $page -lt 3 ]; then
        npx agent-browser --session cnki --headed snapshot -i | grep "下一页"
        npx agent-browser --session cnki --headed click @e100
        npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000
        sleep 3
    fi
done
```

## 并行多页爬取（高级）

> **注意**：此方法较为复杂，仅在需要爬取大量结果（>60篇）时使用。日常场景请使用[脚本化方案]({baseDir}/.claude/skills/cnki/SKILL.md#26-脚本化批量爬取推荐)。

### 使用 Session 并行

```bash
# 启动 3 个并行 session（后台执行）
(npx agent-browser --session cnki-p1 --headed open https://chn.oversea.cnki.net && \
  npx agent-browser --session cnki-p1 --headed snapshot -i && \
  npx agent-browser --session cnki-p1 --headed fill @e16 "关键词" && \
  npx agent-browser --session cnki-p1 --headed click @e17 && \
  npx agent-browser --session cnki-p1 --headed wait --load networkidle --timeout 30000 && \
  npx agent-browser --session cnki-p1 --headed eval "..." > p1-page1.json) &

(npx agent-browser --session cnki-p2 --headed open https://chn.oversea.cnki.net && \
  npx agent-browser --session cnki-p2 --headed snapshot -i && \
  npx agent-browser --session cnki-p2 --headed fill @e16 "关键词" && \
  npx agent-browser --session cnki-p2 --headed click @e17 && \
  npx agent-browser --session cnki-p2 --headed wait --load networkidle --timeout 30000 && \
  npx agent-browser --session cnki-p2 --headed eval "..." > p2-page1.json) &

# 等待所有后台任务完成
wait

# 收集结果
cat p1-page1.json p2-page1.json
```

### Session 特性

- 每个session有独立的浏览器上下文（cookies、存储、历史）
- 完全状态隔离，不会相互干扰
- 可以同时访问不同页面

### 注意事项

- **并发控制**：建议 2-3 个 session，避免触发 CNKI 反爬虫
- **请求间隔**：每个操作间隔 2-4 秒
- **资源清理**：完成后使用 `npx agent-browser --session cnki-pX close` 关闭session
- **复杂度高**：仅在需要爬取大量结果（>60篇）时使用

## 调试技巧

### 截屏调试

```bash
# 保存当前页面截图
npx agent-browser --session cnki --headed screenshot cnki-debug.png
```

### 查看 URL

```bash
# 检查当前页面 URL
npx agent-browser --session cnki --headed get url
```

### 检查元素状态

```bash
# 检查元素是否可见
npx agent-browser --session cnki --headed is visible @e100

# 检查元素是否可点击
npx agent-browser --session cnki --headed is enabled @e100
```

### 查看控制台日志

```bash
# 查看浏览器控制台输出
npx agent-browser --session cnki --headed console
```

### 查看页面错误

```bash
# 查看页面 JavaScript 错误
npx agent-browser --session cnki --headed errors
```

## 页面元素参考

### 首页元素映射

| 元素 | 通常的 ref | 说明 |
|------|-----------|------|
| 搜索框 | @e16 | "中文文献、外文文献" 输入框 |
| 检索按钮 | @e17 | "检索" 按钮 |
| 高级检索链接 | @e19 | "高级检索" 链接 |

> **注意**：ref 会动态变化，每次操作前务必执行 `snapshot -i` 获取最新 ref。

### 结果页面选择器

| 数据类型 | CSS 选择器 | 说明 |
|----------|-----------|------|
| 论文标题 | `.name a` 或 `td.title a` | 标题链接 |
| 作者 | `td:nth-child(3)` | 作者列表 |
| 来源 | `td:nth-child(4)` | 期刊/来源名称 |
| 发表时间 | `td:nth-child(5)` | 发表日期 |
| 下载次数 | `.download` | 下载统计 |

## URL 模式

| 页面类型 | URL 模式 |
|----------|----------|
| 首页 | `chn.oversea.cnki.net` |
| 检索结果 | `kns.cnki.net/kns8s/defaultresult/index` |
| 高级检索 | `kns.cnki.net/kns8s/advancedsearch` |
| 详情页 | `kns.cnki.net/knavi/...` |
