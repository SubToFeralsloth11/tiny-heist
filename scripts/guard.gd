class_name Guard
extends CharacterBody3D
## Patrolling night guard. Sees with a flashlight cone, hears noises, chases when sure.

signal caught_player
signal spotted_player

enum State { PATROL, INVESTIGATE, CHASE }

const PATROL_SPEED := 2.4
const INVESTIGATE_SPEED := 3.4
const CHASE_SPEED := 5.6
const ACCEL := 10.0
const VIEW_RANGE := 14.0
const VIEW_HALF_ANGLE := deg_to_rad(42.0)
## Within this distance the guard notices you even outside the cone (if there is line of sight).
const SENSE_RANGE := 2.2
const CATCH_RANGE := 1.3
const LOSE_SIGHT_TIME := 3.0
const LOOK_AROUND_TIME := 3.5
const WAYPOINT_PAUSE := 1.2
const REPATH_INTERVAL := 0.3

var level: Level
var player: Player
var patrol: Array = []
var state := State.PATROL
## 0..1, how sure the guard is that someone is there. Reaching 1 starts a chase.
var suspicion := 0.0

var _patrol_index := 0
var _path := PackedVector3Array()
var _path_index := 0
var _wait := 0.0
var _repath := 0.0
var _unseen_time := 0.0
var _investigate_target := Vector3.ZERO
var _look_target := Vector3.ZERO
var _look_around := 0.0
var _desired_yaw := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _icon: Label3D
var _flashlight: SpotLight3D
var _head: Node3D
var _body: Node3D
var _walk_phase := 0.0
var _scan_phase := randf() * TAU
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _icon_pop := 0.0
var _last_icon := ""


func _ready() -> void:
	collision_layer = 4
	collision_mask = Level.WORLD_LAYER
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	_build_body()
	if not patrol.is_empty():
		global_position = Level.cell_to_world(patrol[0])
		_set_path_to(Level.cell_to_world(patrol[0]))
	_desired_yaw = rotation.y


func eye_position() -> Vector3:
	return _head.global_position


func can_see_player() -> bool:
	if player.hiding_in:
		return false
	var eye := eye_position()
	var target := player.eye_position() - Vector3(0, 0.25, 0)
	var to := target - eye
	var dist := to.length()
	if dist > VIEW_RANGE:
		return false
	# The head scans left/right, so vision follows the head, not just the body.
	var forward := -_head.global_transform.basis.z
	var flat := Vector3(to.x, 0, to.z).normalized()
	if dist > SENSE_RANGE and Vector3(forward.x, 0, forward.z).normalized().angle_to(flat) > VIEW_HALF_ANGLE:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, Level.WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Called when the player (or a thrown coin) makes a noise this guard can hear.
func hear(pos: Vector3) -> void:
	if state == State.CHASE:
		return
	suspicion = maxf(suspicion, 0.35)
	_start_investigate(pos)


## The alarm sends every guard running toward the player's position.
func alert_to(pos: Vector3) -> void:
	if state == State.CHASE:
		return
	suspicion = maxf(suspicion, 0.6)
	_start_investigate(pos)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var sees := can_see_player()
	_update_suspicion(delta, sees)

	match state:
		State.PATROL:
			_do_patrol(delta)
		State.INVESTIGATE:
			_do_investigate(delta)
		State.CHASE:
			_do_chase(delta, sees)

	rotation.y = lerp_angle(rotation.y, _desired_yaw, 1.0 - exp(-delta * 8.0))
	move_and_slide()
	_animate(delta)


func _update_suspicion(delta: float, sees: bool) -> void:
	if state == State.CHASE:
		return
	if sees:
		var dist := eye_position().distance_to(player.eye_position())
		# Closer = noticed faster. Crouching halves it, sprinting makes it worse.
		var rate := lerpf(2.2, 0.45, clampf(dist / VIEW_RANGE, 0.0, 1.0))
		if player.crouching:
			rate *= 0.5
		if player.sprinting:
			rate *= 1.5
		suspicion = minf(suspicion + rate * delta, 1.0)
		_look_target = player.global_position
		if suspicion >= 1.0:
			_start_chase()
	else:
		suspicion = maxf(suspicion - 0.25 * delta, 0.0)


