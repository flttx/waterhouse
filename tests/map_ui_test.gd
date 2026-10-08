extends SceneTree
## Exercises native HUD controls and map projection independently of game actors.

var failures: int = 0
var checks: int = 0
var difficulty_events: Array[String] = []
var close_events: int = 0
var map_events: int = 0


func _initialize() -> void:
	create_timer(25.0).timeout.connect(func() -> void:
		push_error("Map UI test timed out")
		quit(1))
	call_deferred("_run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)


func _fixture_regions() -> Array[Dictionary]:
	return [
		{"id": "main", "name": "蓄水厅 04", "bounds": Rect2(-28, -55, 56, 108)},
		{"id": "archive", "name": "西侧档案室", "bounds": Rect2(-63, -16, 30, 38)},
		{"id": "west_passage", "name": "连接廊", "bounds": Rect2(-33, -4, 5, 10)},
		{"id": "filter", "name": "过滤池 05", "bounds": Rect2(34, -36, 48, 66)},
		{"id": "east_passage", "name": "连接廊", "bounds": Rect2(28, -4, 6, 10)},
		{"id": "control", "name": "控制室", "bounds": Rect2(43, -53, 26, 17)},
	]


func _fixture_markers() -> Array[Dictionary]:
	return [
		{"id": "breaker", "title": "主供电断路器", "position": Vector3(-24, 0.7, 31), "completed": true, "available": false, "current": false},
		{"id": "valve_south", "title": "南侧隔离阀", "position": Vector3(-9, -6, 24), "completed": false, "available": true, "current": true},
		{"id": "valve_north", "title": "北侧隔离阀", "position": Vector3(11, -7, -28), "completed": false, "available": true, "current": false},
		{"id": "archive", "title": "档案室钥匙", "position": Vector3(-53, 0.7, 5), "completed": false, "available": false, "current": false},
		{"id": "filter", "title": "过滤池旁路阀", "position": Vector3(59, -5, -13), "completed": false, "available": false, "current": false},
		{"id": "pump", "title": "排水泵控制台", "position": Vector3(49, 0.7, -45), "completed": false, "available": false, "current": false},
		{"id": "exit", "title": "北侧逃生门", "position": Vector3(0, 0.7, -52), "completed": false, "available": false, "current": false},
	]


func _run() -> void:
	var hud := WaterhouseHUD.new()
	root.add_child(hud)
	hud.difficulty_changed.connect(func(key: String) -> void: difficulty_events.append(key))
	hud.map_close_requested.connect(func() -> void: close_events += 1)
	hud.map_requested.connect(func() -> void: map_events += 1)
	await process_frame
	await process_frame
	expect(hud.current_page == "title" and hud.selected_difficulty == "survival", "title defaults to survival")
	expect(hud.difficulty_buttons.size() == 3, "title has three native difficulty choices")
	for key in ["exploration", "survival", "abyss"]:
		var choice: Button = hud.difficulty_buttons[key]
		choice.grab_focus()
		_accept_key(true)
		await process_frame
		_accept_key(false)
		await process_frame
		expect(hud.selected_difficulty == key, "keyboard selects " + key)
		var pressed_count := 0
		for button: Button in hud.difficulty_buttons.values():
			if button.button_pressed:
				pressed_count += 1
		expect(pressed_count == 1, "difficulty group keeps one selection for " + key)
	expect(difficulty_events == ["exploration", "survival", "abyss"], "difficulty signals carry selected keys")
	hud.set_difficulty("exploration")
	expect(difficulty_events.size() == 3, "loading difficulty does not emit user change signal")
	hud.show_page("settings")
	expect(hud.menu.find_children("*", "HSlider", true, false).size() == 3, "settings retain brightness volume and sensitivity")
	expect(hud.difficulty_buttons.is_empty(), "settings do not expose difficulty changes")
	hud.set_difficulty("abyss")
	expect(hud.current_page == "settings", "difficulty loading does not cover settings")
	hud.show_page("title")
	expect(hud.difficulty_buttons["abyss"].button_pressed, "loaded choice survives settings roundtrip")
	hud.update_goal("北侧隔离阀", Vector3(20, -6, 0), Vector3.ZERO, 0, "过滤池 05", "abyss", 2, 7)
	expect(hud.goal_hint.text.contains("右侧") and hud.goal_hint.text.contains("直线 21 m"), "goal gives direction and explicitly straight distance")
	expect(hud.goal_hint.text.contains("目标水深 6.0 m"), "goal identifies target water depth")
	hud.update_goal("主供电断路器", Vector3(-20, 0.7, 0), Vector3.ZERO, PI / 2, "蓄水厅 04", "survival", 0, 7)
	expect(hud.goal_hint.text.begins_with("前方"), "goal direction follows native Godot yaw")
	expect(not hud.goal_hint.get_global_rect().intersects(hud.tutorial.get_global_rect()), "goal and lower-right controls occupy separate HUD regions")
	var regions := _fixture_regions()
	var waters: Array[Rect2] = [Rect2(-20, -47, 40, 90), Rect2(39, -31, 38, 55)]
	var markers := _fixture_markers()
	var route: Array[Vector3] = [Vector3(-24, 0.7, 11), Vector3(-9, -1, 11), Vector3(-9, -6, 24)]
	var monsters: Array[Dictionary] = [{"position": Vector3(0, -9, 19), "name": "利维坦", "small": false}, {"position": Vector3(48, -3, -13), "name": "鮟鱇", "small": false}]
	hud.show_page("game")
	hud.update_navigation(regions, waters, markers, Vector3(-24, 0.7, 31), PI / 4, "exploration", route, monsters, "dive")
	expect(hud.navigation_mode == "map" and hud.navigation_hud.diagram.visible, "exploration uses live mini map")
	expect(hud.navigation_hud.diagram.monster_markers.size() == 2 and hud.navigation_hud.diagram.route_points.size() == 3, "exploration map receives actual creature positions and route")
	var miniature := hud.navigation_hud.diagram
	expect(miniature.map_point(miniature.player_position).is_equal_approx(miniature.size * 0.5), "mini map stays centered on player")
	var north_point := miniature.map_point(miniature.player_position + Vector3(0, 0, -10))
	expect(north_point.y < miniature.size.y * 0.5, "mini map keeps north up independently of heading")
	var original_scale := miniature.map_scale
	var zoom_key := InputEventKey.new()
	zoom_key.pressed = true
	zoom_key.physical_keycode = KEY_EQUAL
	root.push_input(zoom_key)
	expect(miniature.zoom > 1 and miniature.map_scale > original_scale, "native plus key zooms mini map")
	miniature.set_zoom(99)
	expect(miniature.zoom == 2.0, "map zoom clamps to readable upper bound")
	miniature.set_zoom(0.01)
	expect(miniature.zoom == 0.5, "map zoom clamps to readable lower bound")
	miniature.set_zoom(1)
	hud.update_navigation(regions, waters, markers, Vector3(-24, 0.7, 31), 0, "survival", route, monsters, "dive")
	expect(hud.navigation_mode == "direction" and not miniature.visible and hud.navigation_hud.arrow_visible, "survival shows arrow without mini map")
	expect(hud.navigation_hud.action_text == "下潜" and hud.goal_hint.text.contains("路线"), "real route exposes medium transition and route distance")
	hud.update_navigation(regions, waters, markers, Vector3(-24, 0.7, 31), 0, "survival", route, monsters, "breathe")
	expect(not hud.navigation_hud.arrow_visible and hud.navigation_hud.action_text == "先上浮呼吸", "breath recovery suppresses misleading directional arrow")
	var facing_route: Array[Vector3] = [Vector3(-20, 0.7, 0)]
	hud.update_navigation(regions, waters, markers, Vector3.ZERO, PI / 2, "survival", facing_route, monsters)
	expect(absf(hud.navigation_hud.direction_angle) < 0.01, "direction arrow rotates into player-relative heading")
	hud.update_goal("墙后设备", Vector3(-12, 0.7, 0), Vector3.ZERO, 0, "维护走廊", "survival", 0, 7)
	var detour: Array[Vector3] = [Vector3.ZERO, Vector3(4, 0.7, 0), Vector3(4, 0.7, -8), Vector3(-12, 0.7, -8), Vector3(-12, 0.7, 0)]
	hud.update_navigation(regions, waters, markers, Vector3.ZERO, 0, "survival", detour, monsters)
	expect(hud.goal_hint.text.begins_with("右侧") and is_equal_approx(hud.navigation_hud.direction_angle, PI / 2), "wall detour caption and arrow both follow right-side waypoint instead of left-side goal")
	hud.update_navigation(regions, waters, markers, Vector3.ZERO, 0, "survival", [], monsters, "", "unreachable")
	expect(not hud.navigation_hud.arrow_visible and hud.navigation_hud.action_text == "路线暂不可达", "unreachable route never draws a usable direction arrow")
	expect(hud.goal_hint.text.begins_with("路线暂不可达") and not hud.goal_hint.text.contains("前方"), "blocked goal caption does not imply an available direction")
	hud.update_navigation(regions, waters, markers, Vector3.ZERO, 0, "survival", [], monsters, "", "reached")
	expect(hud.goal_hint.text.begins_with("已到达目标附近") and not hud.navigation_hud.arrow_visible, "reached caption reports arrival without a direction")
	hud.update_navigation(regions, waters, markers, Vector3.ZERO, 0, "survival", [], monsters, "wait", "waiting")
	expect(hud.goal_hint.text.begins_with("等待设备") and not hud.navigation_hud.arrow_visible, "waiting caption reports device state without a direction")
	hud.update_navigation(regions, waters, markers, Vector3.ZERO, 0, "survival", [], monsters)
	expect(hud.goal_hint.text.begins_with("正在定位路线") and not hud.navigation_hud.arrow_visible, "empty route remains pending without inventing a direction")
	hud.update_navigation(regions, waters, markers, Vector3(-24, 0.7, 31), 0, "abyss", route, monsters)
	expect(hud.navigation_mode == "hidden" and not hud.goal_hint.visible and not hud.navigation_hud.visible and not hud.mission.visible, "abyss suppresses map arrow and task guidance")
	hud.set_difficulty("exploration")
	paused = true
	hud.show_map(regions, waters, markers, Vector3(-24, 0.7, 31), PI / 4, monsters, route)
	await process_frame
	await process_frame
	expect(paused and hud.current_page == "map", "HUD keeps parent pause state while showing map")
	expect(not hud.interface.visible and hud.menu.visible, "map covers gameplay HUD")
	expect(hud.facility_map.markers.size() == 7, "map displays all seven supplied devices")
	expect(hud.facility_map.regions.size() == 6 and hud.facility_map.water_regions.size() == 2, "map contains main pool new wings and connecting passages")
	expect(hud.facility_map.player_yaw == PI / 4, "map retains exact player heading")
	var above_small := {"position": Vector3(5, 6, 0), "small": true, "name": "Lurker"}
	var below_small := {"position": Vector3(8, -5, -12), "small": true, "name": "Drifter"}
	expect(hud.facility_map.monster_vertical_direction(above_small["position"]) == -1.0 and hud.facility_map.monster_vertical_direction(below_small["position"]) == 1.0, "small creatures receive camera-relative above and below chevrons")
	expect(hud.facility_map.monster_vertical_direction(Vector3(0, 4, 0)) == 0.0, "creature height threshold uses eyes rather than feet")
	expect(hud.facility_map.monster_markers.size() == 2 and hud.facility_map.route_points.size() == 3, "exploration full map shares real creature and route data")
	expect(hud.facility_map.marker_color(markers[0]) == FacilityMap.CYAN and hud.facility_map.marker_color(markers[1]) == FacilityMap.AMBER, "map distinguishes completed and current devices")
	var close_button := root.gui_get_focus_owner() as Button
	expect(close_button != null and close_button.text.contains("返回水房"), "map focuses keyboard-operable close button")
	_accept_key(true)
	await process_frame
	_accept_key(false)
	expect(close_events == 1 and paused, "keyboard close requests parent action without unpausing itself")
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var map := hud.facility_map
		expect(map.map_scale > 0 and map.map_bounds.size.x * map.map_scale <= map.map_rect.size.x + 0.1 and map.map_bounds.size.y * map.map_scale <= map.map_rect.size.y + 0.1, "plan fits " + str(dimensions))
		expect(map.map_rect.has_point(map.map_point(map.player_position)), "player remains inside plan at " + str(dimensions))
		if "capture" in OS.get_cmdline_user_args():
			await _capture("res://artifacts/map_%dx%d.png" % [dimensions.x, dimensions.y])
			hud.show_page("title")
			await _capture("res://artifacts/title_%dx%d.png" % [dimensions.x, dimensions.y])
			hud.show_page("game")
			hud.mission.text = "关闭南北隔离阀，寻找过滤池旁路控制"
			hud.update_goal("南侧隔离阀", Vector3(-9, -6, 24), Vector3(-24, 0.7, 31), 0.2, "蓄水厅 04", "survival", 1, 7)
			hud.update_navigation(regions, waters, markers, Vector3(-24, 0.7, 31), PI / 4, "exploration", route, monsters, "dive")
			await _capture("res://artifacts/goal_%dx%d.png" % [dimensions.x, dimensions.y])
			hud.show_map(regions, waters, markers, Vector3(-24, 0.7, 31), PI / 4, monsters, route)
			await process_frame
	var many_markers := markers.duplicate(true)
	for index in range(18):
		many_markers.append({"id": "extra_%d" % index, "title": "扩展区设备 %d" % (index + 1), "position": Vector3(55, -5, index - 20), "completed": false, "available": false, "current": false})
	hud.show_map(regions, waters, many_markers, Vector3(-24, 0.7, 31), PI / 4, monsters, route)
	await process_frame
	await process_frame
	expect(hud.facility_map.markers.size() == 25, "map accepts expanded device counts without a seven-device limit")
	var scroll := hud.facility_map.get_child(0) as ScrollContainer
	expect(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "large device list scrolls instead of overlapping room labels")
	hud.set_difficulty("survival")
	hud.show_map(regions, waters, markers, Vector3(-24, 0.7, 31), PI / 4, monsters, route)
	expect(hud.facility_map.monster_markers.is_empty() and hud.facility_map.route_points.is_empty(), "survival full map protects creature positions and guided route")
	hud.show_page("pause")
	var pause_buttons := hud.menu.find_children("*", "Button", true, false)
	for button: Button in pause_buttons:
		if button.text == "设施地图":
			button.pressed.emit()
	expect(map_events == 1, "pause menu sends map request through native button")
	expect(hud.difficulty_buttons.is_empty(), "pause cannot change a live run difficulty")
	paused = false
	hud.queue_free()
	await process_frame
	print("MAP UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _accept_key(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = pressed
	root.push_input(event)


func _capture(path: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	expect(result == OK, "native UI capture " + path)
