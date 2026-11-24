extends Camera3D
## Orbit camera with four view modes. The main script passes it mouse events
## that are not aimed at the piece (see handle_input); arrow keys orbit too.

enum Mode { OVERVIEW, START, FOLLOW, TUNNEL }
const MODE_NAMES := ["Overview", "Start", "Follow piece", "Through the start (45°)"]
## Distance from the target in each mode, as a multiple of the cube size.
const MODE_DISTANCE := [2.3, 1.45, 0.95, 1.6]
## Field of view per mode.
const MODE_FOV := [70.0, 70.0, 70.0, 50.0]

var mode: int = Mode.TUNNEL
var yaw := deg_to_rad(35.0)
var pitch := deg_to_rad(45.0)
var zoom := 1.0

var cube_centre := Vector3.ZERO
var cube_extent := 24.0
var start_point := Vector3.ZERO
var follow_point := Vector3.ZERO
## Centre of the goal face, straight down the line from the start.
var goal_point := Vector3.ZERO

var _target := Vector3.ZERO
var _distance := 20.0
var _dragging := false


func setup(p_cube_centre: Vector3, p_cube_extent: float, p_start_point: Vector3, p_goal_point: Vector3) -> void:
	cube_centre = p_cube_centre
	goal_point = p_goal_point
	cube_extent = p_cube_extent
	start_point = p_start_point
	follow_point = p_start_point
	set_mode(mode)
	snap_to_mode()


func set_mode(new_mode: int) -> void:
	mode = new_mode
	zoom = 1.0
	if mode == Mode.TUNNEL:
		# Look through the start face at 45 degrees towards the goal face.
		pitch = deg_to_rad(45.0)
	elif pitch > deg_to_rad(70.0):
		pitch = deg_to_rad(32.0)


func cycle_mode() -> void:
	set_mode((mode + 1) % MODE_NAMES.size())


func mode_name() -> String:
	return MODE_NAMES[mode]


## Jumps straight to the current mode's view without the smooth move.
func snap_to_mode() -> void:
	_target = _desired_target()
	_distance = _desired_distance()
	fov = MODE_FOV[mode]
	_apply()


func _desired_target() -> Vector3:
	match mode:
		Mode.OVERVIEW:
			return cube_centre
		Mode.TUNNEL:
			# The middle of the straight line from start to goal.
			return start_point.lerp(goal_point, 0.5)
		Mode.START:
			# Look at the start, nudged towards the middle so the cube stays in view.
			return start_point.lerp(cube_centre, 0.3)
		_:
			return follow_point


func _desired_distance() -> float:
	return MODE_DISTANCE[mode] * cube_extent * zoom


func _process(delta: float) -> void:
	var turn := 1.8 * delta
	if Input.is_key_pressed(KEY_LEFT):
		yaw -= turn
	if Input.is_key_pressed(KEY_RIGHT):
		yaw += turn
	if Input.is_key_pressed(KEY_UP):
		pitch += turn
	if Input.is_key_pressed(KEY_DOWN):
		pitch -= turn
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_PLUS) or Input.is_key_pressed(KEY_KP_ADD):
		zoom *= 1.0 - delta
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom *= 1.0 + delta
	_clamp()
	var t := 1.0 - exp(-8.0 * delta)
	_target = _target.lerp(_desired_target(), t)
	_distance = lerpf(_distance, _desired_distance(), t)
	fov = lerpf(fov, MODE_FOV[mode], t)
	_apply()


## Orbit with a mouse drag, zoom with the wheel or a trackpad pinch.
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom *= 0.9
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom *= 1.1
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.008
		pitch += event.relative.y * 0.008
	elif event is InputEventPanGesture:  # two-finger scroll on a trackpad
		yaw -= event.delta.x * 0.05
		pitch += event.delta.y * 0.05
	elif event is InputEventMagnifyGesture:  # pinch on a trackpad
		zoom /= event.factor
	_clamp()


func is_dragging() -> bool:
	return _dragging


func _clamp() -> void:
	pitch = clampf(pitch, deg_to_rad(-70.0), deg_to_rad(89.0))
	zoom = clampf(zoom, 0.3, 3.0)


func _apply() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	position = _target + dir * _distance
	look_at(_target, Vector3.UP)


## The world axis (as a grid step) that is most "forward" for the viewer,
## flattened onto the floor. Used to move the piece relative to the camera.
func floor_forward() -> Vector3i:
	# Forward plus screen-up also works when looking straight down.
	var f := -global_transform.basis.z + global_transform.basis.y
	if absf(f.x) >= absf(f.z):
		return Vector3i(int(signf(f.x)), 0, 0)
	return Vector3i(0, 0, int(signf(f.z)))


## Horizontal direction the camera faces, as a unit vector.
func flat_forward() -> Vector3:
	var f := -global_transform.basis.z + global_transform.basis.y
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD
