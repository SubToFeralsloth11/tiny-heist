class_name Hud
extends CanvasLayer
## In-game overlay. Built from containers in fixed columns/rows so nothing overlaps:
##   top-left: loot + objectives   top-centre: detection   top-right: timer + inventory
##   centre: crosshair, prompt, hold bar   bottom: message line, controls line

const SIDE_WIDTH := 320

var _loot_label: Label
var _objective_box: VBoxContainer
var _time_label: Label
var _coin_label: Label
var _key_label: Label
var _detect_bar: ProgressBar
var _detect_label: Label
var _detect_fill := StyleBoxFlat.new()
var _prompt: Label
var _hold_bar: ProgressBar
var _message: Label
var _alarm_overlay: ColorRect
var _vents: Control
var _crosshair: ColorRect
var _message_time := 0.0
var _clock := 0.0
var _loot_shown := 0.0
var _loot_target := 0
var _loot_quota := 0


func _ready() -> void:
	layer = 1
	var root := _full_rect(Control.new())
	add_child(root)

	_alarm_overlay = _full_rect(ColorRect.new())
	_alarm_overlay.color = Color(1, 0, 0, 0)
	root.add_child(_alarm_overlay)

	_vents = _full_rect(Control.new())
	_vents.visible = false
	_vents.draw.connect(_draw_vents)
	_vents.resized.connect(_vents.queue_redraw)
	root.add_child(_vents)

	# --- Top bar: three columns ---
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_margins(top, 20, 14, 20, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)

	var left := _panel_column(row, SIDE_WIDTH)
	_loot_label = _label(left, 28)
	_objective_box = VBoxContainer.new()
	_objective_box.add_theme_constant_override("separation", 2)
	left.add_child(_objective_box)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_BEGIN
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(center)
	_detect_label = _label(center, 20)
	_detect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detect_bar = _bar(_detect_fill)
	_detect_bar.custom_minimum_size = Vector2(260, 12)
	_detect_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(_detect_bar)

	var right := _panel_column(row, SIDE_WIDTH)
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	_time_label = _label(right, 28)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coin_label = _label(right, 18)
	_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_key_label = _label(right, 18)
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_key_label.modulate = Color(0.4, 0.75, 1.0)
	_key_label.text = "Keycard"

	# --- Centre: crosshair, then prompt + hold bar directly below it ---
	_crosshair = ColorRect.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -3
	_crosshair.offset_top = -3
	_crosshair.offset_right = 3
	_crosshair.offset_bottom = 3
	_crosshair.color = Color(1, 1, 1, 0.85)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)

	var mid := VBoxContainer.new()
	mid.anchor_left = 0.5
	mid.anchor_right = 0.5
	mid.anchor_top = 0.5
	mid.anchor_bottom = 0.5
	mid.offset_left = -320
	mid.offset_right = 320
	mid.offset_top = 28
	mid.offset_bottom = 110
	mid.add_theme_constant_override("separation", 6)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	_prompt = _label(mid, 24)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.modulate = Color(1, 0.9, 0.45)
	var hold_fill := StyleBoxFlat.new()
	hold_fill.bg_color = Color(0.3, 1, 0.5)
	_hold_bar = _bar(hold_fill)
	_hold_bar.custom_minimum_size = Vector2(240, 10)
	_hold_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hold_bar.visible = false
	mid.add_child(_hold_bar)

	# --- Bottom: message above the controls line ---
	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_margins(bottom, 20, 0, 20, 12)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 8)
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bottom_box)
	_message = _label(bottom_box, 28)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var help := _label(bottom_box, 15)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.5)
	help.text = "WASD move · Shift sprint (loud) · Ctrl/C sneak · Space jump · E use · Q / right-click throw coin · Esc pause"


func _full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _margins(m: MarginContainer, l: int, t: int, r: int, b: int) -> void:
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)


## Side column with a soft dark backing so text reads over bright rooms.
func _panel_column(row: HBoxContainer, width: int) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	bg.set_corner_radius_all(8)
	bg.content_margin_left = 12
	bg.content_margin_right = 12
	bg.content_margin_top = 6
	bg.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", bg)
	row.add_child(panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	return col


func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(fill: StyleBoxFlat) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _process(delta: float) -> void:
	_clock += delta
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time * 2.0, 0.0, 1.0)
	# Loot counter rolls up instead of jumping.
	if absf(_loot_shown - _loot_target) > 0.5:
		_loot_shown = move_toward(_loot_shown, _loot_target, maxf(absf(_loot_target - _loot_shown) * delta * 6.0, 20.0))
		_update_loot_text()


