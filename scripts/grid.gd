extends RefCounted
## The play volume: a box of unit cells. It only knows which cells are taken
## and by which player, so several players can share it later (multiplayer).

const EMPTY := -1

## The six face neighbours of a cell. Pieces "touch" when they share a face.
const NEIGHBOURS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var size: Vector3i
var _owners := {}  # Vector3i -> player id


func _init(p_size: Vector3i) -> void:
	size = p_size


func in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 \
		and cell.x < size.x and cell.y < size.y and cell.z < size.z


func owner_of(cell: Vector3i) -> int:
	return _owners.get(cell, EMPTY)


func is_free(cell: Vector3i) -> bool:
	return in_bounds(cell) and not _owners.has(cell)


func set_cell(cell: Vector3i, player_id: int) -> void:
	_owners[cell] = player_id


func clear_cell(cell: Vector3i) -> void:
	_owners.erase(cell)


func cells_of(player_id: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell in _owners:
		if _owners[cell] == player_id:
			out.append(cell)
	return out
