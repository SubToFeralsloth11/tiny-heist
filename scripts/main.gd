extends Node
## Top-level flow: title screen -> heist -> result screen, plus the pause menu.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"pause": [KEY_ESCAPE, KEY_P],
}

var _game: Game
var _ui: CanvasLayer
var _screen: Control


func _ready() -> void:
	_register_inputs()
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	_show_title()


func _register_inputs() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


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


func _show_title() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box := _new_screen(Color(0.03, 0.03, 0.07, 1.0))
	_title(box, "TINY HEIST", 96, Color(1, 0.8, 0.25))
	_text(box, "Sneak into the museum. Grab the loot. Don't get caught.", 24)
	_text(box, "Guards with flashlights patrol the halls. Stay out of their light,\nsneak to stay quiet, and time your run through the laser door.", 18, Color(0.75, 0.75, 0.8))
	_spacer(box)
	_button(box, "START HEIST", start_game)
	_button(box, "QUIT", get_tree().quit)


func _show_pause() -> void:
	var box := _new_screen(Color(0, 0, 0, 0.6))
	_title(box, "PAUSED", 72, Color.WHITE)
	_button(box, "RESUME", _set_paused.bind(false))
	_button(box, "RESTART", start_game)
	_button(box, "MAIN MENU", func() -> void:
		get_tree().paused = false
		_clear_game()
		_show_title())


func _show_result(won: bool, stats: Dictionary) -> void:
	var box := _new_screen(Color(0, 0, 0, 0.75))
	if won:
		_title(box, "YOU GOT AWAY!", 80, Color(0.4, 1, 0.5))
	else:
		_title(box, "BUSTED!", 96, Color(1, 0.25, 0.2))
		_text(box, "A guard caught you.", 24)
	var t: float = stats.time
	_text(box, "Loot: $%d of $%d      Time: %d:%02d      Times spotted: %d" % [
		stats.loot, stats.loot_total, int(t) / 60, int(t) % 60, stats.spotted], 24)
	if won:
		var stars := score_stars(true, stats.diamond, stats.spotted)
		_title(box, "★".repeat(stars) + "☆".repeat(3 - stars), 64, Color(1, 0.85, 0.2))
		_text(box, "★ Escape   ★ Steal the Big Diamond   ★ Never get spotted", 18, Color(0.75, 0.75, 0.8))
	_spacer(box)
	_button(box, "PLAY AGAIN", start_game)
	_button(box, "MAIN MENU", func() -> void:
		_clear_game()
		_show_title())


static func score_stars(escaped: bool, diamond: bool, spotted: int) -> int:
	if not escaped:
		return 0
	return 1 + int(diamond) + int(spotted == 0)


func _new_screen(bg: Color) -> VBoxContainer:
	_clear_screen()
	var panel := ColorRect.new()
	panel.color = bg
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(panel)
	_screen = panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	return box


func _title(box: VBoxContainer, text: String, size: int, color: Color) -> void:
	var l := _text(box, text, size, color)
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_outline_color", Color.BLACK)


func _text(box: VBoxContainer, text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func _spacer(box: VBoxContainer) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, 20)
	box.add_child(s)


func _button(box: VBoxContainer, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 56)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(action)
	var holder := CenterContainer.new()
	holder.add_child(b)
	box.add_child(holder)
