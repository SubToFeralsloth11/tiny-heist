extends Node
## Player preferences, saved to user://settings.cfg. Autoloaded as `Settings`.

signal changed

const PATH := "user://settings.cfg"

## Multiplier on the base mouse look speed (0.1 – 3.0).
var mouse_sensitivity := 1.0
var invert_y := false
var fov := 75.0
## 0 = no camera bob/tilt (for motion sickness), 1 = full.
var camera_bob := 1.0
## Best haul ever escaped with, shown on the title screen.
var best_loot := 0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = clampf(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity), 0.1, 3.0)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	fov = clampf(cfg.get_value("video", "fov", fov), 60.0, 100.0)
	camera_bob = clampf(cfg.get_value("video", "camera_bob", camera_bob), 0.0, 1.0)
	best_loot = cfg.get_value("stats", "best_loot", best_loot)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "camera_bob", camera_bob)
	cfg.set_value("stats", "best_loot", best_loot)
	cfg.save(PATH)
	changed.emit()
