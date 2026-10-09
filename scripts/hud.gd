class_name WaterhouseHUD
extends CanvasLayer

signal start_requested
signal resume_requested
signal restart_requested
signal quit_requested
signal setting_changed(key: String, value: float)
signal difficulty_changed(key: String)
signal map_requested
signal map_close_requested
signal audio_requested(cue: String)

const INK := Color(0.80, 0.88, 0.84)
const MUTED := Color(0.44, 0.60, 0.60)
const CYAN := Color(0.46, 0.78, 0.70)
const AMBER := Color(0.91, 0.62, 0.29)
var interface: Control
var menu: Control
var effect: ShaderMaterial
var mission: Label
var location_label: Label
var interaction: Label
var interaction_bar: TextureProgressBar
var oxygen_bar: TextureProgressBar
var stamina_bar: TextureProgressBar
var oxygen_text: Label
var inventory: Label
var notification: Label
var notice_time: float = 0.0
var reticle: Label
var tutorial: Label
var font: SystemFont
var brightness: float = 1.12
var sensitivity: float = 0.0022
var volume: float = 0.75
var sfx_volume: float = 1.0
var ambient_volume: float = 0.8
var music_volume: float = 0.6
var bob: bool = true
var reduced_grain: bool = false
var current_page: String = "title"
var result_reason: String = ""
var result_time: float = 0.0
var selected_difficulty: String = "survival"
var difficulty_buttons: Dictionary[String, Button] = {}
var goal_hint: Label
var facility_map: FacilityMap
var _goal_zone: String = ""
var _goal_metadata: String = ""
var navigation_hud: NavigationHUD
var navigation_mode: String = "direction"
var _goal_title: String = ""
var _goal_direction: String = ""
var _goal_depth_text: String = ""
var _goal_distance: float = 0.0
var _goal_angle: float = 0.0
var _navigation_action: String = ""
var _navigation_status: String = "route"
var _route_distance: float = -1.0

