class_name Loot
extends Area3D
## A grabbable valuable sitting on a pedestal. The player's interact ray hits this Area.

var kind := "$"
var display_name := ""
var value := 0

var _mesh: MeshInstance3D
var _time := randf() * TAU


func _ready() -> void:
	collision_layer = Level.LOOT_LAYER
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	add_child(shape)

	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	var glow_color: Color
	_mesh = MeshInstance3D.new()
	match kind:
		"$":
			var box := BoxMesh.new()
			box.size = Vector3(0.5, 0.18, 0.25)
			_mesh.mesh = box
			mat.albedo_color = Color(1.0, 0.78, 0.2)
			mat.metallic = 1.0
			mat.roughness = 0.2
			mat.emission = Color(0.6, 0.4, 0.0)
			glow_color = Color(1.0, 0.8, 0.3)
		"g":
			var gem := SphereMesh.new()
			gem.radius = 0.2
			gem.height = 0.4
			gem.radial_segments = 6
			gem.rings = 2
			_mesh.mesh = gem
			mat.albedo_color = Color(0.95, 0.1, 0.25)
			mat.roughness = 0.05
			mat.emission = Color(0.8, 0.0, 0.15)
			glow_color = Color(1.0, 0.2, 0.3)
		_:
			var diamond := SphereMesh.new()
			diamond.radius = 0.32
			diamond.height = 0.7
			diamond.radial_segments = 8
			diamond.rings = 2
			_mesh.mesh = diamond
			mat.albedo_color = Color(0.75, 0.95, 1.0)
			mat.roughness = 0.0
			mat.emission = Color(0.4, 0.8, 1.0)
			mat.emission_energy_multiplier = 2.0
			glow_color = Color(0.5, 0.9, 1.0)
	_mesh.mesh.surface_set_material(0, mat)
	add_child(_mesh)

	var light := OmniLight3D.new()
	light.light_color = glow_color
	light.light_energy = 0.8
	light.omni_range = 2.5
	add_child(light)


func _process(delta: float) -> void:
	_time += delta
	_mesh.rotation.y = _time * 1.2
	_mesh.position.y = sin(_time * 2.0) * 0.04


func prompt_text() -> String:
	return "[E] Grab %s  ($%d)" % [display_name, value]


## Removes the loot with a quick shrink so the grab reads clearly.
func take() -> void:
	collision_layer = 0
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.2)
	tween.tween_callback(queue_free)
