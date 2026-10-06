class_name Level
extends Node3D
## Builds the museum from an ASCII map and owns grid pathfinding.
##
## Legend:
##   '#' wall   '.' floor   'P' player start   'E' getaway van zone
##   Loot: '$' gold bar  'g' ruby  'a' vase  'p' painting (on wall)  'V' Big Diamond
##   Security: 'C' camera (on wall)  'L' blinking laser door  'D' keycard vault door
##             'K' keycard on a desk  'F' security panel (on wall)
##   'H' hiding locker (against wall)
##   Decor: 'u' pillar  's' statue  'b' bench  'o' potted plant

const CELL := 3.0
const WALL_H := 4.0

const MAP: Array[String] = [
	"#############################################",
	"#C.....#.........p.....C...p.........#..K..H#",
	"#..g...#..u.....u.....u.....u.....u..#.....H#",
	"#......#.................a...........#F....H#",
	"#..s...#..u.....u.....u.....u.....u..#.....H#",
	"#......#....$.........$.........$....#C.....#",
	"#..o.......................................o#",
	"####.####.....p.........o........p...####.###",
	"#.......#####.#########.##############.....##",
	"#.......#C...........#.....#.........#.....##",
	"#.......#....b..b....#.$...#..s...s..#..g..##",
	"#.......#............#.....#.........#.....##",
	"#.......#..g...a.....#.....#....V....L.....##",
	"#..P....#............#.....#.........#.....##",
	"#.......#....b..b....#H....#..s...s..#C....##",
	"#.......#....p.......#.....#.........#.....##",
	"#.......####.#########.....######D####.....##",
	"#..o.......................................##",
	"#.......#####.#######.......#######.#########",
	"#.......#C....#.....#.......#...p...#.......#",
	"#.......#..$..#..a..#...o...#...$...#..u..g.#",
	"#EE.....#.....#.....#.......#.......L.......#",
	"#EE.....#.........................H.#...$...#",
	"#############################################",
]

## Patrol routes in grid cells. Guards walk them in a loop.
const PATROLS := [
	[Vector2i(9, 1), Vector2i(36, 1), Vector2i(36, 5), Vector2i(9, 5)],
	[Vector2i(4, 6), Vector2i(40, 6)],
	[Vector2i(10, 9), Vector2i(19, 9), Vector2i(19, 15), Vector2i(10, 15)],
	[Vector2i(23, 9), Vector2i(25, 16)],
	[Vector2i(29, 9), Vector2i(35, 9), Vector2i(35, 15), Vector2i(29, 15)],
	[Vector2i(1, 17), Vector2i(42, 17)],
	[Vector2i(38, 1), Vector2i(42, 5)],
	[Vector2i(39, 9), Vector2i(42, 16)],
	[Vector2i(10, 21), Vector2i(33, 22)],
]

const LOOT := {
	"$": {"name": "Gold Bar", "value": 500},
	"a": {"name": "Ancient Vase", "value": 750},
	"g": {"name": "Ruby", "value": 1000},
	"p": {"name": "Famous Painting", "value": 1500},
	"V": {"name": "The Big Diamond", "value": 5000},
}

## Cells guards path around (things with a footprint in the middle of the cell).
const BLOCKING := "#usbo$agVK"

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const INTERACT_LAYER := 8

var astar := AStarGrid2D.new()
var player_start := Vector3.ZERO
var loot_total := 0
var cameras: Array[SecurityCamera] = []
var lasers: Array[LaserDoor] = []
var vault_doors: Array[VaultDoor] = []
var interactables: Array[Interactable] = []

var _mats := {}


func _ready() -> void:
	_build_materials()
	_build_floor_and_ceiling()
	_build_walls()
	_build_lights()
	_build_grid()
	_build_runners()
	for y in MAP.size():
		for x in MAP[y].length():
			_build_cell(Vector2i(x, y), MAP[y][x])
	_build_wall_art()
	_spawn_van()


static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL + CELL * 0.5, 0.0, cell.y * CELL + CELL * 0.5)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func char_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= MAP.size() or cell.x < 0 or cell.x >= MAP[cell.y].length():
		return "#"
	return MAP[cell.y][cell.x]


