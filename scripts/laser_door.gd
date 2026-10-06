class_name LaserDoor
extends Area3D
## A doorway full of laser beams that blink on and off. Touching a live beam trips the alarm.

signal tripped

const ON_TIME := 2.4
const OFF_TIME := 1.6
const WARN_TIME := 0.5
const BEAM_HEIGHTS := [0.3, 0.75, 1.2, 1.65, 2.1]

var width := 3.0
var active := true
## False once security is shut down.
var powered := true

var _clock := 0.0
var _beams: Array[MeshInstance3D] = []
var _glow: OmniLight3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Level.PLAYER_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 2.4, width)
	shape.shape = box
	shape.position.y = 1.2
	add_child(shape)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 0.1)
	for h: float in BEAM_HEIGHTS:
		var beam := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.03, 0.03, width)
		mesh.material = mat
		beam.mesh = mesh
		beam.position.y = h
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		_beams.append(beam)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1, 0.1, 0.1)
	_glow.light_energy = 1.2
	_glow.omni_range = 4.0
	_glow.position.y = 1.2
	add_child(_glow)


func _physics_process(delta: float) -> void:
	if not powered:
		return
	_clock = fmod(_clock + delta, ON_TIME + OFF_TIME)
	active = _clock < ON_TIME
	# Flicker during the last moments of the "off" phase as a warning.
	var warning := not active and _clock > ON_TIME + OFF_TIME - WARN_TIME
	var show := active or (warning and fmod(_clock, 0.12) < 0.06)
	for b in _beams:
		b.visible = show
	_glow.visible = show
	if active:
		for body in get_overlapping_bodies():
			if body is Player and body.hiding_in == null:
				_clock = ON_TIME  # Cut the beams so the alarm only fires once per touch.
				active = false
				tripped.emit()
				return


func power_off() -> void:
	powered = false
	active = false
	for b in _beams:
		b.visible = false
	_glow.visible = false
