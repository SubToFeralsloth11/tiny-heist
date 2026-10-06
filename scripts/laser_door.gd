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

var _clock := 0.0
var _beams: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Level.PLAYER_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 2.4, width)
	shape.shape = box
	shape.position.y = 1.2
	add_child(shape)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.1, 0.1)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.0, 0.0)
	_mat.emission_energy_multiplier = 4.0
	for h: float in BEAM_HEIGHTS:
		var beam := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.03, 0.03, width)
		mesh.material = _mat
		beam.mesh = mesh
		beam.position.y = h
		add_child(beam)
		_beams.append(beam)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(1, 0.1, 0.1)
	glow.light_energy = 1.2
	glow.omni_range = 4.0
	glow.position.y = 1.2
	add_child(glow)


func _physics_process(delta: float) -> void:
	_clock = fmod(_clock + delta, ON_TIME + OFF_TIME)
	active = _clock < ON_TIME
	var warning := not active and _clock > ON_TIME + OFF_TIME - WARN_TIME
	var show := active or (warning and fmod(_clock, 0.12) < 0.06)
	for b in _beams:
		b.visible = show
	$Glow.visible = show
	if active:
		for body in get_overlapping_bodies():
			if body is Player:
				active = false
				_clock = ON_TIME  # Cut the beams so the alarm only fires once per touch.
				tripped.emit()
				return
