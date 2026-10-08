class_name FacilityMap
extends Control
## A paused facility plan: world x/z coordinates, no creature information.

const INK := Color(0.80, 0.88, 0.84)
const MUTED := Color(0.52, 0.67, 0.67)
const CYAN := Color(0.46, 0.78, 0.70)
const AMBER := Color(0.91, 0.62, 0.29)
var regions: Array[Dictionary] = []
var water_regions: Array[Rect2] = []
var markers: Array[Dictionary] = []
var player_position: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var player_view_height: float = 1.62
var map_bounds: Rect2 = Rect2(-28, -58, 56, 112)
var map_rect: Rect2
var map_scale: float = 1.0
var map_origin: Vector2
var map_font: Font
var mini_mode: bool = false
var zoom: float = 1.0
var view_width: float = 80.0
var route_points: Array[Vector3] = []
var monster_markers: Array[Dictionary] = []
var _legend_scroll: ScrollContainer
var _legend_rows: VBoxContainer


func configure(room_regions: Array[Dictionary], waters: Array[Rect2], device_markers: Array[Dictionary], player_pos: Vector3, yaw: float, face: Font) -> void:
	regions = room_regions.duplicate(true)
	water_regions = waters.duplicate()
	markers = device_markers.duplicate(true)
	player_position = player_pos
	player_yaw = yaw
	map_font = face
	if not regions.is_empty():
		map_bounds = regions[0].get("bounds", map_bounds)
		for region in regions:
			var bounds: Rect2 = region.get("bounds", Rect2())
			map_bounds = map_bounds.merge(bounds)
	map_bounds = map_bounds.grow(7.0)
	_update_transform()
	if is_inside_tree() and not mini_mode:
		_refresh_legend()
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if not mini_mode:
		_create_legend()
	resized.connect(func() -> void: _update_transform(); queue_redraw())
	_update_transform()


func _update_transform() -> void:
	# Device names stay outside the room plan even when the window changes size.
	if mini_mode:
		map_rect = Rect2(Vector2.ZERO, size)
		map_scale = size.x / (view_width / zoom)
		map_origin = size * 0.5 - Vector2(player_position.x, player_position.z) * map_scale
		return
	var legend_width := 318.0 if size.x >= 1040.0 else 275.0
	map_rect = Rect2(18, 36, maxf(120.0, size.x - legend_width - 70.0), maxf(120.0, size.y - 60.0))
	map_scale = minf(map_rect.size.x / maxf(map_bounds.size.x, 1.0), map_rect.size.y / maxf(map_bounds.size.y, 1.0))
	map_origin = map_rect.position + (map_rect.size - map_bounds.size * map_scale) * 0.5 - map_bounds.position * map_scale
	if is_instance_valid(_legend_scroll):
		_legend_scroll.position = Vector2(map_rect.end.x + 35, 80)
		_legend_scroll.size = Vector2(size.x - _legend_scroll.position.x, maxf(80, size.y - 188))


func set_zoom(value: float) -> void:
	zoom = clampf(value, 0.5, 2.0)
	_update_transform()
	queue_redraw()


func _create_legend() -> void:
	_legend_scroll = ScrollContainer.new()
	_legend_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_legend_scroll.follow_focus = true
	_legend_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_legend_scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_ALL
	for style_name in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = CYAN if style_name != "grabber" else Color(0.28, 0.46, 0.47)
		style.content_margin_left = 3
		style.content_margin_right = 3
		_legend_scroll.get_v_scroll_bar().add_theme_stylebox_override(style_name, style)
	add_child(_legend_scroll)
	_legend_rows = VBoxContainer.new()
	_legend_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legend_rows.add_theme_constant_override("separation", 8)
	_legend_scroll.add_child(_legend_rows)
	_refresh_legend()


func _refresh_legend() -> void:
	if not is_instance_valid(_legend_rows):
		return
	for child in _legend_rows.get_children():
		_legend_rows.remove_child(child)
		child.queue_free()
	for index in range(markers.size()):
		var marker := markers[index]
		var row := VBoxContainer.new()
		row.custom_minimum_size.y = 45
		_legend_rows.add_child(row)
		var title := Label.new()
		title.text = "%d  %s" % [index + 1, marker.get("title", "设备")]
		title.add_theme_font_override("font", map_font)
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", marker_color(marker))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(title)
		var state := Label.new()
		state.text = "已完成" if marker.get("completed", false) else "当前目标" if marker.get("current", false) else "可操作" if marker.get("available", false) else "未解锁"
		state.add_theme_font_override("font", map_font)
		state.add_theme_font_size_override("font_size", 12)
		state.add_theme_color_override("font_color", MUTED)
		row.add_child(state)


