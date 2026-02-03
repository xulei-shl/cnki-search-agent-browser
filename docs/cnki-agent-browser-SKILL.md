---
name: cnki
description: "CNKI 中国知网操作指南。提供 CNKI 网站的特定操作知识、元素定位策略、反爬虫应对方法。用户需要检索 CNKI 论文或操作 CNKI 网站时使用此技能。基于 agent-browser 实现。"
allowed-tools: Bash(agent-browser:*)
---

# CNKI 中国知网操作指南

本技能指导如何使用 **agent-browser** 通用技能来操作 CNKI（中国知网）网站。

CNKI 网站有较强的反爬虫限制，使用时需注意以下特性：
- **必须使用有头模式** `--headed`，无头模式会被检测并限制
- 页面元素 ref 会动态变化，需要每次重新获取
- 检索响应较慢，通常需要 2-4 秒
- 频繁请求可能被限制

## 重要经验总结

### ⚠️ CNKI 必须使用有头模式

CNKI 会检测无头浏览器并阻止访问。**必须使用 `--headed` 参数启动浏览器**。

```bash
# ❌ 错误：无头模式会被检测
agent-browser open https://chn.oversea.cnki.net

# ✅ 正确：使用有头模式
agent-browser --session cnki --headed open https://chn.oversea.cnki.net
```

### ✅ 启动 agent-browser 的正确步骤

**经验教训**：直接使用 `open` 命令会报错 "Browser not launched. Call launch first."，但 `launch` 命令不存在。

**正确做法**：使用 `--session` 参数启动会话。

```bash
# ✅ 正确的启动方式（首次使用需先安装浏览器）
npx agent-browser install  # 首次使用需要安装浏览器

# 使用 --session 参数启动（必须配合 --headed）
npx agent-browser --session <会话名> --headed open <URL>

# 示例
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net
```

### ✅ 翻页操作的最佳实践

**经验教训**：使用 JavaScript `eval` 点击翻页按钮往往无效，返回的是旧页面内容。

**正确做法**：使用 `snapshot -i` 获取元素 ref，然后用 `click` 命令点击。

```bash
# ❌ 错误：使用 JavaScript 点击往往无效
agent-browser eval "document.querySelector('.pagesnums').click()"

# ✅ 正确：使用 snapshot + click
agent-browser snapshot -i | grep '"2"'  # 查找页码2的 ref（如 @e270）
agent-browser click @e270               # 使用 click 命令点击
agent-browser wait --load networkidle --timeout 60000  # 等待加载
```

### ✅ 设置每页显示50条的最佳实践

**经验教训**：使用 JavaScript `eval` 点击下拉框中的"50"选项往往无效，只是展开了下拉菜单但未选择。

**正确做法**：使用 `snapshot -i` 获取"50"选项的 ref，然后用 `click` 命令直接点击。

```bash
# ❌ 错误：使用 eval 只会展开下拉框，不会选择50
agent-browser eval "document.querySelector('[data-val=\"50\"] a')?.click()"

# ✅ 正确：使用 snapshot + click 直接点击50选项
agent-browser snapshot -i | grep -E '"20"|"50"'  # 查找50的 ref（如 @e70）
# 输出示例：- link "20" [ref=e69]
#           - link "50" [ref=e70]
agent-browser click @e70               # 使用 click 命令点击50选项
agent-browser wait --load networkidle --timeout 60000  # 等待页面重新加载
```

## 概述

本技能提供 CNKI 网站专用的操作知识，包括：
- 页面元素定位策略
- 反爬虫应对方法
- 结果提取模板
- 常见问题处理

**使用时机**：用户需要检索 CNKI 论文、获取文献信息、操作 CNKI 网站时。

**基础技能**：本技能依赖 [agent-browser]({baseDir}/.claude/skills/agent-browser/SKILL.md) 通用技能。

## 快速开始

### 完整检索流程示例

```bash
# 1. 打开 CNKI 首页（必须使用 --session 和 --headed）
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net

# 2. 获取页面交互元素（返回 ref 如 @e16, @e17）
npx agent-browser --session cnki --headed snapshot -i

# 3. 填写搜索框（假设搜索框 ref 为 @e16）
npx agent-browser --session cnki --headed fill @e16 "人工智能"

# 4. 点击检索按钮（假设检索按钮 ref 为 @e17）
npx agent-browser --session cnki --headed click @e17

# 5. 等待结果页加载（使用 networkidle，增加超时时间）
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000

# 6. 设置每页显示50条（提升爬取效率，强烈推荐）
npx agent-browser --session cnki --headed snapshot -i | grep -E '"20"|"50"'
# 输出如：- link "20" [ref=e69]
#       - link "50" [ref=e70]
npx agent-browser --session cnki --headed click @e70
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000

# 7. 提取检索结果
npx agent-browser --session cnki --headed eval "[...document.querySelectorAll('tbody tr')].map(row=>({title:row.querySelector('.name a')?.textContent,author:row.querySelector('td:nth-child(3)')?.textContent,source:row.querySelector('td:nth-child(4)')?.textContent}))"
```