func _start_chase() -> void:
	state = State.CHASE
	suspicion = 1.0
	_unseen_time = 0.0
	_repath = 0.0
	_investigate_target = player.global_position
	# Startled hop.
	var tween := create_tween()
	tween.tween_property(_body, "position:y", 0.35, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_body, "position:y", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	spotted_player.emit()


func _start_investigate(pos: Vector3) -> void:
	state = State.INVESTIGATE
	_investigate_target = pos
	_look_around = 0.0
	_set_path_to(pos)


func _do_patrol(delta: float) -> void:
	# A partly suspicious guard stops and stares toward what they saw.
	if suspicion > 0.2:
		_stop(delta)
		_face(_look_target)
		return
	if _wait > 0.0:
		_wait -= delta
		_stop(delta)
		return
	if _follow_path(PATROL_SPEED, delta):
		_wait = WAYPOINT_PAUSE
		_patrol_index = (_patrol_index + 1) % patrol.size()
		_set_path_to(Level.cell_to_world(patrol[_patrol_index]))


func _do_investigate(delta: float) -> void:
	if suspicion > 0.45 and can_see_player():
		_stop(delta)
		_face(_look_target)
		return
	if _look_around <= 0.0:
		if _follow_path(INVESTIGATE_SPEED, delta):
			_look_around = LOOK_AROUND_TIME
		return
	# Reached the spot: sweep the flashlight left and right.
	_stop(delta)
	_look_around -= delta
	_desired_yaw += sin(_look_around * 2.0) * delta * 1.6
	if _look_around <= 0.0:
		state = State.PATROL
		suspicion = 0.0
		_set_path_to(Level.cell_to_world(patrol[_patrol_index]))
		_look_around = 0.0


func _do_chase(delta: float, sees: bool) -> void:
	if sees:
		_unseen_time = 0.0
		_investigate_target = player.global_position
	else:
		_unseen_time += delta
		if _unseen_time > LOSE_SIGHT_TIME:
			suspicion = 0.7
			_start_investigate(_investigate_target)
			return
	# Hidden players are only caught if the guard reaches the spot they were last seen at.
	if global_position.distance_to(player.global_position) < CATCH_RANGE + (0.6 if player.hiding_in else 0.0):
		if player.hiding_in == null or _investigate_target.distance_to(player.global_position) < Level.CELL:
			_stop(delta)
			caught_player.emit()
			return
	_repath -= delta
	if _repath <= 0.0:
		_repath = REPATH_INTERVAL
		_set_path_to(_investigate_target)
	if sees and global_position.distance_to(player.global_position) < Level.CELL:
		# Close range: run straight at the player.
		var to := player.global_position - global_position
		to.y = 0
		_move_dir(to.normalized(), CHASE_SPEED, delta)
	else:
		_follow_path(CHASE_SPEED, delta)


func _set_path_to(target: Vector3) -> void:
	_path = level.find_path(global_position, target)
	_path_index = 0


## Walks along the current path. Returns true when the end is reached.
func _follow_path(speed: float, delta: float) -> bool:
	while _path_index < _path.size():
		var p := _path[_path_index]
		var to := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
		var last := _path_index == _path.size() - 1
		# Cut corners on intermediate points so turns look natural.
		if to.length() < (0.35 if last else 0.9):
			_path_index += 1
			continue
		_move_dir(to.normalized(), speed, delta)
		return false
	_stop(delta)
	return true


func _move_dir(dir: Vector3, speed: float, delta: float) -> void:
	var k := 1.0 - exp(-delta * ACCEL)
	velocity.x = lerpf(velocity.x, dir.x * speed, k)
	velocity.z = lerpf(velocity.z, dir.z * speed, k)
	_face(global_position + dir)


func _stop(delta: float) -> void:
	var k := 1.0 - exp(-delta * ACCEL)
	velocity.x = lerpf(velocity.x, 0.0, k)
	velocity.z = lerpf(velocity.z, 0.0, k)


func _face(target: Vector3) -> void:
	var to := target - global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	_desired_yaw = atan2(-to.x, -to.z)


func _build_body() -> void:
	var uniform := _mat(Color(0.12, 0.18, 0.4))
	var pants := _mat(Color(0.08, 0.08, 0.12))
	var skin := _mat(Color(0.85, 0.65, 0.5))
	var cap_mat := _mat(Color(0.05, 0.08, 0.2))
	var belt := _mat(Color(0.05, 0.05, 0.05))
	var badge := _mat(Color(1, 0.85, 0.2))
	badge.metallic = 1.0
	var eye_mat := _mat(Color(0.05, 0.05, 0.05))

	_body = Node3D.new()
	add_child(_body)
	_box(_body, Vector3(0.6, 0.7, 0.35), Vector3(0, 1.15, 0), uniform)
	_box(_body, Vector3(0.62, 0.08, 0.37), Vector3(0, 0.84, 0), belt)
	_box(_body, Vector3(0.12, 0.12, 0.04), Vector3(-0.15, 1.3, -0.18), badge)
	for side in [-0.15, 0.15]:
		var leg := Node3D.new()
		leg.position = Vector3(side, 0.8, 0)
		_body.add_child(leg)
		_box(leg, Vector3(0.25, 0.8, 0.28), Vector3(0, -0.4, 0), pants)
		_box(leg, Vector3(0.27, 0.12, 0.34), Vector3(0, -0.74, -0.03), belt)
		_legs.append(leg)
	for side in [-0.4, 0.4]:
		var arm := Node3D.new()
		arm.position = Vector3(side, 1.45, 0)
		_body.add_child(arm)
		_box(arm, Vector3(0.2, 0.65, 0.22), Vector3(0, -0.3, 0), uniform)
		_box(arm, Vector3(0.18, 0.12, 0.2), Vector3(0, -0.66, 0), skin)
		_arms.append(arm)

	_head = Node3D.new()
	_head.position.y = 1.7
	_body.add_child(_head)
	_box(_head, Vector3(0.4, 0.4, 0.4), Vector3.ZERO, skin)
	_box(_head, Vector3(0.44, 0.12, 0.44), Vector3(0, 0.2, 0), cap_mat)
	_box(_head, Vector3(0.44, 0.04, 0.2), Vector3(0, 0.15, -0.28), cap_mat)
	for side in [-0.09, 0.09]:
		_box(_head, Vector3(0.07, 0.07, 0.02), Vector3(side, 0.02, -0.205), eye_mat)

	# Flashlight held in the right hand, aimed where the head looks.
	_flashlight = SpotLight3D.new()
	_flashlight.position = Vector3(0.25, -0.3, -0.2)
	_flashlight.spot_range = VIEW_RANGE
	_flashlight.spot_angle = rad_to_deg(VIEW_HALF_ANGLE)
	_flashlight.spot_attenuation = 0.6
	_flashlight.light_energy = 4.0
	_flashlight.light_color = Color(1.0, 0.95, 0.75)
	_flashlight.shadow_enabled = true
	_flashlight.rotation.x = deg_to_rad(-8)
	_head.add_child(_flashlight)

	_icon = Label3D.new()
	_icon.position.y = 2.35
	_icon.font_size = 96
	_icon.outline_size = 16
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	add_child(_icon)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)