func map_point(position_3d: Vector3) -> Vector2:
	return map_origin + Vector2(position_3d.x, position_3d.z) * map_scale


func _project_rect(bounds: Rect2) -> Rect2:
	return Rect2(map_origin + bounds.position * map_scale, bounds.size * map_scale)


func marker_color(marker: Dictionary) -> Color:
	if marker.get("completed", false):
		return CYAN
	if marker.get("current", false):
		return AMBER
	return INK if marker.get("available", false) else MUTED


func _text(point: Vector2, text: String, font_size: int, color: Color) -> void:
	if map_font != null:
		draw_string(map_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw() -> void:
	if map_font == null:
		return
	var legend_x := map_rect.end.x + 35.0
	if not mini_mode:
		draw_line(Vector2(legend_x - 18, 12), Vector2(legend_x - 18, size.y - 10), Color(0.17, 0.30, 0.31), 1.0)
	for region in regions:
		var bounds: Rect2 = region.get("bounds", Rect2())
		var projected := _project_rect(bounds).intersection(map_rect) if mini_mode else _project_rect(bounds)
		if not projected.has_area():
			continue
		draw_rect(projected, Color(0.07, 0.14, 0.15), true)
		draw_rect(projected, Color(0.34, 0.51, 0.52), false, 1.4)
	for bounds in water_regions:
		var projected := _project_rect(bounds).intersection(map_rect) if mini_mode else _project_rect(bounds)
		if not projected.has_area():
			continue
		draw_rect(projected, Color(0.08, 0.24, 0.28), true)
		draw_rect(projected, Color(0.25, 0.46, 0.48), false, 1.0)
	for region in regions:
		var bounds: Rect2 = region.get("bounds", Rect2())
		var projected := _project_rect(bounds)
		var name_text: String = region.get("name", "")
		# Thin connecting passages remain geometry; their labels belong to the room.
		if not mini_mode and projected.size.x > 78 and projected.size.y > 42:
			_draw_region_name(projected, name_text)
	_draw_route()
	for index in range(markers.size()):
		var marker := markers[index]
		var point := map_point(marker.get("position", Vector3.ZERO))
		if not map_rect.has_point(point):
			continue
		var color := marker_color(marker)
		if marker.get("current", false):
			draw_circle(point, 14, Color(0.91, 0.62, 0.29, 0.13))
		draw_circle(point, 10, Color(0.02, 0.07, 0.08))
		draw_arc(point, 10, 0, TAU, 28, color, 1.5, true)
		_text(point + Vector2(-4, 5), str(index + 1), 12, color)
	_draw_monsters()
	_draw_player()
	if mini_mode:
		return
	# North and distance reference stay in the map's margin.
	var north := Vector2(map_rect.position.x + 5, 6)
	_text(north + Vector2(18, 15), "北", 13, MUTED)
	draw_line(north + Vector2(7, 24), north + Vector2(7, 4), MUTED, 1.2)
	draw_line(north + Vector2(7, 4), north + Vector2(2, 10), MUTED, 1.2)
	draw_line(north + Vector2(7, 4), north + Vector2(12, 10), MUTED, 1.2)
	var scale_start := Vector2(map_rect.position.x + 5, size.y - 7)
	draw_line(scale_start, scale_start + Vector2(10 * map_scale, 0), MUTED, 1.5)
	draw_line(scale_start - Vector2(0, 4), scale_start + Vector2(0, 4), MUTED, 1.0)
	draw_line(scale_start + Vector2(10 * map_scale, -4), scale_start + Vector2(10 * map_scale, 4), MUTED, 1.0)
	_text(scale_start + Vector2(10 * map_scale + 10, 4), "10 m", 12, MUTED)
	_draw_legend(legend_x)


func _draw_region_name(bounds: Rect2, caption: String) -> void:
	var dimensions := map_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	dimensions.y = 18
	var top_left := bounds.position + Vector2(7, 20)
	var top_right := Vector2(bounds.end.x - dimensions.x - 7, bounds.position.y + 20)
	var bottom_left := Vector2(bounds.position.x + 7, bounds.end.y - 10)
	var bottom_right := bounds.end - Vector2(dimensions.x + 7, 10)
	for point: Vector2 in [top_left, top_right, bottom_left, bottom_right]:
		var text_bounds := Rect2(point - Vector2(0, 14), dimensions)
		var occupied := text_bounds.intersects(Rect2(map_point(player_position) - Vector2(19, 19), Vector2(38, 38)))
		for marker in markers:
			var marker_point := map_point(marker.get("position", Vector3.ZERO))
			occupied = occupied or text_bounds.intersects(Rect2(marker_point - Vector2(15, 15), Vector2(30, 30)))
		if not occupied and point.x >= bounds.position.x + 6:
			_text(point, caption, 13, INK)
			return


func _draw_player() -> void:
	var point := map_point(player_position)
	var forward := Vector2(-sin(player_yaw), -cos(player_yaw))
	var side := Vector2(-forward.y, forward.x)
	draw_circle(point, 18, Color(0.80, 0.88, 0.84, 0.10))
	draw_colored_polygon(PackedVector2Array([point + forward * 13, point - forward * 8 + side * 6, point - forward * 8 - side * 6]), INK)
	draw_circle(point, 2, Color(0.015, 0.035, 0.043))


func _draw_legend(x: float) -> void:
	_text(Vector2(x, 24), "设备与路线", 19, INK)
	_text(Vector2(x, 55), "数字对应设施位置", 13, MUTED)
	var footer_y := size.y - 85.0
	_text(Vector2(x, footer_y), "三角指向你的朝向", 13, INK)
	_text(Vector2(x, footer_y + 26), "蓝色区域为水域", 13, CYAN)
	_text(Vector2(x, footer_y + 52), "红色菱形为生物位置" if not monster_markers.is_empty() else "此模式不显示生物位置", 13, Color(1.0, 0.55, 0.50) if not monster_markers.is_empty() else MUTED)
	if not monster_markers.is_empty():
		_text(Vector2(x, footer_y + 74), "↑ / ↓ 生物高于 / 低于视线 3 m", 12, MUTED)


func _draw_route() -> void:
	var previous := map_point(player_position)
	for waypoint in route_points:
		var next := map_point(waypoint)
		var clipped := _clip_line(previous, next)
		if clipped.size() == 2:
			draw_line(clipped[0], clipped[1], AMBER, 2.0, true)
		previous = next


func _clip_line(start: Vector2, end: Vector2) -> PackedVector2Array:
	var offset := end - start
	var p := PackedFloat32Array([-offset.x, offset.x, -offset.y, offset.y])
	var q := PackedFloat32Array([start.x - map_rect.position.x, map_rect.end.x - start.x, start.y - map_rect.position.y, map_rect.end.y - start.y])
	var low := 0.0
	var high := 1.0
	for index in range(4):
		if absf(p[index]) < 0.00001:
			if q[index] < 0.0:
				return PackedVector2Array()
			continue
		var ratio := q[index] / p[index]
		if p[index] < 0:
			low = maxf(low, ratio)
		else:
			high = minf(high, ratio)
		if low > high:
			return PackedVector2Array()
	return PackedVector2Array([start + offset * low, start + offset * high])


func _draw_monsters() -> void:
	var color := Color(1.0, 0.48, 0.45)
	for monster in monster_markers:
		var position_3d: Vector3 = monster.get("position", Vector3.ZERO)
		var point := map_point(position_3d)
		if not map_rect.has_point(point):
			continue
		var radius := 4.0 if monster.get("small", false) else 6.0
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -radius), point + Vector2(radius, 0), point + Vector2(0, radius), point + Vector2(-radius, 0)]), color)
		var vertical := monster_vertical_direction(position_3d)
		if vertical != 0.0:
			draw_polyline(PackedVector2Array([point + Vector2(-3, vertical * (radius + 4)), point + Vector2(0, vertical * (radius + 7)), point + Vector2(3, vertical * (radius + 4))]), color, 1.2, true)


func monster_vertical_direction(position_3d: Vector3) -> float:
	var difference := position_3d.y - (player_position.y + player_view_height)
	return -1.0 if difference > 3.0 else 1.0 if difference < -3.0 else 0.0