### 翻页提取多页结果

```bash
# 翻页到第2页：先获取页码元素 ref
npx agent-browser --session cnki --headed snapshot -i | grep '"2"'  # 输出如：- link "2" [ref=e270]
npx agent-browser --session cnki --headed click @e270              # 使用实际 ref 点击
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000
npx agent-browser --session cnki --headed eval "..."               # 提取结果
```

## 标准操作流程

### 1. 检索流程

```bash
# 步骤 1：打开 CNKI（必须使用 --session 和 --headed）
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net

# 步骤 2：获取元素 ref（每次操作前都要重新获取）
npx agent-browser --session cnki --headed snapshot -i

# 步骤 3：输入关键词
npx agent-browser --session cnki --headed fill @e16 "检索关键词"

# 步骤 4：点击检索
npx agent-browser --session cnki --headed click @e17

# 步骤 5：等待结果加载（使用 networkidle，增加超时时间）
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000

# 步骤 6：设置每页显示50条（提升爬取效率，默认执行）
npx agent-browser --session cnki --headed snapshot -i | grep -E '"20"|"50"'
# 输出如：- link "20" [ref=e69]
#       - link "50" [ref=e70]
npx agent-browser --session cnki --headed click @e70
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000

# 步骤 7：验证结果页已加载
npx agent-browser --session cnki --headed get url
```

### 2. 结果提取

> **推荐格式**（简单可靠，避免编码问题）：
> 使用简短属性名（t/a/s/d）和链式调用，避免复杂函数表达式。

**标准提取格式：**
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

**其他提取示例：**

**仅提取标题：**
```javascript
[...document.querySelectorAll('.name a')].map(a=>a.textContent.trim())
```

**去重提取（处理重复条目）：**
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

### 2.4 设置每页显示数量（**默认强制执行**）

CNKI 默认每页显示 20 条结果。**检索结果加载后，必须立即设置为 50 条**以提高爬取效率：

```bash
# 步骤1：查找50选项的 ref
agent-browser snapshot -i | grep -E '"20"|"50"'
# 输出示例：- link "20" [ref=e69]
#           - link "50" [ref=e70]

# 步骤2：点击50选项
agent-browser click @e70

# 步骤3：等待页面重新加载
agent-browser wait --load networkidle --timeout 60000
```

**重要说明**：
- **这是默认强制步骤**，检索结果加载后必须执行
- **必须使用 `click` 命令**，不能用 `eval` 点击（eval 只会展开下拉框）
- 设置后当前页面会重新加载，需要等待加载完成
- 每页显示 50 条可以大幅减少翻页次数，提升效率
- 70篇文献只需翻2页（而非4页）

### 2.5 结果输出说明

检索完成后，**无需输出所有文献列表**，仅向用户提供简要统计信息即可：

```bash
# ✅ 推荐：仅输出简要统计
echo "检索完成！共获取 N 篇文献："
echo "- 第1页：20篇"
echo "- 第2页：20篇"
echo "- 关键词：XXX"
echo "- 检索日期：$(date +%Y-%m-%d)"

# ❌ 避免：输出完整的文献列表（冗长且干扰用户体验）
# 不要将所有文献详情打印到终端
```

**输出建议**：
- 向用户简要说明：检索了多少页、共多少篇文献
- 如需详细数据，可保存到文件供用户查看
- 重点关注检索结果的**质量和相关性**，而非罗列所有条目

### 3. 翻页操作

> **重要**：翻页操作必须使用 `snapshot + click` 方式，使用 JavaScript `eval` 点击往往无效。

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

**常见错误**：
```bash
# ❌ 错误：使用 JavaScript 点击往往无效，返回旧页面内容
npx agent-browser --session cnki --headed eval "document.querySelector('.pagesnums').click()"

# ✅ 正确：使用 snapshot + click
npx agent-browser --session cnki --headed snapshot -i | grep '"2"'
npx agent-browser --session cnki --headed click @e270
```

### 3.2 并行多页爬取（高级）

当需要爬取大量结果时，可以使用 agent-browser 的 `--session` 功能实现多实例并行处理：

