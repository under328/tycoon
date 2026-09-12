## 多设备自适应布局助手: PC / 手机 / 平板横屏统一适配。
## 拉伸模式 canvas_items+expand(设计分辨率 1280x720)下, 逻辑视口恒有 宽>=1280、高>=720:
##   4:3 平板横屏 = 1280x960(多高度) · 20:9 手机横屏 = 1600x720(多宽度) · PC = 任意窗形。
## 因此布局不按设备型号分支, 只按几何锚定:
##   左栏固定 · 中栏随多余宽度按比例右移 · 右栏锚住右缘 · 底部内容锚住底缘。
extends RefCounted


## 触控设备(安卓/iOS 及其 Web 导出): 按钮热区下限 44px
static func is_touch() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") \
			or OS.has_feature("web_ios")


## 控件尺寸变化(窗口缩放/安全区收缩)时触发重排; 首帧延迟执行一次。
## 用法: Responsive.watch(self, _relayout)
static func watch(c: Control, fn: Callable) -> void:
	c.resized.connect(fn)
	fn.call_deferred()
