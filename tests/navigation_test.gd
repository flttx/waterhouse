extends SceneTree
## Native collision and authored-world route regression, no mock path finder.

class GraphFixture extends Node3D:
	var navigation_points: Array[Vector3] = []
	var navigation_edges: Array[Vector2i] = []
	var navigation_ladder_edges: Array[Vector2i] = []
	var ladders: Array[Vector3] = []

var failures: int = 0
var checks: int = 0
var ladder_segments: int = 0


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("Navigation test timed out")
		quit(1))
	call_deferred("_run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _solid(parent: Node3D, position: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	return body


func _run() -> void:
	await _fixture_checks()
	if checks < 10:
		expect(false, "navigation fixtures executed all required checks")
	if "fixtures-only" in OS.get_cmdline_user_args():
		print("NAVIGATION FIXTURES ONLY: %d checks, %d failures; authored world not checked" % [checks, failures])
		quit(1 if failures else 0)
		return
	await _world_checks()
	print("NAVIGATION: %d checks, %d failures, %d verified ladder transitions" % [checks, failures, ladder_segments])
	quit(1 if failures else 0)


func _fixture_checks() -> void:
	var fixture := GraphFixture.new()
	fixture.navigation_points = [Vector3(-6, 0.65, -3), Vector3(6, 0.65, -3), Vector3(-6, 0.65, 3), Vector3(6, 0.65, 3)]
	fixture.navigation_edges = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(0, 99)]
	root.add_child(fixture)
	_solid(fixture, Vector3(0, 0.15, 0), Vector3(22, 1, 16))
	var wall := _solid(fixture, Vector3(0, 2.65, 0), Vector3(0.5, 4, 12))
	await physics_frame
	await physics_frame
	var navigation := WaterhouseNavigation.new()
	navigation.configure(fixture)
	expect(not navigation.graph_ready, "configure defers physics validation until route request")
	var blocked := navigation.get_route(Vector3(-6, 0.65, 0), Vector3(6, 0.65, 0), false, 100)
	expect(blocked["status"] == "blocked" and blocked["points"].is_empty() and not blocked["message"].is_empty(), "wall-separated target returns explicit blocked state")
	expect(navigation.accepted_edges.size() == 2 and navigation.rejected_edges.size() == 3, "graph rejects solid-crossing and invalid-index edges")
	var nearby := navigation.get_route(Vector3(-0.8, 0.65, 0), Vector3(0.8, 0.65, 0), false, 100)
	expect(nearby["status"] == "blocked", "nearby goal across a wall cannot be treated as reached")
	wall.position.z = 100
	await physics_frame
	await physics_frame
	navigation.refresh()
	var restored := navigation.get_route(Vector3(-6, 0.65, 0), Vector3(6, 0.65, 0), false, 100)
	expect(restored["status"] == "route" and not restored["points"].is_empty(), "moving obstruction and refreshing restores native route")
	var midpoint := navigation.get_route(Vector3(0, 0.65, -3), Vector3(6, 0.65, -3), false, 100)
	var midpoint_points: Array[Vector3] = midpoint["points"]
	expect(not midpoint_points.is_empty() and midpoint_points[0].x >= 0, "edge midpoint attaches toward destination rather than backtracking")
	var device := _solid(fixture, Vector3(5, 1.45, 0), Vector3(0.8, 1.0, 0.3))
	await physics_frame
	await physics_frame
	var device_collision := navigation.get_route(Vector3(2, 0.65, 0), Vector3(5, 0.65, 0), false, 100)
	expect(device_collision["status"] == "blocked", "solid device center cannot serve as feet-space destination")
	var approach := navigation.get_route(Vector3(2, 0.65, 2), Vector3(5, 0.65, 2), false, 100)
	expect(approach["status"] == "route", "safe device approach remains reachable outside its solid body")
	device.queue_free()
	fixture.queue_free()
	await physics_frame
	var gap := GraphFixture.new()
	gap.navigation_points = [Vector3(-5, 0.65, 0), Vector3(5, 0.65, 0)]
	gap.navigation_edges = [Vector2i(0, 1)]
	root.add_child(gap)
	_solid(gap, Vector3(-5, -0.1, 0), Vector3(4, 1.5, 4))
	_solid(gap, Vector3(5, -0.1, 0), Vector3(4, 1.5, 4))
	await physics_frame
	await physics_frame
	navigation.configure(gap)
	var unsupported := navigation.get_route(Vector3(-5, 0.65, 0), Vector3(5, 0.65, 0), false, 100)
	expect(unsupported["status"] == "blocked" and navigation.accepted_edges.is_empty(), "empty space between dry decks cannot become a walking route")
	gap.queue_free()
	await physics_frame
	var underwater := GraphFixture.new()
	underwater.navigation_points = [Vector3(0, -4, 0), Vector3(0, -1.43, 0), Vector3(6, -1.43, 0), Vector3(6, -4, 0)]
	underwater.navigation_edges = [Vector2i(0, 1), Vector2i(0, 3), Vector2i(3, 2)]
	root.add_child(underwater)
	_solid(underwater, Vector3(0, -1, 0), Vector3(4, 0.2, 4))
	await physics_frame
	await physics_frame
	navigation.configure(underwater)
	var breath := navigation.get_route(Vector3(0, -4, 0), Vector3(6, -4, 0), true, 10)
	var breath_points: Array[Vector3] = breath["points"]
	expect(breath["status"] == "breathe" and breath["action"] == "breathe" and not breath_points.is_empty(), "low oxygen routes to an existing breathable graph node")
	expect(not breath_points.is_empty() and breath_points.back().x == 6 and is_equal_approx(breath_points.back().y, -1.43), "breath route goes around overhead slab instead of through it")
	_expect_segments(navigation, Vector3(0, -4, 0), breath_points, "under-slab breath route")
	var recovered := navigation.get_route(Vector3(6, -1.43, 0), Vector3(6, -4, 0), true, 15)
	expect(recovered["status"] == "breathe" and recovered["points"].is_empty(), "surface recovery does not redirect player underwater before breathing")
	underwater.queue_free()
	await physics_frame
	var ladder_fixture := GraphFixture.new()
	ladder_fixture.navigation_points = [Vector3(0, 0.65, 0), Vector3(2, -1.43, 0)]
	ladder_fixture.navigation_edges = [Vector2i(0, 1)]
	ladder_fixture.navigation_ladder_edges = [Vector2i(0, 1)]
	ladder_fixture.ladders = [Vector3(0, 0.7, 0)]
	root.add_child(ladder_fixture)
	_solid(ladder_fixture, Vector3(-1.5, -0.1, 0), Vector3(5, 1.5, 10))
	await physics_frame
	await physics_frame
	navigation.configure(ladder_fixture)
	var shore := navigation.get_route(Vector3(2, -1.43, 0), Vector3(0, 0.65, 0), true, 100)
	expect(navigation.accepted_ladder_edges.size() == 1 and not navigation.is_segment_clear(Vector3(2, -1.43, 0), Vector3(0, 0.65, 0)), "authored ladder preserves valid climb despite blocking diagonal pool lip")
	expect(shore["status"] == "route" and shore["action"] == "climb", "reached ladder waypoint still directs player to climb onto deck")
	ladder_fixture.queue_free()
	await physics_frame
	var empty := GraphFixture.new()
	root.add_child(empty)
	navigation.configure(empty)
	var absent := navigation.get_route(Vector3.ZERO, Vector3.ONE, false, 100)
	expect(absent["status"] == "blocked", "missing navigation metadata produces a real blocked result")
	empty.queue_free()
	await physics_frame


