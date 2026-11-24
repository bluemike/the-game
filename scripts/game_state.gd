extends RefCounted
## The rules: where a piece may go, placing and undoing pieces, and winning.
## Nothing here draws anything, so the rules can be tested on their own.

const Grid := preload("res://scripts/grid.gd")

var grid: Grid
var players: Array = []
var _history: Array = []  # each entry: {"player": id, "cells": Array[Vector3i]}


func _init(size: Vector3i) -> void:
	grid = Grid.new(size)


## Adds a player and marks their start cell as the first cell of their tunnel.
func add_player(player) -> void:
	players.append(player)
	grid.set_cell(player.start_cell, player.id)


## Returns "" if the cells can be placed, otherwise the reason they can't.
func check_placement(player, cells: Array) -> String:
	if player.has_won:
		return "Tunnel already complete"
	for cell in cells:
		if not grid.in_bounds(cell):
			return "Outside the cube"
		var owner_id: int = grid.owner_of(cell)
		if owner_id == player.id:
			return "Overlaps your tunnel"
		if owner_id != Grid.EMPTY:
			return "Blocked by another tunnel"
	if not touches_tunnel(player, cells):
		return "Must touch your tunnel"
	return ""


## True if any of the cells shares a face with the player's tunnel.
## Any part of the tunnel counts, not only the last piece.
func touches_tunnel(player, cells: Array) -> bool:
	for cell in cells:
		for step in Grid.NEIGHBOURS:
			if grid.owner_of(cell + step) == player.id:
				return true
	return false


func place(player, cells: Array) -> bool:
	if check_placement(player, cells) != "":
		return false
	for cell in cells:
		grid.set_cell(cell, player.id)
	_history.append({"player": player.id, "cells": cells.duplicate()})
	player.has_won = reaches_goal(player)
	return true


## Removes the player's most recent piece. Returns false if there is none.
func undo_last(player) -> bool:
	for i in range(_history.size() - 1, -1, -1):
		if _history[i]["player"] == player.id:
			for cell in _history[i]["cells"]:
				grid.clear_cell(cell)
			_history.remove_at(i)
			player.has_won = reaches_goal(player)
			return true
	return false


func pieces_placed(player) -> int:
	var count := 0
	for entry in _history:
		if entry["player"] == player.id:
			count += 1
	return count


func reaches_goal(player) -> bool:
	for cell in grid.cells_of(player.id):
		if player.is_goal_cell(cell):
			return true
	return false


## The furthest the player's tunnel has got from the start face.
func best_progress(player) -> int:
	var best := 0
	for cell in grid.cells_of(player.id):
		best = maxi(best, player.progress_of(cell))
	return best
