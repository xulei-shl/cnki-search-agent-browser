---
name: cnki-search-agent-browser
description: "CNKI 中国知网操作指南。检索论文、获取文献信息。用户需要检索 CNKI 论文或操作 CNKI 网站时使用此技能。"
allowed-tools: "Read, Edit, Write, Bash, Glob, Grep, AskUserQuestion, Task"
---

# CNKI 技能主流程

## 技能入口：交互式检索

当用户请求检索 CNKI 论文时，按以下流程处理：

### 步骤1：交互式选择检索类型

**使用 AskUserQuestion 让用户选择检索类型**（唯一交互）：

```json
{
  "question": "请选择检索类型",
  "header": "检索类型",
  "options": [
    {"label": "简单检索", "description": "快速检索，无时间/期刊限制"},
    {"label": "高级检索", "description": "支持时间范围、核心期刊筛选"}
  ],
  "multiSelect": false
}
```

### 步骤2：询问检索参数
**不要使用AskUserQuestion工具，直接一次性询问所有参数**：
检索关键词、时间范围、来源类别（是否核心期刊）、爬取数量

### 步骤3：展示检索条件并执行

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 检索条件确认
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
检索类型: 高级检索
检索关键词: XXX
时间范围: 最近2年 (2024-2025)
来源类别: 仅核心期刊
爬取数量: 50 篇
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

正在开始检索...
```

### 步骤4：调用脚本并展示结果

根据检索条件调用对应脚本，完成后展示结果，并使用AskUserQuestion询问是否继续爬取剩余文献：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 爬取总结报告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
检索关键词: XXX
相关文献总数: 约 XXXX 篇
本次爬取: XX 篇
未爬取: XXXX 篇
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

```

---

# CNKI 操作流程

## 核心约束

1. **必须使用有头模式**：`--headed` 参数（无头模式会被检测）
2. **必须使用 session**：`--session` 参数启动会话
3. **元素 ref 动态变化**：每次操作前执行 `snapshot -i` 获取最新 ref
4. **翻页/设置必须用 click**：不能用 `eval` 点击（eval 往往无效）
5. **检索成功检测**：不要依赖 `wait --load networkidle`，改用 `sleep + snapshot + grep` 循环检测
6. **高级检索反爬处理**：必须先打开主站，再在新tab中打开高级检索页面（使用 `tab new` + `open`）
7. **高级检索元素定位**：snapshot 中 textbox 不显示 placeholder，需通过 `[nth=X]` 定位

## 元素定位参考（高级检索页面）

从快照中获取元素时，参考以下 ref 顺序（可能动态变化）：

```
- textbox [ref=e18]           # 第1个输入框（主题）
- textbox [ref=e19] [nth=1]   # 第2个输入框
- textbox [ref=e22] [nth=2]   # 第3个输入框
- textbox "起始年" [ref=e32]  # 起始年输入框
- textbox "结束年" [ref=e33]  # 结束年输入框
- checkbox "全部期刊" [ref=e35]    # 全部期刊
- checkbox "WJCI" [ref=e36]        # WJCI
- checkbox "SCI来源期刊" [ref=e37] # SCI
- checkbox "EI来源期刊" [ref=e38]  # EI
- checkbox "北大核心" [ref=e39]    # 北大核心
- checkbox "CSSCI" [ref=e40]       # CSSCI
- checkbox "CSCD" [ref=e41]        # CSCD
- checkbox "AMI" [ref=e42]         # AMI
- button "检索" [ref=e44]          # 检索按钮
```

**定位方法**：
- 主题输入框：`grep 'textbox \[ref=' | head -1` 或使用 nth=0
- 起始年：`grep 'textbox.*起始年'`
- 结束年：`grep 'textbox.*结束年'`
- 核心期刊：`grep 'checkbox.*"SCI"'` 等（注意用引号匹配 value）

## 检索流程（底层操作参考）

### 方式一：简单检索

#### 步骤1：启动浏览器

```bash
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net
```

#### 步骤2：获取元素 ref

```bash
npx agent-browser --session cnki --headed snapshot -i
```

#### 步骤3：输入关键词并检索

```bash
npx agent-browser --session cnki --headed fill @e16 "关键词"
npx agent-browser --session cnki --headed click @e17
```

#### 步骤4：检测检索是否成功

```bash
sleep 5
RETRY=0
while [ $RETRY -lt 3 ]; do
    sleep 3
    SNAPSHOT=$(npx agent-browser --session cnki --headed snapshot -i)
    if echo "$SNAPSHOT" | grep -q "共找到\|总库"; then
        echo "✓ 检索成功！"
        break
    fi
    RETRY=$((RETRY + 1))
    echo "   等待结果加载... ($RETRY/3)"
done
```

### 方式二：高级检索

**关键修复点**：
1. 先打开主站，再使用 `tab new` + `open` 在新tab中打开高级检索页面
2. 元素定位时注意 textbox 不显示 placeholder 属性
3. 起始年/结束年输入框的 placeholder 在快照中可见
4. 核心期刊需用 value 加引号匹配，如 `"SCI"`

**高级检索脚本**：`cnki-adv-search.sh`

## 自动化爬取脚本

脚本路径：`{baseDir}/.claude/skills/cnki-search-agent-browser/scripts/`

### 脚本参数

#### cnki-search.sh（简单检索）

```bash
cnki-search.sh <keyword> [count] [output_dir]
```

| 参数 | 说明 | 必填 | 默认值 |
|------|------|------|--------|
| `keyword` | 检索关键词 | 是 | - |
| `count` | 爬取数量 | 否 | 50 |
| `output_dir` | 输出目录 | 否 | outputs |

#### cnki-adv-search.sh（高级检索）

```bash
cnki-adv-search.sh <keyword> [options]
```

| 参数 | 说明 | 必填 | 默认值 |
|------|------|------|--------|
| `keyword` | 检索关键词 | 是 | - |
| `-s, --start` | 起始年份 | 否 | 最近3年 |
| `-e, --end` | 结束年份 | 否 | 最近3年 |
| `-c, --core` | 核心期刊标识 | 否 | 是 |
| `-n, --count` | 爬取数量 | 否 | 50 |
| `-o, --output` | 输出目录 | 否 | outputs |

**使用示例**：
```bash
# 简单检索（默认50篇）
bash scripts/cnki-search.sh "人工智能"

# 高级检索（默认最近3年核心期刊，50篇）
bash scripts/cnki-adv-search.sh "人工智能"

# 高级检索 - 自定义参数
bash scripts/cnki-adv-search.sh "人工智能" -s 2020 -e 2024 -c -n 50
```

### 依赖

- `jq`：JSON 处理工具
  - Windows (Git Bash): `scoop install jq` 或 `choco install jq`

## 错误排查

| 错误 | 原因 | 解决方法 |
|------|------|----------|
| 元素定位失败 | 页面未完全加载 | 增加等待时间，检查快照输出 |
| 无法找到输入框 | textbox 无 placeholder 属性 | 使用 nth 索引或 grep 第一个 textbox |
| 核心期刊未勾选 | grep 匹配不准确 | 使用 `"value"` 带引号匹配 |

## CSS 选择器参考

| 数据类型 | 选择器 |
|----------|--------|
| 论文标题 | `.name a` |
| 作者 | `td:nth-child(3)` |
| 来源 | `td:nth-child(4)` |
| 发表时间 | `td:nth-child(5)` |
