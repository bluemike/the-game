extends SceneTree
## Loads the real game scene and drives it with key presses.
##   godot --headless -s tests/smoke_test.gd

const Piece := preload("res://scripts/piece.gd")
const Pieces := preload("res://scripts/pieces.gd")

var main
var frames := 0
var failures := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		printerr("  FAIL ", what)


func key(code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	main._unhandled_input(e)


func mouse(pos: Vector2, pressed: bool, shift := false, double := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = pos
	e.pressed = pressed
	e.shift_pressed = shift
	e.double_click = double
	main._unhandled_input(e)


func move_mouse(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	main._unhandled_input(e)


func test_mouse() -> void:
	main._set_view(1)  # overview
	main.camera.snap_to_mode()
	main.piece = Piece.new("Bar", Pieces.SHAPES["Bar"])
	main.piece.origin = Vector3i(4, 4, 4)
	main.selected = false
	main._refresh()
	var p: Vector2 = main.camera.unproject_position(main.piece.centre())
	var yaw_before: float = main.camera.yaw
	mouse(Vector2(20, 400), true)
	move_mouse(Vector2(80, 400), Vector2(60, 0))
	mouse(Vector2(80, 400), false)
	check(main.camera.yaw != yaw_before and not main.selected, "dragging empty space orbits the camera")
	yaw_before = main.camera.yaw
	mouse(p, true)
	move_mouse(p + Vector2(60, 0), Vector2(60, 0))
	mouse(p + Vector2(60, 0), false)
	check(main.piece.origin == Vector3i(4, 4, 4) and not main.selected, "dragging over an unselected piece orbits, piece stays")
	main.camera.snap_to_mode()
	p = main.camera.unproject_position(main.piece.centre())
	mouse(p, true)
	mouse(p, false)
	check(main.selected and main._rings[0].visible, "clicking the piece picks it up and shows the rings")
	yaw_before = main.camera.yaw
	mouse(p, true)
	move_mouse(p + Vector2(150, 0), Vector2(150, 0))
	mouse(p + Vector2(150, 0), false)
	check(main.piece.origin != Vector3i(4, 4, 4) and main.piece.origin.y == 4, "dragging a picked-up piece slides it sideways")
	check(main.camera.yaw == yaw_before, "the camera stays put while moving the piece")
	var o: Vector3i = main.piece.origin
	p = main.camera.unproject_position(main.piece.centre())
	mouse(p, true, true)
	move_mouse(p + Vector2(0, -150), Vector2(0, -150))
	mouse(p + Vector2(0, -150), false)
	check(main.piece.origin.y > o.y and main.piece.origin.x == o.x and main.piece.origin.z == o.z, "Shift+drag moves it up")
	# Click the Y ring (it lies flat around the piece).
	var before: Array = main.piece.offsets.duplicate()
	var ring_point: Vector3 = main.piece.centre() + Vector3(1, 0, 1).normalized() * main.RING_RADIUS
	var rp: Vector2 = main.camera.unproject_position(ring_point)
	check(main._ring_at(rp) == 1, "the flat (Y) ring is found under the mouse")
	mouse(rp, true)
	mouse(rp, false)
	check(main.piece.offsets != before and main.selected, "clicking a ring rotates the piece")
	p = main.camera.unproject_position(main.piece.centre())
	mouse(p, true)
	mouse(p, false)
	check(not main.selected and not main._rings[0].visible, "clicking again lets go of the piece")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.grid_size = Vector3i(9, 9, 9)  # the positions below assume a 9-cell cube
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	check(main.piece != null, "a piece is dealt")
	check(main.next_name in Pieces.SHAPES, "a next piece is chosen")
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_Q, KEY_X, KEY_Y, KEY_Z, KEY_1, KEY_2, KEY_3, KEY_4, KEY_V, KEY_V, KEY_H, KEY_H, KEY_N]:
		key(k)
	key(KEY_X, true)
	check(main.skips == 1, "N skips a piece")
	key(KEY_4)
	check(main.camera.mode == 3 and main._tunnel_material.albedo_color.a < 1.0, "4 shows the 45° view with a see-through tunnel")
	key(KEY_2)
	check(main._tunnel_material.albedo_color.a == 1.0, "other views make the tunnel solid again")

	test_mouse()

	# Put a known piece straight under the start and place it with Space.
	main.piece = Piece.new("Bar", Pieces.SHAPES["Bar"])
	main.piece.rotate_90(Vector3.AXIS_Z, 1)  # stand the bar upright
	main.piece.origin = Vector3i(4, 6, 4)
	key(KEY_SPACE)
	check(main.state.pieces_placed(main.player) == 1, "Space places a valid piece")
	var cells_before: int = main.state.grid.cells_of(0).size()
	main.piece.origin = Vector3i(0, 0, 0)
	key(KEY_SPACE)
	check(main.state.grid.cells_of(0).size() == cells_before, "an invalid piece is not placed")
	key(KEY_BACKSPACE)
	check(main.state.pieces_placed(main.player) == 0, "Backspace undoes")

	# Dig straight down to win.
	for o in [Vector3i(4, 6, 4), Vector3i(4, 3, 4), Vector3i(5, 1, 4)]:
		main.piece = Piece.new("Bar", Pieces.SHAPES["Bar"])
		main.piece.rotate_90(Vector3.AXIS_Z, 1)
		main.piece.origin = o
		main.try_place()
	check(main.player.has_won, "reaching the goal face wins")
	check(main._banner.visible, "win banner shows")
	key(KEY_R)
	check(not main.player.has_won and main.state.pieces_placed(main.player) == 0, "R restarts")

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
	return true