func _world_checks() -> void:
	var scene := load("res://scenes/world.tscn") as PackedScene
	if scene == null:
		expect(false, "authored world scene loads")
		return
	var world := scene.instantiate() as Node3D
	root.add_child(world)
	await physics_frame
	await physics_frame
	var source_points: Variant = world.get("navigation_points")
	var source_edges: Variant = world.get("navigation_edges")
	var source_targets: Variant = world.get("navigation_targets")
	if not source_points is Array or source_points.is_empty() or not source_edges is Array or source_edges.is_empty() or not source_targets is Dictionary or source_targets.size() < 10:
		expect(false, "authored world supplies nonempty graph and all ten device approaches")
		world.queue_free()
		await physics_frame
		return
	expect(true, "authored world supplies graph and all ten device approaches")
	var targets: Dictionary = source_targets
	var game_script := load("res://scripts/game.gd") as GDScript
	var devices: Array = game_script.get_script_constant_map().get("DEVICE_DATA", []) if game_script != null else []
	expect(devices.size() >= 10, "native device definitions are available for approach collision verification")
	for data: Array in devices:
		var device := WaterhouseDevice.new()
		device.device_id = data[0]
		device.title = data[1]
		device.position = data[3]
		world.add_child(device)
	await physics_frame
	await physics_frame
	var navigation := WaterhouseNavigation.new()
	navigation.configure(world)
	var position := Vector3(-21, 0.72, 36)
	for id: String in ["archive", "annex_valve", "tier_valve", "overflow_valve", "reservoir_valve"]:
		if not targets.has(id):
			expect(false, "authored route target exists: " + id)
			continue
		var destination: Vector3 = targets[id]
		var result := navigation.get_route(position, destination, position.y < 0.1, 100)
		var points: Array[Vector3] = result["points"]
		expect(result["status"] in ["route", "reached"] and not points.is_empty(), "actual facility route reaches " + id)
		_expect_segments(navigation, position, points, "actual route " + id)
		if not points.is_empty():
			expect(points.back().distance_to(destination) < 0.05, "route ends at safe feet-space approach: " + id)
		position = destination
	expect(not navigation.accepted_edges.is_empty(), "actual authored graph has collision-validated connections")
	var authored_ladders: Array = world.get("navigation_ladder_edges")
	expect(authored_ladders.size() >= 14 and navigation.accepted_ladder_edges.size() == authored_ladders.size(), "all authored ladders preserve validated medium transition connections")
	for id: String in targets:
		expect(navigation.is_segment_clear(targets[id], targets[id]), "device approach fits standing player body: " + id)
	print("NAV_GRAPH edges=%d accepted=%d rejected=%d ladders=%d" % [source_edges.size(), navigation.accepted_edges.size(), navigation.rejected_edges.size(), navigation.accepted_ladder_edges.size()])
	for edge in navigation.rejected_edges:
		if edge.x >= 0 and edge.y >= 0 and edge.x < source_points.size() and edge.y < source_points.size():
			print("NAV_EDGE_FILTERED ", source_points[edge.x], " -> ", source_points[edge.y], " collider=", _collision_label(world, source_points[edge.x], source_points[edge.y]))
	world.queue_free()
	await physics_frame
	await physics_frame