```bash
# 启动 3 个并行 session（后台执行）
(agent-browser --session cnki-p1 open https://chn.oversea.cnki.net && \
  agent-browser --session cnki-p1 snapshot -i && \
  agent-browser --session cnki-p1 fill @e16 "关键词" && \
  agent-browser --session cnki-p1 click @e17 && \
  agent-browser --session cnki-p1 wait --load networkidle --timeout 30000 && \
  agent-browser --session cnki-p1 eval "..." > p1-page1.json) &

(agent-browser --session cnki-p2 open https://chn.oversea.cnki.net && \
  agent-browser --session cnki-p2 snapshot -i && \
  agent-browser --session cnki-p2 fill @e16 "关键词" && \
  agent-browser --session cnki-p2 click @e17 && \
  agent-browser --session cnki-p2 wait --load networkidle --timeout 30000 && \
  agent-browser --session cnki-p2 eval "..." > p2-page1.json) &

# 等待所有后台任务完成
wait

# 收集结果
cat p1-page1.json p2-page1.json
```

**Session 特性**：
- 每个session有独立的浏览器上下文（cookies、存储、历史）
- 完全状态隔离，不会相互干扰
- 可以同时访问不同页面

**注意事项**：
- **并发控制**：建议 2-3 个 session，避免触发 CNKI 反爬虫
- **请求间隔**：每个操作间隔 -2-4 秒
- **资源清理**：完成后使用 `agent-browser --session cnki-pX close` 关闭session
- **复杂度高**：仅在需要爬取大量结果（>60篇）时使用

## CNKI 页面元素参考

### 首页元素映射

| 元素 | 通常的 ref | 说明 |
|------|-----------|------|
| 搜索框 | @e16 | "中文文献、外文文献" 输入框 |
| 检索按钮 | @e17 | "检索" 按钮 |
| 高级检索链接 | @e19 | "高级检索" 链接 |

> **注意**：ref 会动态变化，每次操作前务必执行 `agent-browser snapshot -i` 获取最新 ref。

### 结果页面选择器

| 数据类型 | CSS 选择器 | 说明 |
|----------|-----------|------|
| 论文标题 | `.name a` 或 `td.title a` | 标题链接 |
| 作者 | `td:nth-child(3)` | 作者列表 |
| 来源 | `td:nth-child(4)` | 期刊/来源名称 |
| 发表时间 | `td:nth-child(5)` | 发表日期 |
| 下载次数 | `.download` | 下载统计 |

## 网站特性与应对策略

| 特性 | 说明 | 应对策略 |
|------|------|----------|
| **必须使用有头模式** | 无头模式会被检测并阻止访问 | **必须使用 `--headed` 参数** |
| **需要 session 启动** | 直接 open 会报错 "Browser not launched" | **必须使用 `--session` 参数** |
| **元素 ref 动态变化** | 每次 snapshot 后 ref 可能重新分配 | 每次操作前重新执行 `snapshot -i` |
| **翻页必须用 click** | JavaScript eval 点击翻页往往无效 | 使用 `snapshot + click` 命令 |
| **页面加载缓慢** | 检索可能需要 2-4 秒 | 使用 `--timeout 60000` 或更长 |
| **反爬虫限制** | 频繁请求可能被限制 | 检索间隔至少 5 秒 |
| **需要登录** | 部分功能需要机构订阅 | 使用 `agent-browser state save` 保存登录状态 |
| **验证码** | 高频请求可能触发验证码 | 降低请求频率，或使用有头模式 `--headed` 手动处理 |

## 实用示例

### 示例 1：基础检索（完整流程）

```bash
# 首次使用需要安装浏览器
npx agent-browser install

# 使用有头模式打开 CNKI（必须配合 --session）
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net

# 获取元素并检索
npx agent-browser --session cnki --headed snapshot -i
npx agent-browser --session cnki --headed fill @e16 "知识图谱"
npx agent-browser --session cnki --headed click @e17
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000

# 设置每页显示50条（提升效率，默认执行）
npx agent-browser --session cnki --headed snapshot -i | grep -E '"20"|"50"'
# 输出如：- link "20" [ref=e69]
#       - link "50" [ref=e70]
npx agent-browser --session cnki --headed click @e70
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000

# 提取结果
npx agent-browser --session cnki --headed eval "[...document.querySelectorAll('tbody tr')].slice(0,10).map(row=>({title:row.querySelector('.name a')?.textContent,source:row.querySelector('td:nth-child(4)')?.textContent}))"
```

### 示例 2：翻页提取多页

```bash
# 翻到第2页
npx agent-browser --session cnki --headed snapshot -i | grep '"2"'  # 获取页码2的 ref
npx agent-browser --session cnki --headed click @e270
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000
npx agent-browser --session cnki --headed eval "..."

# 翻到第3页
npx agent-browser --session cnki --headed snapshot -i | grep '"3"'
npx agent-browser --session cnki --headed click @e280
npx agent-browser --session cnki --headed wait --load networkidle --timeout 60000
npx agent-browser --session cnki --headed eval "..."
```

### 示例 3：保存登录状态

```bash
# 首次登录后保存状态
npx agent-browser --session cnki --headed state save cnki-auth.json

# 后续会话中恢复状态
npx agent-browser --session cnki --headed state load cnki-auth.json
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net
```

