class_name Keycard
extends Interactable
## Security keycard on the guard desk. Opens the vault door.

var _card: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	_card = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.02, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.4, 1.0)
	mat.emission_energy_multiplier = 1.5
	box.material = mat
	_card.mesh = box
	add_child(_card)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.6, 1.0)
	light.omni_range = 2.0
	light.position.y = 0.3
	add_child(light)
	add_hit_box(Vector3(0.8, 0.6, 0.8), Vector3(0, 0.2, 0))


func _process(delta: float) -> void:
	_time += delta
	_card.position.y = 0.12 + sin(_time * 2.5) * 0.04
	_card.rotation.y = _time


func prompt_text(_player: Player) -> String:
	return "[E] Take Security Keycard"


func interact(player: Player) -> void:
	disable_interaction()
	player.has_keycard = true
	player.collect_item(self)
	queue_free()