func _expect_segments(navigation: WaterhouseNavigation, start: Vector3, points: Array[Vector3], description: String) -> void:
	var previous := start
	var clear := not points.is_empty()
	for point in points:
		if navigation.is_ladder_segment(previous, point):
			ladder_segments += 1
			print("NAV_LADDER_ALLOWED ", previous, " -> ", point)
		elif not navigation.is_segment_clear(previous, point):
			clear = false
			push_error("NAV_SEGMENT_BLOCKED " + str(previous) + " -> " + str(point))
		previous = point
	expect(clear, "all normal segments pass native capsule collision: " + description)


func _collision_label(world: Node3D, start: Vector3, finish: Vector3) -> String:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	query.shape = capsule
	query.collision_mask = 1
	query.margin = 0.005
	query.transform.origin = start + Vector3.UP * 0.935
	var space := world.get_world_3d().direct_space_state
	var hits := space.intersect_shape(query, 1)
	if hits.is_empty():
		query.motion = finish - start
		var fraction := space.cast_motion(query)
		if fraction.size() == 2:
			query.transform.origin += query.motion * minf(1.0, fraction[1] + 0.001)
			query.motion = Vector3.ZERO
			hits = space.intersect_shape(query, 1)
	if not hits.is_empty():
		var collider := hits[0].get("collider") as Node
		return str(collider.get_parent().name) if collider != null else "static body"
	return "invalid or unsupported edge"
