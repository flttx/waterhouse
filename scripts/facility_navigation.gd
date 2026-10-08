class_name WaterhouseNavigation
extends RefCounted
## Authored graph, native AStar3D and real player-sized collision sweeps.
## All coordinates describe feet, not the camera or a device's solid body.

const SURFACE_FEET: float = -1.43
const BODY_HEIGHT: float = 1.8
const BODY_RADIUS: float = 0.32
const MAX_ATTACHMENTS: int = 8
const MAX_CANDIDATES: int = 32
var accepted_edges: Array[Vector2i] = []
var rejected_edges: Array[Vector2i] = []
var accepted_ladder_edges: Array[Vector2i] = []
var graph_ready: bool = false
var _world: Node3D
var _points: Array[Vector3] = []
var _edges: Array[Vector2i] = []
var _ladder_edges: Array[Vector2i] = []
var _ladders: Array[Vector3] = []
var _astar := AStar3D.new()
var _capsule := CapsuleShape3D.new()
var _last_validation_ms: int = 0


func configure(world: Node3D) -> void:
	_world = world
	_points.clear()
	_edges.clear()
	_ladder_edges.clear()
	_ladders.clear()
	_astar.clear()
	accepted_edges.clear()
	rejected_edges.clear()
	accepted_ladder_edges.clear()
	graph_ready = false
	_capsule.radius = BODY_RADIUS
	_capsule.height = BODY_HEIGHT
	if not is_instance_valid(world):
		return
	_copy_vectors(world.get("navigation_points"), _points)
	_copy_edges(world.get("navigation_edges"), _edges)
	_copy_edges(world.get("navigation_ladder_edges"), _ladder_edges)
	_copy_vectors(world.get("ladders"), _ladders)
	for index in range(_points.size()):
		if _points[index].is_finite():
			_astar.add_point(index, _points[index])
	# Scene construction happens before physics synchronizes its static bodies.
	# Edge validation therefore belongs to the first physics-frame route request.


func _copy_vectors(source: Variant, target: Array[Vector3]) -> void:
	if source is Array:
		for value: Variant in source:
			if value is Vector3:
				target.append(value)
			else:
				# Preserve point IDs when rejecting malformed metadata.
				target.append(Vector3.INF)


func _copy_edges(source: Variant, target: Array[Vector2i]) -> void:
	if source is Array:
		for value: Variant in source:
			if value is Vector2i:
				target.append(value)


func refresh() -> void:
	graph_ready = false


func _validate_graph() -> void:
	accepted_edges.clear()
	rejected_edges.clear()
	accepted_ladder_edges.clear()
	for edge in _edges:
		if _astar.has_point(edge.x) and _astar.has_point(edge.y) and _astar.are_points_connected(edge.x, edge.y):
			_astar.disconnect_points(edge.x, edge.y)
	for edge in _edges:
		if edge.x == edge.y or not _astar.has_point(edge.x) or not _astar.has_point(edge.y):
			rejected_edges.append(edge)
			continue
		var a := _points[edge.x]
		var b := _points[edge.y]
		var ladder := _is_authored_ladder_edge(edge)
		var clear := _ladder_clear(a, b) if ladder else is_segment_clear(a, b)
		# Medium changes require an explicitly authored and usable ladder.
		if not ladder and _is_wet(a) != _is_wet(b):
			clear = false
		if clear:
			_astar.connect_points(edge.x, edge.y)
			accepted_edges.append(edge)
			if ladder:
				accepted_ladder_edges.append(edge)
		else:
			rejected_edges.append(edge)
	graph_ready = true
	_last_validation_ms = Time.get_ticks_msec()


