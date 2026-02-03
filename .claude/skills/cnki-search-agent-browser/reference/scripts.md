# CNKI 自动化爬取脚本使用文档

> **说明**：本文档详细说明 CNKI 技能中所有自动化爬取脚本的参数、用法和依赖。

## 脚本位置

```
{baseDir}/.claude/skills/cnki-search-agent-browser/scripts/
```

## 脚本列表

### cnki-search.sh - 简单检索

快速检索，无时间/期刊限制。

**语法**：
```bash
cnki-search.sh <keyword> [count] [output_dir]
```

**参数**：

| 参数 | 说明 | 必填 | 默认值 |
|------|------|------|--------|
| `keyword` | 检索关键词 | 是 | - |
| `count` | 爬取数量 | 否 | 50 |
| `output_dir` | 输出目录 | 否 | outputs |

**使用示例**：
```bash
# 使用默认参数（50篇，输出到 outputs）
bash scripts/cnki-search.sh "人工智能"

# 自定义数量和输出目录
bash scripts/cnki-search.sh "人工智能" 100 my_outputs
```

---

### cnki-adv-search.sh - 高级检索

支持时间范围、核心期刊筛选。

**语法**：
```bash
cnki-adv-search.sh <keyword> [options]
```

**参数**：

| 参数 | 说明 | 必填 | 默认值 |
|------|------|------|--------|
| `keyword` | 检索关键词 | 是 | - |
| `-s, --start <year>` | 起始年份 | 否 | 最近3年 |
| `-e, --end <year>` | 结束年份 | 否 | 最近3年 |
| `-c, --core` | 核心期刊标识 | 否 | 是（勾选） |
| `-n, --count <num>` | 爬取数量 | 否 | 50 |
| `-o, --output <dir>` | 输出目录 | 否 | outputs |

**核心期刊选项**：
勾选 `-c` 后会选中：SCI、EI、北大核心、CSSCI、CSCD、AMI、WJCI

**使用示例**：
```bash
# 使用默认参数（最近3年，核心期刊，50篇）
bash scripts/cnki-adv-search.sh "人工智能"

# 自定义时间范围
bash scripts/cnki-adv-search.sh "人工智能" -s 2020 -e 2024

# 不限制核心期刊
bash scripts/cnki-adv-search.sh "人工智能" --no-core

# 完整自定义
bash scripts/cnki-adv-search.sh "人工智能" -s 2019 -e 2023 -c -n 100 -o results
```

---

### cnki-crawl.sh - 延续爬取

从上次停止的位置继续爬取剩余文献。

**设计理念**：脚本作为**执行层**，只负责跳转到指定页、跳过指定条数、提取数据。参数计算由 Skill 层（大模型）负责。

**语法**：
```bash
cnki-crawl.sh <session> <output_dir> <keyword> --target-page <页码> --skip-in-page <条数> --count <数量> [--start-idx <序号>]
```

**参数**：

| 参数 | 说明 | 必填 | 默认值 |
|------|------|------|--------|
| `session` | 浏览器会话名称 | 是 | - |
| `output_dir` | 输出目录（需与首次检索一致） | 是 | - |
| `keyword` | 检索关键词（需与首次检索一致） | 是 | - |
| `--target-page` | 目标页码（从1开始） | 否 | 当前页 |
| `--skip-in-page` | 当前页内需要跳过的条数 | 否 | 0 |
| `--count` | 本次要爬取的数量 | 否 | 100 |
| `--start-idx` | 输出文件的起始序号 | 否 | 1 |

**职责分工**：

| 职责 | Skill 层（大模型） | 脚本层 |
|------|-------------------|--------|
| 理解用户输入 | "继续爬30篇" → 解析意图 | - |
| 读取当前状态 | 读取状态文件 | - |
| 计算参数 | target_page, skip_in_page, start_idx | - |
| 执行操作 | - | 跳页、提取、保存、输出状态 |

**状态文件格式** (`.cnki_state.json`)：
```json
{
  "keyword": "关键词",
  "total_collected": 10,
  "current_page": 1,
  "items_per_page": 20,
  "timestamp": "2026-02-03T12:34:56Z"
}
```

**Skill 层参数计算示例**：
```bash
# 1. 读取状态文件获取所有必要信息
STATE=$(cat outputs/.cnki_state.json)
EXISTING_COUNT=$(echo "$STATE" | jq -r '.total_collected')  # 10
CURRENT_PAGE=$(echo "$STATE" | jq -r '.current_page')       # 1
ITEMS_PER_PAGE=$(echo "$STATE" | jq -r '.items_per_page')   # 20

# 2. 计算目标参数
TARGET_PAGE=$((EXISTING_COUNT / ITEMS_PER_PAGE + 1))        # 10/20+1 = 1
SKIP_IN_PAGE=$((EXISTING_COUNT % ITEMS_PER_PAGE))          # 10%20 = 10
START_IDX=$((EXISTING_COUNT + 1))                           # 11
```

**使用示例**：
```bash
# 已爬取10篇，每页20条，继续爬30篇
# Skill 计算: target_page=1, skip_in_page=10, start_idx=11
bash scripts/cnki-crawl.sh cnki outputs "关键词" \
  --target-page 1 \
  --skip-in-page 10 \
  --count 30 \
  --start-idx 11

# 已爬取50篇，每页50条，继续爬50篇
# Skill 计算: target_page=2, skip_in_page=0, start_idx=51
bash scripts/cnki-crawl.sh cnki outputs "关键词" \
  --target-page 2 \
  --skip-in-page 0 \
  --count 50 \
  --start-idx 51

# 从当前页继续爬取（不指定目标页）
bash scripts/cnki-crawl.sh cnki outputs "关键词" --count 30 --start-idx 11
```

**注意事项**：
- 必须使用与首次检索相同的 session 名称
- output_dir 和 keyword 必须与首次检索一致
- --start_idx 应设置为 `已爬取数量 + 1`
- --skip_in_page 只在目标页与当前页相同时需要设置

---

## 依赖要求

### jq - JSON 处理工具

所有脚本都需要 `jq` 工具来处理 JSON 数据。

**安装方式**：

| 平台 | 命令 |
|------|------|
| Windows (Scoop) | `scoop install jq` |
| Windows (Chocolatey) | `choco install jq` |
| macOS (Homebrew) | `brew install jq` |
| Linux (apt) | `sudo apt install jq` |
| Linux (yum) | `sudo yum install jq` |

**验证安装**：
```bash
jq --version
```

---

## 输出格式

所有脚本都会在输出目录中生成以下文件：

| 文件 | 说明 |
|------|------|
| `{keyword}-{date}.json` | 结构化 JSON 结果 |
| `{keyword}-{date}.md` | Markdown 格式报告 |

**JSON 格式示例**：
```json
[
  {
    "title": "论文标题",
    "author": "作者1; 作者2",
    "source": "期刊名称",
    "date": "2024-01-01"
  }
]
```

---

## 注意事项

1. **首次使用**：建议先用小数量测试（如 10 篇），确认结果符合预期
2. **爬取数量**：CNKI 每页显示 20 条，建议按 20 的倍数设置（如 40、60、100）
3. **输出目录**：脚本会自动创建输出目录（如不存在）
4. **会话管理**：脚本执行完成后会保持浏览器会话打开，便于延续爬取
