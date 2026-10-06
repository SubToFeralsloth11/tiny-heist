class_name Player
extends CharacterBody3D
## First-person thief: walk, sprint (loud), sneak, jump, interact, throw coins, hide in lockers.

signal noise_made(pos: Vector3, radius: float)
signal loot_grabbed(loot: Loot)
signal item_collected(item: Interactable)
signal coin_thrown(coin: Coin)

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const CROUCH_SPEED := 2.3
const JUMP_VELOCITY := 4.8
## Radians per pixel at sensitivity 1.0.
const BASE_MOUSE_SPEED := 0.0025
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_OFFSET := 0.2
const REACH := 2.8
const START_COINS := 5
const THROW_SPEED := 13.0
## Noise radius in metres for each movement style, emitted every NOISE_INTERVAL.
const NOISE_SPRINT := 10.0
const NOISE_WALK := 3.5
const NOISE_INTERVAL := 0.35
const NOISE_GRAB := 4.0
const NOISE_LAND := 6.0

var crouching := false
var sprinting := false
var controls_enabled := true
var has_keycard := false
var coins := START_COINS
var hiding_in: Locker = null
## 0..1 progress of a held interaction, -1 when not holding.
var hold_progress := -1.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _head: Node3D
var _camera: Camera3D
var _shape: CapsuleShape3D
var _collider: CollisionShape3D
var _ray: RayCast3D
var _left_arm: Node3D
var _right_arm: Node3D
var _bob_phase := 0.0
var _bob_amount := 0.0
var _land_dip := 0.0
var _grab_anim := 0.0
var _throw_anim := 0.0
var _strafe_tilt := 0.0
var _noise_clock := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _hold_target: Interactable = null
var _hold_time := 0.0
var _pre_hide_transform: Transform3D


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
	_head.position.y = STAND_HEIGHT - EYE_OFFSET
	add_child(_head)
	_camera = Camera3D.new()
	_camera.fov = Settings.fov
	_camera.near = 0.05
	_head.add_child(_camera)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -REACH)
	_ray.collision_mask = Level.WORLD_LAYER | Level.INTERACT_LAYER
	_ray.collide_with_areas = true
	_head.add_child(_ray)

	_build_arms()


## Eye position used by guards and cameras for line-of-sight checks.
func eye_position() -> Vector3:
	return _head.global_position


## Where grabbed loot flies to.
func hand_position() -> Vector3:
	return _right_arm.global_position


## The interactable under the crosshair that currently has something to say, or null.
func aimed_interactable() -> Interactable:
	if hiding_in:
		return hiding_in
	var hit := _ray.get_collider() as Interactable
	if hit and hit.prompt_text(self) != "":
		return hit
	return null


func collect(loot: Loot) -> void:
	_grab_anim = 1.0
	loot_grabbed.emit(loot)
	noise_made.emit(global_position, NOISE_GRAB)


func collect_item(item: Interactable) -> void:
	_grab_anim = 1.0
	item_collected.emit(item)


func enter_locker(locker: Locker) -> void:
	hiding_in = locker
	_pre_hide_transform = global_transform
	_collider.disabled = true
	velocity = Vector3.ZERO
	_set_crouch(false)
	global_position = locker.hide_position()
	rotation.y = locker.facing_yaw()
	_head.rotation.x = 0.0


func leave_locker() -> void:
	var locker := hiding_in
	hiding_in = null
	_collider.disabled = false
	# Step out in front of the locker, still facing out.
	global_position = locker.global_transform * Vector3(0, 0.05, 1.0)
	rotation.y = locker.facing_yaw()


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var speed := BASE_MOUSE_SPEED * Settings.mouse_sensitivity
		var dy: float = event.relative.y * (-1.0 if Settings.invert_y else 1.0)
		rotate_y(-event.relative.x * speed)
		var limit := 0.6 if hiding_in else 1.45
		_head.rotation.x = clampf(_head.rotation.x - dy * speed, -limit, limit)
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("throw") and coins > 0 and hiding_in == null:
		_throw_coin()


func _try_interact() -> void:
	var target := aimed_interactable()
	if target == null:
		return
	if target.hold_time() > 0.0:
		_hold_target = target
		_hold_time = 0.0
		hold_progress = 0.0
	else:
		target.interact(self)


func _throw_coin() -> void:
	coins -= 1
	_throw_anim = 1.0
	var coin := Coin.new()
	get_parent().add_child(coin)
	var forward := -_camera.global_transform.basis.z
	coin.global_position = _camera.global_position + forward * 0.5 + Vector3(0, -0.1, 0)
	coin.linear_velocity = forward * THROW_SPEED + Vector3(0, 2.5, 0) + velocity * 0.5
	coin.angular_velocity = Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
	coin_thrown.emit(coin)


func _physics_process(delta: float) -> void:
	_update_hold(delta)
	if hiding_in:
		_animate_view(delta)
		return

	var input_dir := Vector2.ZERO
	var want_crouch := false
	var want_sprint := false
	if controls_enabled and _hold_target == null:
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
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_land_dip = clampf(_fall_speed / 8.0, 0.15, 0.6)
		if _fall_speed > 4.0:
			noise_made.emit(global_position, NOISE_LAND)
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()

	_strafe_tilt = lerpf(_strafe_tilt, -input_dir.x, delta * 6.0)
	_emit_footstep_noise(delta)
	_animate_view(delta)


