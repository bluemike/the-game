extends RefCounted
## One tunnel digger: where they start, which face they must reach.
## The prototype has one player; multiplayer adds more on other faces.

var id: int
var display_name: String
var color: Color
var start_cell: Vector3i
var goal_axis: int          # Vector3.AXIS_X, AXIS_Y or AXIS_Z
var goal_value: int         # coordinate of the goal face on goal_axis
var goal_at_max: bool       # true if the goal face is on the high side
var dig_direction: Vector3i # unit step from start towards goal
var has_won := false


## Starts in the centre of one face of the grid and digs to the opposite face.
func _init(p_id: int, p_name: String, p_color: Color, grid_size: Vector3i,
		axis: int, start_on_high_side: bool) -> void:
	id = p_id
	display_name = p_name
	color = p_color
	goal_axis = axis
	start_cell = grid_size / 2
	start_cell[axis] = grid_size[axis] - 1 if start_on_high_side else 0
	goal_at_max = not start_on_high_side
	goal_value = 0 if start_on_high_side else grid_size[axis] - 1
	dig_direction = Vector3i.ZERO
	dig_direction[axis] = -1 if start_on_high_side else 1


func is_goal_cell(cell: Vector3i) -> bool:
	return cell[goal_axis] == goal_value


## How far a cell is from the start face, measured towards the goal.
func progress_of(cell: Vector3i) -> int:
	var d := cell - start_cell
	return d.x * dig_direction.x + d.y * dig_direction.y + d.z * dig_direction.z
