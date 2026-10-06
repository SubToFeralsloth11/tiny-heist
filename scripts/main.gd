extends Node
## Top-level flow: title -> heist -> result, plus pause and settings menus.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"throw": [KEY_Q],
	"pause": [KEY_ESCAPE, KEY_P],
}
const MOUSE_BUTTONS := {
	"throw": [MOUSE_BUTTON_RIGHT],
}

var _game: Game
var _ui: CanvasLayer
var _screen: Control


func _ready() -> void:
	register_inputs()
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	_show_title()


static func register_inputs() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for button: MouseButton in MOUSE_BUTTONS.get(action, []):
			var mb := InputEventMouseButton.new()
			mb.button_index = button
			InputMap.action_add_event(action, mb)


func _unhandled_input(event: InputEvent) -> void:
	if not _game or _game.over:
		return
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func start_game() -> void:
	_clear_game()
	_clear_screen()
	get_tree().paused = false
	_game = Game.new()
	_game.process_mode = Node.PROCESS_MODE_PAUSABLE
	_game.finished.connect(_on_finished)
	add_child(_game)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_game.hud.visible = not paused
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_show_pause()
	else:
		_clear_screen()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_finished(won: bool, stats: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_result(won, stats)


func _clear_game() -> void:
	if _game:
		_game.queue_free()
		_game = null


func _clear_screen() -> void:
	if _screen:
		_screen.queue_free()
		_screen = null


func _to_title() -> void:
	get_tree().paused = false
	_clear_game()
	_show_title()


# --- Screens ---

func _show_title() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box := _new_screen(Color(0.03, 0.03, 0.07, 1.0))
	_title(box, "TINY HEIST", 104, Color(1, 0.8, 0.25))
	_text(box, "Sneak into the museum. Grab the loot. Don't get caught.", 24)
	_text(box, "Dodge flashlights and cameras, find the keycard, crack the vault,\nhide in lockers, and throw coins to lure guards away.", 18, Color(0.75, 0.75, 0.8))
	if Settings.best_loot > 0:
		_text(box, "Best haul: $%d" % Settings.best_loot, 20, Color(0.5, 1, 0.5))
	_spacer(box)
	_button(box, "START HEIST", start_game, true)
	_button(box, "SETTINGS", _show_settings.bind(_show_title))
	_button(box, "QUIT", get_tree().quit)


func _show_pause() -> void:
	var box := _new_screen(Color(0.02, 0.02, 0.05, 0.85))
	_title(box, "PAUSED", 72, Color.WHITE)
	_button(box, "RESUME", _set_paused.bind(false), true)
	_button(box, "SETTINGS", _show_settings.bind(_show_pause))
	_button(box, "RESTART", start_game)
	_button(box, "MAIN MENU", _to_title)


func _show_settings(back: Callable) -> void:
	var opaque := _game == null
	var box := _new_screen(Color(0.03, 0.03, 0.07, 1.0 if opaque else 0.85))
	_title(box, "SETTINGS", 64, Color.WHITE)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	_slider_row(grid, "Mouse sensitivity", Settings.SENSITIVITY_MIN, Settings.SENSITIVITY_MAX, 0.01,
		Settings.mouse_sensitivity, "x",
		func(v: float) -> void: Settings.mouse_sensitivity = v)
	_slider_row(grid, "Field of view", 60.0, 100.0, 1.0, Settings.fov, "°",
		func(v: float) -> void: Settings.fov = v)
	_slider_row(grid, "Camera bob", 0.0, 100.0, 5.0, Settings.camera_bob * 100.0, "%",
		func(v: float) -> void: Settings.camera_bob = v / 100.0)
	var label := _text(grid, "Invert mouse Y", 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var check := CheckButton.new()
	check.button_pressed = Settings.invert_y
	check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	check.toggled.connect(func(on: bool) -> void:
		Settings.invert_y = on
		Settings.save())
	grid.add_child(check)
	grid.add_child(Control.new())
	_spacer(box)
	_button(box, "BACK", back, true)


func _show_result(won: bool, stats: Dictionary) -> void:
	var box := _new_screen(Color(0.02, 0.02, 0.05, 0.9))
	if won:
		_title(box, "YOU GOT AWAY!", 84, Color(0.4, 1, 0.5))
	else:
		_title(box, "BUSTED!", 104, Color(1, 0.25, 0.2))
		_text(box, "A guard caught you.", 24)
	var t: float = stats.time
	_text(box, "Loot: $%d of $%d      Time: %d:%02d      Times spotted: %d" % [
		stats.loot, stats.loot_total, int(t) / 60, int(t) % 60, stats.spotted], 22)
	if won:
		var stars := score_stars(true, stats.diamond, stats.spotted)
		var star_label := _title(box, "★".repeat(stars) + "☆".repeat(3 - stars), 72, Color(1, 0.85, 0.2))
		star_label.pivot_offset = Vector2(star_label.get_minimum_size().x * 0.5, 40)
		star_label.scale = Vector2.ZERO
		var tween := star_label.create_tween()
		tween.tween_interval(0.3)
		tween.tween_property(star_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_text(box, "%s Escape    %s Big Diamond    %s Never spotted" % [
			"★", "★" if stats.diamond else "☆", "★" if stats.spotted == 0 else "☆"], 18, Color(0.8, 0.8, 0.85))
		if stats.security_off:
			_text(box, "Bonus: you shut down security", 18, Color(0.5, 0.8, 1))
		if stats.loot >= Settings.best_loot:
			_text(box, "New best haul!", 22, Color(0.5, 1, 0.5))
	_spacer(box)
	_button(box, "PLAY AGAIN", start_game, true)
	_button(box, "MAIN MENU", _to_title)


static func score_stars(escaped: bool, diamond: bool, spotted: int) -> int:
	if not escaped:
		return 0
	return 1 + int(diamond) + int(spotted == 0)


# --- Widgets ---

func _new_screen(bg: Color) -> VBoxContainer:
	_clear_screen()
	var panel := ColorRect.new()
	panel.color = bg
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme = _theme()
	_ui.add_child(panel)
	_screen = panel
	panel.modulate.a = 0.0
	panel.create_tween().tween_property(panel, "modulate:a", 1.0, 0.2)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	return box


func _theme() -> Theme:
	var theme := Theme.new()
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.12, 0.18)
	normal.border_color = Color(1, 0.8, 0.25, 0.4)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.22, 0.2, 0.12)
	hover.border_color = Color(1, 0.8, 0.25)
	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.35, 0.28, 0.08)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", hover)
	theme.set_color("font_hover_color", "Button", Color(1, 0.85, 0.35))
	theme.set_color("font_focus_color", "Button", Color(1, 0.85, 0.35))
	return theme


