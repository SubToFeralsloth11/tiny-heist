class_name Game
extends Node3D
## One heist attempt: builds the museum, player, guards and HUD, tracks objectives, decides win/lose.

signal finished(won: bool, stats: Dictionary)

const QUOTA := 6000
const ALARM_TIME := 8.0

var level: Level
var player: Player
var guards: Array[Guard] = []
var hud: Hud

var loot_value := 0
var has_diamond := false
var security_off := false
var vault_open := false
var times_spotted := 0
var elapsed := 0.0
var over := false

var _alarm := 0.0
var _alarm_light: OmniLight3D


func _ready() -> void:
	_build_environment()
	level = Level.new()
	add_child(level)

	player = Player.new()
	add_child(player)
	player.global_position = level.player_start
	player.rotation.y = 0.0  # Face north, toward the main corridor.
	player.noise_made.connect(_on_noise)
	player.loot_grabbed.connect(_on_loot_grabbed)
	player.item_collected.connect(_on_item_collected)
	player.coin_thrown.connect(func(coin: Coin) -> void: coin.clinked.connect(_on_coin_clinked))

	for route in Level.PATROLS:
		var g := Guard.new()
		g.level = level
		g.player = player
		g.patrol = route
		add_child(g)
		g.caught_player.connect(_on_caught)
		g.spotted_player.connect(_on_spotted)
		guards.append(g)

	for laser in level.lasers:
		laser.tripped.connect(_raise_alarm.bind("Laser tripped! The guards are coming!"))
	for cam in level.cameras:
		cam.player = player
		cam.spotted.connect(_raise_alarm.bind("A camera spotted you! The guards are coming!"))
	for door in level.vault_doors:
		door.opened.connect(_on_vault_opened)
	for item in level.interactables:
		if item is SecurityPanel:
			item.hacked.connect(_on_security_hacked)
	level.get_node("ExitZone").body_entered.connect(_on_exit_entered)

	_alarm_light = OmniLight3D.new()
	_alarm_light.light_color = Color(1, 0, 0)
	_alarm_light.omni_range = 12.0
	_alarm_light.visible = false
	player.add_child(_alarm_light)
	_alarm_light.position.y = 2.5

	hud = Hud.new()
	add_child(hud)
	_refresh_hud()
	hud.flash_message("Steal $%d and get back to the van. The Big Diamond is in the vault..." % QUOTA, 6.0)


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
	env.ssao_enabled = true
	env.ssao_intensity = 1.5
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
	for cam in level.cameras:
		max_suspicion = maxf(max_suspicion, cam.suspicion)
	hud.set_detection(max_suspicion, chased, player.hiding_in != null)
	hud.set_time(elapsed)
	var aimed := player.aimed_interactable()
	hud.set_prompt(aimed.prompt_text(player) if aimed else "")
	hud.set_hold(player.hold_progress)
	hud.set_hiding(player.hiding_in != null)
	hud.set_inventory(player.coins, player.has_keycard)

	if _alarm > 0.0:
		_alarm -= delta
		_alarm_light.visible = _alarm > 0.0
		_alarm_light.light_energy = 2.0 + sin(elapsed * 14.0) * 1.5
	hud.set_alarm(_alarm > 0.0)


func objectives() -> Array[Dictionary]:
	return [
		{"text": "Steal $%d" % QUOTA, "done": loot_value >= QUOTA, "optional": false},
		{"text": "Escape in the van", "done": false, "optional": false},
		{"text": "Get into the vault", "done": vault_open or has_diamond, "optional": true},
		{"text": "Steal the Big Diamond", "done": has_diamond, "optional": true},
		{"text": "Shut down security", "done": security_off, "optional": true},
		{"text": "Never get spotted", "done": times_spotted == 0, "optional": true},
	]


func _refresh_hud() -> void:
	hud.set_loot(loot_value, QUOTA)
	hud.set_objectives(objectives())


func _on_noise(pos: Vector3, radius: float) -> void:
	for g in guards:
		if g.global_position.distance_to(pos) <= radius:
			g.hear(pos)


func _on_coin_clinked(pos: Vector3) -> void:
	_on_noise(pos, Coin.NOISE_RADIUS)


func _on_loot_grabbed(loot: Loot) -> void:
	loot_value += loot.value
	if loot.kind == "V":
		has_diamond = true
		hud.flash_message("THE BIG DIAMOND! Get out of here!", 3.0)
	elif loot_value >= QUOTA and loot_value - loot.value < QUOTA:
		hud.flash_message("Quota reached! Head to the van, or get greedy.", 4.0)
	else:
		hud.flash_message("+$%d  %s" % [loot.value, loot.display_name], 1.5)
	_refresh_hud()


func _on_item_collected(item: Interactable) -> void:
	if item is Keycard:
		hud.flash_message("Got the keycard! The vault door is south of the vault room.", 4.0)
	_refresh_hud()


func _on_vault_opened() -> void:
	vault_open = true
	hud.flash_message("Vault door open!", 2.5)
	_refresh_hud()


func _on_security_hacked() -> void:
	security_off = true
	for cam in level.cameras:
		cam.disable()
	for laser in level.lasers:
		laser.power_off()
	hud.flash_message("Security offline: cameras and lasers are down!", 4.0)
	_refresh_hud()


func _raise_alarm(message: String) -> void:
	_alarm = ALARM_TIME
	times_spotted += 1
	hud.flash_message(message, 3.0)
	for g in guards:
		g.alert_to(player.global_position)
	_refresh_hud()


func _on_spotted() -> void:
	times_spotted += 1
	_refresh_hud()


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
	hud.visible = false
	if won and loot_value > Settings.best_loot:
		Settings.best_loot = loot_value
		Settings.save()
	finished.emit(won, {
		"loot": loot_value,
		"loot_total": level.loot_total,
		"time": elapsed,
		"diamond": has_diamond,
		"security_off": security_off,
		"spotted": times_spotted,
	})
