class_name Hud
extends CanvasLayer
## In-game overlay: loot counter, detection meter, timer, interact prompt, messages.

var _loot_label: Label
var _time_label: Label
var _detect_bar: ProgressBar
var _detect_label: Label
var _detect_fill := StyleBoxFlat.new()
var _prompt: Label
var _message: Label
var _alarm_overlay: ColorRect
var _message_time := 0.0
var _clock := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_alarm_overlay = ColorRect.new()
	_alarm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_alarm_overlay.color = Color(1, 0, 0, 0)
	_alarm_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_alarm_overlay)

	_loot_label = _label(root, 30, Vector2(0, 0), Rect2(24, 18, 700, 44))

	_time_label = _label(root, 26, Vector2(1, 0), Rect2(-224, 18, 200, 40))
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_detect_label = _label(root, 20, Vector2(0.5, 0), Rect2(-150, 12, 300, 30))
	_detect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detect_bar = ProgressBar.new()
	_place(_detect_bar, Vector2(0.5, 0), Rect2(-150, 44, 300, 14))
	_detect_bar.max_value = 1.0
	_detect_bar.show_percentage = false
	_detect_bar.add_theme_stylebox_override("fill", _detect_fill)
	root.add_child(_detect_bar)

	var crosshair := ColorRect.new()
	_place(crosshair, Vector2(0.5, 0.5), Rect2(-3, -3, 6, 6))
	crosshair.color = Color(1, 1, 1, 0.8)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	_prompt = _label(root, 26, Vector2(0.5, 0.5), Rect2(-300, 40, 600, 40))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.modulate = Color(1, 0.9, 0.4)

	_message = _label(root, 30, Vector2(0.5, 1), Rect2(-450, -150, 900, 50))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var help := _label(root, 16, Vector2(0, 1), Rect2(24, -40, 900, 30))
	help.modulate = Color(1, 1, 1, 0.55)
	help.text = "WASD move   Shift sprint (loud)   Ctrl/C sneak   Space jump   E grab   Esc pause"


## Pins a control to an anchor point (0..1 of the screen) with a pixel rect relative to it.
func _place(c: Control, anchor: Vector2, rect: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.end.x
	c.offset_bottom = rect.end.y


func _label(parent: Control, font_size: int, anchor: Vector2, rect: Rect2) -> Label:
	var l := Label.new()
	_place(l, anchor, rect)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	_clock += delta
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time, 0.0, 1.0)


func set_loot(value: int, quota: int) -> void:
	_loot_label.text = "LOOT  $%d / $%d" % [value, quota]
	_loot_label.modulate = Color(0.5, 1, 0.5) if value >= quota else Color.WHITE


func set_time(t: float) -> void:
	_time_label.text = "%d:%02d" % [int(t) / 60, int(t) % 60]


func set_detection(amount: float, chased: bool) -> void:
	_detect_bar.value = amount
	if chased:
		_detect_label.text = "SPOTTED! RUN!"
		_detect_fill.bg_color = Color(1, 0.15, 0.1)
	elif amount > 0.05:
		_detect_label.text = "SUSPICIOUS..."
		_detect_fill.bg_color = Color(1, 0.8, 0.1).lerp(Color(1, 0.4, 0.1), amount)
	else:
		_detect_label.text = "HIDDEN"
		_detect_fill.bg_color = Color(0.4, 0.8, 1)
	_detect_label.modulate = _detect_fill.bg_color


func set_prompt(text: String) -> void:
	_prompt.text = text


func set_alarm(on: bool) -> void:
	_alarm_overlay.color.a = (0.12 + sin(_clock * 12.0) * 0.08) if on else 0.0


func flash_message(text: String, seconds: float) -> void:
	_message.text = text
	_message_time = seconds
	_message.modulate.a = 1.0
