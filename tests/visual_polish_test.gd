extends SceneTree
## Visual dressing must preserve the native collision/navigation contract.
## Run without --headless for three reproducible Compatibility captures.

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


func _run() -> void:
	var world := preload("res://scenes/world.tscn").instantiate() as WaterhouseWorld
	root.add_child(world)
	await process_frame
	var records: Array[String] = []
	_collision_records(world, records)
	records.sort()
	_check(records.size() == 401, "Visual dressing changed collision count")
	_check("\n".join(records).sha256_text() == "8f6645f84a86b2f377932f0b914463553ca5d69397af5e6102ab45bf2d377f11", "Visual dressing changed physical shape, transform or layer")
	_check(world.ladders.size() == 16 and world.water_regions.size() == 10, "Visual pass changed traversal volumes")
	_check(world.navigation_edges.size() >= 260, "Visual pass removed authored routes")
	var silt := world.get_node("FirstDiveSuspension") as MultiMeshInstance3D
	_check(silt.multimesh.instance_count <= 300, "First dive particle budget exceeded")
	var reservoir_silt := world.get_node("ReservoirSuspension") as MultiMeshInstance3D
	_check(reservoir_silt.multimesh.instance_count <= 500, "Reservoir particle budget exceeded")
	_check(world.get_node("ReservoirMaintenanceCradle").position.y > 8, "Overhead dressing entered swimming corridor")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440, 900)
		var camera := Camera3D.new()
		camera.fov = 78
		camera.near = 0.06
		camera.far = 180
		world.add_child(camera)
		camera.current = true
		var player_scene := preload("res://scenes/player.tscn").instantiate()
		var flashlight := player_scene.get_node("Head/Camera3D/Flashlight").duplicate() as SpotLight3D
		camera.add_child(flashlight)
		player_scene.free()
		camera.position = Vector3(-21, 2.25, 36)
		camera.look_at(Vector3(6, 4, -15))
		await _capture("main_hall")
		camera.position = Vector3(169, 2.25, 43)
		camera.look_at(Vector3(136, 4.7, 43))
		await _capture("reservoir")
		flashlight.light_energy = 1.35
		flashlight.spot_range = 9.0
		flashlight.light_color = Color(0.48, 0.77, 0.84)
		world.environment.ambient_light_energy *= 0.68
		world.environment.fog_density = 0.075
		world.environment.fog_light_color = Color(0.015, 0.10, 0.115)
		camera.position = Vector3(-17, -2.4, 27)
		camera.look_at(Vector3(-10, -5.6, 16))
		await _capture("first_dive")
	print("VISUAL_POLISH checks=7 failures=", failures)
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func _capture(label: String) -> void:
	for frame in range(45):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var result := root.get_texture().get_image().save_png("res://artifacts/polish_" + label + ".png")
	_check(result == OK, "Could not save capture " + label)


func _collision_records(node: Node, records: Array[String]) -> void:
	if node is CollisionShape3D:
		var shape_record: String = node.shape.get_class()
		if node.shape is BoxShape3D:
			shape_record += " " + str(node.shape.size)
		elif node.shape is CylinderShape3D:
			shape_record += " %f %f" % [node.shape.radius, node.shape.height]
		var body := node.get_parent() as StaticBody3D
		records.append("%s %s %d %d" % [shape_record, node.global_transform, body.collision_layer, body.collision_mask])
	for child in node.get_children():
		_collision_records(child, records)