## Direction (in cells) of the first wall touching this cell, used to mount things.
static func wall_dir(cell: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		if char_at(cell + d) == "#":
			return d
	return Vector2i.ZERO


## Yaw that makes a node's local +Z face away from the wall in direction `d`.
static func facing_from_wall(d: Vector2i) -> float:
	return atan2(-d.x, -d.y)


## World-space path between two points, following walkable cells.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := _nearest_walkable(world_to_cell(from))
	var b := _nearest_walkable(world_to_cell(to))
	var cells := astar.get_id_path(a, b)
	for c in cells:
		out.append(cell_to_world(c))
	if out.size() > 0 and not astar.is_point_solid(world_to_cell(to)):
		# End exactly on the requested point instead of the cell centre.
		out[out.size() - 1] = Vector3(to.x, 0.0, to.z)
	return out


func set_walkable(cell: Vector2i, walkable: bool) -> void:
	astar.set_point_solid(cell, not walkable)


func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if astar.is_in_boundsv(cell) and not astar.is_point_solid(cell):
		return cell
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n := cell + d
		if astar.is_in_boundsv(n) and not astar.is_point_solid(n):
			return n
	return cell


func _build_grid() -> void:
	astar.region = Rect2i(0, 0, MAP[0].length(), MAP.size())
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in MAP.size():
		for x in MAP[y].length():
			var c := MAP[y][x]
			astar.set_point_solid(Vector2i(x, y), BLOCKING.contains(c) or c == "D")


func _build_cell(cell: Vector2i, c: String) -> void:
	var p := cell_to_world(cell)
	match c:
		"P":
			player_start = p
		"$", "g", "a", "V":
			_spawn_pedestal_loot(cell, c)
		"p":
			_spawn_painting_loot(cell)
		"L":
			var laser := LaserDoor.new()
			laser.position = p
			laser.width = CELL
			laser.rotation.y = 0.0 if char_at(cell + Vector2i.UP) == "#" else PI * 0.5
			add_child(laser)
			lasers.append(laser)
		"D":
			var door := VaultDoor.new()
			door.cell = cell
			door.level = self
			door.position = p
			door.rotation.y = 0.0 if char_at(cell + Vector2i.LEFT) == "#" else PI * 0.5
			add_child(door)
			vault_doors.append(door)
			interactables.append(door)
		"C":
			var cam := SecurityCamera.new()
			var d := wall_dir(cell)
			cam.position = p + Vector3(d.x, 0, d.y) * (CELL * 0.5 - 0.15) + Vector3(0, WALL_H - 0.5, 0)
			cam.base_yaw = facing_from_wall(d)
			add_child(cam)
			cameras.append(cam)
		"K":
			_add_box(p + Vector3(0, 0.45, 0), Vector3(1.6, 0.9, 0.9), _mats.desk, true)
			var card := Keycard.new()
			card.position = p + Vector3(0, 0.95, 0)
			add_child(card)
			interactables.append(card)
		"F":
			var panel := SecurityPanel.new()
			var d := wall_dir(cell)
			panel.position = p + Vector3(d.x, 0, d.y) * (CELL * 0.5 - 0.1)
			panel.rotation.y = facing_from_wall(d)
			add_child(panel)
			interactables.append(panel)
		"H":
			var locker := Locker.new()
			var d := wall_dir(cell)
			locker.position = p + Vector3(d.x, 0, d.y) * (CELL * 0.5 - 0.45)
			locker.rotation.y = facing_from_wall(d)
			add_child(locker)
			interactables.append(locker)
		"u":
			_add_box(p + Vector3(0, WALL_H * 0.5, 0), Vector3(0.9, WALL_H, 0.9), _mats.marble, true)
			_add_box(p + Vector3(0, 0.15, 0), Vector3(1.2, 0.3, 1.2), _mats.marble_dark, false)
			_add_box(p + Vector3(0, WALL_H - 0.15, 0), Vector3(1.2, 0.3, 1.2), _mats.marble_dark, false)
		"s":
			_spawn_statue(p)
		"b":
			_add_box(p + Vector3(0, 0.25, 0), Vector3(2.0, 0.5, 0.7), _mats.wood, true)
			_add_box(p + Vector3(0, 0.55, 0), Vector3(2.0, 0.1, 0.7), _mats.leather, false)
		"o":
			_spawn_plant(p)


func _build_materials() -> void:
	_mats.wall = _mat(Color(0.42, 0.16, 0.18), 0.9)
	_mats.trim = _mat(Color(0.85, 0.72, 0.45), 0.35, 0.6)
	_mats.marble = _mat(Color(0.86, 0.85, 0.82), 0.3)
	_mats.marble_dark = _mat(Color(0.55, 0.53, 0.5), 0.4)
	_mats.wood = _mat(Color(0.35, 0.2, 0.1), 0.7)
	_mats.leather = _mat(Color(0.15, 0.05, 0.05), 0.6)
	_mats.desk = _mat(Color(0.25, 0.25, 0.28), 0.6)
	_mats.pedestal = _mat(Color(0.9, 0.88, 0.82), 0.5)
	_mats.gold = _mat(Color(0.85, 0.68, 0.3), 0.3, 0.9)
	_mats.velvet = _mat(Color(0.55, 0.02, 0.05), 0.8)
	_mats.runner = _mat(Color(0.4, 0.03, 0.06), 1.0)
	_mats.pot = _mat(Color(0.6, 0.35, 0.2), 0.8)
	_mats.leaf = _mat(Color(0.15, 0.45, 0.18), 0.8)
	_mats.lamp = _mat(Color(1, 0.9, 0.7), 0.5)
	_mats.lamp.emission_enabled = true
	_mats.lamp.emission = Color(1.0, 0.85, 0.6)
	_mats.lamp.emission_energy_multiplier = 2.0


func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


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
	_add_box(Vector3(w * 0.5, WALL_H + 0.25, d * 0.5), Vector3(w, 0.5, d), _mat(Color(0.12, 0.11, 0.14), 1.0), true)


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
			_add_box(center, Vector3(length, WALL_H, CELL), _mats.wall, true)
			# Gold trim along the base and a crown moulding at the top.
			_add_box(center + Vector3(0, -WALL_H * 0.5 + 0.15, 0), Vector3(length + 0.04, 0.3, CELL + 0.04), _mats.trim, false)
			_add_box(center + Vector3(0, WALL_H * 0.5 - 0.12, 0), Vector3(length + 0.06, 0.24, CELL + 0.06), _mats.trim, false)


## Red carpet runners along the two long corridors.
func _build_runners() -> void:
	for y in [6, 17]:
		var row := MAP[y]
		var x := 1
		while x < row.length():
			if row[x] == "#":
				x += 1
				continue
			var start := x
			while x < row.length() and row[x] != "#":
				x += 1
			var length := (x - start) * CELL - 1.0
			_add_box(Vector3(start * CELL + 0.5 + length * 0.5, 0.01, y * CELL + CELL * 0.5), Vector3(length, 0.02, 1.4), _mats.runner, false)


func _build_lights() -> void:
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
			_add_box(p + Vector3(0, WALL_H - 0.05, 0), Vector3(0.8, 0.1, 0.8), _mats.lamp, false)


## Decorative framed art on plain walls so rooms don't feel empty.
func _build_wall_art() -> void:
	var palette := [Color(0.2, 0.35, 0.6), Color(0.75, 0.55, 0.2), Color(0.25, 0.5, 0.3),
		Color(0.6, 0.2, 0.25), Color(0.5, 0.4, 0.65), Color(0.85, 0.8, 0.6)]
	for y in MAP.size():
		for x in MAP[y].length():
			if MAP[y][x] != "." or (x * 73 + y * 151) % 5 != 0:
				continue
			var cell := Vector2i(x, y)
			var d := wall_dir(cell)
			if d == Vector2i.ZERO:
				continue
			var art := Node3D.new()
			art.position = cell_to_world(cell) + Vector3(d.x, 0, d.y) * (CELL * 0.5 - 0.02) + Vector3(0, 2.1, 0)
			art.rotation.y = facing_from_wall(d)
			add_child(art)
			var seed := x * 31 + y * 17
			_add_box_to(art, Vector3(1.3, 1.0, 0.06), Vector3(0, 0, 0.03), _mats.trim)
			_add_box_to(art, Vector3(1.1, 0.8, 0.02), Vector3(0, 0, 0.07), _mat(palette[seed % palette.size()], 0.9))
			for i in 3:
				var c: Color = palette[(seed + i + 1) % palette.size()]
				var size := Vector3(0.2 + 0.1 * ((seed + i) % 3), 0.2 + 0.1 * ((seed * 2 + i) % 3), 0.02)
				var off := Vector3(-0.3 + 0.3 * i, -0.15 + 0.15 * ((seed + i) % 3), 0.085)
				_add_box_to(art, size, off, _mat(c, 0.9))


func _spawn_pedestal_loot(cell: Vector2i, kind: String) -> void:
	var p := cell_to_world(cell)
	_add_box(p + Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9), _mats.pedestal, true)
	_add_box(p + Vector3(0, 1.02, 0), Vector3(1.0, 0.06, 1.0), _mats.trim, false)
	if kind in ["g", "V"]:
		_spawn_velvet_ropes(p)
	_spawn_loot(kind, p + Vector3(0, 1.25, 0), 0.0)


