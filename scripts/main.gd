extends Node3D
## Prototype entry point. Builds the whole scene in code (cube, camera, HUD),
## reads the keyboard and mouse, and asks GameState whether moves are allowed.

const GameState := preload("res://scripts/game_state.gd")
const Player := preload("res://scripts/player.gd")
const Pieces := preload("res://scripts/pieces.gd")
const Piece := preload("res://scripts/piece.gd")
const OrbitCamera := preload("res://scripts/orbit_camera.gd")
const CellMesh := preload("res://scripts/cell_mesh.gd")

## Size of the play cube in cells.
@export var grid_size := Vector3i(24, 24, 24)
## Which piece sizes (number of cells) can be dealt. [4] deals only 4-cell pieces.
@export var piece_sizes: Array[int] = [3, 4, 5]

const HELP_TEXT := """MOUSE                 H hides this
Drag          orbit camera,  wheel  zoom
Click piece   pick it up (rings appear)
 then drag    slide it sideways
 Shift+drag   move it up / down
 click ring   rotate (Shift: other way)
 click again  let go, back to camera
Double-click  place the piece
Right-drag    always orbits

KEYBOARD
Move piece    W A S D  (follows camera)
Up / down     E / Q
Rotate        X  Y  Z  (Shift: other way)
Place         Space or Enter
Skip piece    N
Undo          Backspace
Restart       R

Orbit         drag mouse, arrow keys
Zoom          mouse wheel, + / -
View          1 Overview  2 Start  3 Follow
              4 Through the start, 45°
              V or Tab cycles views"""

## Radius of the rotation rings around the selected piece.
const RING_RADIUS := 2.4
const RING_PICK_WIDTH := 0.45
const RING_AXES := [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]
const RING_COLORS := [Color(1, 0.35, 0.35), Color(0.4, 1, 0.4), Color(0.4, 0.6, 1)]

enum Drag { NONE, PIECE, CAMERA }

var state: GameState
var player: Player
var piece: Piece
var next_name := ""
var skips := 0
var rng := RandomNumberGenerator.new()

var camera: OrbitCamera
var _tunnel_root: Node3D
var _ghost_root: Node3D
var _shadow_mesh := BoxMesh.new()
var _tunnel_material: StandardMaterial3D
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _status: RichTextLabel
var _help_panel: Control
var _banner: Control
var _banner_label: Label
var _face_labels: Array[Label3D] = []

# Mouse handling
var selected := false
var _drag := Drag.NONE
var _drag_plane: Plane
var _drag_vertical := false
var _drag_start_hit := Vector3.ZERO
var _drag_start_origin := Vector3i.ZERO
var _press_position := Vector2.ZERO
var _rings: Array[MeshInstance3D] = []
var _ring_materials: Array[StandardMaterial3D] = []
var _hover_ring := -1


func _ready() -> void:
	rng.randomize()
	_build_environment()
	_build_frame()
	_build_axis_gizmo()
	_tunnel_root = Node3D.new()
	add_child(_tunnel_root)
	_ghost_root = Node3D.new()
	add_child(_ghost_root)
	_build_rings()
	camera = OrbitCamera.new()
	add_child(camera)
	_build_hud()
	new_game()


func new_game() -> void:
	state = GameState.new(grid_size)
	player = Player.new(0, "Player 1", Color(0.25, 0.6, 1.0), grid_size, Vector3.AXIS_Y, true)
	state.add_player(player)
	_build_player_materials()
	skips = 0
	next_name = Pieces.random_name(piece_sizes, rng)
	var goal_point := _cell_centre(player.start_cell)
	goal_point[player.goal_axis] = float(grid_size[player.goal_axis]) if player.goal_at_max else 0.0
	camera.setup(Vector3(grid_size) / 2.0, float(grid_size[grid_size.max_axis_index()]),
		_cell_centre(player.start_cell), goal_point)
	_apply_view_style()
	_deal_piece()
	_rebuild_tunnel()