func get_route(player_position: Vector3, goal_position: Vector3, in_water: bool, oxygen: float) -> Dictionary:
	if not is_instance_valid(_world) or not _world.is_inside_tree() or _points.is_empty() or _edges.is_empty():
		return _blocked("设施导航数据尚未就绪。")
	if not player_position.is_finite() or not goal_position.is_finite() or not is_finite(oxygen):
		return _blocked("当前位置或目标位置无效。")
	if not graph_ready:
		_validate_graph()
	if in_water and oxygen <= 25.0 and player_position.y >= SURFACE_FEET - 0.25:
		return _result([], "breathe", "breathe", 0.0, "保持在水面补充呼吸。")
	var start_id := _points.size()
	var goal_id := start_id + 1
	_astar.add_point(start_id, player_position)
	var starts := _attach(start_id, player_position, in_water)
	if starts == 0:
		_astar.remove_point(start_id)
		return _blocked("当前位置没有可通行的设施路线。")
	var points: Array[Vector3] = []
	var status := "route"
	if in_water and oxygen <= 25.0:
		points = _surface_route(start_id, player_position)
		status = "breathe"
	else:
		if player_position.distance_to(goal_position) <= 2.0 and _is_wet(goal_position) == in_water and is_segment_clear(player_position, goal_position):
			_astar.remove_point(start_id)
			return _result([], "continue", "reached", 0.0, "已到达目标附近。")
		_astar.add_point(goal_id, goal_position)
		if _attach(goal_id, goal_position, _is_wet(goal_position)) > 0:
			points = _path(start_id, goal_id, player_position)
		_astar.remove_point(goal_id)
	_astar.remove_point(start_id)
	if points.is_empty():
		# Reconsider a moved gate on a later physics request, without wall fallbacks.
		if Time.get_ticks_msec() - _last_validation_ms > 1500:
			graph_ready = false
		return _blocked("没有可通行路线。先寻找相连的走道或检修梯。")
	var next_point := points[0]
	for point in points:
		if point.distance_to(player_position) > 0.75:
			next_point = point
			break
	var action := "breathe" if status == "breathe" else _next_action(player_position, next_point, in_water)
	return _result(points, action, status, _route_length(player_position, points), "先返回水面补充呼吸。" if status == "breathe" else "")


func _attach(id: int, position: Vector3, wet: bool) -> int:
	var candidates := _candidates(position, wet)
	var count := 0
	for candidate in candidates:
		var node_id: int = candidate["id"]
		if is_segment_clear(position, _points[node_id]):
			_astar.connect_points(id, node_id)
			count += 1
			if count >= MAX_ATTACHMENTS:
				break
	return count


func _candidates(position: Vector3, wet: bool, surface_only: bool = false) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for index in range(_points.size()):
		if not _astar.has_point(index) or _is_wet(_points[index]) != wet:
			continue
		if surface_only and absf(_points[index].y - SURFACE_FEET) > 0.20:
			continue
		candidates.append({"id": index, "distance": position.distance_squared_to(_points[index])})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	if candidates.size() > MAX_CANDIDATES:
		candidates.resize(MAX_CANDIDATES)
	return candidates


func _surface_route(start_id: int, position: Vector3) -> Array[Vector3]:
	var best: Array[Vector3] = []
	var best_distance := INF
	for candidate in _candidates(position, true, true):
		var path := _path(start_id, candidate["id"], position)
		if path.is_empty():
			continue
		var distance := _route_length(position, path)
		if distance < best_distance:
			best = path
			best_distance = distance
	return best


