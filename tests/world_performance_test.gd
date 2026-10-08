extends SceneTree
## Repeatable native GPU sampling; no captures or image downloads during the measured frames.

const SAMPLE_FRAMES: int = 180
const WARMUP_FRAMES: int = 90


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("World performance sampling requires the native renderer, without --headless.")
		quit(1)
		return
	root.size = Vector2i(1440, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var args := OS.get_cmdline_user_args()
	var label := args[0] if not args.is_empty() else "sample"
	var world := preload("res://scenes/world.tscn").instantiate() as WaterhouseWorld
	if label == "baseline" and world.get("batch_static_boxes") != null:
		world.set("batch_static_boxes", false)
	root.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.06
	camera.far = 180.0
	world.add_child(camera)
	camera.current = true
	var views: Array[Dictionary] = []
	camera.position = Vector3(-21, 2.25, 36)
	camera.look_at(Vector3(6, 4, -27))
	views.append(await _sample("south_deck"))
	camera.position = Vector3(0, 4.0, 40)
	camera.look_at(Vector3(0, -0.2, 2))
	views.append(await _sample("pool_overview"))
	world.environment.fog_density = 0.055
	world.environment.fog_light_color = Color(0.015, 0.10, 0.115)
	camera.position = Vector3(-8, -4.0, 22)
	camera.look_at(Vector3(-10, -6.1, 16))
	views.append(await _sample("submerged_filter"))
	var result := {
		"label": label, "renderer": RenderingServer.get_video_adapter_name(),
		"resolution": [1440, 900], "vsync": "disabled", "frames_per_view": SAMPLE_FRAMES,
		"captures_during_sample": false, "views": views, "scene_contract": _scene_contract(world),
	}
	print("WORLD_PERFORMANCE ", JSON.stringify(result))
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var output := FileAccess.open("res://artifacts/world_perf_" + label + ".json", FileAccess.WRITE)
	if output == null:
		push_error("Could not write world performance evidence.")
		quit(1)
		return
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	world.queue_free()
	await process_frame
	quit(0)


func _sample(view_name: String) -> Dictionary:
	for i in range(WARMUP_FRAMES):
		await process_frame
	var times_ms: Array[float] = []
	var draws_total: float = 0.0
	var objects_total: float = 0.0
	var previous_us := Time.get_ticks_usec()
	for i in range(SAMPLE_FRAMES):
		await process_frame
		var now_us := Time.get_ticks_usec()
		times_ms.append(float(now_us - previous_us) / 1000.0)
		previous_us = now_us
		draws_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects_total += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var total_ms: float = 0.0
	for sample_ms in times_ms:
		total_ms += sample_ms
	times_ms.sort()
	return {
		"view": view_name, "mean_ms": total_ms / SAMPLE_FRAMES,
		"median_ms": times_ms[SAMPLE_FRAMES / 2],
		"p95_ms": times_ms[int(float(SAMPLE_FRAMES) * 0.95)],
		"average_drawcalls": draws_total / SAMPLE_FRAMES,
		"average_visible_objects": objects_total / SAMPLE_FRAMES,
	}


func _scene_contract(world: WaterhouseWorld) -> Dictionary:
	var collision_records: Array[String] = []
	_collision_records(world, collision_records)
	var box_records: Array[String] = []
	var batch_count: int = 0
	for child in world.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			_box_records(child.global_transform, child.mesh.size, box_records)
		elif child is MultiMeshInstance3D:
			batch_count += 1
			for i in range(child.multimesh.instance_count):
				_box_records(child.global_transform * child.multimesh.get_instance_transform(i), Vector3.ONE, box_records)
	collision_records.sort()
	box_records.sort()
	return {
		"collision_count": collision_records.size(), "box_corner_count": box_records.size(),
		"collision_hash": "\n".join(collision_records).sha256_text(),
		"geometry_hash": "\n".join(box_records).sha256_text(), "native_box_batches": batch_count,
	}


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


func _box_records(transform_value: Transform3D, size_value: Vector3, records: Array[String]) -> void:
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var point := transform_value * (Vector3(x, y, z) * size_value)
				records.append(str(point.snapped(Vector3(0.0001, 0.0001, 0.0001))))
