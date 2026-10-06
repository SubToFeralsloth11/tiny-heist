class_name SecurityPanel
extends Interactable
## Wall panel. Hold E to shut down every camera and laser in the museum.

signal hacked

const HACK_TIME := 3.0

var _screen_mat: StandardMaterial3D
var _done := false


func _ready() -> void:
	var case_mat := StandardMaterial3D.new()
	case_mat.albedo_color = Color(0.2, 0.22, 0.25)
	case_mat.metallic = 0.5
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.1, 0.9, 0.3)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0.1, 0.9, 0.3)
	_screen_mat.emission_energy_multiplier = 1.5
	_part(Vector3(1.2, 1.4, 0.15), Vector3(0, 1.6, 0.075), case_mat)
	_part(Vector3(0.9, 0.5, 0.02), Vector3(0, 1.9, 0.16), _screen_mat)
	for i in 6:
		var btn := StandardMaterial3D.new()
		btn.albedo_color = [Color.RED, Color.YELLOW, Color.GREEN][i % 3]
		btn.emission_enabled = true
		btn.emission = btn.albedo_color
		_part(Vector3(0.12, 0.12, 0.04), Vector3(-0.3 + (i % 3) * 0.3, 1.35 - (i / 3) * 0.2, 0.17), btn)
	add_hit_box(Vector3(1.4, 1.6, 0.8), Vector3(0, 1.6, 0.4))


func prompt_text(_player: Player) -> String:
	return "" if _done else "[Hold E] Shut down cameras & lasers"


func hold_time() -> float:
	return HACK_TIME


func interact(_player: Player) -> void:
	_done = true
	disable_interaction()
	_screen_mat.albedo_color = Color(0.9, 0.1, 0.1)
	_screen_mat.emission = Color(0.9, 0.1, 0.1)
	hacked.emit()


func _part(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	add_child(mi)