func _path(start_id: int, goal_id: int, position: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var ids := _astar.get_id_path(start_id, goal_id)
	for index in range(1, ids.size()):
		var point := _astar.get_point_position(ids[index])
		var previous: Vector3 = position if points.is_empty() else points.back()
		if not is_ladder_segment(previous, point) and not is_segment_clear(previous, point):
			return []
		# Only consume an already reached leading waypoint, never skip a ladder.
		if points.is_empty() and position.distance_to(point) < 0.55 and index < ids.size() - 1 and not is_ladder_segment(point, _astar.get_point_position(ids[index + 1])):
			continue
		points.append(point)
	return points


func _next_action(position: Vector3, waypoint: Vector3, in_water: bool) -> String:
	if in_water and not _is_wet(waypoint):
		return "climb"
	if not in_water and _is_wet(waypoint):
		return "dive"
	if waypoint.y < position.y - 0.7:
		return "dive"
	if in_water and waypoint.y > position.y + 0.7:
		return "surface"
	return "continue"


func _route_length(position: Vector3, points: Array[Vector3]) -> float:
	var distance := 0.0
	var previous := position
	for point in points:
		distance += previous.distance_to(point)
		previous = point
	return distance


func _is_wet(position: Vector3) -> bool:
	return position.y < 0.1


func _is_authored_ladder_edge(edge: Vector2i) -> bool:
	return edge in _ladder_edges or Vector2i(edge.y, edge.x) in _ladder_edges


func is_ladder_segment(a: Vector3, b: Vector3) -> bool:
	if _is_wet(a) == _is_wet(b):
		return false
	for edge in accepted_ladder_edges:
		if (a.distance_to(_points[edge.x]) < 0.8 and b.distance_to(_points[edge.y]) < 0.8) or (a.distance_to(_points[edge.y]) < 0.8 and b.distance_to(_points[edge.x]) < 0.8):
			return true
	return false


func _ladder_clear(a: Vector3, b: Vector3) -> bool:
	if _is_wet(a) == _is_wet(b):
		return false
	var wet := a if _is_wet(a) else b
	var dry := b if _is_wet(a) else a
	if absf(wet.y - SURFACE_FEET) > 0.2 or absf(dry.y - 0.65) > 0.25:
		return false
	var authored := false
	for ladder in _ladders:
		if Vector2(dry.x - ladder.x, dry.z - ladder.z).length() < 1.4 and Vector2(wet.x - ladder.x, wet.z - ladder.z).length() < 2.8:
			authored = true
			break
	if not authored:
		return false
	# The player's E action rises clear of the lip before moving onto the deck.
	var corner := Vector3(wet.x, dry.y + 0.11, wet.z)
	var landing := dry + Vector3.UP * 0.11
	return _capsule_clear(wet, corner) and _capsule_clear(corner, landing)


func is_segment_clear(start: Vector3, finish: Vector3) -> bool:
	if not _capsule_clear(start, finish):
		return false
	var samples := maxi(1, int(ceil(start.distance_to(finish) / 1.5)))
	if not _is_wet(start) and not _is_wet(finish):
		# A collision-free line above a basin is not a walking route.
		var space := _world.get_world_3d().direct_space_state
		for index in range(samples + 1):
			var feet := start.lerp(finish, float(index) / float(samples))
			var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.20, feet + Vector3.DOWN * 1.8, 1)
			var ground := space.intersect_ray(query)
			if ground.is_empty() or Vector3(ground["normal"]).y < 0.55:
				return false
	elif _is_wet(start) and _is_wet(finish) and _world.has_method("is_water"):
		for index in range(samples + 1):
			if not _world.call("is_water", start.lerp(finish, float(index) / float(samples))):
				return false
	return true


func _capsule_clear(start: Vector3, finish: Vector3) -> bool:
	if not is_instance_valid(_world) or not _world.is_inside_tree() or not start.is_finite() or not finish.is_finite():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY, start + Vector3.UP * (BODY_HEIGHT * 0.5 + 0.035))
	query.collision_mask = 1
	query.margin = 0.005
	query.collide_with_areas = false
	var space := _world.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.motion = finish - start
	var fraction := space.cast_motion(query)
	if fraction.size() != 2 or fraction[0] < 0.999:
		return false
	query.transform.origin = finish + Vector3.UP * (BODY_HEIGHT * 0.5 + 0.035)
	query.motion = Vector3.ZERO
	return space.intersect_shape(query, 1).is_empty()


func _blocked(message: String) -> Dictionary:
	return _result([], "", "blocked", INF, message)


func _result(points: Array[Vector3], action: String, status: String, distance: float, message: String) -> Dictionary:
	return {"points": points, "action": action, "status": status, "distance": distance, "message": message}
