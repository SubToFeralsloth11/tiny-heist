class_name Interactable
extends Area3D
## Something the player can aim at and press E on. The player's ray hits this Area.


func _init() -> void:
	collision_layer = Level.INTERACT_LAYER
	collision_mask = 0
	monitoring = false


## Text shown under the crosshair. Empty hides the prompt and blocks interaction.
func prompt_text(_player: Player) -> String:
	return ""


## Seconds E must be held. 0 means instant.
func hold_time() -> float:
	return 0.0


func interact(_player: Player) -> void:
	pass


## Adds a box-shaped hit area, slightly larger than the visible object.
func add_hit_box(size: Vector3, offset := Vector3.ZERO) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	add_child(shape)


func disable_interaction() -> void:
	collision_layer = 0
