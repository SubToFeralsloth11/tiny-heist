class_name Locker
extends Interactable
## Staff locker you can hide inside. Guards can't see you in here, unless they watched you get in.

var _door: Node3D


func _ready() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.35, 0.42, 0.45)
	metal.metallic = 0.6
	metal.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.06)
	# Back, sides and roof as separate slabs so the player camera sits in a hollow box.
	_part(self, Vector3(1.0, 2.2, 0.05), Vector3(0, 1.1, -0.42), metal)
	_part(self, Vector3(0.05, 2.2, 0.85), Vector3(-0.5, 1.1, 0), metal)
	_part(self, Vector3(0.05, 2.2, 0.85), Vector3(0.5, 1.1, 0), metal)
	_part(self, Vector3(1.0, 0.05, 0.85), Vector3(0, 2.2, 0), metal)

	var body := StaticBody3D.new()
	body.collision_layer = Level.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.2, 0.85)
	shape.shape = box
	shape.position.y = 1.1
	body.add_child(shape)
	add_child(body)

	# Door hinged on its left edge so it can swing open.
	_door = Node3D.new()
	_door.position = Vector3(-0.5, 0, 0.43)
	add_child(_door)
	_part(_door, Vector3(1.0, 2.2, 0.04), Vector3(0.5, 1.1, 0), metal)
	for i in 4:
		_part(_door, Vector3(0.6, 0.03, 0.02), Vector3(0.5, 1.75 - i * 0.06, 0.025), dark)
	add_hit_box(Vector3(1.2, 2.3, 1.1), Vector3(0, 1.15, 0.15))


## Where the player's feet go while hiding.
func hide_position() -> Vector3:
	return global_transform * Vector3(0, 0.05, 0.05)


## The direction the hidden player looks (out through the vents).
func facing_yaw() -> float:
	return global_rotation.y


func prompt_text(player: Player) -> String:
	return "[E] Get out" if player.hiding_in == self else "[E] Hide in locker"


func interact(player: Player) -> void:
	var entering := player.hiding_in != self
	if entering:
		player.enter_locker(self)
	else:
		player.leave_locker()
	swing_door(entering)


## Swings the door open and shut. From inside, the door is hidden so the
## HUD's vent overlay is the only thing between you and the room.
func swing_door(hide_after: bool) -> void:
	_door.visible = true
	var tween := create_tween()
	tween.tween_property(_door, "rotation:y", -1.6, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.2)
	tween.tween_property(_door, "rotation:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD)
	if hide_after:
		tween.tween_callback(func() -> void: _door.visible = false)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
