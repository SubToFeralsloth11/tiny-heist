class_name VaultDoor
extends Interactable
## Heavy steel door that slides up when you swipe the keycard.

signal opened

var cell := Vector2i.ZERO
var level: Level
var is_open := false

var _slab: Node3D
var _light_mat: StandardMaterial3D


func _ready() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.45, 0.47, 0.5)
	steel.metallic = 0.9
	steel.roughness = 0.3
	_slab = Node3D.new()
	add_child(_slab)
	_part(_slab, Vector3(Level.CELL, Level.WALL_H, 0.5), Vector3(0, Level.WALL_H * 0.5, 0), steel)
	var bolt := StandardMaterial3D.new()
	bolt.albedo_color = Color(0.2, 0.2, 0.22)
	bolt.metallic = 1.0
	for side in [-1, 1]:
		_part(_slab, Vector3(1.2, 1.2, 0.1), Vector3(0, 1.6, side * 0.28), bolt)
	var body := StaticBody3D.new()
	body.collision_layer = Level.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Level.CELL, Level.WALL_H, 0.5)
	shape.shape = box
	shape.position.y = Level.WALL_H * 0.5
	body.add_child(shape)
	_slab.add_child(body)

	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_color = Color(1, 0.1, 0.1)
	_light_mat.emission_enabled = true
	_light_mat.emission = Color(1, 0.1, 0.1)
	_light_mat.emission_energy_multiplier = 3.0
	for side in [-1, 1]:
		_part(_slab, Vector3(0.25, 0.25, 0.05), Vector3(1.1, 1.4, side * 0.3), _light_mat)
	add_hit_box(Vector3(Level.CELL, 2.5, 1.6), Vector3(0, 1.25, 0))


func prompt_text(player: Player) -> String:
	if is_open:
		return ""
	return "[E] Swipe keycard" if player.has_keycard else "Locked: find the keycard in the security office"


func interact(player: Player) -> void:
	if is_open or not player.has_keycard:
		return
	is_open = true
	disable_interaction()
	_light_mat.albedo_color = Color(0.1, 1, 0.3)
	_light_mat.emission = Color(0.1, 1, 0.3)
	var tween := create_tween()
	tween.tween_interval(0.3)
	tween.tween_property(_slab, "position:y", Level.WALL_H - 0.3, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	level.set_walkable(cell, true)
	opened.emit()


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
