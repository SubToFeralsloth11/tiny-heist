class_name SecurityCamera
extends Node3D
## Wall camera that sweeps left and right. Watching you for too long trips the alarm.

signal spotted

const RANGE := 13.0
const HALF_ANGLE := deg_to_rad(30.0)
const PITCH := deg_to_rad(-32.0)
const SWEEP := deg_to_rad(55.0)
const SWEEP_SPEED := 0.55
const DETECT_TIME := 1.1
const COOLDOWN := 6.0

var player: Player
var base_yaw := 0.0
var active := true
## 0..1, how close the camera is to raising the alarm.
var suspicion := 0.0

var _pivot: Node3D
var _light: SpotLight3D
var _led_mat: StandardMaterial3D
var _clock := randf() * TAU
var _cooldown := 0.0


func _ready() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.85, 0.85, 0.82)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(1, 0.1, 0.1)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1, 0.1, 0.1)
	_led_mat.emission_energy_multiplier = 3.0

	rotation.y = base_yaw
	_part(self, Vector3(0.2, 0.2, 0.25), Vector3(0, 0.05, 0.1), dark)  # wall mount
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0, 0.3)
	add_child(_pivot)
	# Camera body points along local +Z (away from the wall).
	_part(_pivot, Vector3(0.3, 0.28, 0.6), Vector3(0, 0, 0.15), body_mat)
	_part(_pivot, Vector3(0.2, 0.2, 0.06), Vector3(0, 0, 0.47), dark)
	_part(_pivot, Vector3(0.06, 0.06, 0.02), Vector3(0.1, 0.1, 0.46), _led_mat)

	_light = SpotLight3D.new()
	_light.spot_range = RANGE
	_light.spot_angle = rad_to_deg(HALF_ANGLE)
	_light.light_energy = 1.2
	_light.light_color = Color(1.0, 0.95, 0.6)
	_light.position.z = 0.5
	_light.rotation.y = PI  # SpotLight shines down -Z; flip so it follows +Z.
	_pivot.add_child(_light)


func _physics_process(delta: float) -> void:
	if not active:
		return
	_clock += delta * SWEEP_SPEED
	# While suspicious, freeze the sweep and stare.
	if suspicion < 0.15:
		_pivot.rotation = Vector3(-PITCH, sin(_clock) * SWEEP, 0)
	_cooldown = maxf(_cooldown - delta, 0.0)

	if _sees_player():
		var rate := 1.0 / DETECT_TIME
		if player.crouching:
			rate *= 0.6
		suspicion = minf(suspicion + rate * delta, 1.0)
		if suspicion >= 1.0 and _cooldown <= 0.0:
			_cooldown = COOLDOWN
			spotted.emit()
	else:
		suspicion = maxf(suspicion - delta * 0.5, 0.0)
	var c := Color(1.0, 0.95, 0.6).lerp(Color(1, 0.1, 0.05), suspicion)
	_light.light_color = c
	_light.light_energy = 1.2 + suspicion * 2.0


func disable() -> void:
	active = false
	suspicion = 0.0
	_light.visible = false
	_led_mat.emission_energy_multiplier = 0.0
	_led_mat.albedo_color = Color(0.2, 0.05, 0.05)
	var tween := create_tween()
	tween.tween_property(_pivot, "rotation:x", 0.9, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _sees_player() -> bool:
	if player == null or player.hiding_in != null:
		return false
	var eye := _pivot.global_position
	var target := player.eye_position() - Vector3(0, 0.3, 0)
	var to := target - eye
	if to.length() > RANGE:
		return false
	var forward := _pivot.global_transform.basis.z
	if forward.angle_to(to) > HALF_ANGLE:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, Level.WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