# --- Game actions -----------------------------------------------------------

func _deal_piece() -> void:
	piece = Piece.new(next_name, Pieces.SHAPES[next_name])
	next_name = Pieces.random_name(piece_sizes, rng)
	piece.origin = _spawn_origin()
	piece.clamp_into(grid_size)
	selected = false
	_refresh()


## New pieces appear just beyond the deepest point of the tunnel. If that
## spot doesn't fit, nearby spots are tried so the player starts close to a fit.
func _spawn_origin() -> Vector3i:
	var best := player.start_cell
	for c in state.grid.cells_of(player.id):
		if player.progress_of(c) > player.progress_of(best):
			best = c
	var preferred := best + player.dig_direction * 2
	var probe := Piece.new(piece.shape_name, Pieces.SHAPES[piece.shape_name])
	for depth in [2, 1, 3]:
		for side in [Vector3i.ZERO, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			probe.origin = best + player.dig_direction * depth + side
			if state.check_placement(player, probe.cells()) == "":
				return probe.origin
	return preferred


func try_place() -> bool:
	if player.has_won:
		return false
	if not state.place(player, piece.cells()):
		return false
	_rebuild_tunnel()
	if player.has_won:
		_show_win()
		_refresh()
	else:
		_deal_piece()
	return true


func skip_piece() -> void:
	if player.has_won:
		return
	skips += 1
	_deal_piece()


func undo() -> void:
	if not state.undo_last(player):
		return
	_banner.visible = false
	_rebuild_tunnel()
	_refresh()


## Moves the piece relative to where the camera is looking.
## x is left/right on screen, y is away from/towards the viewer.
func move_relative(screen_x: int, screen_y: int) -> void:
	var fwd := camera.floor_forward()
	var right := Vector3i(-fwd.z, 0, fwd.x)
	_move(right * screen_x + fwd * screen_y)


func _move(step: Vector3i) -> void:
	if player.has_won:
		return
	piece.move(step)
	piece.clamp_into(grid_size)
	_refresh()


func rotate_piece(axis: int, direction: int) -> void:
	if player.has_won:
		return
	piece.rotate_90(axis, direction)
	piece.clamp_into(grid_size)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse or event is InputEventGesture:
		_handle_mouse(event)
		return
	if not (event is InputEventKey and event.pressed):
		return
	var key := event as InputEventKey
	var dir := -1 if key.shift_pressed else 1
	match key.keycode:
		KEY_W:
			move_relative(0, 1)
		KEY_S:
			move_relative(0, -1)
		KEY_A:
			move_relative(-1, 0)
		KEY_D:
			move_relative(1, 0)
		KEY_E, KEY_PAGEUP:
			_move(Vector3i.UP)
		KEY_Q, KEY_PAGEDOWN:
			_move(Vector3i.DOWN)
		KEY_X:
			if not key.echo:
				rotate_piece(Vector3.AXIS_X, dir)
		KEY_Y:
			if not key.echo:
				rotate_piece(Vector3.AXIS_Y, dir)
		KEY_Z:
			if not key.echo:
				rotate_piece(Vector3.AXIS_Z, dir)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if not key.echo:
				try_place()
		KEY_N:
			if not key.echo:
				skip_piece()
		KEY_BACKSPACE:
			if not key.echo:
				undo()
		KEY_R:
			if not key.echo:
				new_game()
		KEY_1:
			_set_view(OrbitCamera.Mode.OVERVIEW)
		KEY_2:
			_set_view(OrbitCamera.Mode.START)
		KEY_3:
			_set_view(OrbitCamera.Mode.FOLLOW)
		KEY_4:
			_set_view(OrbitCamera.Mode.TUNNEL)
		KEY_V, KEY_TAB:
			if not key.echo:
				_set_view((camera.mode + 1) % OrbitCamera.MODE_NAMES.size())
		KEY_H, KEY_F1:
			if not key.echo:
				_help_panel.visible = not _help_panel.visible
		KEY_ESCAPE:
			selected = false
			_refresh()
		_:
			return
	get_viewport().set_input_as_handled()


func _set_view(mode: int) -> void:
	camera.set_mode(mode)
	_apply_view_style()
	_update_hud()


## In the 45° view the tunnel is partly see-through, so you can look past it
## towards the goal face and still see the piece you are placing.
func _apply_view_style() -> void:
	var tunnel_view := camera.mode == OrbitCamera.Mode.TUNNEL
	var alpha := 0.6 if tunnel_view else 1.0
	for l in _face_labels:
		l.visible = not tunnel_view  # they would sit right on the line of sight
	_tunnel_material.albedo_color.a = alpha
	_tunnel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 \
		else BaseMaterial3D.TRANSPARENCY_DISABLED


# --- Mouse ------------------------------------------------------------------

func _handle_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_press(event)
		else:
			_on_left_release(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _drag == Drag.PIECE:
			_drag_piece_to(event.position)
		elif _drag == Drag.NONE:
			_update_hover(event.position)
	if _drag != Drag.PIECE:
		camera.handle_input(event)


## The mouse controls the camera until you click the piece. Then it controls
## the piece (drag to move, click a ring to rotate) until you click again.
func _on_left_press(event: InputEventMouseButton) -> void:
	_press_position = event.position
	_drag = Drag.NONE
	if player.has_won:
		_drag = Drag.CAMERA
		camera.handle_input(event)
		return
	var hit = _piece_hit(event.position)
	if event.double_click and hit != null:
		try_place()
		return
	if not selected:
		_drag = Drag.CAMERA
		camera.handle_input(event)
		return
	var ring := _ring_at(event.position)
	if ring >= 0:
		rotate_piece(RING_AXES[ring], -1 if event.shift_pressed else 1)
		return
	# Selected: a drag anywhere moves the piece, measured in a plane through it.
	_drag = Drag.PIECE
	_drag_vertical = event.shift_pressed
	_drag_start_origin = piece.origin
	var through: Vector3 = hit if hit != null else piece.centre()
	if _drag_vertical:
		_drag_plane = Plane(camera.flat_forward(), through)
	else:
		_drag_plane = Plane(Vector3.UP, through)
	var start = _drag_plane.intersects_ray(camera.project_ray_origin(event.position),
		camera.project_ray_normal(event.position))
	_drag_start_hit = start if start != null else through


func _on_left_release(event: InputEventMouseButton) -> void:
	var clicked := event.position.distance_to(_press_position) < 4.0
	if _drag == Drag.CAMERA:
		camera.handle_input(event)
		# A click (not a drag) on the piece picks it up.
		if clicked and not player.has_won and _piece_hit(event.position) != null:
			selected = true
	elif _drag == Drag.PIECE and clicked:
		selected = false  # a second click lets go, the mouse controls the camera again
	_drag = Drag.NONE
	_refresh()


func _drag_piece_to(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit = _drag_plane.intersects_ray(from, dir)
	if hit == null:
		return
	var delta: Vector3 = hit - _drag_start_hit
	var step := Vector3i(roundi(delta.x), roundi(delta.y), roundi(delta.z))
	if _drag_vertical:
		step = Vector3i(0, step.y, 0)
	else:
		step.y = 0
	var old := piece.origin
	piece.origin = _drag_start_origin + step
	piece.clamp_into(grid_size)
	if piece.origin != old:
		_refresh(false)


## Point where the mouse ray first hits the piece, or null.
func _piece_hit(screen_pos: Vector2):
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best = null
	var best_dist := INF
	for cell in piece.cells():
		var p = AABB(Vector3(cell), Vector3.ONE).intersects_ray(from, dir)
		if p != null and from.distance_to(p) < best_dist:
			best = p
			best_dist = from.distance_to(p)
	return best


## Index of the rotation ring under the mouse, or -1.
func _ring_at(screen_pos: Vector2) -> int:
	if not selected or player.has_won:
		return -1
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var centre := piece.centre()
	var best := -1
	var best_dist := INF
	for i in RING_AXES.size():
		var normal := Vector3.ZERO
		normal[RING_AXES[i]] = 1.0
		var p = Plane(normal, centre).intersects_ray(from, dir)
		if p == null:
			continue
		var r: float = (p - centre).length()
		if absf(r - RING_RADIUS) < RING_PICK_WIDTH and from.distance_to(p) < best_dist:
			best = i
			best_dist = from.distance_to(p)
	return best


func _update_hover(screen_pos: Vector2) -> void:
	var ring := _ring_at(screen_pos)
	if ring != _hover_ring:
		_hover_ring = ring
		_style_rings()
	if ring >= 0:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	elif not player.has_won and _piece_hit(screen_pos) != null:
		Input.set_default_cursor_shape(Input.CURSOR_MOVE)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _build_rings() -> void:
	for i in RING_AXES.size():
		var torus := TorusMesh.new()
		torus.inner_radius = RING_RADIUS - 0.07
		torus.outer_radius = RING_RADIUS + 0.07
		torus.rings = 48
		var mat := _material(RING_COLORS[i], true)
		mat.no_depth_test = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.render_priority = 1
		var mi := MeshInstance3D.new()
		mi.mesh = torus
		mi.material_override = mat
		# A torus lies flat (around Y); turn it to circle the X or Z axis.
		if RING_AXES[i] == Vector3.AXIS_X:
			mi.rotation_degrees = Vector3(0, 0, 90)
		elif RING_AXES[i] == Vector3.AXIS_Z:
			mi.rotation_degrees = Vector3(90, 0, 0)
		add_child(mi)
		_rings.append(mi)
		_ring_materials.append(mat)
	_style_rings()


func _style_rings() -> void:
	for i in _rings.size():
		var hot := i == _hover_ring
		_ring_materials[i].albedo_color = RING_COLORS[i].lightened(0.3) if hot else Color(RING_COLORS[i], 0.6)
		_rings[i].scale = Vector3.ONE * (1.06 if hot else 1.0)


# --- Drawing ----------------------------------------------------------------

func _cell_centre(cell: Vector3i) -> Vector3:
	return Vector3(cell) + Vector3(0.5, 0.5, 0.5)


func _material(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -145, 0)
	fill.light_energy = 0.35
	add_child(fill)

	_ghost_ok = _material(Color(0.35, 1.0, 0.45, 0.55))
	_ghost_ok.emission_enabled = true
	_ghost_ok.emission = Color(0.1, 0.5, 0.15)
	_ghost_bad = _material(Color(1.0, 0.3, 0.3, 0.55))
	_ghost_bad.emission_enabled = true
	_ghost_bad.emission = Color(0.5, 0.08, 0.08)
	_shadow_material = _material(Color(1, 1, 1, 0.25), true)


func _build_player_materials() -> void:
	_tunnel_material = _material(Color.WHITE)
	_tunnel_material.vertex_color_use_as_albedo = true
	var s := Vector3.ONE * 0.9
	s[player.goal_axis] = 0.04
	_shadow_mesh.size = s


## Cube outline, plus a grid drawn on the start face (green) and goal face (gold).
func _build_frame() -> void:
	var lines := ImmediateMesh.new()
	var line_mat := _material(Color.WHITE, true)
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	var s := Vector3(grid_size)
	var edge := Color(0.8, 0.85, 1.0, 0.6)
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		for i in 2:
			for j in 2:
				var p := Vector3.ZERO
				p[b] = s[b] * i
				p[c] = s[c] * j
				var q := p
				q[a] = s[a]
				_line(lines, p, q, edge)
	# Start face is the top (y = max), goal face is the bottom (y = 0).
	_face_grid(lines, Vector3.AXIS_Y, s.y, Color(0.4, 1.0, 0.5, 0.22))
	_face_grid(lines, Vector3.AXIS_Y, 0.0, Color(1.0, 0.8, 0.3, 0.6))
	lines.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = lines
	add_child(mi)

	_face_quad(Vector3.AXIS_Y, s.y + 0.01, Color(0.3, 1.0, 0.45, 0.07))
	_face_quad(Vector3.AXIS_Y, -0.01, Color(1.0, 0.75, 0.2, 0.22))

	_face_labels.append(_label("START", Vector3(s.x / 2.0, s.y + 0.9, s.z / 2.0), Color(0.5, 1.0, 0.6)))
	_face_labels.append(_label("GOAL", Vector3(s.x / 2.0, -0.9, s.z / 2.0), Color(1.0, 0.8, 0.3)))


func _line(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	im.surface_set_color(color)
	im.surface_add_vertex(a)
	im.surface_set_color(color)
	im.surface_add_vertex(b)


func _face_grid(im: ImmediateMesh, axis: int, value: float, color: Color) -> void:
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var s := Vector3(grid_size)
	for i in grid_size[u] + 1:
		var a := Vector3.ZERO
		a[axis] = value
		a[u] = i
		var b := a
		b[v] = s[v]
		_line(im, a, b, color)
	for j in grid_size[v] + 1:
		var a := Vector3.ZERO
		a[axis] = value
		a[v] = j
		var b := a
		b[u] = s[u]
		_line(im, a, b, color)


func _face_quad(axis: int, value: float, color: Color) -> void:
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var corners: Array[Vector3] = []
	for p in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var c := Vector3.ZERO
		c[axis] = value
		c[u] = p.x * grid_size[u]
		c[v] = p.y * grid_size[v]
		corners.append(c)
	var im := ImmediateMesh.new()
	var mat := _material(color, true)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for idx in [0, 1, 2, 0, 2, 3]:
		im.surface_add_vertex(corners[idx])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)


func _label(text: String, pos: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.pixel_size = 0.01
	l.outline_size = 12
	add_child(l)
	return l


## Small X / Y / Z arrows next to the cube so the rotate keys make sense.
func _build_axis_gizmo() -> void:
	var origin := Vector3(-0.6, grid_size.y, grid_size.z + 0.6)
	var im := ImmediateMesh.new()
	var mat := _material(Color.WHITE, true)
	mat.vertex_color_use_as_albedo = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var axes := [
		[Vector3.RIGHT, Color(1, 0.35, 0.35), "X"],
		[Vector3.UP, Color(0.4, 1, 0.4), "Y"],
		[Vector3.BACK, Color(0.4, 0.6, 1), "Z"],
	]
	for a in axes:
		_line(im, origin, origin + a[0] * 1.2, a[1])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)
	for a in axes:
		var l := _label(a[2], origin + a[0] * 1.5, a[1])
		l.font_size = 36


## The tunnel is drawn as one solid shape, coloured lighter near the start
## and darker towards the goal.
func _rebuild_tunnel() -> void:
	for child in _tunnel_root.get_children():
		child.queue_free()
	var depth := maxi(1, grid_size[player.goal_axis] - 1)
	var near := player.color.lightened(0.35)
	var far := player.color.darkened(0.35)
	var mesh := CellMesh.build(state.grid.cells_of(player.id), func(cell: Vector3i) -> Color:
		if cell == player.start_cell:
			return Color(0.3, 1.0, 0.45)
		return near.lerp(far, float(player.progress_of(cell)) / depth))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _tunnel_material
	_tunnel_root.add_child(mi)


## Redraws the ghost piece, its shadow on the goal face, the rings and the HUD.
## follow: whether the follow camera should chase the piece (not while dragging).
func _refresh(follow := true) -> void:
	for child in _ghost_root.get_children():
		child.queue_free()
	var reason := state.check_placement(player, piece.cells())
	var show_piece := not player.has_won
	if show_piece:
		var ghost := MeshInstance3D.new()
		ghost.mesh = CellMesh.build(piece.cells(), func(_c: Vector3i) -> Color: return Color.WHITE)
		ghost.material_override = _ghost_ok if reason == "" else _ghost_bad
		_ghost_root.add_child(ghost)
		for cell in piece.cells():
			var shadow := MeshInstance3D.new()
			shadow.mesh = _shadow_mesh
			shadow.material_override = _shadow_material
			var p := _cell_centre(cell)
			p[player.goal_axis] = float(grid_size[player.goal_axis]) + 0.03 if player.goal_at_max else -0.03
			shadow.position = p
			_ghost_root.add_child(shadow)
		if follow and _drag != Drag.PIECE:
			camera.follow_point = piece.centre()
	for ring in _rings:
		ring.visible = show_piece and selected
		ring.position = piece.centre()
	_update_hud(reason)


# --- HUD --------------------------------------------------------------------

func _panel(parent: Node, preset: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.06, 0.72)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	return panel


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])

	var status_panel := _panel(layer, Control.PRESET_TOP_LEFT)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size = Vector2(360, 0)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_override("normal_font", mono)
	_status.add_theme_font_override("bold_font", mono)
	_status.add_theme_font_size_override("normal_font_size", 15)
	_status.add_theme_font_size_override("bold_font_size", 15)
	status_panel.add_child(_status)

	_help_panel = _panel(layer, Control.PRESET_TOP_RIGHT)
	_help_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var help := Label.new()
	help.text = HELP_TEXT
	help.add_theme_font_override("font", mono)
	help.add_theme_font_size_override("font_size", 14)
	_help_panel.add_child(help)

	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner = _panel(centre, Control.PRESET_CENTER)
	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 30)
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_banner.add_child(_banner_label)
	_banner.visible = false

	# Buttons along the bottom, so the game can be played with the mouse only.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	layer.add_child(bar)
	for spec in [["Place", try_place], ["Skip", skip_piece], ["Undo", undo],
			["Next view", func(): _set_view((camera.mode + 1) % OrbitCamera.MODE_NAMES.size())],
			["Restart", new_game]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE  # keep Space for placing, not for the button
		b.custom_minimum_size = Vector2(110, 40)
		b.pressed.connect(spec[1])
		bar.add_child(b)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _show_win() -> void:
	_banner_label.text = "Tunnel complete!\n%d pieces, %d skipped\n\nR to play again, Backspace to undo" \
		% [state.pieces_placed(player), skips]
	_banner.visible = true


func _update_hud(reason := "") -> void:
	if _status == null or piece == null:
		return
	var t := ""
	t += "[b]THE-GAME[/b]  tunnel prototype\n\n"
	t += "Pieces placed  %d    skipped  %d\n" % [state.pieces_placed(player), skips]
	t += "Depth reached  %d / %d\n\n" % [state.best_progress(player), grid_size[player.goal_axis] - 1]
	var now_rows := Pieces.preview_rows(piece.shape_name)
	var next_rows := Pieces.preview_rows(next_name)
	t += ("Now: %s" % piece.shape_name).rpad(18) + "Next: %s\n" % next_name
	for i in 3:
		t += "  " + now_rows[i].rpad(16) + "  " + next_rows[i] + "\n"
	t += "\n"
	var o := piece.origin
	t += "Piece at  x %d  y %d  z %d\n" % [o.x, o.y, o.z]
	if player.has_won:
		t += "[color=#ffd75a]Goal reached![/color]\n"
	elif reason == "":
		t += "[color=#6dff7a]Fits. Space or double-click to place.[/color]\n"
	else:
		t += "[color=#ff6b6b]%s[/color]\n" % reason
	if not player.has_won:
		if selected:
			t += "[color=#9fd0ff]Mouse moves the piece. Click to let go.[/color]\n"
		else:
			t += "Click the piece to move it with the mouse.\n"
	t += "View  %s" % camera.mode_name()
	_status.text = t