### 示例 4：有头模式处理验证码

```bash
# 使用有头模式，方便手动处理验证码（CNKI 必须使用有头模式）
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net
```

### 示例 5：截屏调试

```bash
npx agent-browser --session cnki --headed screenshot cnki-debug.png
```

### 示例 5：保存结果到 Markdown

**重要**：结果文件保存在项目根目录的 `outputs` 目录下，文件名格式为 `检索词-YYYYMMDD.md`。

```bash
# 创建输出目录（项目根目录下的 outputs）
mkdir -p {baseDir}/outputs

# 设置输出文件名（格式：检索词-YYYYMMDD.md）
OUTPUT_FILE="{baseDir}/outputs/图书馆-智能体-$(date +%Y%m%d).md"

# 写入 Markdown 头部
echo "# CNKI 检索结果：图书馆 智能体" > "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**检索日期**: $(date +%Y-%m-%d)" >> "$OUTPUT_FILE"
echo "**检索关键词**: 图书馆 智能体" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "## 第1页" >> "$OUTPUT_FILE"

# 提取结果并追加到文件
agent-browser eval "[...document.querySelectorAll('tbody tr')].map((r,i)=>(\`\${i+1}. \${r.querySelector('.name a')?.textContent}\`)).join('\\n')" >> "$OUTPUT_FILE"
```

**输出文件路径格式**：
```
{baseDir}/outputs/图书馆-智能体-20260202.md
```

**输出文件内容格式**：
```markdown
# CNKI 检索结果：图书馆 智能体

**检索日期**: 2026-02-02
**检索关键词**: 图书馆 智能体

## 第1页

1. 多模态大模型驱动下的图书馆个性化知识服务模式研究
2. 人工智能语料图书馆：内涵、功能需求与建设路径
...
```

## URL 模式

| 页面类型 | URL 模式 |
|----------|----------|
| 首页 | `chn.oversea.cnki.net` |
| 检索结果 | `kns.cnki.net/kns8s/defaultresult/index` |
| 高级检索 | `kns.cnki.net/kns8s/advancedsearch` |
| 详情页 | `kns.cnki.net/knavi/...` |

## 故障排除

### 常见问题

**问题 1：Browser not launched. Call launch first.**
- **现象**：直接使用 `open` 命令报错
- **解决**：**必须使用 `--session` 参数启动**，如 `npx agent-browser --session cnki --headed open <URL>`

**问题 2：无头模式页面一直加载中**
- **现象**：页面显示"加载中"，无法获取结果
- **解决**：**必须使用 `--headed` 参数**，CNKI 会检测无头浏览器并阻止访问

**问题 3：元素 ref 变化导致操作失败**
- **现象**：`fill @e16` 报错元素不存在
- **解决**：每次操作前执行 `snapshot -i` 获取最新 ref

**问题 4：翻页后返回旧页面内容**
- **现象**：使用 JavaScript `eval` 点击翻页，但提取的结果和之前一样
- **解决**：使用 `snapshot -i` 获取页码 ref，然后用 `click` 命令点击，不要用 `eval`

**问题 5：结果页面加载超时**
- **现象**：等待超时
- **解决**：增加超时时间 `--timeout 60000`

**问题 6：JavaScript 返回空结果**
- **现象**：`eval` 返回空数组
- **解决**：检查页面是否完全加载，可能需要等待更长时间或使用不同的选择器

**问题 7：需要登录才能查看**
- **现象**：页面跳转到登录页
- **解决**：使用 `agent-browser state` 保存登录状态，或使用有头模式手动登录

**问题 8：频繁请求被限制**
- **现象**：返回验证码或错误页
- **解决**：降低请求频率，每次检索间隔至少 5 秒

**问题 9：设置每页显示50条无效**
- **现象**：使用 `eval` 点击后只展开下拉框，没有选择50
- **解决**：**必须使用 `snapshot + click` 方式**，用 `snapshot -i | grep -E '"20"|"50"'` 获取50的ref，然后用 `click` 命令点击

## 结果数据结构

### 单条论文记录

```typescript
interface PaperRecord {
  title: string;      // 论文标题
  author: string;     // 作者
  source: string;     // 来源期刊/出版物
  date: string;       // 发表日期
}
```

## 注意事项

1. **元素 ref 动态变化**：每次 `snapshot` 后 ref 可能重新分配，需要重新获取
2. **页面加载时间**：CNKI 检索可能需要 2-4 秒，耐心等待
3. **并发限制**：避免过于频繁的检索请求
4. **结果分页**：默认只显示第一页结果，需要翻页获取更多
5. **字符编码**：关键词使用 UTF-8 编码

## 相关技能

- [agent-browser]({baseDir}/.claude/skills/agent-browser/SKILL.md) - 基础浏览器自动化技能
