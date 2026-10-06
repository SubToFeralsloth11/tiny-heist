class_name Coin
extends RigidBody3D
## Thrown distraction. The first time it hits something it clinks, and nearby guards come to look.

signal clinked(pos: Vector3)

const NOISE_RADIUS := 11.0
const LIFETIME := 8.0

var _clinked := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Level.WORLD_LAYER
	contact_monitor = true
	max_contacts_reported = 1
	continuous_cd = true
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.08
	cyl.height = 0.03
	shape.shape = cyl
	add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.08
	mesh.height = 0.03
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.8, 0.3)
	mat.metallic = 1.0
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.35, 0.0)
	mesh.material = mat
	mi.mesh = mesh
	add_child(mi)
	body_entered.connect(_on_hit)
	get_tree().create_timer(LIFETIME, false).timeout.connect(queue_free)


func _on_hit(_body: Node) -> void:
	if _clinked:
		return
	_clinked = true
	clinked.emit(global_position)
	# A small sparkle so the player sees where it landed.
	var flash := OmniLight3D.new()
	flash.light_color = Color(1, 0.85, 0.4)
	flash.light_energy = 3.0
	flash.omni_range = 3.0
	add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.6)