const DIFFICULTIES: Dictionary = {
	"exploration": ["探索", "长呼吸 · 较弱感知 · 路线小地图"],
	"survival": ["求生", "标准呼吸与感知 · 方向指引"],
	"abyss": ["深渊", "短呼吸 · 敏锐感知 · 无导航"],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var post := ColorRect.new()
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect = ShaderMaterial.new()
	effect.shader = load("res://shaders/immersion.gdshader")
	post.material = effect
	add_child(post)
	interface = Control.new()
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(interface)
	location_label = _label(interface, "蓄水厅 04  /  维护层", Vector2(38, 28), 16, MUTED)
	mission = _label(interface, "", Vector2(38, 65), 20, INK)
	mission.size = Vector2(1120, 32)
	goal_hint = _label(interface, "", Vector2(38, 103), 15, MUTED)
	goal_hint.size = Vector2(680, 56)
	goal_hint.add_theme_constant_override("line_spacing", 6)
	navigation_hud = NavigationHUD.new()
	navigation_hud.map_font = font
	navigation_hud.anchor_left = 1.0
	navigation_hud.position = Vector2(-342, 166)
	navigation_hud.size = Vector2(304, 242)
	interface.add_child(navigation_hud)
	reticle = _label(interface, "·", Vector2(-7, -17), 26, CYAN)
	reticle.anchor_left = 0.5
	reticle.anchor_top = 0.5
	interaction = _label(interface, "", Vector2(-270, 72), 18, INK)
	interaction.anchor_left = 0.5
	interaction.anchor_top = 0.5
	interaction.size = Vector2(540, 66)
	interaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_bar = _bar(interface, Vector2(-100, 143), Vector2(200, 3), CYAN)
	interaction_bar.anchor_left = 0.5
	interaction_bar.anchor_top = 0.5
	interaction_bar.visible = false
	oxygen_text = _label(interface, "呼吸 / 100", Vector2(38, -94), 13, MUTED)
	oxygen_text.anchor_top = 1.0
	oxygen_bar = _bar(interface, Vector2(38, -63), Vector2(170, 4), CYAN)
	oxygen_bar.anchor_top = 1.0
	var stamina_label := _label(interface, "体力", Vector2(244, -94), 13, MUTED)
	stamina_label.anchor_top = 1.0
	stamina_bar = _bar(interface, Vector2(244, -63), Vector2(130, 4), INK)
	stamina_bar.anchor_top = 1.0
	inventory = _label(interface, "Q  金属诱饵  3", Vector2(412, -88), 14, MUTED)
	inventory.anchor_top = 1.0
	notification = _label(interface, "", Vector2(-360, -170), 18, AMBER)
	notification.anchor_left = 0.5
	notification.anchor_top = 1.0
	notification.size = Vector2(720, 58)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial = _label(interface, "WASD  移动     鼠标  视角\nShift  快速移动（更响）\nC / Ctrl  蹲伏 · 水中下潜\nSpace  跳跃 · 水中上浮\nE  持续操作 · 梯子上岸\nF  手电     Q  金属诱饵\nM  设施地图     Esc  暂停", Vector2(-290, -240), 14, MUTED)
	tutorial.anchor_left = 1.0
	tutorial.anchor_top = 1.0
	tutorial.add_theme_constant_override("line_spacing", 6)
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	show_page("title")


func _label(parent: Control, content: String, pos: Vector2, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.position = pos
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _bar(parent: Control, pos: Vector2, dimensions: Vector2, color: Color) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.position = pos
	bar.size = dimensions
	bar.nine_patch_stretch = true
	var background := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	background.fill(Color(0.14, 0.23, 0.24, 0.8))
	var fill := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	fill.fill(color)
	bar.texture_under = ImageTexture.create_from_image(background)
	bar.texture_progress = ImageTexture.create_from_image(fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = dimensions
	parent.add_child(bar)
	return bar


func _button(parent: Control, text: String, pos: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = Vector2(310, 49)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", INK)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for style_name in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.10, 0.12, 0.72) if style_name == "normal" else Color(0.09, 0.22, 0.23, 0.94)
		style.border_width_left = 2
		style.border_color = MUTED if style_name == "normal" else CYAN
		style.content_margin_left = 20
		style.content_margin_right = 20
		button.add_theme_stylebox_override(style_name, style)
	parent.add_child(button)
	button.focus_entered.connect(func() -> void: audio_requested.emit("ui_move"))
	button.pressed.connect(func() -> void:
		audio_requested.emit("ui_confirm")
		callback.call())
	return button


func show_page(page: String) -> void:
	current_page = page
	difficulty_buttons.clear()
	facility_map = null
	for child in menu.get_children():
		menu.remove_child(child)
		child.queue_free()
	menu.visible = page != "game"
	interface.visible = page == "game"
	if page == "game":
		return
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.043, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(backdrop)
	var panel := Control.new()
	panel.anchor_left = 0.08
	panel.anchor_top = 0.16
	panel.size = Vector2(840, 630)
	menu.add_child(panel)
	_label(panel, "THE WATERHOUSE  /  CHAPTER 01", Vector2.ZERO, 14, CYAN)
	var focus_button: Button
	if page == "title":
		_label(panel, "深渊水房", Vector2(-3, 38), 64, INK)
		_label(panel, "水面很安静。\n你知道它在下面。", Vector2(0, 144), 22, MUTED)
		focus_button = _button(panel, "进入蓄水厅", Vector2(0, 265), func() -> void: start_requested.emit())
		_button(panel, "设置", Vector2(0, 325), func() -> void: show_page("settings"))
		_button(panel, "离开", Vector2(0, 385), func() -> void: quit_requested.emit())
		_difficulty_selector(panel)
		_label(panel, "第一人称恐怖潜行 · 建议佩戴耳机\n设备会发声。黑暗会保护你。水下才有出口。", Vector2(0, 478), 14, MUTED)
	elif page == "pause":
		_label(panel, "暂时屏息", Vector2(0, 45), 48, INK)
		_label(panel, "设施仍在等待。", Vector2(0, 117), 18, MUTED)
		focus_button = _button(panel, "继续", Vector2(0, 205), func() -> void: resume_requested.emit())
		_button(panel, "设施地图", Vector2(0, 265), func() -> void: map_requested.emit())
		_button(panel, "设置", Vector2(0, 325), func() -> void: show_page("settings"))
		_button(panel, "重新开始", Vector2(0, 385), func() -> void: restart_requested.emit())
		_button(panel, "离开", Vector2(0, 445), func() -> void: quit_requested.emit())
	elif page == "settings":
		_label(panel, "调整感官", Vector2(0, 45), 48, INK)
		var first_slider := _slider(panel, "亮度", 1.0, 1.5, brightness, 148, "brightness", 0, 360)
		_slider(panel, "鼠标灵敏度", 0.0008, 0.005, sensitivity, 232, "sensitivity", 0, 360)
		_slider(panel, "总音量", 0.0, 1.0, volume, 148, "volume", 430, 330)
		_slider(panel, "音效", 0.0, 1.0, sfx_volume, 232, "sfx_volume", 430, 330)
		_slider(panel, "环境", 0.0, 1.0, ambient_volume, 316, "ambient_volume", 430, 330)
		_slider(panel, "音乐", 0.0, 1.0, music_volume, 400, "music_volume", 430, 330)
		var check := CheckButton.new()
		check.text = "镜头步行起伏"
		check.position = Vector2(0, 332)
		check.button_pressed = bob
		check.add_theme_font_override("font", font)
		check.toggled.connect(func(value: bool) -> void: bob = value; setting_changed.emit("bob", 1.0 if value else 0.0))
		panel.add_child(check)
		var grain := CheckButton.new()
		grain.text = "减少胶片颗粒"
		grain.position = Vector2(0, 387)
		grain.button_pressed = reduced_grain
		grain.add_theme_font_override("font", font)
		grain.toggled.connect(func(value: bool) -> void: reduced_grain = value; setting_changed.emit("grain", 0.0 if value else 1.0))
		panel.add_child(grain)
		_button(panel, "返回", Vector2(0, 492), func() -> void: show_page("pause" if get_tree().paused else "title"))
		call_deferred("_focus_button", first_slider)
	elif page == "dead":
		_label(panel, "水房留下了你", Vector2(0, 45), 48, INK)
		_label(panel, result_reason, Vector2(0, 129), 20, AMBER)
		_label(panel, "水下设备附近有隔墙可以遮蔽视线。\n关闭手电，放慢动作，先找到下一处梯子。", Vector2(0, 192), 17, MUTED)
		focus_button = _button(panel, "再次进入", Vector2(0, 310), func() -> void: restart_requested.emit())
		_button(panel, "离开", Vector2(0, 370), func() -> void: quit_requested.emit())
	elif page == "won":
		_label(panel, "你回到了空气中", Vector2(0, 45), 48, INK)
		_label(panel, "外面没有人。\n身后的水声，终于远了。", Vector2(0, 143), 22, MUTED)
		_label(panel, "逃离蓄水厅 04  /  %02d:%02d" % [int(result_time) / 60, int(result_time) % 60], Vector2(0, 241), 16, CYAN)
		focus_button = _button(panel, "重新进入", Vector2(0, 330), func() -> void: restart_requested.emit())
		_button(panel, "离开", Vector2(0, 390), func() -> void: quit_requested.emit())
	if focus_button != null:
		call_deferred("_focus_button", focus_button)


func _difficulty_selector(parent: Control) -> void:
	_label(parent, "选择难度", Vector2(390, 224), 17, INK)
	var group := ButtonGroup.new()
	for index in range(DIFFICULTIES.size()):
		var key: String = DIFFICULTIES.keys()[index]
		var choice: Array = DIFFICULTIES[key]
		var button := _button(parent, "%s\n%s" % [choice[0], choice[1]], Vector2(390, 259 + index * 71), func() -> void: _choose_difficulty(key))
		button.size = Vector2(408, 63)
		button.add_theme_font_size_override("font_size", 14)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = key == selected_difficulty
		if button.button_pressed:
			var selected := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
			selected.bg_color = Color(0.08, 0.19, 0.20, 0.95)
			selected.border_color = CYAN
			button.add_theme_stylebox_override("normal", selected)
		difficulty_buttons[key] = button


func _choose_difficulty(key: String) -> void:
	if current_page != "title" or not DIFFICULTIES.has(key):
		return
	selected_difficulty = key
	difficulty_changed.emit(key)
	# Rebuild the chosen style and keep keyboard focus on the selected difficulty.
	show_page("title")
	call_deferred("_focus_button", difficulty_buttons[key])


func set_difficulty(key: String) -> void:
	selected_difficulty = key if DIFFICULTIES.has(key) else "survival"
	if current_page == "title" and is_instance_valid(menu):
		show_page("title")


func show_map(regions: Array[Dictionary], waters: Array[Rect2], markers: Array[Dictionary], player_position: Vector3, player_yaw: float, monsters: Array[Dictionary] = [], route_points: Array[Vector3] = [], player_view_height: float = 1.62) -> void:
	show_page("game")
	current_page = "map"
	interface.visible = false
	menu.visible = true
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.043, 0.97)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(backdrop)
	_label(menu, "设施地图", Vector2(38, 32), 36, INK)
	_label(menu, "浏览地图时游戏暂停。探索模式显示实际路线；水下纵深以设备提示为准。", Vector2(40, 85), 15, MUTED)
	var close_button := _button(menu, "返回水房  /  M · Esc", Vector2(-288, 39), func() -> void: map_close_requested.emit())
	close_button.anchor_left = 1.0
	close_button.size = Vector2(250, 49)
	facility_map = FacilityMap.new()
	facility_map.name = "FacilityMap"
	facility_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	facility_map.offset_left = 38
	facility_map.offset_right = -38
	facility_map.offset_top = 143
	facility_map.offset_bottom = -57
	facility_map.player_view_height = player_view_height
	if selected_difficulty == "exploration":
		facility_map.monster_markers = monsters
		facility_map.route_points = route_points
	facility_map.configure(regions, waters, markers, player_position, player_yaw, font)
	menu.add_child(facility_map)
	_label(menu, "设施平面图  /  水下结构的纵深以设备提示为准", Vector2(40, -36), 13, MUTED).anchor_top = 1.0
	call_deferred("_focus_button", close_button)


func update_goal(goal_title: String, goal_position: Vector3, player_position: Vector3, player_yaw: float, zone: String, difficulty_key: String, completed: int, total: int) -> void:
	_goal_zone = zone
	var key := difficulty_key if DIFFICULTIES.has(difficulty_key) else "survival"
	_goal_metadata = "%s · 设备 %d/%d" % [DIFFICULTIES[key][0], completed, total]
	_goal_title = goal_title
	var offset := goal_position - player_position
	var angle := wrapf(atan2(offset.x, -offset.z) + player_yaw, -PI, PI)
	var depth := maxf(0.0, -goal_position.y)
	_goal_direction = _direction_caption(angle)
	_goal_distance = offset.length()
	_goal_angle = angle
	_goal_depth_text = "目标水深 %.1f m" % depth if depth > 0.5 else "目标位于岸上"
	_apply_navigation_mode(key)
	_refresh_goal_hint()


func update_navigation(regions: Array[Dictionary], waters: Array[Rect2], markers: Array[Dictionary], player_position: Vector3, player_yaw: float, difficulty_key: String, route_points: Array[Vector3] = [], monsters: Array[Dictionary] = [], navigation_action: String = "", navigation_status: String = "route", player_view_height: float = 1.62) -> void:
	_apply_navigation_mode(difficulty_key)
	_navigation_action = navigation_action
	_navigation_status = navigation_status
	_route_distance = -1.0
	var angle := 0.0
	if not route_points.is_empty():
		_route_distance = 0.0
		var previous := player_position
		for point in route_points:
			_route_distance += previous.distance_to(point)
			previous = point
		var next_point: Vector3 = route_points.back()
		for point in route_points:
			if point.distance_to(player_position) > 1.2:
				next_point = point
				break
		var offset := next_point - player_position
		angle = wrapf(atan2(offset.x, -offset.z) + player_yaw, -PI, PI)
		_goal_direction = _direction_caption(angle)
	elif _navigation_status == "route":
		_navigation_status = "pending"
	navigation_hud.direction_angle = angle
	navigation_hud.arrow_visible = not _goal_title.is_empty() and not route_points.is_empty() and _navigation_status not in ["unreachable", "blocked", "arrived", "reached", "waiting", "breathe"] and navigation_action != "breathe"
	navigation_hud.action_text = _navigation_action_text()
	if navigation_mode == "map":
		var diagram := navigation_hud.diagram
		diagram.player_view_height = player_view_height
		diagram.route_points = route_points
		diagram.monster_markers = monsters
		diagram.configure(regions, waters, markers, player_position, player_yaw, font)
	navigation_hud.queue_redraw()
	_refresh_goal_hint()


func _direction_caption(angle: float) -> String:
	var directions: Array[String] = ["前方", "前方偏右", "右侧", "后方偏右", "后方", "后方偏左", "左侧", "前方偏左"]
	return directions[posmod(int(round(angle / (PI / 4.0))), directions.size())]


func _navigation_state_text() -> String:
	match _navigation_status:
		"unreachable", "blocked": return "路线暂不可达"
		"arrived", "reached": return "已到达目标附近"
		"waiting": return "等待设备"
		"pending": return "正在定位路线"
		"breathe": return "先上浮呼吸"
	return ""


func _apply_navigation_mode(difficulty_key: String) -> void:
	navigation_mode = "map" if difficulty_key == "exploration" else "hidden" if difficulty_key == "abyss" else "direction"
	navigation_hud.set_mode(navigation_mode)
	mission.visible = navigation_mode != "hidden"
	goal_hint.visible = navigation_mode != "hidden"


func _navigation_action_text() -> String:
	var state := _navigation_state_text()
	if not state.is_empty():
		return state
	var captions: Dictionary = {"breathe": "先上浮呼吸", "dive": "下潜", "surface": "上浮", "climb": "梯子上岸", "wait": "等待设备", "turn": "持续操作", "continue": "继续前进"}
	return captions.get(_navigation_action, "")


func _refresh_goal_hint() -> void:
	if _goal_title.is_empty():
		goal_hint.text = "M  浏览设施地图"
		return
	var state := _navigation_state_text()
	if not state.is_empty():
		goal_hint.text = "%s  /  %s\n%s     M  浏览设施地图" % [state, _goal_title, _goal_depth_text]
		return
	var measure := "路线 %.0f m" % _route_distance if _route_distance >= 0.0 else "直线 %.0f m" % _goal_distance
	var action := _navigation_action_text()
	var next_step := action + " · " if not action.is_empty() else ""
	goal_hint.text = "%s  /  %s  /  %s\n%s%s     M  浏览设施地图" % [_goal_direction, _goal_title, measure, next_step, _goal_depth_text]


func _unhandled_key_input(event: InputEvent) -> void:
	if current_page != "game" or navigation_mode != "map" or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode in [KEY_EQUAL, KEY_KP_ADD]:
		navigation_hud.diagram.set_zoom(navigation_hud.diagram.zoom * 1.25)
	elif key.physical_keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		navigation_hud.diagram.set_zoom(navigation_hud.diagram.zoom / 1.25)
	else:
		return
	navigation_hud.queue_redraw()
	get_viewport().set_input_as_handled()


func _focus_button(button: Variant) -> void:
	if is_instance_valid(button) and button is Control and button.is_inside_tree():
		button.grab_focus()


func _slider(parent: Control, caption: String, low: float, high: float, value: float, y: float, key: String, x: float = 0.0, width: float = 480.0) -> HSlider:
	_label(parent, caption, Vector2(x, y), 17, INK)
	var slider := HSlider.new()
	slider.name = key + "_slider"
	slider.tooltip_text = caption
	slider.position = Vector2(x, y + 32)
	slider.size = Vector2(width, 26)
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 100.0
	slider.value = value
	parent.add_child(slider)
	slider.focus_entered.connect(func() -> void: audio_requested.emit("ui_move"))
	slider.drag_ended.connect(func(_changed: bool) -> void: audio_requested.emit("ui_confirm"))
	slider.value_changed.connect(func(v: float) -> void:
		match key:
			"brightness": brightness = v
			"volume": volume = v
			"sfx_volume": sfx_volume = v
			"ambient_volume": ambient_volume = v
			"music_volume": music_volume = v
			"sensitivity": sensitivity = v
		setting_changed.emit(key, v))
	return slider


func update_status(player: PlayerController, objective: String, decoys: int, threat: float, delta: float, elapsed: float) -> void:
	mission.text = objective
	oxygen_bar.value = player.oxygen
	stamina_bar.value = player.stamina
	oxygen_text.text = "呼吸 / %03d" % int(player.oxygen)
	oxygen_text.modulate = AMBER if player.oxygen < 25.0 else Color.WHITE
	inventory.text = "Q  金属诱饵  %d" % decoys
	var depth: float = maxf(0.0, -player.camera.global_position.y)
	var zone := _goal_zone if not _goal_zone.is_empty() else "蓄水厅 04"
	var medium := "水下 %.1f m" % depth if player.submerged else "维护层"
	location_label.text = "%s  /  %s  /  %s" % [zone, medium, _goal_metadata] if not _goal_metadata.is_empty() else "%s  /  %s" % [zone, medium]
	var under: float = float(effect.get_shader_parameter("underwater"))
	effect.set_shader_parameter("underwater", move_toward(under, 1.0 if player.submerged else 0.0, delta * 2.2))
	effect.set_shader_parameter("stress", threat)
	effect.set_shader_parameter("injury", 1.0 - player.health / 100.0)
	tutorial.visible = elapsed < 95.0
	if notice_time > 0.0:
		notice_time -= delta
		notification.modulate.a = clampf(notice_time, 0.0, 1.0)
	else:
		notification.text = ""


func show_interaction(text: String, progress: float = -1.0) -> void:
	interaction.text = text
	interaction_bar.visible = progress >= 0.0
	interaction_bar.value = progress * 100.0
	reticle.modulate = AMBER if not text.is_empty() else CYAN


func notify(text: String, seconds: float = 6.0) -> void:
	notification.text = text
	notification.modulate.a = 1.0
	notice_time = seconds
