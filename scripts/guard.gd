class_name Guard
extends CharacterBody3D
## Patrolling night guard. Sees with a flashlight cone, hears noises, chases when sure.

signal caught_player
signal spotted_player

enum State { PATROL, INVESTIGATE, CHASE }

const PATROL_SPEED := 2.4
const INVESTIGATE_SPEED := 3.4
const CHASE_SPEED := 5.6
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
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _icon: Label3D
var _flashlight: SpotLight3D
var _head: Node3D
var _walk_phase := 0.0
var _legs: Array[Node3D] = []


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


func eye_position() -> Vector3:
	return _head.global_position


func can_see_player() -> bool:
	var eye := eye_position()
	var target := player.eye_position() - Vector3(0, 0.25, 0)
	var to := target - eye
	var dist := to.length()
	if dist > VIEW_RANGE:
		return false
	var forward := -global_transform.basis.z
	var flat := Vector3(to.x, 0, to.z).normalized()
	if dist > SENSE_RANGE and forward.angle_to(flat) > VIEW_HALF_ANGLE:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, Level.WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Called when the player makes a noise this guard can hear.
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

	move_and_slide()
	_animate(delta)


func _update_suspicion(delta: float, sees: bool) -> void:
	if state == State.CHASE:
		return
	if sees:
		var dist := eye_position().distance_to(player.eye_position())
		# Closer = noticed faster. Crouching halves it.
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
	spotted_player.emit()


func _start_investigate(pos: Vector3) -> void:
	state = State.INVESTIGATE
	_investigate_target = pos
	_look_around = 0.0
	_set_path_to(pos)


func _do_patrol(delta: float) -> void:
	# A partly suspicious guard stops and stares toward what they saw.
	if suspicion > 0.2:
		_stop()
		_face(_look_target, delta, 4.0)
		return
	if _wait > 0.0:
		_wait -= delta
		_stop()
		return
	if _follow_path(PATROL_SPEED, delta):
		_wait = WAYPOINT_PAUSE
		_patrol_index = (_patrol_index + 1) % patrol.size()
		_set_path_to(Level.cell_to_world(patrol[_patrol_index]))


func _do_investigate(delta: float) -> void:
	if suspicion > 0.45 and can_see_player():
		_stop()
		_face(_look_target, delta, 5.0)
		return
	if _look_around <= 0.0:
		if _follow_path(INVESTIGATE_SPEED, delta):
			_look_around = LOOK_AROUND_TIME
		return
	# Reached the spot: sweep the flashlight left and right.
	_stop()
	_look_around -= delta
	rotation.y += sin(_look_around * 2.0) * delta * 1.6
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
	if global_position.distance_to(player.global_position) < CATCH_RANGE:
		_stop()
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
		if to.length() < 0.4:
			_path_index += 1
			continue
		_move_dir(to.normalized(), speed, delta)
		return false
	_stop()
	return true


func _move_dir(dir: Vector3, speed: float, delta: float) -> void:
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(global_position + dir, delta, 8.0)


func _stop() -> void:
	velocity.x = 0
	velocity.z = 0


func _face(target: Vector3, delta: float, turn_speed: float) -> void:
	var to := target - global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	var want := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(turn_speed * delta, 0.0, 1.0))


func _build_body() -> void:
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = Color(0.12, 0.18, 0.4)
	var pants := StandardMaterial3D.new()
	pants.albedo_color = Color(0.08, 0.08, 0.12)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.65, 0.5)
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.05, 0.08, 0.2)
	var badge := StandardMaterial3D.new()
	badge.albedo_color = Color(1, 0.85, 0.2)
	badge.metallic = 1.0

	_box(self, Vector3(0.6, 0.7, 0.35), Vector3(0, 1.15, 0), uniform)
	_box(self, Vector3(0.12, 0.12, 0.04), Vector3(-0.15, 1.3, -0.18), badge)
	for side in [-0.15, 0.15]:
		var leg := Node3D.new()
		leg.position = Vector3(side, 0.8, 0)
		add_child(leg)
		_box(leg, Vector3(0.25, 0.8, 0.28), Vector3(0, -0.4, 0), pants)
		_legs.append(leg)
	for side in [-0.4, 0.4]:
		_box(self, Vector3(0.2, 0.65, 0.22), Vector3(side, 1.15, 0), uniform)

	_head = Node3D.new()
	_head.position.y = 1.7
	add_child(_head)
	_box(_head, Vector3(0.4, 0.4, 0.4), Vector3.ZERO, skin)
	_box(_head, Vector3(0.44, 0.12, 0.44), Vector3(0, 0.2, 0), cap_mat)
	_box(_head, Vector3(0.44, 0.04, 0.2), Vector3(0, 0.15, -0.28), cap_mat)

	_flashlight = SpotLight3D.new()
	_flashlight.position = Vector3(0.4, 1.35, -0.2)
	_flashlight.spot_range = VIEW_RANGE
	_flashlight.spot_angle = rad_to_deg(VIEW_HALF_ANGLE)
	_flashlight.spot_attenuation = 0.6
	_flashlight.light_energy = 4.0
	_flashlight.light_color = Color(1.0, 0.95, 0.75)
	_flashlight.shadow_enabled = true
	_flashlight.rotation.x = deg_to_rad(-8)
	add_child(_flashlight)

	_icon = Label3D.new()
	_icon.position.y = 2.35
	_icon.font_size = 96
	_icon.outline_size = 16
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	add_child(_icon)


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
	_walk_phase += delta * speed * 3.0
	var swing := sin(_walk_phase) * clampf(speed / CHASE_SPEED, 0.0, 1.0) * 0.8
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing

	if state == State.CHASE:
		_icon.text = "!"
		_icon.modulate = Color(1, 0.15, 0.1)
		_flashlight.light_color = Color(1.0, 0.4, 0.3)
	elif suspicion > 0.05 or state == State.INVESTIGATE:
		_icon.text = "?"
		_icon.modulate = Color(1, 0.85, 0.1).lerp(Color(1, 0.4, 0.1), suspicion)
		_flashlight.light_color = Color(1.0, 0.95, 0.75)
	else:
		_icon.text = ""
		_flashlight.light_color = Color(1.0, 0.95, 0.75)