func _title(box: Control, text: String, size: int, color: Color) -> Label:
	var l := _text(box, text, size, color)
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


func _text(box: Control, text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func _spacer(box: Control) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, 16)
	box.add_child(s)


## Slider plus a linked SpinBox so the exact value can also be typed in.
func _slider_row(grid: GridContainer, name: String, lo: float, hi: float, step: float,
		value: float, suffix: String, apply: Callable) -> void:
	var label := _text(grid, name, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var slider := HSlider.new()
	var spin := SpinBox.new()
	for r: Range in [slider, spin]:
		r.min_value = lo
		r.max_value = hi
		r.step = step
		r.value = value
	# Link both to one shared value so dragging and typing stay in sync.
	slider.share(spin)
	slider.custom_minimum_size = Vector2(320, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(slider)
	spin.suffix = suffix
	spin.select_all_on_focus = true
	spin.custom_minimum_size.x = 120
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := spin.get_line_edit()
	line.add_theme_font_size_override("font_size", 22)
	line.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	line.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(spin)
	slider.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		Settings.save())


func _button(box: Control, text: String, action: Callable, focus := false) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 54)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(action)
	# Small grow on hover.
	b.mouse_entered.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.05, 0.08))
	b.mouse_exited.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.08))
	var holder := CenterContainer.new()
	holder.add_child(b)
	box.add_child(holder)
	if focus:
		b.call_deferred("grab_focus")
