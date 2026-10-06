class_name Game
extends Node3D
## One heist attempt: builds the museum, player, guards and HUD, and decides win/lose.

signal finished(won: bool, stats: Dictionary)

const QUOTA := 4000
const ALARM_TIME := 8.0

var level: Level
var player: Player
var guards: Array[Guard] = []
var hud: Hud

var loot_value := 0
var has_diamond := false
var times_spotted := 0
var elapsed := 0.0

var _alarm := 0.0
var over := false
var _alarm_light: OmniLight3D


func _ready() -> void:
	_build_environment()
	level = Level.new()
	add_child(level)

	player = Player.new()
	add_child(player)
	player.global_position = level.player_start
	player.rotation.y = PI * 0.5  # Face east, into the museum.
	player.noise_made.connect(_on_noise)
	player.loot_grabbed.connect(_on_loot_grabbed)

	for route in Level.PATROLS:
		var g := Guard.new()
		g.level = level
		g.player = player
		g.patrol = route
		add_child(g)
		g.caught_player.connect(_on_caught)
		g.spotted_player.connect(_on_spotted)
		guards.append(g)

	for node in level.get_children():
		if node is LaserDoor:
			node.tripped.connect(_on_laser_tripped)
	level.get_node("ExitZone").body_entered.connect(_on_exit_entered)

	_alarm_light = OmniLight3D.new()
	_alarm_light.light_color = Color(1, 0, 0)
	_alarm_light.omni_range = 12.0
	_alarm_light.visible = false
	player.add_child(_alarm_light)
	_alarm_light.position.y = 2.5

	hud = Hud.new()
	add_child(hud)
	hud.set_loot(0, QUOTA)
	hud.flash_message("Steal at least $%d, then get back to the van!" % QUOTA, 5.0)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.45)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.05, 0.1)
	env.fog_density = 0.01
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _process(delta: float) -> void:
	if over:
		return
	elapsed += delta
	var max_suspicion := 0.0
	var chased := false
	for g in guards:
		max_suspicion = maxf(max_suspicion, g.suspicion)
		chased = chased or g.state == Guard.State.CHASE
	hud.set_detection(max_suspicion, chased)
	hud.set_time(elapsed)
	var aimed := player.aimed_loot()
	hud.set_prompt(aimed.prompt_text() if aimed else "")

	if _alarm > 0.0:
		_alarm -= delta
		_alarm_light.visible = _alarm > 0.0
		_alarm_light.light_energy = 2.0 + sin(elapsed * 14.0) * 1.5
	hud.set_alarm(_alarm > 0.0)


func _on_noise(pos: Vector3, radius: float) -> void:
	for g in guards:
		if g.global_position.distance_to(pos) <= radius:
			g.hear(pos)


func _on_loot_grabbed(loot: Loot) -> void:
	loot_value += loot.value
	if loot.kind == "V":
		has_diamond = true
		hud.flash_message("THE BIG DIAMOND! Get out of here!", 3.0)
	elif loot_value >= QUOTA and loot_value - loot.value < QUOTA:
		hud.flash_message("Quota reached! Head back to the van (or get greedy).", 4.0)
	hud.set_loot(loot_value, QUOTA)


func _on_laser_tripped() -> void:
	_alarm = ALARM_TIME
	times_spotted += 1
	hud.flash_message("ALARM! The guards are coming!", 3.0)
	for g in guards:
		g.alert_to(player.global_position)


func _on_spotted() -> void:
	times_spotted += 1


func _on_caught() -> void:
	_end(false)


func _on_exit_entered(body: Node3D) -> void:
	if over or body != player:
		return
	if loot_value >= QUOTA:
		_end(true)
	elif elapsed > 3.0:
		hud.flash_message("Not enough loot yet! You need $%d." % QUOTA, 3.0)


func _end(won: bool) -> void:
	over = true
	player.controls_enabled = false
	for g in guards:
		g.set_physics_process(false)
	finished.emit(won, {
		"loot": loot_value,
		"loot_total": level.loot_total,
		"time": elapsed,
		"diamond": has_diamond,
		"spotted": times_spotted,
	})