## Holding E on something with a hold time (the security panel). Releasing or looking away cancels.
func _update_hold(delta: float) -> void:
	if _hold_target == null:
		return
	if not controls_enabled or not Input.is_action_pressed("interact") or aimed_interactable() != _hold_target:
		_hold_target = null
		hold_progress = -1.0
		return
	_hold_time += delta
	hold_progress = clampf(_hold_time / _hold_target.hold_time(), 0.0, 1.0)
	if hold_progress >= 1.0:
		var target := _hold_target
		_hold_target = null
		hold_progress = -1.0
		target.interact(self)


func _set_crouch(want: bool) -> void:
	if want == crouching:
		return
	crouching = want
	var h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_shape.height = h
	_collider.position.y = h * 0.5


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
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.96, 0.78, 0.6)
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.1, 0.1, 0.13)
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.85, 0.85, 0.85)
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.03, 0.03, 0.03)
	_left_arm = _make_arm(sleeve, stripe, skin, glove)
	_right_arm = _make_arm(sleeve, stripe, skin, glove)
	_camera.add_child(_left_arm)
	_camera.add_child(_right_arm)


## A Roblox-style blocky arm: striped sleeve, a strip of skin, and a black glove.
func _make_arm(sleeve: Material, stripe: Material, skin: Material, glove: Material) -> Node3D:
	var arm := Node3D.new()
	var parts := [
		[sleeve, Vector3(0.16, 0.16, 0.5), Vector3(0, 0, 0.15)],
		[stripe, Vector3(0.165, 0.165, 0.05), Vector3(0, 0, 0.05)],
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


## Head bob, strafe lean, FOV kick and arm swing, all eased so nothing snaps.
func _animate_view(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var moving := is_on_floor() and horizontal > 0.5 and hiding_in == null
	var freq := 5.0 if crouching else (11.0 if sprinting else 7.5)
	var target_amount := clampf(horizontal / SPRINT_SPEED, 0.0, 1.0) if moving else 0.0
	_bob_amount = lerpf(_bob_amount, target_amount, delta * 8.0)
	_bob_phase += delta * freq * (1.0 if moving else 0.3)
	var bob_scale := Settings.camera_bob

	# Eye height eases toward standing/crouching height.
	var eye_h := (CROUCH_HEIGHT if crouching else STAND_HEIGHT) - EYE_OFFSET
	_head.position.y = lerpf(_head.position.y, eye_h, 1.0 - exp(-delta * 14.0))

	var amp := 0.06 if sprinting else 0.035
	var bob_y := absf(sin(_bob_phase)) * amp * _bob_amount * bob_scale
	var bob_x := cos(_bob_phase) * amp * 0.6 * _bob_amount * bob_scale
	_land_dip = move_toward(_land_dip, 0.0, delta * 2.5)
	_camera.position = Vector3(bob_x, bob_y - _land_dip * 0.25 * bob_scale, 0)
	_camera.rotation.z = (-bob_x * 0.4 + _strafe_tilt * 0.025) * bob_scale

	var target_fov := Settings.fov + (8.0 if sprinting and horizontal > 1.0 else 0.0) - (4.0 if crouching else 0.0)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-delta * 8.0))

	# Arms swing opposite each other like a walk cycle.
	var breathe := sin(Time.get_ticks_msec() * 0.002) * 0.008
	var swing := sin(_bob_phase) * _bob_amount * (0.12 if sprinting else 0.06)
	var lift := (0.06 if sprinting else 0.0) * _bob_amount
	var base_y := -0.32 + breathe + lift + _land_dip * 0.1
	var sprint_pitch := (0.25 if sprinting else 0.0) * _bob_amount
	var left_pos := Vector3(-0.32, base_y, -0.35 + swing)
	var right_pos := Vector3(0.32, base_y, -0.35 - swing)
	var left_rot := Vector3(swing * 1.5 + sprint_pitch, 0, 0)
	var right_rot := Vector3(-swing * 1.5 + sprint_pitch, 0, 0)

	if crouching:
		# Sneaky pose: arms pulled in and low.
		left_pos += Vector3(0.06, -0.05, 0.05)
		right_pos += Vector3(-0.06, -0.05, 0.05)
	if hold_progress >= 0.0:
		# Both hands forward, fiddling with the panel.
		var jiggle := sin(Time.get_ticks_msec() * 0.03) * 0.02
		left_pos += Vector3(0.12, 0.12 + jiggle, -0.2)
		right_pos += Vector3(-0.12, 0.12 - jiggle, -0.2)
		left_rot.x += 0.5
		right_rot.x += 0.5
	if hiding_in:
		left_pos.y -= 0.4
		right_pos.y -= 0.4
	if _grab_anim > 0.0:
		_grab_anim = move_toward(_grab_anim, 0.0, delta * 3.5)
		var reach := sin(_grab_anim * PI)
		right_pos += Vector3(-0.12, 0.12, -0.35) * reach
		right_rot.x += 0.5 * reach
	if _throw_anim > 0.0:
		_throw_anim = move_toward(_throw_anim, 0.0, delta * 3.0)
		# Wind up behind the shoulder, then snap forward.
		var t := 1.0 - _throw_anim
		var wind := sin(clampf(t * 2.5, 0.0, 1.0) * PI)
		var fling := sin(clampf((t - 0.3) * 1.6, 0.0, 1.0) * PI)
		right_pos += Vector3(0.0, 0.2 * wind, 0.15 * wind - 0.35 * fling)
		right_rot.x += 1.2 * wind - 0.6 * fling

	var k := 1.0 - exp(-delta * 20.0)
	_left_arm.position = _left_arm.position.lerp(left_pos, k)
	_right_arm.position = _right_arm.position.lerp(right_pos, k)
	_left_arm.rotation = _left_arm.rotation.lerp(left_rot, k)
	_right_arm.rotation = _right_arm.rotation.lerp(right_rot, k)