func set_loot(value: int, quota: int) -> void:
	_loot_target = value
	_loot_quota = quota
	_update_loot_text()
	if value > 0:
		_loot_label.pivot_offset = _loot_label.size * 0.5
		var tween := create_tween()
		tween.tween_property(_loot_label, "scale", Vector2.ONE * 1.15, 0.08)
		tween.tween_property(_loot_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)


func _update_loot_text() -> void:
	_loot_label.text = "$%d / $%d" % [roundi(_loot_shown), _loot_quota]
	_loot_label.modulate = Color(0.5, 1, 0.5) if _loot_target >= _loot_quota else Color(1, 0.9, 0.5)


func set_objectives(list: Array[Dictionary]) -> void:
	for child in _objective_box.get_children():
		child.queue_free()
	for o in list:
		var l := _label(_objective_box, 16)
		var mark := "✔" if o.done else ("○" if o.optional else "■")
		l.text = "%s %s%s" % [mark, o.text, "  (bonus)" if o.optional else ""]
		if o.done:
			l.modulate = Color(0.55, 1, 0.55)
		elif o.optional:
			l.modulate = Color(0.8, 0.8, 0.85)


func set_time(t: float) -> void:
	_time_label.text = "%d:%02d" % [int(t) / 60, int(t) % 60]


func set_inventory(coins: int, keycard: bool) -> void:
	_coin_label.text = "Coins: %d" % coins
	_coin_label.modulate = Color(1, 0.85, 0.4) if coins > 0 else Color(0.6, 0.6, 0.6)
	_key_label.visible = keycard


func set_detection(amount: float, chased: bool, hidden: bool) -> void:
	_detect_bar.value = lerpf(_detect_bar.value, amount, 0.25)
	if chased:
		_detect_label.text = "SPOTTED! RUN!"
		_detect_fill.bg_color = Color(1, 0.15, 0.1)
	elif hidden:
		_detect_label.text = "HIDING"
		_detect_fill.bg_color = Color(0.5, 0.5, 0.6)
	elif amount > 0.05:
		_detect_label.text = "SUSPICIOUS..."
		_detect_fill.bg_color = Color(1, 0.8, 0.1).lerp(Color(1, 0.4, 0.1), amount)
	else:
		_detect_label.text = "HIDDEN"
		_detect_fill.bg_color = Color(0.4, 0.8, 1)
	_detect_label.modulate = _detect_fill.bg_color
	if chased:
		_detect_label.scale = Vector2.ONE * (1.0 + sin(_clock * 12.0) * 0.06)
		_detect_label.pivot_offset = _detect_label.size * 0.5
	else:
		_detect_label.scale = Vector2.ONE


func set_prompt(text: String) -> void:
	_prompt.text = text


func set_hold(progress: float) -> void:
	_hold_bar.visible = progress >= 0.0
	_hold_bar.value = maxf(progress, 0.0)


func set_hiding(hiding: bool) -> void:
	_vents.visible = hiding
	_crosshair.visible = not hiding


func set_alarm(on: bool) -> void:
	_alarm_overlay.color.a = (0.12 + sin(_clock * 12.0) * 0.08) if on else 0.0


func flash_message(text: String, seconds: float) -> void:
	_message.text = text
	_message_time = seconds
	_message.modulate.a = 1.0


## Dark locker interior with horizontal vent slits to peek through.
func _draw_vents() -> void:
	var s := _vents.size
	var slit_top := s.y * 0.38
	var slit_h := s.y * 0.045
	var gap := s.y * 0.03
	var count := 4
	var bottom := slit_top + count * (slit_h + gap)
	var dark := Color(0.02, 0.02, 0.03, 0.97)
	_vents.draw_rect(Rect2(0, 0, s.x, slit_top), dark)
	_vents.draw_rect(Rect2(0, bottom, s.x, s.y - bottom), dark)
	for i in count:
		var y := slit_top + i * (slit_h + gap) + slit_h
		_vents.draw_rect(Rect2(0, y, s.x, gap), dark)
	# Slits are narrower than the screen.
	_vents.draw_rect(Rect2(0, slit_top, s.x * 0.2, bottom - slit_top), dark)
	_vents.draw_rect(Rect2(s.x * 0.8, slit_top, s.x * 0.2, bottom - slit_top), dark)
