extends Node3D
## Prototype entry point. Builds the whole scene in code (cube, camera, HUD),
## reads the keyboard, and asks GameState whether moves are allowed.

const GameState := preload("res://scripts/game_state.gd")
const Player := preload("res://scripts/player.gd")
const Pieces := preload("res://scripts/pieces.gd")
const Piece := preload("res://scripts/piece.gd")
const OrbitCamera := preload("res://scripts/orbit_camera.gd")

## Size of the play cube in cells.
@export var grid_size := Vector3i(15, 15, 15)
## Which piece sizes (number of cells) can be dealt. [4] deals only 4-cell pieces.
@export var piece_sizes: Array[int] = [3, 4, 5]

const HELP_TEXT := """CONTROLS              H hides this
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
              4 Down the tunnel
              V or Tab cycles views"""

var state: GameState
var player: Player
var piece: Piece
var next_name := ""
var skips := 0
var rng := RandomNumberGenerator.new()

var camera: OrbitCamera
var _tunnel_root: Node3D
var _ghost_root: Node3D
var _cell_mesh := BoxMesh.new()
var _ghost_mesh := BoxMesh.new()
var _shadow_mesh := BoxMesh.new()
var _layer_materials := {}
var _start_material: StandardMaterial3D
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _status: RichTextLabel
var _help_panel: Control
var _banner: Control
var _banner_label: Label
var _face_labels: Array[Label3D] = []


func _ready() -> void:
	rng.randomize()
	_cell_mesh.size = Vector3.ONE * 0.94
	_ghost_mesh.size = Vector3.ONE * 0.98
	_build_environment()
	_build_frame()
	_build_axis_gizmo()
	_tunnel_root = Node3D.new()
	add_child(_tunnel_root)
	_ghost_root = Node3D.new()
	add_child(_ghost_root)
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
		_:
			return
	get_viewport().set_input_as_handled()


func _set_view(mode: int) -> void:
	camera.set_mode(mode)
	_apply_view_style()
	_update_hud()


## In the tunnel view the tunnel turns see-through, so you can look past it
## down to the goal face and see the piece you are placing.
func _apply_view_style() -> void:
	var tunnel_view := camera.mode == OrbitCamera.Mode.TUNNEL
	var alpha := 0.3 if tunnel_view else 1.0
	for l in _face_labels:
		l.visible = not tunnel_view  # they would sit right on the line of sight
	var mats: Array = _layer_materials.values()
	mats.append(_start_material)
	for mat in mats:
		mat.albedo_color.a = alpha
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 \
			else BaseMaterial3D.TRANSPARENCY_DISABLED


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
	_layer_materials.clear()
	_start_material = _material(Color(0.3, 1.0, 0.45))
	_start_material.emission_enabled = true
	_start_material.emission = Color(0.1, 0.45, 0.15)
	var depth := grid_size[player.goal_axis] - 1
	for i in depth + 1:
		var t: float = float(i) / maxi(1, depth)
		var c := player.color.lightened(0.35).lerp(player.color.darkened(0.35), t)
		_layer_materials[i] = _material(c)
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
	_face_grid(lines, Vector3.AXIS_Y, s.y, Color(0.4, 1.0, 0.5, 0.45))
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


func _rebuild_tunnel() -> void:
	for child in _tunnel_root.get_children():
		child.queue_free()
	for cell in state.grid.cells_of(player.id):
		var mi := MeshInstance3D.new()
		mi.mesh = _cell_mesh
		mi.position = _cell_centre(cell)
		if cell == player.start_cell:
			mi.material_override = _start_material
		else:
			mi.material_override = _layer_materials.get(player.progress_of(cell), _start_material)
		_tunnel_root.add_child(mi)


## Redraws the ghost piece and its shadow on the goal face, and the HUD.
func _refresh() -> void:
	for child in _ghost_root.get_children():
		child.queue_free()
	var reason := state.check_placement(player, piece.cells())
	if not player.has_won:
		var mat := _ghost_ok if reason == "" else _ghost_bad
		for cell in piece.cells():
			var mi := MeshInstance3D.new()
			mi.mesh = _ghost_mesh
			mi.material_override = mat
			mi.position = _cell_centre(cell)
			_ghost_root.add_child(mi)
			var shadow := MeshInstance3D.new()
			shadow.mesh = _shadow_mesh
			shadow.material_override = _shadow_material
			var p := _cell_centre(cell)
			p[player.goal_axis] = float(grid_size[player.goal_axis]) + 0.03 if player.goal_at_max else -0.03
			shadow.position = p
			_ghost_root.add_child(shadow)
		camera.follow_point = piece.centre()
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
		t += "[color=#6dff7a]Fits. Space to place.[/color]\n"
	else:
		t += "[color=#ff6b6b]%s[/color]\n" % reason
	t += "View  %s" % camera.mode_name()
	_status.text = t
