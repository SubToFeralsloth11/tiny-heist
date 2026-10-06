class_name Loot
extends Interactable
## A valuable on a pedestal (or a painting on a wall). Grabbing it flies it into your hand.

var kind := "$"
var display_name := ""
var value := 0

var _mesh: Node3D
var _time := randf() * TAU


func _ready() -> void:
	var glow_color := Color(1.0, 0.8, 0.3)
	match kind:
		"$":
			_mesh = _box(Vector3(0.5, 0.18, 0.25), _shiny(Color(1.0, 0.78, 0.2), Color(0.6, 0.4, 0.0), 1.0))
		"g":
			_mesh = _gem(0.2, 0.4, 6, _shiny(Color(0.95, 0.1, 0.25), Color(0.8, 0.0, 0.15), 1.0))
			glow_color = Color(1.0, 0.2, 0.3)
		"a":
			_mesh = Node3D.new()
			var clay := _shiny(Color(0.25, 0.45, 0.7), Color(0.05, 0.1, 0.2), 0.3)
			var band := _shiny(Color(0.9, 0.75, 0.3), Color(0.3, 0.2, 0.0), 0.5)
			_part(_mesh, Vector3(0.36, 0.4, 0.36), Vector3(0, 0.05, 0), clay)
			_part(_mesh, Vector3(0.2, 0.2, 0.2), Vector3(0, 0.33, 0), clay)
			_part(_mesh, Vector3(0.38, 0.05, 0.38), Vector3(0, 0.1, 0), band)
			_part(_mesh, Vector3(0.26, 0.05, 0.26), Vector3(0, 0.45, 0), band)
			glow_color = Color(0.5, 0.7, 1.0)
		"p":
			_mesh = Node3D.new()
			var frame := _shiny(Color(0.9, 0.7, 0.25), Color(0.3, 0.2, 0.0), 0.5)
			_part(_mesh, Vector3(1.6, 1.2, 0.08), Vector3(0, 0, 0.04), frame)
			_part(_mesh, Vector3(1.4, 1.0, 0.02), Vector3(0, 0, 0.09), _shiny(Color(0.1, 0.2, 0.45), Color.BLACK, 0.0))
			_part(_mesh, Vector3(0.5, 0.5, 0.02), Vector3(0.2, 0.1, 0.11), _shiny(Color(1.0, 0.8, 0.2), Color(0.5, 0.35, 0), 0.4))
			_part(_mesh, Vector3(1.4, 0.3, 0.02), Vector3(0, -0.35, 0.11), _shiny(Color(0.15, 0.4, 0.2), Color.BLACK, 0.0))
			_part(_mesh, Vector3(0.25, 0.6, 0.02), Vector3(-0.4, -0.05, 0.12), _shiny(Color(0.05, 0.05, 0.08), Color.BLACK, 0.0))
			glow_color = Color(1.0, 0.85, 0.5)
		_:
			_mesh = _gem(0.32, 0.7, 8, _shiny(Color(0.75, 0.95, 1.0), Color(0.4, 0.8, 1.0), 2.0))
			glow_color = Color(0.5, 0.9, 1.0)
	add_child(_mesh)
	if kind == "p":
		add_hit_box(Vector3(1.7, 1.3, 0.6), Vector3(0, 0, 0.3))
	else:
		add_hit_box(Vector3(0.9, 0.9, 0.9))

	var light := OmniLight3D.new()
	light.light_color = glow_color
	light.light_energy = 0.8
	light.omni_range = 2.5
	light.position.z = 0.5 if kind == "p" else 0.0
	add_child(light)


func _process(delta: float) -> void:
	if kind == "p":
		return
	_time += delta
	_mesh.rotation.y = _time * 1.2
	_mesh.position.y = sin(_time * 2.0) * 0.04


func prompt_text(_player: Player) -> String:
	return "[E] Steal %s  ($%d)" % [display_name, value]


func interact(player: Player) -> void:
	disable_interaction()
	set_process(false)
	player.collect(self)
	# Fly into the player's hand while shrinking.
	var hand := player.hand_position()
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "global_position", hand, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


func _shiny(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = 0.6
	mat.roughness = 0.2
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	return mat


func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	return mi


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := _box(size, mat)
	mi.position = pos
	parent.add_child(mi)


func _gem(radius: float, height: float, sides: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radius = radius
	gem.height = height
	gem.radial_segments = sides
	gem.rings = 2
	gem.material = mat
	mi.mesh = gem
	return mi
