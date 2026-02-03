# CNKI 检索技能

基于 [agent-browser](../agent-browser/) 的中国知网(CNKI)专用检索技能。

## 功能特性

- ✅ 关键词检索
- ✅ 结构化结果提取
- ✅ 多种输出格式（JSON、表格、Markdown）
- ✅ 批量检索支持
- ✅ 结果去重

## 快速开始

### 方式1：使用 Bash 脚本

```bash
# 赋予执行权限
chmod +x cnki-search.sh

# 执行检索
./cnki-search.sh "图书馆 智能体" 10
```

### 方式2：使用 Python 脚本

```bash
# 安装依赖（无额外依赖，仅需 Python 3.7+）

# Markdown 格式输出（默认）
python cnki_search.py "图书馆 智能体"

# JSON 格式输出
python cnki_search.py "图书馆 智能体" --format json

# 表格格式输出
python cnki_search.py "图书馆 智能体" --format table

# 限制结果数量
python cnki_search.py "图书馆 智能体" --limit 5
```

### 方式3：手动执行 agent-browser 命令

```bash
# 1. 打开 CNKI
agent-browser open https://chn.oversea.cnki.net

# 2. 获取页面元素
agent-browser snapshot -i

# 3. 填写搜索框（通常是 @e16）
agent-browser fill @e16 "图书馆 智能体"

# 4. 点击检索按钮（通常是 @e17）
agent-browser click @e17

# 5. 等待结果页加载
agent-browser wait --url "**/result**" --timeout 30000

# 6. 提取结果
agent-browser eval "(()=>{const r=[];document.querySelectorAll('tbody tr').forEach(t=>{const e=t.querySelector('.name a');e&&r.push({title:e.textContent.trim(),author:t.querySelector('td:nth-child(3)')?.textContent.trim(),source:t.querySelector('td:nth-child(4)')?.textContent.trim()})});return r})()"
```

## 成功案例

### 检索"图书馆 智能体"相关论文

```bash
python cnki_search.py "图书馆 智能体" --limit 10
```

输出示例：

```
## CNKI 检索结果

| 序号 | 论文标题 | 作者 | 来源 | 发表日期 |
|------|----------|------|------|----------|
| 1 | 多模态大模型驱动下的图书馆个性化知识服务模式研究 | 储节旺;周柯堰 | 情报理论与实践 | 2026-01-29 |
| 2 | 人工智能语料图书馆：内涵、功能需求与建设路径 | 刘细文;钱力;涂志芳 | 图书情报工作 | 2026-01-27 |
| 3 | 学术检索智能体持续使用意愿形成机制 | 陈宇人;龚芙蓉 | 图书情报知识 | 2026-01-06 |
...
```

## 文件结构

```
cnki/
├── SKILL.md           # 技能文档（核心文档）
├── README.md          # 本文件
├── cnki-search.sh     # Bash 脚本版本
└── cnki_search.py     # Python 脚本版本
```

## 技术要点

### 1. 页面元素识别

CNKI 首页的关键元素：
- 搜索框：通常为 `@e16`（每次 `snapshot` 后可能变化）
- 检索按钮：通常为 `@e17`

### 2. URL 跳转模式

- 首页：`https://chn.oversea.cnki.net`
- 检索结果页：`https://kns.cnki.net/kns8s/defaultresult/index?kw=...`

### 3. 结果提取选择器

```javascript
// 论文标题
.name a 或 td.title a

// 作者
td:nth-child(3)

// 来源
td:nth-child(4)

// 发表日期
td:nth-child(5)
```

## 故障排除

### 问题：页面元素 ref 变化

**原因**：每次执行 `snapshot`，元素 ref 都会重新分配

**解决**：每次检索前重新执行 `snapshot -i`

### 问题：结果页面加载缓慢

**解决**：增加超时时间
```bash
agent-browser wait --url "**/result**" --timeout 60000
```

### 问题：JavaScript 返回空结果

**原因**：页面尚未完全加载

**解决**：
```bash
# 方式1：等待网络空闲
agent-browser wait --load networkidle

# 方式2：固定等待时间
agent-browser wait 5000
```

## 依赖

- [agent-browser](../agent-browser/) - 基础浏览器自动化工具
- Python 3.7+（仅 Python 脚本版本需要）
- Bash 4.0+（仅 Shell 脚本版本需要）
