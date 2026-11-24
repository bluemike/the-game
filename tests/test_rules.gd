extends SceneTree
## Rule tests. Run from the project folder:
##   godot --headless -s tests/test_rules.gd

const GameState := preload("res://scripts/game_state.gd")
const Player := preload("res://scripts/player.gd")
const Pieces := preload("res://scripts/pieces.gd")
const Piece := preload("res://scripts/piece.gd")

var failures := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		printerr("  FAIL ", what)


func bar(x: int, y_top: int, z: int) -> Array:
	return [Vector3i(x, y_top, z), Vector3i(x, y_top - 1, z), Vector3i(x, y_top - 2, z)]


func _initialize() -> void:
	var size := Vector3i(9, 9, 9)

	print("Player")
	var p := Player.new(0, "P1", Color.BLUE, size, Vector3.AXIS_Y, true)
	check(p.start_cell == Vector3i(4, 8, 4), "starts in the centre of the top face")
	check(p.dig_direction == Vector3i(0, -1, 0), "digs downwards")
	check(p.is_goal_cell(Vector3i(0, 0, 8)) and not p.is_goal_cell(Vector3i(4, 1, 4)), "goal is the bottom face")

	print("Pieces")
	for shape_name in Pieces.SHAPES:
		var cells: Array = Pieces.SHAPES[shape_name]
		var inside := true
		for c in cells:
			inside = inside and abs(c.x) <= 1 and abs(c.y) <= 1
		var unique := {}
		for c in cells:
			unique[c] = true
		check(inside and unique.size() == cells.size() and cells.size() >= 3, "%s fits 3x3, %d cells" % [shape_name, cells.size()])
	check(Pieces.names_with_sizes([4]).size() == 4, "four shapes have 4 cells")
	var piece := Piece.new("L", Pieces.SHAPES["L"])
	var before := piece.offsets.duplicate()
	for axis in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
		for i in 4:
			piece.rotate_90(axis, 1)
		check(piece.offsets == before, "four turns around axis %d return to start" % axis)
		piece.rotate_90(axis, 1)
		piece.rotate_90(axis, -1)
		check(piece.offsets == before, "turn and turn back around axis %d" % axis)
	piece.rotate_90(Vector3.AXIS_X, 1)
	var flat := true
	for c in piece.cells():
		flat = flat and c.y == piece.origin.y
	check(flat, "turning around X lays an upright piece flat")
	piece.origin = Vector3i(-3, 12, 0)
	piece.clamp_into(size)
	var all_in := true
	for c in piece.cells():
		all_in = all_in and c.x >= 0 and c.y < 9 and c.z >= 0
	check(all_in, "clamp pulls the piece back inside the cube")

	print("Placement")
	var s := GameState.new(size)
	s.add_player(p)
	check(s.check_placement(p, [Vector3i(4, 8, 4)]) == "Overlaps your tunnel", "cannot overlap the start")
	check(s.check_placement(p, bar(4, 4, 4)) == "Must touch your tunnel", "floating piece is refused")
	check(s.check_placement(p, bar(4, 9, 3)) == "Outside the cube", "out of bounds is refused")
	check(s.check_placement(p, bar(4, 7, 4)) == "", "piece below the start fits")
	check(s.check_placement(p, bar(4, 8, 3)) == "", "piece beside the start fits")
	check(s.place(p, bar(4, 7, 4)), "place first bar")
	check(s.check_placement(p, bar(5, 8, 4)) == "", "may touch any part of the tunnel, not only the last piece")
	check(s.place(p, bar(4, 4, 4)), "place second bar")
	check(not p.has_won, "not won yet")
	check(s.best_progress(p) == 6, "depth reached is 6")
	check(s.place(p, bar(5, 2, 4)), "place third bar touching the side")
	check(p.has_won, "reaching the bottom face wins")
	check(s.check_placement(p, bar(3, 8, 4)) == "Tunnel already complete", "no moves after winning")
	check(s.undo_last(p) and not p.has_won and s.pieces_placed(p) == 2, "undo removes the winning piece")

	print("Multiplayer groundwork")
	var p2 := Player.new(1, "P2", Color.RED, size, Vector3.AXIS_X, false)
	s.add_player(p2)
	check(p2.start_cell == Vector3i(0, 4, 4), "second player starts on the left face")
	check(s.check_placement(p2, [Vector3i(1, 4, 4), Vector3i(2, 4, 4), Vector3i(3, 4, 4), Vector3i(4, 4, 4)]) == "Blocked by another tunnel", "tunnels block each other")

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
