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
	check(main.camera.mode == 3 and main._start_material.albedo_color.a < 1.0, "4 shows the see-through tunnel view")
	key(KEY_2)
	check(main._start_material.albedo_color.a == 1.0, "other views make the tunnel solid again")

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
