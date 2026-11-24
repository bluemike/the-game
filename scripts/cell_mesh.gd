extends RefCounted
## Builds a single mesh for a group of cells. Only the outside faces are drawn,
## so a tunnel looks like one continuous solid instead of a stack of boxes.

const DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## color_of(cell) gives each cell's vertex colour. Returns null for no cells.
static func build(cells: Array, color_of: Callable) -> ArrayMesh:
	if cells.is_empty():
		return null
	var filled := {}
	for c in cells:
		filled[c] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in cells:
		var color: Color = color_of.call(c)
		for dir in DIRECTIONS:
			if not filled.has(c + dir):
				_add_face(st, c, dir, color)
	return st.commit()


static func _add_face(st: SurfaceTool, cell: Vector3i, dir: Vector3i, color: Color) -> void:
	var a := 0 if dir.x != 0 else (1 if dir.y != 0 else 2)
	var positive: bool = dir[a] > 0
	var u := (a + 1) % 3
	var v := (a + 2) % 3
	var corners: Array[Vector3] = []
	for p in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var q := Vector3(cell)
		q[a] += 1.0 if positive else 0.0
		q[u] += p.x
		q[v] += p.y
		corners.append(q)
	# Godot treats clockwise triangles (as seen from outside) as the front.
	var order := [0, 2, 1, 0, 3, 2] if positive else [0, 1, 2, 0, 2, 3]
	st.set_normal(Vector3(dir))
	st.set_color(color)
	for i in order:
		st.add_vertex(corners[i])
