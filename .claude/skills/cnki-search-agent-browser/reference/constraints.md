# CNKI 操作约束详解

> **重要性**：这些约束是 CNKI 网站反爬虫机制决定的，违反会导致操作失败。

## 完整约束列表

### 1. 必须使用有头模式

**约束**：必须使用 `--headed` 参数启动浏览器

**原因**：无头模式（headless）会被 CNKI 检测为爬虫，导致页面加载异常或直接拒绝访问

**正确示例**：
```bash
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net
```

**错误示例**：
```bash
# 无头模式会被检测
npx agent-browser --session cnki open https://chn.oversea.cnki.net
```

---

### 2. 必须使用 session

**约束**：必须使用 `--session` 参数启动会话

**原因**：
- 保持浏览器上下文（cookies、状态）在多次操作间持久化
- 避免重复打开浏览器导致资源浪费
- 支持延续爬取等复杂操作

**正确示例**：
```bash
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net
```

---

### 3. 元素 ref 动态变化

**约束**：每次操作前执行 `snapshot -i` 获取最新 ref

**原因**：agent-browser 每次执行 snapshot 都会重新分配元素引用（ref），之前获取的 ref 会失效

**正确做法**：
```bash
# 每次操作前重新获取 ref
npx agent-browser --session cnki --headed snapshot -i
# 然后使用最新的 ref 进行操作
npx agent-browser --session cnki --headed fill @e18 "关键词"
```

---

### 4. 翻页/设置必须用 click

**约束**：翻页和设置操作必须使用 `click` 命令，不能用 `eval`

**原因**：CNKI 页面的翻页按钮使用特殊的事件处理，JavaScript `eval` 点击往往无效

**正确示例**：
```bash
# 先获取 ref
npx agent-browser --session cnki --headed snapshot -i | grep '"2"'
# 使用 click 点击
npx agent-browser --session cnki --headed click @e270
```

**错误示例**：
```bash
# JavaScript 点击往往无效
npx agent-browser --session cnki --headed eval "document.querySelector('.pagesnums').click()"
```

---

### 5. 检索成功检测方法

**约束**：不要依赖 `wait --load networkidle`，改用 `sleep + snapshot + grep` 循环检测

**原因**：CNKI 检索结果页的网络请求复杂，`networkidle` 可能永远不触发或触发过早

**推荐模式**：
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

### 6. 高级检索反爬处理

**约束**：必须先打开主站，再在新 tab 中打开高级检索页面

**原因**：直接访问高级检索 URL 可能触发 CNKI 的反爬虫机制

**正确流程**：
```bash
# 步骤1：打开主站
npx agent-browser --session cnki --headed open https://chn.oversea.cnki.net

# 步骤2：创建新 tab
npx agent-browser --session cnki --headed tab new

# 步骤3：在新 tab 中打开高级检索
npx agent-browser --session cnki --headed open https://kns.cnki.net/kns8s/advancedsearch
```

**错误流程**：
```bash
# 直接访问高级检索可能被检测
npx agent-browser --session cnki --headed open https://kns.cnki.net/kns8s/advancedsearch
```

---

### 7. 高级检索元素定位

**约束**：snapshot 中 textbox 不显示 placeholder，需通过 `[nth=X]` 定位

**原因**：高级检索页面的输入框在 accessibility tree 中不暴露 placeholder 属性

**定位方法**：
```bash
# 第1个输入框（主题）
npx agent-browser --session cnki --headed snapshot -i | grep 'textbox \[ref=' | head -1

# 或使用 nth
npx agent-browser --session cnki --headed fill 'textbox[nth=0]' "关键词"

# 起始年（有 placeholder）
npx agent-browser --session cnki --headed snapshot -i | grep 'textbox.*起始年'
```

---

### 8. 核心期刊选择技巧

**约束**：使用引号包裹 value 精确匹配

**原因**：checkbox 的 value 可能包含空格或特殊字符，不带引号的 grep 可能匹配不准确

**正确示例**：
```bash
npx agent-browser --session cnki --headed snapshot -i | grep 'checkbox.*"SCI"'
```

**错误示例**：
```bash
# 可能匹配到其他内容
npx agent-browser --session cnki --headed snapshot -i | grep 'checkbox.*SCI'
```

---

## 违反约束的常见后果

| 违反行为 | 后果 |
|----------|------|
| 使用无头模式 | 页面加载异常、验证码触发 |
| 不使用 session | 无法延续爬取、资源浪费 |
| 使用过期的 ref | 元素定位失败 |
| 使用 eval 点击翻页 | 页面不跳转、内容不变 |
| 依赖 networkidle | 永久等待或过早返回 |
| 直接访问高级检索 | 反爬虫检测、页面加载失败 |

---

## 相关文档

- [手动操作参考](manual-operations.md) - 详细的操作步骤和调试技巧
- [故障排查指南](troubleshooting.md) - 常见错误及解决方案
