class_name NavigationHUD
extends Control
## Matches Web guidance modes: exploration map, survival arrow, abyss silence.

const INK := Color(0.80, 0.88, 0.84)
const MUTED := Color(0.44, 0.60, 0.60)
const AMBER := Color(0.91, 0.62, 0.29)

var navigation_mode: String = "direction"
var diagram: FacilityMap
var map_font: Font
var direction_angle: float = 0.0
var arrow_visible: bool = false
var action_text: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	diagram = FacilityMap.new()
	diagram.mini_mode = true
	diagram.position = Vector2(12, 37)
	diagram.size = Vector2(280, 171)
	diagram.map_font = map_font
	add_child(diagram)
	diagram.visible = navigation_mode == "map"


func set_mode(mode: String) -> void:
	navigation_mode = mode if mode in ["map", "direction", "hidden"] else "direction"
	visible = navigation_mode != "hidden"
	if is_instance_valid(diagram):
		diagram.visible = navigation_mode == "map"
	queue_redraw()


func _draw() -> void:
	if map_font == null or navigation_mode == "hidden":
		return
	if navigation_mode == "map":
		draw_rect(Rect2(0, 0, 304, 242), Color(0.015, 0.035, 0.043, 0.90), true)
		draw_rect(Rect2(0, 0, 304, 242), Color(0.26, 0.43, 0.44, 0.7), false, 1.0)
		draw_string(map_font, Vector2(12, 25), "逃生路线", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
		draw_string(map_font, Vector2(228, 25), "北朝上", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
		draw_string(map_font, Vector2(12, 230), "视宽 %.0f m  /  - · + 缩放" % (diagram.view_width / diagram.zoom), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
		draw_colored_polygon(PackedVector2Array([Vector2(240, 220), Vector2(244, 224), Vector2(240, 228), Vector2(236, 224)]), Color(1.0, 0.48, 0.45))
		draw_string(map_font, Vector2(252, 230), "生物", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.55, 0.50))
	else:
		var center := Vector2(270, 28)
		if arrow_visible:
			var forward := Vector2(sin(direction_angle), -cos(direction_angle))
			var side := Vector2(-forward.y, forward.x)
			draw_colored_polygon(PackedVector2Array([center + forward * 19, center - forward * 13 + side * 9, center - forward * 7, center - forward * 13 - side * 9]), AMBER)
		if not action_text.is_empty():
			draw_string(map_font, Vector2(178, 77), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