func _spawn_painting_loot(cell: Vector2i) -> void:
	var d := wall_dir(cell)
	var p := cell_to_world(cell) + Vector3(d.x, 0, d.y) * (CELL * 0.5 - 0.1) + Vector3(0, 2.0, 0)
	_spawn_loot("p", p, facing_from_wall(d))
	_spawn_velvet_ropes(cell_to_world(cell) + Vector3(d.x, 0, d.y) * 0.4, true)


func _spawn_loot(kind: String, pos: Vector3, yaw: float) -> void:
	var info: Dictionary = LOOT[kind]
	loot_total += info.value
	var loot := Loot.new()
	loot.kind = kind
	loot.display_name = info.name
	loot.value = info.value
	loot.position = pos
	loot.rotation.y = yaw
	add_child(loot)
	interactables.append(loot)


## Brass posts with red rope. `front_only` draws a single rope line (for wall paintings).
func _spawn_velvet_ropes(center: Vector3, front_only := false) -> void:
	var r := 1.0
	var corners := [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]
	if front_only:
		corners = [Vector3(-r, 0, 0), Vector3(r, 0, 0)]
	for c: Vector3 in corners:
		_add_box(center + c + Vector3(0, 0.45, 0), Vector3(0.08, 0.9, 0.08), _mats.gold, false)
	var count := corners.size() if not front_only else 1
	for i in count:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var mid := (a + b) * 0.5
		var size := Vector3(absf(b.x - a.x) + 0.04, 0.05, absf(b.z - a.z) + 0.04)
		_add_box(center + mid + Vector3(0, 0.78, 0), size, _mats.velvet, false)


