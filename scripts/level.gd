class_name Level
extends Node3D
## Builds the museum from an ASCII map and owns grid pathfinding.
##
## Legend: '#' wall, '.' floor, 'P' player start, 'E' getaway van zone,
## '$' gold bar, 'g' gem, 'V' the Big Diamond, 'L' blinking laser door.

const CELL := 3.0
const WALL_H := 4.0

const MAP: Array[String] = [
	"###############################",
	"#.......#.........#..........$#",
	"#...g...#....$....#...........#",
	"#.......#.........#....####...#",
	"#...................#..#$.#...#",
	"#.......#.........#.#..#..#...#",
	"#.......#.........#....##.#...#",
	"####.#####.......##...........#",
	"#.......####.#######.....g....#",
	"#.P.....#.....................#",
	"#.......#.........#############",
	"#.......#..g......#..........$#",
	"#EE.....#.........L.....V.....#",
	"#EE.....#....$....#...........#",
	"###############################",
]

## Patrol routes in grid cells. Guards walk them in a loop.
const PATROLS := [
	[Vector2i(10, 1), Vector2i(16, 1), Vector2i(16, 6), Vector2i(10, 6)],
	[Vector2i(20, 1), Vector2i(29, 2), Vector2i(29, 8), Vector2i(20, 8)],
	[Vector2i(9, 9), Vector2i(29, 9)],
	[Vector2i(10, 11), Vector2i(16, 11), Vector2i(16, 13), Vector2i(10, 13)],
	[Vector2i(20, 11), Vector2i(28, 11), Vector2i(28, 13), Vector2i(20, 13)],
]

const LOOT := {
	"$": {"name": "Gold Bar", "value": 500},
	"g": {"name": "Ruby Gem", "value": 1000},
	"V": {"name": "The Big Diamond", "value": 5000},
}

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const LOOT_LAYER := 8

var astar := AStarGrid2D.new()
var player_start := Vector3.ZERO
var loot_total := 0

var _wall_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D


func _ready() -> void:
	_build_materials()
	_build_floor_and_ceiling()
	_build_walls()
	_build_lights()
	_build_grid()
	for y in MAP.size():
		for x in MAP[y].length():
			var c := MAP[y][x]
			var cell := Vector2i(x, y)
			match c:
				"P":
					player_start = cell_to_world(cell)
				"$", "g", "V":
					_spawn_loot(cell, c)
				"L":
					_spawn_laser(cell)
	_spawn_van()


static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL + CELL * 0.5, 0.0, cell.y * CELL + CELL * 0.5)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func is_floor(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= MAP.size() or cell.x < 0 or cell.x >= MAP[cell.y].length():
		return false
	return MAP[cell.y][cell.x] != "#"


## World-space path between two points, following floor cells.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := _nearest_floor(world_to_cell(from))
	var b := _nearest_floor(world_to_cell(to))
	for c in astar.get_id_path(a, b):
		out.append(cell_to_world(c))
	if out.size() > 0:
		# End exactly on the requested point instead of the cell centre.
		out[out.size() - 1] = Vector3(to.x, 0.0, to.z)
	return out


func _nearest_floor(cell: Vector2i) -> Vector2i:
	if is_floor(cell):
		return cell
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if is_floor(cell + d):
			return cell + d
	return cell


func _build_grid() -> void:
	astar.region = Rect2i(0, 0, MAP[0].length(), MAP.size())
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in MAP.size():
		for x in MAP[y].length():
			astar.set_point_solid(Vector2i(x, y), MAP[y][x] == "#")


func _build_materials() -> void:
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.42, 0.16, 0.18)
	_wall_mat.roughness = 0.9
	_trim_mat = StandardMaterial3D.new()
	_trim_mat.albedo_color = Color(0.85, 0.72, 0.45)
	_trim_mat.metallic = 0.6
	_trim_mat.roughness = 0.35


func _checker_texture(a: Color, b: Color) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, a if ((x / 32) + (y / 32)) % 2 == 0 else b)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_floor_and_ceiling() -> void:
	var w := MAP[0].length() * CELL
	var d := MAP.size() * CELL
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = _checker_texture(Color(0.82, 0.8, 0.74), Color(0.22, 0.22, 0.25))
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_scale = Vector3.ONE / CELL
	floor_mat.roughness = 0.25
	_add_box(Vector3(w * 0.5, -0.25, d * 0.5), Vector3(w, 0.5, d), floor_mat, true)
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.12, 0.11, 0.14)
	_add_box(Vector3(w * 0.5, WALL_H + 0.25, d * 0.5), Vector3(w, 0.5, d), ceil_mat, true)