func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var stride := clampf(speed / CHASE_SPEED, 0.0, 1.0)
	_walk_phase += delta * (4.0 + speed * 1.6)
	var swing := sin(_walk_phase) * stride * 0.9
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	# Arms swing opposite to legs; when chasing they pump harder and reach forward.
	var reach := -0.5 if state == State.CHASE else 0.0
	_arms[0].rotation.x = -swing * 0.8 + reach
	_arms[1].rotation.x = swing * 0.8 + reach
	# Body bobs with each step and leans into a sprint.
	_body.rotation.x = lerpf(_body.rotation.x, -stride * 0.18, 1.0 - exp(-delta * 6.0))
	var bob := absf(sin(_walk_phase)) * 0.05 * stride

	# Head: idle scan while patrolling, locked forward otherwise.
	var head_yaw := 0.0
	if state == State.PATROL and suspicion < 0.2:
		_scan_phase += delta * 0.9
		head_yaw = sin(_scan_phase) * 0.55
	_head.rotation.y = lerp_angle(_head.rotation.y, head_yaw, 1.0 - exp(-delta * 5.0))
	_head.position.y = 1.7 + bob

	var icon := ""
	if state == State.CHASE:
		icon = "!"
		_icon.modulate = Color(1, 0.15, 0.1)
		_flashlight.light_color = Color(1.0, 0.4, 0.3)
	elif suspicion > 0.05 or state == State.INVESTIGATE:
		icon = "?"
		_icon.modulate = Color(1, 0.85, 0.1).lerp(Color(1, 0.4, 0.1), suspicion)
		_flashlight.light_color = Color(1.0, 0.95, 0.75)
	else:
		_flashlight.light_color = Color(1.0, 0.95, 0.75)
	# Pop the icon when it changes.
	if icon != _last_icon:
		_last_icon = icon
		_icon_pop = 1.0
	_icon_pop = move_toward(_icon_pop, 0.0, delta * 4.0)
	_icon.text = icon
	_icon.scale = Vector3.ONE * (1.0 + _icon_pop * 0.6)
	_icon.position.y = 2.35 + sin(Time.get_ticks_msec() * 0.006) * 0.05