func _spawn_statue(p: Vector3) -> void:
	_add_box(p + Vector3(0, 0.4, 0), Vector3(1.2, 0.8, 1.2), _mats.marble_dark, true)
	_add_box(p + Vector3(0, 1.3, 0), Vector3(0.6, 1.0, 0.4), _mats.marble, false)
	_add_box(p + Vector3(0, 2.0, 0), Vector3(0.36, 0.4, 0.36), _mats.marble, false)
	_add_box(p + Vector3(0.45, 1.6, 0), Vector3(0.2, 0.7, 0.2), _mats.marble, false)
	_add_box(p + Vector3(-0.45, 1.3, 0), Vector3(0.2, 0.7, 0.2), _mats.marble, false)


func _spawn_plant(p: Vector3) -> void:
	_add_box(p + Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), _mats.pot, true)
	for i in 4:
		var a := i * PI * 0.5 + 0.4
		_add_box(p + Vector3(cos(a) * 0.15, 0.95, sin(a) * 0.15), Vector3(0.35, 0.7, 0.35), _mats.leaf, false)
	_add_box(p + Vector3(0, 1.35, 0), Vector3(0.3, 0.4, 0.3), _mats.leaf, false)


func _add_box(pos: Vector3, size: Vector3, mat: Material, solid: bool) -> void:
	_add_box_to(self, size, pos, mat)
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


func _add_box_to(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)


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

	var van := Node3D.new()
	van.name = "Van"
	van.position = center + Vector3(-1.2, 0, 0)
	add_child(van)
	var body_mat := _mat(Color(0.15, 0.15, 0.17), 0.5)
	var glass_mat := _mat(Color(0.3, 0.5, 0.6), 0.1, 0.8)
	var wheel_mat := _mat(Color(0.05, 0.05, 0.05), 0.9)
	var head_mat := _mat(Color(1, 1, 0.8), 0.2)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1, 0.95, 0.7)
	head_mat.emission_energy_multiplier = 3.0
	var body := Node3D.new()
	body.name = "Body"
	van.add_child(body)
	_add_box_to(body, Vector3(2.2, 1.9, 4.2), Vector3(0, 1.2, 0), body_mat)
	_add_box_to(body, Vector3(2.0, 0.8, 0.1), Vector3(0, 1.6, -2.15), glass_mat)
	for sx in [-0.7, 0.7]:
		_add_box_to(body, Vector3(0.4, 0.25, 0.06), Vector3(sx, 0.75, -2.12), head_mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.4, 1.4]:
			_add_box_to(van, Vector3(0.3, 0.7, 0.7), Vector3(sx * 1.1, 0.35, sz), wheel_mat)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = WORLD_LAYER
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(2.2, 2.2, 4.2)
	bshape.shape = bbox
	bshape.position.y = 1.1
	blocker.add_child(bshape)
	van.add_child(blocker)
	# Idling engine wobble.
	var tween := body.create_tween().set_loops()
	tween.tween_property(body, "position:y", 0.03, 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_property(body, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_SINE)

	var label := Label3D.new()
	label.text = "GETAWAY VAN"
	label.font_size = 64
	label.outline_size = 12
	label.modulate = Color(0.4, 1.0, 0.5)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.9, 0)
	van.add_child(label)
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