func _build_walls() -> void:
	# Merge horizontal runs of wall cells into single boxes.
	for y in MAP.size():
		var x := 0
		var row := MAP[y]
		while x < row.length():
			if row[x] != "#":
				x += 1
				continue
			var start := x
			while x < row.length() and row[x] == "#":
				x += 1
			var length := (x - start) * CELL
			var center := Vector3(start * CELL + length * 0.5, WALL_H * 0.5, y * CELL + CELL * 0.5)
			_add_box(center, Vector3(length, WALL_H, CELL), _wall_mat, true)
			# Gold trim strip along the base for a museum look.
			_add_box(center + Vector3(0, -WALL_H * 0.5 + 0.15, 0), Vector3(length + 0.04, 0.3, CELL + 0.04), _trim_mat, false)


func _build_lights() -> void:
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.85, 0.6)
	lamp_mat.emission_energy_multiplier = 2.0
	lamp_mat.albedo_color = Color(1, 0.9, 0.7)
	for y in MAP.size():
		for x in MAP[y].length():
			if MAP[y][x] == "#" or x % 4 != 2 or y % 4 != 1:
				continue
			var p := cell_to_world(Vector2i(x, y))
			var light := OmniLight3D.new()
			light.position = p + Vector3(0, WALL_H - 0.6, 0)
			light.light_color = Color(1.0, 0.82, 0.6)
			light.light_energy = 0.9
			light.omni_range = 8.0
			add_child(light)
			_add_box(p + Vector3(0, WALL_H - 0.05, 0), Vector3(0.8, 0.1, 0.8), lamp_mat, false)


func _add_box(pos: Vector3, size: Vector3, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		body.position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)


func _spawn_loot(cell: Vector2i, kind: String) -> void:
	var info: Dictionary = LOOT[kind]
	loot_total += info.value
	var p := cell_to_world(cell)
	var pedestal_mat := StandardMaterial3D.new()
	pedestal_mat.albedo_color = Color(0.9, 0.88, 0.82)
	_add_box(p + Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9), pedestal_mat, true)
	var loot := Loot.new()
	loot.kind = kind
	loot.display_name = info.name
	loot.value = info.value
	loot.position = p + Vector3(0, 1.25, 0)
	add_child(loot)


func _spawn_laser(cell: Vector2i) -> void:
	var laser := LaserDoor.new()
	laser.position = cell_to_world(cell)
	laser.width = CELL
	add_child(laser)


func _spawn_van() -> void:
	var cells: Array[Vector2i] = []
	for y in MAP.size():
		for x in MAP[y].length():
			if MAP[y][x] == "E":
				cells.append(Vector2i(x, y))
	var center := Vector3.ZERO
	for c in cells:
		center += cell_to_world(c)
	center /= cells.size()

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.15, 0.15, 0.17)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.3, 0.5, 0.6)
	glass_mat.metallic = 0.8
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.05, 0.05, 0.05)
	var van_pos := center + Vector3(-1.2, 0, 0)
	_add_box(van_pos + Vector3(0, 1.2, 0), Vector3(2.2, 1.9, 4.2), body_mat, true)
	_add_box(van_pos + Vector3(0, 1.6, -2.15), Vector3(2.0, 0.8, 0.1), glass_mat, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.4, 1.4]:
			_add_box(van_pos + Vector3(sx * 1.1, 0.35, sz), Vector3(0.3, 0.7, 0.7), wheel_mat, false)

	var label := Label3D.new()
	label.text = "GETAWAY VAN"
	label.font_size = 64
	label.modulate = Color(0.4, 1.0, 0.5)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = van_pos + Vector3(0, 2.8, 0)
	add_child(label)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.3, 1.0, 0.4)
	glow.light_energy = 1.5
	glow.omni_range = 6.0
	glow.position = center + Vector3(0, 2.5, 0)
	add_child(glow)

	var zone := Area3D.new()
	zone.name = "ExitZone"
	zone.collision_layer = 0
	zone.collision_mask = PLAYER_LAYER
	zone.position = center + Vector3(0, 1, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL * 2, 2, CELL * 2)
	shape.shape = box
	zone.add_child(shape)
	add_child(zone)
