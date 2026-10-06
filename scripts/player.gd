class_name Player
extends CharacterBody3D
## First-person thief. Walk, sprint (loud), crouch (quiet + harder to spot), jump, grab loot.

signal noise_made(pos: Vector3, radius: float)
signal loot_grabbed(loot: Loot)

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const CROUCH_SPEED := 2.3
const JUMP_VELOCITY := 4.8
const MOUSE_SENS := 0.0025
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const REACH := 2.6
## Noise radius in metres for each movement style, emitted every NOISE_INTERVAL.
const NOISE_SPRINT := 10.0
const NOISE_WALK := 3.5
const NOISE_INTERVAL := 0.35
const NOISE_GRAB := 4.0
const NOISE_LAND := 6.0

var crouching := false
var sprinting := false
var controls_enabled := true

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _head: Node3D
var _camera: Camera3D
var _shape: CapsuleShape3D
var _collider: CollisionShape3D
var _ray: RayCast3D
var _arms: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _bob_phase := 0.0
var _bob_amount := 0.0
var _land_dip := 0.0
var _grab_anim := 0.0
var _noise_clock := 0.0
var _was_on_floor := true
var _fall_speed := 0.0


func _ready() -> void:
	collision_layer = Level.PLAYER_LAYER
	collision_mask = Level.WORLD_LAYER
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.35
	_shape.height = STAND_HEIGHT
	_collider = CollisionShape3D.new()
	_collider.shape = _shape
	_collider.position.y = STAND_HEIGHT * 0.5
	add_child(_collider)

	_head = Node3D.new()
	_head.position.y = STAND_HEIGHT - 0.2
	add_child(_head)
	_camera = Camera3D.new()
	_camera.fov = 75
	_camera.near = 0.05
	_head.add_child(_camera)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -REACH)
	_ray.collision_mask = Level.WORLD_LAYER | Level.LOOT_LAYER
	_ray.collide_with_areas = true
	_camera.add_child(_ray)

	_build_arms()


## Eye position used by guards for line-of-sight checks.
func eye_position() -> Vector3:
	return _head.global_position


## The loot the player is looking at, or null.
func aimed_loot() -> Loot:
	var hit := _ray.get_collider()
	return hit as Loot


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_head.rotation.x = clampf(_head.rotation.x - event.relative.y * MOUSE_SENS, -1.45, 1.45)
	elif event.is_action_pressed("interact"):
		var loot := aimed_loot()
		if loot:
			loot.take()
			_grab_anim = 1.0
			loot_grabbed.emit(loot)
			noise_made.emit(global_position, NOISE_GRAB)


func _physics_process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	var want_crouch := false
	var want_sprint := false
	if controls_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want_crouch = Input.is_action_pressed("crouch")
		want_sprint = Input.is_action_pressed("sprint") and input_dir.y < 0.0

	_set_crouch(want_crouch)
	sprinting = want_sprint and not crouching
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if sprinting else WALK_SPEED)

	if not is_on_floor():
		velocity.y -= _gravity * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif controls_enabled and Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VELOCITY

	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var accel := 14.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_land_dip = clampf(_fall_speed / 8.0, 0.15, 0.6)
		if _fall_speed > 4.0:
			noise_made.emit(global_position, NOISE_LAND)
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()

	_emit_footstep_noise(delta)
	_animate_view(delta)


func _set_crouch(want: bool) -> void:
	if want == crouching:
		return
	crouching = want
	var h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_shape.height = h
	_collider.position.y = h * 0.5
	var tween := create_tween()
	tween.tween_property(_head, "position:y", h - 0.2, 0.15)


func _emit_footstep_noise(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or horizontal < 0.5:
		_noise_clock = 0.0
		return
	_noise_clock += delta
	if _noise_clock < NOISE_INTERVAL:
		return
	_noise_clock = 0.0
	if sprinting:
		noise_made.emit(global_position, NOISE_SPRINT)
	elif not crouching:
		noise_made.emit(global_position, NOISE_WALK)


func _build_arms() -> void:
	_arms = Node3D.new()
	_camera.add_child(_arms)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.96, 0.78, 0.6)
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.08, 0.08, 0.1)
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.02, 0.02, 0.02)
	_left_arm = _make_arm(sleeve, skin, glove)
	_left_arm.position = Vector3(-0.32, -0.32, -0.35)
	_right_arm = _make_arm(sleeve, skin, glove)
	_right_arm.position = Vector3(0.32, -0.32, -0.35)
	_arms.add_child(_left_arm)
	_arms.add_child(_right_arm)


## A Roblox-style blocky arm: black sleeve, a strip of skin, and a black glove.
func _make_arm(sleeve: Material, skin: Material, glove: Material) -> Node3D:
	var arm := Node3D.new()
	var parts := [
		[sleeve, Vector3(0.16, 0.16, 0.5), Vector3(0, 0, 0.15)],
		[skin, Vector3(0.15, 0.15, 0.06), Vector3(0, 0, -0.13)],
		[glove, Vector3(0.17, 0.17, 0.14), Vector3(0, 0, -0.22)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[1]
		box.material = p[0]
		mi.mesh = box
		mi.position = p[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.add_child(mi)
	return arm


## Head bob + arm swing. Bigger and faster when sprinting, low and slow when sneaking.
func _animate_view(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var moving := is_on_floor() and horizontal > 0.5
	var freq := 7.0 if not sprinting else 11.0
	if crouching:
		freq = 5.0
	var target_amount := clampf(horizontal / SPRINT_SPEED, 0.0, 1.0) if moving else 0.0
	_bob_amount = lerpf(_bob_amount, target_amount, delta * 8.0)
	_bob_phase += delta * freq * (1.0 if moving else 0.25)

	var amp := 0.06 if sprinting else 0.035
	var bob_y := absf(sin(_bob_phase)) * amp * _bob_amount
	var bob_x := cos(_bob_phase) * amp * 0.6 * _bob_amount
	_land_dip = move_toward(_land_dip, 0.0, delta * 2.5)
	var breathe := sin(Time.get_ticks_msec() * 0.002) * 0.008
	_camera.position = Vector3(bob_x, bob_y - _land_dip * 0.25, 0)
	_camera.rotation.z = -bob_x * 0.4

	# Arms swing opposite each other like a walk cycle.
	var swing := sin(_bob_phase) * _bob_amount * (0.12 if sprinting else 0.06)
	var lift := 0.06 if sprinting else 0.0
	_left_arm.position = Vector3(-0.32, -0.32 + breathe + lift * _bob_amount + _land_dip * 0.1, -0.35 + swing)
	_right_arm.position = Vector3(0.32, -0.32 + breathe + lift * _bob_amount + _land_dip * 0.1, -0.35 - swing)
	_left_arm.rotation.x = swing * 1.5 + (0.25 if sprinting else 0.0) * _bob_amount
	_right_arm.rotation.x = -swing * 1.5 + (0.25 if sprinting else 0.0) * _bob_amount

	# Sneaky pose: arms pulled in and down while crouching.
	if crouching:
		_left_arm.position += Vector3(0.06, -0.04, 0.05)
		_right_arm.position += Vector3(-0.06, -0.04, 0.05)

	# Grab: right arm snaps forward then returns.
	if _grab_anim > 0.0:
		_grab_anim = move_toward(_grab_anim, 0.0, delta * 3.5)
		var reach := sin(_grab_anim * PI)
		_right_arm.position += Vector3(-0.12, 0.12, -0.35) * reach
		_right_arm.rotation.x += 0.5 * reach
