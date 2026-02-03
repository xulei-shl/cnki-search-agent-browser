# CNKI 技能故障排查指南

> **快速索引**：根据错误类型快速定位解决方案。

## 常见错误速查表

| 错误现象 | 可能原因 | 解决方法 |
|----------|----------|----------|
| 元素定位失败 | 页面未完全加载 | 增加等待时间，检查快照输出 |
| 无法找到输入框 | textbox 无 placeholder 属性 | 使用 nth 索引或 grep 第一个 textbox |
| 核心期刊未勾选 | grep 匹配不准确 | 使用 `"value"` 带引号匹配 |
| 检索无结果 | 关键词格式问题 | 检查关键词是否包含特殊字符 |
| 浏览器启动失败 | agent-browser 未安装 | `npm install -g agent-browser` |
| jq 命令不存在 | jq 未安装 | 参考下方 [依赖安装](#依赖安装) |

---

## 按错误类型排查

### 1. 浏览器相关问题

#### 错误：`npx: command not found` 或 `agent-browser: command not found`

**原因**：Node.js 或 agent-browser 未正确安装

**解决方案**：
```bash
# 安装 Node.js (如果尚未安装)
# 访问 https://nodejs.org 下载安装

# 全局安装 agent-browser
npm install -g agent-browser

# 验证安装
agent-browser --version
```

---

#### 错误：浏览器启动但立即关闭

**原因**：可能是无头模式被 CNKI 检测

**解决方案**：确保使用 `--headed` 参数
```bash
# 正确
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net

# 错误（会被检测）
npx agent-browser --session cnki open https://chn.oversea.cnki.net
```

---

### 2. 元素定位问题

#### 错误：`Element not found: @eXX`

**原因**：元素 ref 动态变化，每次 snapshot 后都会重新分配

**解决方案**：每次操作前重新获取 ref
```bash
# 步骤1：获取最新 ref
npx agent-browser --session cnki --headed snapshot -i

# 步骤2：从输出中找到需要的 ref
npx agent-browser --session cnki --headed snapshot -i | grep "textbox"

# 步骤3：使用最新的 ref 操作
npx agent-browser --session cnki --headed fill @e18 "关键词"
```

---

#### 错误：高级检索页面无法找到输入框

**原因**：高级检索页面的 textbox 不显示 placeholder 属性

**解决方案**：使用 nth 索引定位
```bash
# 第1个输入框（主题）
npx agent-browser --session cnki --headed snapshot -i | grep 'textbox \[ref=' | head -1

# 或者使用 nth
npx agent-browser --session cnki --headed fill 'textbox[nth=0]' "关键词"
```

---

### 3. 翻页操作问题

#### 错误：翻页后内容不变

**原因**：使用 JavaScript `eval` 点击翻页按钮往往无效

**解决方案**：使用 `snapshot + click` 方式
```bash
# 正确方式
npx agent-browser --session cnki --headed snapshot -i | grep '"2"'
npx agent-browser --session cnki --headed click @e270

# 错误方式（无效）
npx agent-browser --session cnki --headed eval "document.querySelector('.pagesnums').click()"
```

---

### 4. 检索结果问题

#### 错误：检索一直等待，无结果返回

**原因**：`wait --load networkidle` 对 CNKI 可能不可靠

**解决方案**：使用 `sleep + snapshot + grep` 循环检测
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

---

### 5. 高级检索特定问题

#### 错误：高级检索页面被检测或加载失败

**原因**：直接访问高级检索 URL 可能触发反爬虫

**解决方案**：先打开主站，再在新 tab 中打开高级检索
```bash
# 步骤1：打开主站
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net

# 步骤2：创建新 tab 并打开高级检索
npx agent-browser --session cnki --headed tab new
npx agent-browser --session cnki --headed open https://kns.cnki.net/kns8s/advancedsearch
```

---

### 6. 核心期刊选择问题

#### 错误：核心期刊复选框未勾选成功

**原因**：grep 匹配不准确，value 可能包含空格或特殊字符

**解决方案**：使用引号包裹 value 精确匹配
```bash
# 正确（带引号）
npx agent-browser --session cnki --headed snapshot -i | grep 'checkbox.*"SCI"'

# 错误（可能匹配到其他内容）
npx agent-browser --session cnki --headed snapshot -i | grep 'checkbox.*SCI'
```

---

## 依赖安装

### jq - JSON 处理工具

**检查是否已安装**：
```bash
jq --version
```

**安装方式**：

| 平台 | 命令 |
|------|------|
| Windows (Scoop) | `scoop install jq` |
| Windows (Chocolatey) | `choco install jq` |
| macOS (Homebrew) | `brew install jq` |
| Linux (apt) | `sudo apt install jq` |
| Linux (yum) | `sudo yum install jq` |

---

## 调试技巧

### 1. 截屏调试

```bash
# 保存当前页面截图
npx agent-browser --session cnki --headed screenshot cnki-debug.png
```

### 2. 查看 URL

```bash
# 检查当前页面 URL
npx agent-browser --session cnki --headed get url
```

### 3. 检查元素状态

```bash
# 检查元素是否可见
npx agent-browser --session cnki --headed is visible @e100

# 检查元素是否可点击
npx agent-browser --session cnki --headed is enabled @e100
```

### 4. 查看控制台日志

```bash
# 查看浏览器控制台输出
npx agent-browser --session cnki --headed console

# 查看页面 JavaScript 错误
npx agent-browser --session cnki --headed errors
```

---

## 仍然无法解决？

如果以上方法都无法解决您的问题：

1. 记录完整的错误信息
2. 保存页面截图
3. 检查 [手动操作参考](manual-operations.md) 中的相关内容
4. 确认 CNKI 网站是否可正常访问
