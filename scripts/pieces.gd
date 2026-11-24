extends RefCounted
## The flat piece shapes. Each fits in a 3x3 square.
## Cells are (column, row) from -1 to 1, with row 1 at the top.
## Mirror images are not needed: in 3D a flat piece can be flipped over.

const SHAPES := {
	# 3 cells
	"Bar": [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)],
	"Corner": [Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0)],
	# 4 cells
	"Square": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"L": [Vector2i(0, 1), Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, -1)],
	"T": [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1)],
	"S": [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, 0)],
	# 5 cells
	"Plus": [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1)],
	"Big T": [Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 0), Vector2i(0, -1)],
	"U": [Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)],
	"V": [Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)],
	"P": [Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1)],
	"Z": [Vector2i(-1, 1), Vector2i(0, 1), Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, -1)],
	"W": [Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, -1)],
}


## Names of all shapes whose cell count is in `sizes`, e.g. [3, 4, 5].
static func names_with_sizes(sizes: Array) -> Array[String]:
	var out: Array[String] = []
	for shape_name in SHAPES:
		if SHAPES[shape_name].size() in sizes:
			out.append(shape_name)
	return out


static func random_name(sizes: Array, rng: RandomNumberGenerator) -> String:
	var names := names_with_sizes(sizes)
	if names.is_empty():
		names = names_with_sizes([3, 4, 5])
	return names[rng.randi_range(0, names.size() - 1)]


## Three text rows that draw the shape, for the on-screen preview.
static func preview_rows(shape_name: String) -> Array[String]:
	var cells: Array = SHAPES[shape_name]
	var rows: Array[String] = []
	for row in [1, 0, -1]:
		var line := ""
		for col in [-1, 0, 1]:
			line += "■ " if Vector2i(col, row) in cells else "· "
		rows.append(line.strip_edges(false, true))
	return rows
