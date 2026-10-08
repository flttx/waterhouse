extends SceneTree
## One native GPU matrix of the actual game: title, live guidance, paused map.

var failures: int = 0


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("Actual game UI visual test timed out")
		quit(1))
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = dimensions
		var game := load("res://scenes/main.tscn").instantiate() as Node3D
		root.add_child(game)
		current_scene = game
		await physics_frame
		await physics_frame
		# Exercise the real run profile without persisting test settings.
		game.selected_difficulty = "exploration"
		game.hud.set_difficulty("exploration")
		await _capture("title", dimensions)
		game.start_run()
		game._set_enemies_enabled(false)
		await physics_frame
		await physics_frame
		await physics_frame
		game._update_guidance()
		if game.hud.navigation_mode != "map" or game.hud.navigation_hud.diagram.markers.size() != game.devices.size():
			failures += 1
			push_error("Actual guide must use all native device markers")
		await _capture("guide", dimensions)
		game.open_map()
		await process_frame
		if game.hud.facility_map.markers.size() != game.devices.size() or game.hud.facility_map.regions.size() != game.world.map_regions.size():
			failures += 1
			push_error("Actual map must reflect the complete authored facility")
		await _capture("map", dimensions, game)
		print("GAME_UI_MATRIX ", dimensions, " regions=", game.world.map_regions.size(), " markers=", game.devices.size(), " facility=", game.hud.facility_map.map_bounds, " route_points=", game._route_points().size())
		paused = false
		game.queue_free()
		await process_frame
		await process_frame
		await create_timer(0.2).timeout
	print("ACTUAL GAME UI MATRIX: 6 captures, %d failures" % failures)
	quit(1 if failures else 0)


func _capture(state: String, dimensions: Vector2i, game: Node3D = null) -> void:
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/game_ui_%s_%dx%d.png" % [state, dimensions.x, dimensions.y]
	var rendered := root.get_texture().get_image()
	if rendered.save_png(path) != OK:
		failures += 1
		push_error("Could not save actual game UI capture: " + path)
	if state == "map" and game != null:
		_verify_small_creature_chevrons(game, rendered)


func _verify_small_creature_chevrons(game: Node3D, rendered: Image) -> void:
	var map: FacilityMap = game.hud.facility_map
	var scale := Vector2(rendered.get_width(), rendered.get_height()) / root.get_visible_rect().size
	var checked := 0
	for monster in map.monster_markers:
		var position: Vector3 = monster["position"]
		if not monster.get("small", false) or absf(position.y - game.player.camera.global_position.y) <= 3.0:
			continue
		var vertical := map.monster_vertical_direction(position)
		var tip := map.map_point(position) + Vector2(0, vertical * 11)
		var pixel := (map.get_global_transform_with_canvas() * tip) * scale
		var red_tip := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := int(round(pixel.x)) + dx
				var y := int(round(pixel.y)) + dy
				if x < 0 or y < 0 or x >= rendered.get_width() or y >= rendered.get_height():
					continue
				var color := rendered.get_pixel(x, y)
				red_tip = red_tip or (color.r > 0.65 and color.r > color.g * 1.5 and color.r > color.b * 1.5)
		checked += 1
		if vertical == 0.0 or not red_tip:
			failures += 1
			push_error("Small creature height chevron missing from native render: " + str(monster.get("name", "creature")))
	if checked == 0:
		failures += 1
		push_error("Actual map must exercise at least one small creature height chevron")
	print("GAME_UI_SMALL_HEIGHT_RENDER verified=", checked)
