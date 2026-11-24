extends RefCounted
## The piece the player is currently moving. It is a set of cell offsets
## around an origin cell; moving changes the origin, rotating turns the offsets.

var shape_name: String
var offsets: Array[Vector3i] = []
var origin := Vector3i.ZERO


## Starts upright, in the X/Y plane, so it points into the cube.
func _init(p_shape_name: String, shape: Array) -> void:
	shape_name = p_shape_name
	for c in shape:
		offsets.append(Vector3i(c.x, c.y, 0))


func cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for o in offsets:
		out.append(origin + o)
	return out


func move(step: Vector3i) -> void:
	origin += step


## Turns the piece 90 degrees around a world axis. direction is 1 or -1.
func rotate_90(axis: int, direction: int) -> void:
	for i in offsets.size():
		offsets[i] = rotated(offsets[i], axis, direction)


static func rotated(v: Vector3i, axis: int, d: int) -> Vector3i:
	match axis:
		Vector3.AXIS_X:
			return Vector3i(v.x, -v.z * d, v.y * d)
		Vector3.AXIS_Y:
			return Vector3i(v.z * d, v.y, -v.x * d)
		_:
			return Vector3i(-v.y * d, v.x * d, v.z)


## Shifts the piece so every cell is inside a grid of the given size.
func clamp_into(grid_size: Vector3i) -> void:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for c in cells():
		for a in 3:
			lo[a] = mini(lo[a], c[a])
			hi[a] = maxi(hi[a], c[a])
	var shift := Vector3i.ZERO
	for a in 3:
		if lo[a] < 0:
			shift[a] = -lo[a]
		elif hi[a] > grid_size[a] - 1:
			shift[a] = grid_size[a] - 1 - hi[a]
	origin += shift


## Centre of the piece in world units (cell (0,0,0) spans 0..1).
func centre() -> Vector3:
	var sum := Vector3.ZERO
	for c in cells():
		sum += Vector3(c) + Vector3(0.5, 0.5, 0.5)
	return sum / float(maxi(1, offsets.size()))
