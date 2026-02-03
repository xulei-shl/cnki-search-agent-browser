#!/bin/bash
# CNKI 异常检测与处理工具函数
#
# 功能：
#   - 检测验证码/人机验证
#   - 检测异常弹窗
#   - 统一异常处理（保存截图、关闭会话、返回重试信号）
#
# 用法：
#   source "$SCRIPT_DIR/cnki-utils.sh"
#   detect_exception "$BASE_OPTS" && handle_exception "$SESSION" "验证码"

# 检测页面是否出现验证码/人机验证
# 参数: $1 - BASE_OPTS (agent-browser 基础选项)
# 返回: 0=检测到验证码, 1=未检测到
# 改进: 使用精确关键词 + DOM验证的多重检测机制
check_verification() {
    local BASE_OPTS="$1"
    local SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i 2>/dev/null)

    # 方案2: 使用更精确的验证码关键词（移除过于宽泛的"验证"）
    local VERIFICATION_KEYWORDS=""
    if echo "$SNAPSHOT" | grep -qiE "验证码|captcha|人机验证|请完成验证|slide.*verify|点击验证|完成下方验证|拖动滑块|点击图中"; then
        VERIFICATION_KEYWORDS="yes"
    fi

    # 方案3: DOM检测 - 检测验证码相关的DOM元素
    local DOM_VERIFICATION=""

    # 检测 reCAPTCHA 框架
    if npx agent-browser $BASE_OPTS eval '!!document.querySelector("iframe[src*=recaptcha], iframe[src*=captcha]")' 2>/dev/null | grep -q "true"; then
        DOM_VERIFICATION="recaptcha"
    fi

    # 检测滑块验证（更精确的选择器，匹配常见的滑块验证class/id）
    if npx agent-browser $BASE_OPTS eval '!!document.querySelector("[class*=slide-verify], [id*=slide-verify], [class*=slider-verify], [id*=slider-verify], [class*=captcha-slider], [id*=captcha-slider], .yidun_slider, .slider_mask")' 2>/dev/null | grep -q "true"; then
        DOM_VERIFICATION="slider"
    fi

    # 检测点选验证（更精确的选择器）
    if npx agent-browser $BASE_OPTS eval '!!document.querySelector("[class*=click-verify], [id*=click-verify], [class*=click-captcha], [id*=click-captcha], .yidun_click")' 2>/dev/null | grep -q "true"; then
        DOM_VERIFICATION="click"
    fi

    # 方案3: 多重验证机制 - 关键词和DOM元素同时存在才判定为验证码
    # 单独匹配关键词不够，必须有对应的DOM元素支持
    if [ -n "$VERIFICATION_KEYWORDS" ] && [ -n "$DOM_VERIFICATION" ]; then
        return 0  # 检测到验证码
    fi

    # 特殊情况: 如果检测到非常明确的验证码DOM元素，即使关键词不匹配也判定为验证码
    if [ -n "$DOM_VERIFICATION" ]; then
        return 0
    fi

    return 1  # 未检测到验证码
}

# 检测页面是否出现异常弹窗
# 参数: $1 - BASE_OPTS
# 返回: 0=检测到弹窗, 1=未检测到
# 改进: 使用精确关键词 + DOM验证的多重检测机制
check_popup() {
    local BASE_OPTS="$1"
    local SNAPSHOT=$(npx agent-browser $BASE_OPTS snapshot -i 2>/dev/null)

    # 方案2: 使用更精确的弹窗关键词（移除过于宽泛的"提示"、"error"等）
    local POPUP_KEYWORDS=""
    # 只匹配明确的弹窗/模态框相关词汇，需要同时包含弹窗上下文
    if echo "$SNAPSHOT" | grep -qiE "弹窗|弹出窗口|访问异常|系统繁忙|操作过于频繁|请求过于频繁|请稍后再试|风险检测|安全检测"; then
        POPUP_KEYWORDS="yes"
    fi

    # 方案3: DOM检测 - 检测弹窗相关的DOM元素（使用更精确的选择器）
    local DOM_POPUP=""

    # 检测可见的模态框/弹窗（必须是可见的）
    local POPUP_CHECK=$(npx agent-browser $BASE_OPTS eval '
        (() => {
            const modals = document.querySelectorAll("[role=dialog], [role=alertdialog], .modal, .dialog, .popup, [class*=modal], [class*=dialog]");
            for (let m of modals) {
                const style = window.getComputedStyle(m);
                if (style.display !== "none" && style.visibility !== "hidden" && style.opacity !== "0") {
                    return "true";
                }
            }
            return "false";
        })()
    ' 2>/dev/null)

    if [ "$POPUP_CHECK" = "true" ]; then
        DOM_POPUP="yes"
    fi

    # 方案3: 多重验证机制
    # 只有当关键词和DOM元素同时存在时才判定为异常弹窗
    # 或者检测到非常明确的异常关键词（访问异常、系统繁忙等）
    if [ -n "$POPUP_KEYWORDS" ]; then
        return 0  # 明确的异常关键词直接判定
    fi

    if [ -n "$POPUP_KEYWORDS" ] && [ -n "$DOM_POPUP" ]; then
        return 0  # 关键词 + DOM同时存在
    fi

    return 1  # 未检测到弹窗
}

# 综合异常检测
# 参数: $1 - BASE_OPTS
# 返回: 0=检测到异常, 1=无异常
# 输出: 异常类型描述
detect_exception() {
    local BASE_OPTS="$1"

    if check_verification "$BASE_OPTS"; then
        echo "验证码/人机验证"
        return 0
    fi

    if check_popup "$BASE_OPTS"; then
        echo "异常弹窗"
        return 0
    fi

    return 1
}

# 异常处理：关闭会话并返回重试信号
# 参数:
#   $1 - SESSION_NAME (会话名称)
#   $2 - ERROR_TYPE (异常类型描述)
#   $3 - OUTPUT_DIR (输出目录，用于保存截图)
# 返回: 退出码 42（重试信号码）
handle_exception() {
    local SESSION="$1"
    local ERROR_TYPE="$2"
    local OUTPUT_DIR="${3:-.}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  检测到异常: $ERROR_TYPE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 创建输出目录（如果不存在）
    mkdir -p "$OUTPUT_DIR"

    # 保存截图
    local SCREENSHOT_FILE="$OUTPUT_DIR/exception_$(date +%Y%m%d_%H%M%S).png"
    echo "📸 正在保存错误截图: $SCREENSHOT_FILE"
    npx agent-browser --session $SESSION --headed screenshot "$SCREENSHOT_FILE" 2>/dev/null || true

    echo "🔒 正在关闭会话..."
    npx agent-browser --session $SESSION close 2>/dev/null || true

    echo "🔄 将自动重试一次..."
    echo ""

    # 返回重试信号码 42
    exit 42
}
