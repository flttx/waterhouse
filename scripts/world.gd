class_name WaterhouseWorld
extends Node3D
## Authored metric environment. The basin remains open for the animal's water navigation.

const WATER_Y: float = 0.0
const DECK_Y: float = 0.65
const FLOOR_Y: float = -13.0
const POOL_HALF_WIDTH: float = 19.0
const POOL_HALF_LENGTH: float = 42.0

@export var batch_static_boxes: bool = true

var ladders: Array[Vector3] = [
	Vector3(-20.5, 0.7, 22.0), Vector3(20.5, 0.7, 12.0),
	Vector3(-20.5, 0.7, -20.0), Vector3(20.5, 0.7, -22.0),
	Vector3(35.5, 0.7, -8.0), Vector3(67.5, 0.7, -8.0),
	Vector3(35.5, 0.7, 8.0), Vector3(67.5, 0.7, 8.0),
	Vector3(-101.5, 0.7, 1), Vector3(-62.5, 0.7, 31),
	Vector3(77.5, 0.7, -49), Vector3(138.5, 0.7, -60),
	Vector3(99.5, 0.7, 36), Vector3(174.5, 0.7, 54),
	Vector3(-107.5, 0.7, -25), Vector3(179.5, 0.7, -8),
]
# Rect2 maps world X/Z into the same coordinates used by the facility plan.
var map_regions: Array[Dictionary] = [
	{"id": "main_hall", "name": "第七蓄水厅", "bounds": Rect2(-24, -47, 48, 94)},
	{"id": "pump_room", "name": "排水泵房", "bounds": Rect2(-33, -30, 9, 10)},
	{"id": "power_room", "name": "配电间", "bounds": Rect2(24, 20, 9, 10)},
	{"id": "archives", "name": "西侧封存档案库", "bounds": Rect2(-57, -36, 24, 22)},
	{"id": "filter_corridor", "name": "过滤维护走廊", "bounds": Rect2(33, 21, 36, 8)},
	{"id": "filter_hall", "name": "第八过滤池", "bounds": Rect2(34, -17, 35, 38)},
	{"id": "egress", "name": "地面撤离通道", "bounds": Rect2(-2.4, -57, 4.8, 10)},
	{"id": "west_connector", "name": "西侧输水长廊", "bounds": Rect2(-106, -28, 49, 6)},
	{"id": "east_connector", "name": "东侧观察长廊", "bounds": Rect2(69, -11, 109, 6)},
	{"id": "north_canal", "name": "北环形输水渠", "bounds": Rect2(-118, -89, 308, 12)},
	{"id": "south_canal", "name": "南环形输水渠", "bounds": Rect2(-118, 67, 308, 12)},
	{"id": "west_canal", "name": "西环形输水渠", "bounds": Rect2(-118, -77, 12, 144)},
	{"id": "east_canal", "name": "东环形输水渠", "bounds": Rect2(178, -77, 12, 144)},
	{"id": "tier_link", "name": "阶梯浴场连廊", "bounds": Rect2(-106, 12, 3, 6)},
	{"id": "tier_baths", "name": "西侧阶梯浴场", "bounds": Rect2(-103, -13, 42, 58)},
	{"id": "overflow_link", "name": "溢流池联络走道", "bounds": Rect2(135.5, -27, 6, 16)},
	{"id": "overflow_hall", "name": "北侧溢流池与潜水塔", "bounds": Rect2(76, -77, 64, 50)},
	{"id": "reservoir_link", "name": "地下水库联络走道", "bounds": Rect2(171.5, -5, 6, 24)},
	{"id": "reservoir", "name": "黑水地下水库", "bounds": Rect2(98, 19, 78, 48)},
]
var water_regions: Array[Rect2] = [
	Rect2(-19, -42, 38, 84), Rect2(19, -4, 4.55, 10), Rect2(37, -14, 29, 32),
	Rect2(-115, -86, 302, 6), Rect2(-115, 70, 302, 6),
	Rect2(-115, -80, 6, 150), Rect2(181, -80, 6, 150),
	Rect2(-100, -10, 36, 52), Rect2(79, -74, 58, 44), Rect2(101, 22, 72, 42),
]
var water_depths: Array[float] = [-13.0, -13.0, -10.0, -6.0, -6.0, -6.0, -6.0, -24.0, -12.0, -22.0]
var navigation_points: Array[Vector3] = []
var navigation_edges: Array[Vector2i] = []
var navigation_ladder_edges: Array[Vector2i] = []
var nav_targets: Dictionary[String, Vector3] = {
	"breaker": Vector3(27, 0.65, 26.8), "pump": Vector3(-28, 0.65, -23.3),
	"valve_south": Vector3(-10, -7.62, 17.8), "valve_north": Vector3(10, -9.62, -18.8),
	"archive": Vector3(-48, 0.65, -23.2), "annex_valve": Vector3(51, -6.62, 5.4),
	"tier_valve": Vector3(-82, -6.62, 15.4), "overflow_valve": Vector3(108, -7.62, -46.6),
	"reservoir_valve": Vector3(137, -8.62, 45.4), "exit": Vector3(-1.4, 0.65, -44),
}
var navigation_targets: Dictionary[String, Vector3]:
	get:
		return nav_targets
var canal_patrol_points: Array[Vector3] = [
	Vector3(-112, -3, -83), Vector3(184, -3, -83), Vector3(184, -3, 73), Vector3(-112, -3, 73),
]
var water_material: ShaderMaterial
var annex_water_material: ShaderMaterial
var environment: Environment

var _tile: ShaderMaterial
var _pool_tile: ShaderMaterial
var _concrete: ShaderMaterial
var _dark_concrete: ShaderMaterial
var _rust: StandardMaterial3D
var _metal: StandardMaterial3D
var _yellow: StandardMaterial3D
var _black: StandardMaterial3D
var _green_emission: StandardMaterial3D
var _warm_emission: StandardMaterial3D
var _cyan_emission: StandardMaterial3D
var _pulse_lights: Array[OmniLight3D] = []
var _floaters: Array[Node3D] = []
var _elapsed: float = 0.0
var _font: SystemFont
var _basin_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_make_materials()
	_make_environment()
	_make_shell()
	_make_structure()
	_make_water()
	_make_deck_details()
	_make_rooms()
	_make_archive_wing()
	_make_filter_wing()
	_make_canal_network()
	_make_outer_basins()
	_make_submerged_structures()
	_make_lighting()
	_make_signage()
	_make_surface_debris()
	_make_navigation_metadata()
	if batch_static_boxes:
		_batch_static_boxes()


func is_water(pos: Vector3) -> bool:
	if pos.y >= WATER_Y + 0.12:
		return false
	var point := Vector2(pos.x, pos.z)
	for index in range(water_regions.size()):
		var floor_level: float = water_depths[index]
		if water_regions[index].has_point(point) and pos.y > floor_level - 1.0:
			return true
	return false


func region_at(pos: Vector3) -> String:
	for region in map_regions:
		var bounds: Rect2 = region["bounds"]
		if bounds.has_point(Vector2(pos.x, pos.z)):
			return String(region["name"])
	return "设施边界"


func region_id_at(pos: Vector3) -> String:
	for region: Dictionary in map_regions:
		var bounds: Rect2 = region["bounds"]
		if bounds.has_point(Vector2(pos.x, pos.z)):
			return str(region["id"])
	return "main_hall"


func is_underwater(pos: Vector3) -> bool:
	return is_water(pos) and pos.y < WATER_Y - 0.18


func _process(delta: float) -> void:
	_elapsed += delta
	for material in _basin_materials:
		material.set_shader_parameter("ripple_origin", water_material.get_shader_parameter("ripple_origin"))
		material.set_shader_parameter("ripple_strength", water_material.get_shader_parameter("ripple_strength"))
	for i in range(_pulse_lights.size()):
		var lamp := _pulse_lights[i]
		var hum := sin(_elapsed * 7.3 + float(i) * 4.2) * sin(_elapsed * 3.7 + float(i))
		var failing := 0.68 if i == 2 and fmod(_elapsed, 19.0) > 17.2 else 1.0
		lamp.light_energy = float(lamp.get_meta("base_energy")) * (0.97 + hum * 0.035) * failing
	for i in range(_floaters.size()):
		var floater := _floaters[i]
		floater.position.y = 0.045 + sin(_elapsed * 0.72 + float(i) * 2.1) * 0.025
		floater.rotation.z = sin(_elapsed * 0.43 + float(i)) * 0.015


func _make_materials() -> void:
	var shader := load("res://shaders/surface.gdshader") as Shader
	_tile = _surface(shader, Color(0.43, 0.49, 0.46), true, 1.8, 0.34)
	_pool_tile = _surface(shader, Color(0.23, 0.40, 0.39), true, 1.7, 0.39)
	_pool_tile.set_shader_parameter("waterline", true)
	_concrete = _surface(shader, Color(0.26, 0.31, 0.30), false, 1.0, 0.72)
	_dark_concrete = _surface(shader, Color(0.16, 0.21, 0.21), false, 1.0, 0.83)
	_rust = _plain(Color(0.24, 0.15, 0.085), 0.80, 0.40)
	_metal = _plain(Color(0.22, 0.28, 0.27), 0.34, 0.72)
	_yellow = _plain(Color(0.53, 0.39, 0.11), 0.61)
	_black = _plain(Color(0.015, 0.025, 0.027), 0.88)
	_green_emission = _emissive(Color(0.19, 0.71, 0.47), 1.9)
	_warm_emission = _emissive(Color(0.95, 0.61, 0.29), 2.4)
	_cyan_emission = _emissive(Color(0.40, 0.76, 0.78), 2.0)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])


func _surface(shader: Shader, color: Color, ceramic: bool, scale_value: float, roughness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("ceramic", ceramic)
	material.set_shader_parameter("tile_scale", scale_value)
	material.set_shader_parameter("roughness_value", roughness)
	return material


func _plain(color: Color, roughness: float, metalness: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metalness
	return material


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := _plain(color, 0.42)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _make_environment() -> void:
	get_viewport().use_occlusion_culling = true
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.006, 0.013, 0.018)
	sky_material.sky_horizon_color = Color(0.12, 0.19, 0.19)
	sky_material.ground_bottom_color = Color(0.015, 0.037, 0.035)
	sky_material.ground_horizon_color = Color(0.12, 0.19, 0.19)
	sky_material.sky_energy_multiplier = 0.65
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.28, 0.30)
	environment.ambient_light_energy = 0.60
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.035, 0.075, 0.085)
	environment.fog_light_energy = 0.8
	environment.fog_density = 0.005
	environment.fog_sky_affect = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WaterhouseAtmosphere"
	world_environment.environment = environment
	add_child(world_environment)
	for z in [-23.0, 23.0]:
		var probe := ReflectionProbe.new()
		probe.name = "WetArchitectureReflection"
		probe.position = Vector3(0.0, 6.0, z)
		probe.size = Vector3(46.0, 24.0, 48.0)
		probe.box_projection = true
		probe.interior = true
		probe.intensity = 0.60
		probe.max_distance = 80.0
		probe.enable_shadows = false
		add_child(probe)


func _make_shell() -> void:
	_box("BasinFloor", Vector3(0, -13.4, 0), Vector3(48, 0.8, 94), _pool_tile, true)
	_box("WestDeck", Vector3(-21.5, -0.1, 0), Vector3(5, 1.5, 94), _tile, true)
	_box("EastDeckSouth", Vector3(21.5, -0.1, 26.5), Vector3(5, 1.5, 41), _tile, true)
	_box("EastDeckNorth", Vector3(21.5, -0.1, -25.5), Vector3(5, 1.5, 43), _tile, true)
	_box("NorthDeck", Vector3(0, -0.1, -44.5), Vector3(38, 1.5, 5), _tile, true)
	_box("SouthDeck", Vector3(0, -0.1, 44.5), Vector3(38, 1.5, 5), _tile, true)
	_box("WestPoolLiner", Vector3(-19.15, -6.2, 0), Vector3(0.3, 13.7, 84), _pool_tile, true)
	_box("EastPoolLinerSouth", Vector3(19.15, -6.2, 24), Vector3(0.3, 13.7, 36), _pool_tile, true)
	_box("EastPoolLinerNorth", Vector3(19.15, -6.2, -23), Vector3(0.3, 13.7, 38), _pool_tile, true)
	_box("NorthPoolLiner", Vector3(0, -6.2, -42.15), Vector3(38, 13.7, 0.3), _pool_tile, true)
	_box("SouthPoolLiner", Vector3(0, -6.2, 42.15), Vector3(38, 13.7, 0.3), _pool_tile, true)
	# Side doors are openings in the physical shell, rather than a visual door on a solid wall.
	_box("WestWallSouth", Vector3(-24.2, 6.4, 13.5), Vector3(0.8, 13.5, 67), _concrete, true)
	_box("WestWallNorth", Vector3(-24.2, 6.4, -38.5), Vector3(0.8, 13.5, 17), _concrete, true)
	_box("WestDoorLintel", Vector3(-24.2, 8.7, -25), Vector3(0.8, 8.9, 10), _concrete, true)
	_box("EastWallSouth", Vector3(24.2, 6.4, 38.5), Vector3(0.8, 13.5, 17), _concrete, true)
	_box("EastWallNorth", Vector3(24.2, 6.4, -13.5), Vector3(0.8, 13.5, 67), _concrete, true)
	_box("EastDoorLintel", Vector3(24.2, 8.7, 25), Vector3(0.8, 8.9, 10), _concrete, true)
	# A physical opening leads beyond the raised gate; escape requires walking out.
	_box("NorthEndWallWest", Vector3(-13.45, 12.9, -47.2), Vector3(22.1, 26.5, 0.8), _concrete, true)
	_box("NorthEndWallEast", Vector3(13.45, 12.9, -47.2), Vector3(22.1, 26.5, 0.8), _concrete, true)
	_box("NorthEscapeHeader", Vector3(0, 15.675, -47.2), Vector3(4.8, 20.95, 0.8), _concrete, true)
	_make_escape_corridor()
	_box("SouthEndWall", Vector3(0, 12.9, 47.2), Vector3(49, 26.5, 0.8), _concrete, true)
	# The collapsed deck floods out to the exterior wall. It is still contained physically.
	_box("BreakRetainingWall", Vector3(23.85, -6.2, 1), Vector3(0.7, 13.7, 10), _pool_tile, true)
	_arch_ceiling()
	for side in [-1.0, 1.0]:
		for z in range(-40, 42, 4):
			if side > 0 and z > -4 and z < 6:
				continue
			_box("DrainGrate", Vector3(side * 23.25, 0.66, float(z)), Vector3(0.38, 0.02, 1.25), _black)
			for k in range(6):
				_box("DrainRib", Vector3(side * 23.25, 0.68, float(z) - 0.5 + float(k) * 0.2), Vector3(0.38, 0.025, 0.025), _metal)


func _make_escape_corridor() -> void:
	var pale_concrete := _surface(load("res://shaders/surface.gdshader") as Shader, Color(0.47, 0.52, 0.48), false, 1.0, 0.83)
	_box("EscapeCorridorFloor", Vector3(0, -0.1, -52), Vector3(4.8, 1.5, 10), pale_concrete, true)
	for side in [-1.0, 1.0]:
		_box("EscapeCorridorSide", Vector3(side * 2.65, 2.925, -52), Vector3(0.5, 4.55, 10), pale_concrete, true)
	_box("EscapeCorridorRoof", Vector3(0, 5.45, -52), Vector3(5.8, 0.5, 10), pale_concrete, true)
	_box("EscapeCorridorEnd", Vector3(0, 2.675, -57.25), Vector3(5.8, 5.05, 0.5), pale_concrete, true)
	var pale_light := _emissive(Color(0.72, 0.83, 0.77), 1.5)
	for z in [-50.0, -55.0]:
		_box("EscapeCorridorFixture", Vector3(0, 5.05, z), Vector3(0.32, 0.12, 1.3), pale_light)
		_lamp(Vector3(0, 4.6, z), Color(0.74, 0.86, 0.80), 2.4, 7.0)
	_box("EscapeAirLocator", Vector3(0, 4.45, -56.95), Vector3(1.6, 0.13, 0.08), _green_emission)
	_label("外 部 空 气\nEXIT  /  SURFACE ACCESS", Vector3(0, 3.7, -56.95), Vector3.ZERO, 0.004, Color(0.55, 0.82, 0.65))


func _arch_ceiling() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(48):
		var x0 := -24.0 + float(i)
		var x1 := x0 + 1.0
		var y0 := 11.0 + sqrt(maxf(0.0, 576.0 - x0 * x0)) * 0.625
		var y1 := 11.0 + sqrt(maxf(0.0, 576.0 - x1 * x1)) * 0.625
		var a := Vector3(x0, y0, 47.0)
		var b := Vector3(x1, y1, 47.0)
		var c := Vector3(x1, y1, -47.0)
		var d := Vector3(x0, y0, -47.0)
		for point in [a, c, b, a, d, c]:
			surface.add_vertex(point)
	surface.generate_normals()
	var ceiling := MeshInstance3D.new()
	ceiling.name = "BarrelVault"
	ceiling.mesh = surface.commit()
	ceiling.material_override = _dark_concrete
	add_child(ceiling)


func _make_structure() -> void:
	for z in [-40.0, -16.0, 8.0, 32.0]:
		for side in [-1.0, 1.0]:
			_box("VaultButtress", Vector3(side * 23.6, 6.2, z), Vector3(0.85, 11.2, 1.1), _dark_concrete, true)
			_box("ButtressFoot", Vector3(side * 23.3, 1.0, z), Vector3(1.45, 0.7, 1.65), _concrete, true)
		for i in range(32):
			var angle0 := PI * float(i) / 32.0
			var angle1 := PI * float(i + 1) / 32.0
			var a := Vector3(cos(angle0) * 23.8, 11.0 + sin(angle0) * 14.6, z)
			var b := Vector3(cos(angle1) * 23.8, 11.0 + sin(angle1) * 14.6, z)
			_beam("VaultRib", a, b, 0.62, 0.75, _concrete)
	for side in [-1.0, 1.0]:
		for height in [3.6, 4.25]:
			_pipe("ServiceMain", Vector3(side * 23.7, height, -46), Vector3(side * 23.7, height, 46), 0.15, _rust)
		for z in range(-42, 44, 8):
			_box("PipeClamp", Vector3(side * 23.55, 3.92, float(z)), Vector3(0.25, 1.15, 0.18), _metal)
	# Long overhead service bridge gives the vault a readable human scale.
	_box("OverheadServiceTray", Vector3(0, 16.5, -15), Vector3(42, 0.18, 1.2), _metal)
	for x in [-19.0, -8.0, 8.0, 19.0]:
		_pipe("BridgeSuspension", Vector3(x, 16.5, -15), Vector3(x, 24.5, -15), 0.035, _metal)
	for i in range(10):
		_box("BridgeGuardPost", Vector3(-19.0 + float(i) * 4.2, 17.0, -14.4), Vector3(0.055, 1.0, 0.055), _metal)
	_box("BridgeGuardRail", Vector3(0, 17.5, -14.4), Vector3(42, 0.05, 0.05), _metal)
	for z in [-46.72, 46.72]:
		_box("VentFrame", Vector3(0, 18.0, z), Vector3(10, 3.5, 0.15), _metal)
		_box("VentDarkness", Vector3(0, 18.0, z + signf(z) * 0.03), Vector3(9.5, 3, 0.16), _black)
		for i in range(12):
			_box("VentLouvre", Vector3(0, 16.65 + float(i) * 0.25, z - signf(z) * 0.08), Vector3(9.5, 0.08, 0.28), _rust)


func _make_water() -> void:
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://shaders/water.gdshader") as Shader
	_water_plane("MainWater", Vector3.ZERO, Vector2(38, 84), 75, 167)
	_water_plane("BrokenWalkwayWater", Vector3(21.2, 0, 1), Vector2(4.4, 10), 9, 20)
	# Floor lane lines disappear into the turbidity instead of relying on depth-screen effects.
	var dark_lane := _plain(Color(0.045, 0.095, 0.12), 0.9)
	for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		_box("SubmergedLane", Vector3(x, -12.985, 0), Vector3(0.19, 0.015, 78), dark_lane)
		_box("LaneEndMarkerNorth", Vector3(x, -12.98, -38), Vector3(2.0, 0.02, 0.19), dark_lane)
		_box("LaneEndMarkerSouth", Vector3(x, -12.98, 38), Vector3(2.0, 0.02, 0.19), dark_lane)


func _water_plane(node_name: String, pos: Vector3, size_value: Vector2, x_segments: int, z_segments: int, material: ShaderMaterial = null) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size_value
	mesh.subdivide_width = x_segments
	mesh.subdivide_depth = z_segments
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = water_material if material == null else material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 0.5
	add_child(instance)


func _make_deck_details() -> void:
	for side in [-1.0, 1.0]:
		var sections: Array[Vector2] = [Vector2(-38, -28), Vector2(-15, -7), Vector2(28, 40)]
		if side < 0:
			sections.append(Vector2(3, 16))
		else:
			sections.append(Vector2(17, 24))
		for section in sections:
			_rail(Vector3(side * 19.35, 0.65, section.x), Vector3(side * 19.35, 0.65, section.y))
		for z in range(-40, 41, 2):
			if side > 0 and z >= -4 and z <= 6:
				continue
			_box("PoolEdgeSafetyMark", Vector3(side * 19.65, 0.668, float(z)), Vector3(0.11, 0.018, 1.1), _yellow)
	for point in ladders:
		if absf(point.x) < 30.0:
			_ladder(point)
	# Recessed bench, lifebuoy and old service fixtures make the space inhabited in the past.
	for side in [-1.0, 1.0]:
		for z in [-35.0, 34.0]:
			_box("BenchSeat", Vector3(side * 22.8, 1.12, z), Vector3(0.55, 0.13, 3.2), _metal)
			_box("BenchBack", Vector3(side * 23.12, 1.6, z), Vector3(0.12, 0.7, 3.2), _metal)
			for dz in [-1.2, 1.2]:
				_box("BenchFoot", Vector3(side * 22.8, 0.9, z + dz), Vector3(0.12, 0.4, 0.3), _rust)
	for z in [-5.0, 7.0]:
		for x in [19.7, 23.1]:
			_box("CollapseWarningPost", Vector3(x, 1.35, z), Vector3(0.10, 1.4, 0.10), _yellow, true)
			_box("WarningLamp", Vector3(x, 2.1, z), Vector3(0.12, 0.12, 0.12), _warm_emission)
		for i in range(7):
			var stripe := _box("BrokenDeckHazardStripe", Vector3(19.8 + float(i) * 0.48, 0.675, z), Vector3(0.18, 0.025, 0.7), _yellow)
			stripe.rotation.y = 0.55
	# Rubble stays below the swim path through the break.
	for i in range(7):
		var rubble := _box("CollapsedSlab", Vector3(20.0 + float(i % 3) * 1.1, -10.8 + float(i % 2) * 0.8, -2.5 + float(i) * 1.1), Vector3(1.7, 0.4, 2.2), _tile, true)
		rubble.rotation = Vector3(0.2 * float(i % 3), 0.43 * float(i), -0.3)
	for x in [-21.0, 21.0]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.22
		ring.outer_radius = 0.40
		var instance := MeshInstance3D.new()
		instance.name = "AbandonedLifeRing"
		instance.mesh = ring
		instance.material_override = _yellow
		instance.position = Vector3(x, 2.05, 46.68)
		instance.rotation.x = PI * 0.5
		add_child(instance)


func _rail(a: Vector3, b: Vector3) -> void:
	var length_value := a.distance_to(b)
	var count := int(ceil(length_value / 2.4))
	_beam("SafetyTopRail", a + Vector3.UP * 1.05, b + Vector3.UP * 1.05, 0.075, 0.075, _metal, true)
	_beam("SafetyMidRail", a + Vector3.UP * 0.48, b + Vector3.UP * 0.48, 0.04, 0.04, _rust)
	for i in range(count + 1):
		var p := a.lerp(b, float(i) / float(count))
		_box("RailUpright", p + Vector3.UP * 0.52, Vector3(0.08, 1.04, 0.08), _metal)
		_box("RailAnchor", p + Vector3.UP * 0.04, Vector3(0.2, 0.08, 0.18), _rust)


func _ladder(point: Vector3) -> void:
	var side := signf(point.x)
	var x := side * 18.78
	for dz in [-0.48, 0.48]:
		_pipe("LadderRail", Vector3(x, -2.8, point.z + dz), Vector3(x, 1.6, point.z + dz), 0.045, _metal)
		_pipe("LadderHandrail", Vector3(x, 1.6, point.z + dz), Vector3(side * 20.2, 1.6, point.z + dz), 0.045, _metal)
		_pipe("LadderDeckAnchor", Vector3(side * 20.2, 1.6, point.z + dz), Vector3(side * 20.2, 0.67, point.z + dz), 0.045, _metal)
	for i in range(12):
		_pipe("LadderRung", Vector3(x, -2.65 + float(i) * 0.28, point.z - 0.48), Vector3(x, -2.65 + float(i) * 0.28, point.z + 0.48), 0.035, _metal)
	_box("LadderRestPlatform", Vector3(side * 18.45, -2.88, point.z), Vector3(1.05, 0.18, 1.5), _metal, true)
	_box("LadderExitMark", Vector3(side * 20.5, 0.672, point.z), Vector3(0.55, 0.02, 1.0), _yellow)
	_box("LadderLocator", Vector3(side * 23.7, 2.0, point.z), Vector3(0.09, 0.18, 0.45), _green_emission)
	_lamp(Vector3(side * 22.0, 2.7, point.z), Color(0.25, 0.68, 0.56), 0.8, 6.0)
	_label("池 梯  /  LADDER", Vector3(side * 23.72, 2.7, point.z), Vector3(0, -side * PI * 0.5, 0), 0.003, Color(0.46, 0.70, 0.61))


func _make_rooms() -> void:
	_make_service_room(Vector3(28.5, 0.65, 25), "PowerRoom")
	_make_service_room(Vector3(-28.5, 0.65, -25), "PumpRoom")
	# Dry electrical room: lockers and suspended cables leave the breaker at (27, 1.6, 25) reachable.
	for z in [21.4, 28.6]:
		_box("ElectricalCabinet", Vector3(30.5, 1.95, z), Vector3(1.3, 2.6, 1.0), _metal, true)
		_box("CabinetVent", Vector3(29.82, 2.05, z), Vector3(0.025, 1.1, 0.55), _black)
		for k in range(4):
			_box("CabinetVentBar", Vector3(29.79, 1.62 + float(k) * 0.25, z), Vector3(0.025, 0.04, 0.55), _rust)
	for z in [23.1, 26.9]:
		_pipe("PowerCable", Vector3(24.0, 4.1, z), Vector3(32.5, 4.1, z), 0.07, _black)
	_box("SwitchboardBacking", Vector3(27, 1.7, 24.1), Vector3(1.3, 1.7, 0.22), _dark_concrete)
	# Pump housings sit beside the usable control point, with obvious pipe connections to the basin.
	for z in [-28.3, -21.7]:
		_box("PumpConcretePlinth", Vector3(-29.4, 0.97, z), Vector3(3.2, 0.64, 1.9), _concrete, true)
		_pipe("PumpHousing", Vector3(-30.5, 1.8, z), Vector3(-28.4, 1.8, z), 0.65, _metal, true)
		_pipe("PumpOutlet", Vector3(-28.2, 1.8, z), Vector3(-24.1, 1.8, z), 0.28, _rust)
		_pipe("PumpRiser", Vector3(-30.7, 1.8, z), Vector3(-30.7, 3.8, z), 0.28, _rust)
		_pipe("PumpReturn", Vector3(-30.7, 3.8, z), Vector3(-24.0, 3.8, z), 0.28, _rust)
	_box("PumpControlBacking", Vector3(-28, 1.65, -25.9), Vector3(1.4, 1.6, 0.18), _metal)
	_label("配 电 间  /  AUXILIARY POWER", Vector3(23.65, 3.2, 25), Vector3(0, -PI * 0.5, 0), 0.0035, Color(0.60, 0.70, 0.65))
	_label("排 水 泵 房  /  PUMP CONTROL", Vector3(-23.65, 3.2, -25), Vector3(0, PI * 0.5, 0), 0.0035, Color(0.60, 0.70, 0.65))
	_label("08 / 过滤维护 →", Vector3(32.85, 4.3, 25), Vector3(0, -PI * 0.5, 0), 0.0040, Color(0.66, 0.71, 0.66))
	_label("封存档案库 / 安全继电器", Vector3(-32.85, 4.3, -25), Vector3(0, PI * 0.5, 0), 0.0034, Color(0.66, 0.71, 0.66))


func _make_service_room(center: Vector3, room_name: String) -> void:
	var side := signf(center.x)
	_box(room_name + "Floor", Vector3(center.x, -0.1, center.z), Vector3(9.4, 1.5, 10), _tile, true)
	# The expansion doors remain real holes in both service-room back walls.
	for dz in [-4.2, 4.2]:
		_box(room_name + "BackPier", Vector3(side * 33.3, 2.8, center.z + dz), Vector3(0.8, 4.5, 2.4), _concrete, true)
	_box(room_name + "BackLintel", Vector3(side * 33.3, 4.7, center.z), Vector3(0.8, 0.7, 6), _concrete, true)
	_box(room_name + "South", Vector3(center.x, 2.8, center.z + 5.3), Vector3(9.4, 4.5, 0.6), _concrete, true)
	_box(room_name + "North", Vector3(center.x, 2.8, center.z - 5.3), Vector3(9.4, 4.5, 0.6), _concrete, true)
	_box(room_name + "Roof", Vector3(center.x, 5.3, center.z), Vector3(9.4, 0.5, 10.8), _dark_concrete, true)
	for dz in [-4.95, 4.95]:
		_box("DoorJamb", Vector3(side * 24.0, 2.1, center.z + dz), Vector3(0.28, 3.0, 0.25), _yellow)
	_box("RoomFluorescent", Vector3(center.x, 4.85, center.z), Vector3(0.25, 0.13, 2.1), _warm_emission)
	_lamp(Vector3(center.x, 4.5, center.z), Color(0.76, 0.62, 0.40), 2.2, 10.0)


func _make_archive_wing() -> void:
	# Perimeter storage leaves a generous central hunting ground and a readable escape route.
	_box("ArchiveFloor", Vector3(-45, -0.1, -25), Vector3(24, 1.5, 22), _tile, true)
	_wall_openings("ArchiveWestWall", Vector3(-57.3, 3.6, -25), 22.6, 6.5, false, [Vector2(-28, -22)])
	_box("ArchiveSouthWall", Vector3(-45, 3.6, -13.7), Vector3(24, 6.5, 0.6), _concrete, true)
	_box("ArchiveRoof", Vector3(-45, 7.05, -25), Vector3(24.6, 0.4, 22.6), _dark_concrete, true)
	for z in [-33.1, -16.9]:
		_box("ArchiveEastWallExtension", Vector3(-33.3, 3.6, z), Vector3(0.6, 6.5, 5.8), _concrete, true)
	for x in [-54.0, -37.5]:
		_box("ArchiveObservationPier", Vector3(x, 3.6, -36.3), Vector3(6 if x < -50.0 else 9, 6.5, 0.6), _concrete, true)
	_box("ArchiveObservationSill", Vector3(-46.5, 1.18, -36.3), Vector3(9, 1.06, 0.6), _tile, true)
	_box("ArchiveObservationHeader", Vector3(-46.5, 5.73, -36.3), Vector3(9, 2.24, 0.6), _concrete, true)
	var glass := _plain(Color(0.11, 0.22, 0.20, 0.28), 0.16, 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box("ArchiveObservationGlass", Vector3(-46.5, 3.16, -36.15), Vector3(9, 2.9, 0.08), glass, true)
	for x in [-49.5, -46.5, -43.5]:
		_box("ObservationMullion", Vector3(x, 3.15, -36.04), Vector3(0.065, 2.95, 0.12), _metal)
	_rail(Vector3(-50.8, 0.65, -35.6), Vector3(-42.2, 0.65, -35.6))
	# A sealed pipe gallery beyond the glass makes the boundary architectural, not a void.
	_box("ObservationGalleryFloor", Vector3(-46.5, -0.1, -38.2), Vector3(9, 1.5, 3.2), _dark_concrete, true)
	_box("ObservationGalleryBack", Vector3(-46.5, 3.6, -39.9), Vector3(9, 6.5, 0.3), _dark_concrete, true)
	_box("ObservationGalleryRoof", Vector3(-46.5, 6.85, -38.2), Vector3(9, 0.3, 3.2), _dark_concrete)
	for x in [-50.8, -42.2]:
		_box("ObservationGallerySide", Vector3(x, 3.6, -38.2), Vector3(0.3, 6.5, 3.2), _dark_concrete, true)
	for y in [1.7, 3.9]:
		_pipe("SealedGalleryPipe", Vector3(-50.5, y, -38.1), Vector3(-42.5, y, -38.1), 0.24, _rust)
	_lamp(Vector3(-46.5, 3.0, -38), Color(0.16, 0.42, 0.39), 1.5, 8.0)
	for x in [-53.7, -38.8]:
		for z in [-33.9, -16.1]:
			_archive_rack(Vector3(x, 0.65, z))
	for z in [-30.0, -20.0]:
		_archive_rack(Vector3(-55.7, 0.65, z), true)
	_box("ArchiveCargoCrate", Vector3(-40.8, 1.26, -29.9), Vector3(2.1, 1.22, 1.7), _dark_concrete, true)
	for x in [-41.6, -40.0]:
		_box("CrateSteelBand", Vector3(x, 1.88, -29.9), Vector3(0.055, 0.04, 1.8), _rust)
	_box("ArchiveRelayBacking", Vector3(-48, 1.8, -26.05), Vector3(1.9, 2.3, 0.16), _metal)
	_box("ArchiveRelayPipeTrench", Vector3(-48, 0.66, -28.8), Vector3(0.35, 0.02, 5.6), _black)
	for x in [-52.8, -44.8, -36.8]:
		_box("ArchiveCeilingBeam", Vector3(x, 6.75, -25), Vector3(0.28, 0.38, 22), _metal)
		_pipe("ArchiveFeedPipe", Vector3(x + 0.7, 6.2, -35.8), Vector3(x + 0.7, 6.2, -14.2), 0.13, _rust)
		_box("ArchiveLightHousing", Vector3(x, 6.38, -25), Vector3(0.38, 0.16, 2.4), _metal)
		_box("ArchiveLightTube", Vector3(x, 6.27, -25), Vector3(0.12, 0.08, 2.15), _warm_emission)
		_lamp(Vector3(x, 5.85, -25), Color(0.56, 0.51, 0.33), 2.5, 11.0)
	var shadow_light := _lamp(Vector3(-48, 4.5, -25), Color(0.39, 0.61, 0.54), 1.4, 10.0)
	shadow_light.shadow_enabled = true
	shadow_light.shadow_blur = 1.5
	for z in [-27.7, -22.3]:
		_box("ArchiveDoorStripe", Vector3(-34, 0.67, z), Vector3(1.6, 0.025, 0.12), _yellow)
	_label("安 全 继 电 器 / SR-08", Vector3(-48, 3.55, -26.14), Vector3(0, PI, 0), 0.0040, Color(0.50, 0.78, 0.63))
	_label("西 侧 封 存 档 案 库\nARCHIVE / INTAKE RECORDS", Vector3(-56.94, 4.85, -25), Vector3(0, PI * 0.5, 0), 0.006, Color(0.49, 0.58, 0.47))
	_label("1994.11  停止记录\n禁止在库内奔跑", Vector3(-33.65, 2.8, -18), Vector3(0, -PI * 0.5, 0), 0.0037, Color(0.65, 0.57, 0.36))
	_label("泵房 / 返回主池 →", Vector3(-33.69, 4.0, -25), Vector3(0, -PI * 0.5, 0), 0.0035, Color(0.48, 0.70, 0.57))
	_add_local_reflection("ArchiveWetFloorReflection", Vector3(-45, 3.3, -25), Vector3(24, 7, 22), 0.28)


func _archive_rack(base: Vector3, rotated: bool = false) -> void:
	var span := Vector3(4.4, 0, 0) if not rotated else Vector3(0, 0, 4.4)
	var thickness := Vector3(4.4, 0.10, 0.9) if not rotated else Vector3(0.9, 0.10, 4.4)
	for side in [-1.0, 1.0]:
		for depth in [-0.38, 0.38]:
			var foot: Vector3 = base + span * side * 0.48 + (Vector3(0, 0, depth) if not rotated else Vector3(depth, 0, 0))
			_box("ArchiveRackUpright", foot + Vector3.UP * 1.7, Vector3(0.09, 3.4, 0.09), _rust, true)
	for tier in range(4):
		var level := base + Vector3.UP * (0.16 + float(tier) * 0.84)
		_box("ArchiveRackShelf", level, thickness, _metal, true)
		for index in range(6):
			var box_pos := level + span * (-0.4 + float(index) * 0.16) + Vector3.UP * 0.32
			_box("DampRecordCase", box_pos, Vector3(0.53, 0.54, 0.65) if not rotated else Vector3(0.65, 0.54, 0.53), _dark_concrete)
			_box("RecordCaseLabel", box_pos + (Vector3(0, 0, 0.333) if not rotated else Vector3(0.333, 0, 0)), Vector3(0.28, 0.12, 0.015) if not rotated else Vector3(0.015, 0.12, 0.28), _yellow)


func _make_filter_wing() -> void:
	_box("FilterCorridorFloor", Vector3(51, -0.1, 25), Vector3(36.4, 1.5, 8), _tile, true)
	_box("FilterCorridorSouth", Vector3(51, 3.6, 29.3), Vector3(36.4, 6.5, 0.6), _concrete, true)
	_box("FilterCorridorEast", Vector3(69.3, 3.6, 25), Vector3(0.6, 6.5, 8.6), _concrete, true)
	_box("FilterCorridorRoof", Vector3(51, 7.05, 25), Vector3(36.4, 0.4, 8.6), _dark_concrete, true)
	_box("FilterCorridorWestPier", Vector3(33.3, 3.6, 28.4), Vector3(0.6, 6.5, 1.8), _concrete, true)
	_box("FilterCorridorNorthWest", Vector3(33.4, 3.6, 20.7), Vector3(0.8, 6.5, 0.6), _concrete, true)
	for x in [39.0, 50.0, 62.0]:
		_box("CorridorLightHousing", Vector3(x, 6.7, 25), Vector3(2.4, 0.13, 0.35), _metal)
		_box("CorridorLightTube", Vector3(x, 6.58, 25), Vector3(2.1, 0.08, 0.12), _warm_emission)
		_lamp(Vector3(x, 6.1, 25), Color(0.55, 0.54, 0.38), 2.3, 13.0)
		_box("CorridorEmergencyLine", Vector3(x, 0.67, 28.5), Vector3(7.5, 0.025, 0.09), _yellow)
	for y in [4.7, 5.3]:
		_pipe("FilterReturnMain", Vector3(33.6, y, 28.7), Vector3(68.7, y, 28.7), 0.17, _rust)
	_label("配电间 / 主池 ←", Vector3(38, 3.8, 28.93), Vector3(0, PI, 0), 0.004, Color(0.54, 0.72, 0.59))
	_label("08 / 过滤池\n旁通阀在水下 5 M", Vector3(53, 3.8, 28.93), Vector3(0, PI, 0), 0.0048, Color(0.55, 0.73, 0.64))
	_box("FilterBasinFloor", Vector3(51.5, -10.4, 2), Vector3(35, 0.8, 38), _pool_tile, true)
	for x in [35.5, 67.5]:
		_box("FilterSideDeck", Vector3(x, -0.1, 2), Vector3(3, 1.5, 38), _tile, true)
	for z in [-15.5, 19.5]:
		_box("FilterEndDeck", Vector3(51.5, -0.1, z), Vector3(29, 1.5, 3), _tile, true)
	for x in [36.85, 66.15]:
		_box("FilterSideLiner", Vector3(x, -4.7, 2), Vector3(0.3, 10.7, 32), _pool_tile, true)
	for z in [-14.15, 18.15]:
		_box("FilterEndLiner", Vector3(51.5, -4.7, z), Vector3(29, 10.7, 0.3), _pool_tile, true)
	_box("FilterHallSideWall", Vector3(33.7, 6.3, 2), Vector3(0.6, 11.3, 38.6), _concrete, true)
	_wall_openings("FilterHallEastWall", Vector3(69.3, 6.3, 2), 38.6, 11.3, false, [Vector2(-11, -5)])
	_box("FilterHallNorthWall", Vector3(51.5, 6.3, -17.3), Vector3(35, 11.3, 0.6), _concrete, true)
	# Openings at the west walkway and central bay connect the entire south ring to the corridor.
	_box("FilterHallSouthPierWest", Vector3(43, 6.3, 21.3), Vector3(8, 11.3, 0.6), _concrete, true)
	_box("FilterHallSouthPierEast", Vector3(63.1, 6.3, 21.3), Vector3(12.4, 11.3, 0.6), _concrete, true)
	_box("FilterHallSouthDoorHeader", Vector3(51.5, 9.25, 21.3), Vector3(35, 5.4, 0.6), _concrete, true)
	_box("FilterHallRoof", Vector3(51.5, 12.2, 2), Vector3(35.6, 0.5, 38.6), _dark_concrete, true)
	for z in [-11.0, -2.0, 7.0, 16.0]:
		_box("FilterRoofTruss", Vector3(51.5, 11.65, z), Vector3(35, 0.3, 0.35), _metal)
		for x in [40.0, 63.0]:
			_box("FilterStripHousing", Vector3(x, 11.1, z), Vector3(0.36, 0.16, 2.65), _metal)
			_box("FilterStripTube", Vector3(x, 10.97, z), Vector3(0.13, 0.07, 2.3), _cyan_emission)
			_lamp(Vector3(x, 10.65, z), Color(0.32, 0.58, 0.59), 2.7, 19.0)
	for x in [34.15, 68.85]:
		_pipe("FilterOverheadPipe", Vector3(x, 4.5, -16.5), Vector3(x, 4.5, 20.5), 0.24, _rust)
	for point in ladders:
		if point.x > 30.0 and point.x < 70.0:
			_filter_ladder(point)
	for x in [37.35, 65.65]:
		for section in [Vector2(-13, -10), Vector2(-5, 5), Vector2(10, 17)]:
			_rail(Vector3(x, 0.65, section.x), Vector3(x, 0.65, section.y))
	for x in [40.3, 62.7]:
		for z in [-10.0, 13.0]:
			_box("FilterSubmergedPylon", Vector3(x, -5.2, z), Vector3(1.25, 9.6, 1.25), _pool_tile, true)
			_box("FilterPylonFoot", Vector3(x, -9.4, z), Vector3(2.7, 1.2, 2.7), _dark_concrete, true)
	for x in [47.1, 55.0]:
		_box("AnnexValveBaffle", Vector3(x, -5.2, 3), Vector3(0.35, 5.0, 6.4), _dark_concrete, true)
	_box("AnnexValvePlatform", Vector3(51, -7.85, 3), Vector3(7.55, 0.3, 6.6), _metal, true)
	_pipe("AnnexBypassPipe", Vector3(51, -5.6, -13.6), Vector3(51, -5.6, 3), 0.29, _rust)
	_pipe("AnnexValveRiser", Vector3(51, -5.6, 3), Vector3(51, -3.8, 3), 0.24, _rust)
	_box("AnnexValveServicePlate", Vector3(51, -3.1, 3.48), Vector3(1.8, 0.7, 0.08), _metal)
	_label("旁 通 / BYPASS-08", Vector3(51, -3.1, 3.54), Vector3(0, PI, 0), 0.0035, Color(0.49, 0.76, 0.64))
	_lamp(Vector3(51, -3.2, 2.5), Color(0.18, 0.52, 0.43), 1.1, 8.0)
	_bubbles(Vector3(52.2, -6.2, 3.8))
	for z in [-11.0, 15.0]:
		_box("AnnexDrain", Vector3(51.5, -9.965, z), Vector3(13, 0.025, 1.1), _black)
		for x in range(46, 58):
			_box("AnnexDrainBar", Vector3(float(x), -9.94, z), Vector3(0.055, 0.04, 1.1), _metal)
	annex_water_material = ShaderMaterial.new()
	annex_water_material.shader = water_material.shader
	annex_water_material.set_shader_parameter("pool_center", Vector2(51.5, 2))
	annex_water_material.set_shader_parameter("pool_half_size", Vector2(14.5, 16))
	annex_water_material.set_shader_parameter("water_color", Color(0.02, 0.105, 0.12))
	_basin_materials.append(annex_water_material)
	_water_plane("FilterAnnexWater", Vector3(51.5, 0, 2), Vector2(29, 32), 57, 63, annex_water_material)
	_label("第 八 过 滤 池", Vector3(51.5, 8.7, -16.94), Vector3.ZERO, 0.0085, Color(0.42, 0.58, 0.53))
	_label("INTAKE 08 / DEPTH 10 M / DO NOT ENTER", Vector3(51.5, 7.3, -16.94), Vector3.ZERO, 0.0037, Color(0.43, 0.56, 0.48))
	_label("检修梯 ↑  /  回到配电间 ↓", Vector3(34.08, 2.7, 16), Vector3(0, PI * 0.5, 0), 0.0037, Color(0.48, 0.69, 0.55))
	_add_local_reflection("FilterHallReflection", Vector3(51.5, 2.5, 2), Vector3(35, 20, 38), 0.48)


func _filter_ladder(point: Vector3, basin: Rect2 = Rect2(37, -14, 29, 32)) -> void:
	var west := point.x < basin.get_center().x
	var water_x: float = basin.position.x + 0.22 if west else basin.end.x - 0.22
	var anchor_x: float = point.x + 0.3 if west else point.x - 0.3
	var wall_x: float = basin.position.x - 2.92 if west else basin.end.x + 2.92
	for dz in [-0.48, 0.48]:
		_pipe("AnnexLadderRail", Vector3(water_x, -2.8, point.z + dz), Vector3(water_x, 1.6, point.z + dz), 0.045, _metal)
		_pipe("AnnexLadderHandrail", Vector3(water_x, 1.6, point.z + dz), Vector3(anchor_x, 1.6, point.z + dz), 0.045, _metal)
		_pipe("AnnexLadderAnchor", Vector3(anchor_x, 1.6, point.z + dz), Vector3(anchor_x, 0.67, point.z + dz), 0.045, _metal)
	for index in range(12):
		_pipe("AnnexLadderRung", Vector3(water_x, -2.65 + float(index) * 0.28, point.z - 0.48), Vector3(water_x, -2.65 + float(index) * 0.28, point.z + 0.48), 0.035, _metal)
	_box("AnnexLadderRest", Vector3(water_x + 0.33 if west else water_x - 0.33, -2.88, point.z), Vector3(1.05, 0.18, 1.5), _metal, true)
	_box("AnnexLadderExitMark", Vector3(point.x, 0.672, point.z), Vector3(0.5, 0.02, 1.0), _yellow)
	_box("AnnexLadderLocator", Vector3(wall_x, 2.0, point.z), Vector3(0.10, 0.18, 0.45), _green_emission)
	_lamp(Vector3(point.x, 2.7, point.z), Color(0.25, 0.68, 0.56), 0.85, 5.5)
	_label("池梯 / LADDER", Vector3(wall_x, 2.7, point.z), Vector3(0, PI * 0.5 if west else -PI * 0.5, 0), 0.003, Color(0.48, 0.72, 0.61))


func _add_local_reflection(node_name: String, pos: Vector3, size_value: Vector3, strength: float) -> void:
	var probe := ReflectionProbe.new()
	probe.name = node_name
	probe.position = pos
	probe.size = size_value
	probe.box_projection = true
	probe.interior = true
	probe.intensity = strength
	probe.max_distance = 45.0
	probe.enable_shadows = false
	add_child(probe)


func _wall_openings(node_name: String, center: Vector3, length_value: float, height: float, horizontal: bool, openings: Array[Vector2]) -> void:
	var start: float = (center.x if horizontal else center.z) - length_value * 0.5
	var finish := start + length_value
	var cursor := start
	for opening in openings:
		var lo := clampf(opening.x, start, finish)
		var hi := clampf(opening.y, start, finish)
		if lo > cursor:
			var pos := Vector3((cursor + lo) * 0.5, center.y, center.z) if horizontal else Vector3(center.x, center.y, (cursor + lo) * 0.5)
			_box(node_name + "Pier", pos, Vector3(lo - cursor, height, 0.6) if horizontal else Vector3(0.6, height, lo - cursor), _concrete, true)
		var top := center.y + height * 0.5
		var header_pos := Vector3((lo + hi) * 0.5, (top + 4.65) * 0.5, center.z) if horizontal else Vector3(center.x, (top + 4.65) * 0.5, (lo + hi) * 0.5)
		_box(node_name + "DoorHeader", header_pos, Vector3(hi - lo, top - 4.65, 0.6) if horizontal else Vector3(0.6, top - 4.65, hi - lo), _concrete, true)
		cursor = maxf(cursor, hi)
	if cursor < finish:
		var pos := Vector3((cursor + finish) * 0.5, center.y, center.z) if horizontal else Vector3(center.x, center.y, (cursor + finish) * 0.5)
		_box(node_name + "Pier", pos, Vector3(finish - cursor, height, 0.6) if horizontal else Vector3(0.6, height, finish - cursor), _concrete, true)


func _long_gallery(bounds: Rect2, title: String, horizontal: bool = true, first_gaps: Array[Vector2] = [], second_gaps: Array[Vector2] = []) -> void:
	var center := bounds.get_center()
	_box("GalleryFloor", Vector3(center.x, -0.1, center.y), Vector3(bounds.size.x, 1.5, bounds.size.y), _tile, true)
	_box("GalleryRoof", Vector3(center.x, 6.35, center.y), Vector3(bounds.size.x, 0.4, bounds.size.y), _dark_concrete, true)
	for sign_value in [-1.0, 1.0]:
		var side_pos := Vector3(center.x, 3.3, center.y + sign_value * (bounds.size.y * 0.5 + 0.3)) if horizontal else Vector3(center.x + sign_value * (bounds.size.x * 0.5 + 0.3), 3.3, center.y)
		_wall_openings("GallerySide", side_pos, bounds.size.x if horizontal else bounds.size.y, 5.3, horizontal, first_gaps if sign_value < 0 else second_gaps)
	var length_value := bounds.size.x if horizontal else bounds.size.y
	var count := maxi(1, int(ceil(length_value / 18.0)))
	for index in range(count):
		var t := (float(index) + 0.5) / float(count)
		var point := Vector3(lerpf(bounds.position.x, bounds.end.x, t), 5.9, center.y) if horizontal else Vector3(center.x, 5.9, lerpf(bounds.position.y, bounds.end.y, t))
		_box("GalleryFixture", point, Vector3(2.5, 0.08, 0.16) if horizontal else Vector3(0.16, 0.08, 2.5), _warm_emission)
		_lamp(point - Vector3.UP * 0.35, Color(0.49, 0.59, 0.49), 2.0, 13.0)
		_box("GalleryExpansionJoint", Vector3(point.x, 0.67, point.z), Vector3(0.10, 0.025, bounds.size.y) if horizontal else Vector3(bounds.size.x, 0.025, 0.10), _black)
		if index % 2 == 0:
			var side := point + Vector3(0, -2.2, bounds.size.y * 0.5 - 0.03) if horizontal else point + Vector3(bounds.size.x * 0.5 - 0.03, -2.2, 0)
			_label(title + " / %02d" % (index + 1), side, Vector3(0, PI if horizontal else -PI * 0.5, 0), 0.0035, Color(0.48, 0.64, 0.51))


func _make_canal_network() -> void:
	_long_gallery(Rect2(-106, -28, 49, 6), "西侧输水")
	_long_gallery(Rect2(69, -11, 109, 6), "东侧观察", true, [Vector2(135.5, 141.5)], [Vector2(171.5, 177.5)])
	_long_gallery(Rect2(-106, 12, 3, 6), "阶梯浴场")
	_long_gallery(Rect2(135.5, -27, 6, 16), "北侧溢流池", false)
	_long_gallery(Rect2(171.5, -5, 6, 24), "地下水库", false)
	for z in [-83.0, 73.0]:
		var north: bool = z < 0.0
		var inner_z: float = z + 4.5 if north else z - 4.5
		var outer_z: float = z - 4.5 if north else z + 4.5
		_box("LongCanalFloor", Vector3(36, -6.4, z), Vector3(308, 0.8, 12), _pool_tile, true)
		_box("LongCanalOuterDeck", Vector3(36, -0.1, outer_z), Vector3(308, 1.5, 3), _tile, true)
		for interval in [Vector2(-118, -115), Vector2(-109, 181), Vector2(187, 190)]:
			_box("LongCanalInnerDeck", Vector3((interval.x + interval.y) * 0.5, -0.1, inner_z), Vector3(interval.y - interval.x, 1.5, 3), _tile, true)
			_box("LongCanalInnerLiner", Vector3((interval.x + interval.y) * 0.5, -2.7, z + (3.15 if north else -3.15)), Vector3(interval.y - interval.x, 6.7, 0.3), _pool_tile, true)
		_box("LongCanalOuterLiner", Vector3(36, -2.7, z + (-3.15 if north else 3.15)), Vector3(308, 6.7, 0.3), _pool_tile, true)
		_box("LongCanalOutsideWall", Vector3(36, 3.3, z + (-6.3 if north else 6.3)), Vector3(308, 5.3, 0.6), _concrete, true)
		var doors: Array[Vector2] = []
		doors.append(Vector2(132, 140) if north else Vector2(171.5, 176))
		_wall_openings("LongCanalInsideWall", Vector3(36, 3.3, z + (6.3 if north else -6.3)), 284, 5.3, true, doors)
		_box("LongCanalRoof", Vector3(36, 6.2, z), Vector3(308, 0.5, 12.6), _dark_concrete, true)
		_external_water(Rect2(-115, z - 3, 302, 6), "RingCanalWater", false)
		for x in range(-108, 187, 22):
			_box("CanalCeilingRib", Vector3(float(x), 5.9, z), Vector3(0.3, 0.4, 12), _metal)
			_box("CanalStrip", Vector3(float(x), 5.55, inner_z), Vector3(2.7, 0.08, 0.17), _cyan_emission)
			_lamp(Vector3(float(x), 5.2, inner_z), Color(0.25, 0.48, 0.49), 2.4, 16.0)
	for x in [-112.0, 184.0]:
		var west: bool = x < 0.0
		_box("SideCanalFloor", Vector3(x, -6.4, -5), Vector3(12, 0.8, 150), _pool_tile, true)
		for offset in [-4.5, 4.5]:
			_box("SideCanalDeck", Vector3(x + offset, -0.1, -5), Vector3(3, 1.5, 144), _tile, true)
			_box("SideCanalLiner", Vector3(x + signf(offset) * 3.15, -2.7, -5), Vector3(0.3, 6.7, 144), _pool_tile, true)
		_box("SideCanalOutsideWall", Vector3(x + (-6.3 if west else 6.3), 3.3, -5), Vector3(0.6, 5.3, 144), _concrete, true)
		var doors: Array[Vector2] = []
		if west:
			doors.append_array([Vector2(-28, -22), Vector2(12, 18)])
		else:
			doors.append(Vector2(-11, -5))
		_wall_openings("SideCanalInsideWall", Vector3(x + (6.3 if west else -6.3), 3.3, -5), 144, 5.3, false, doors)
		_box("SideCanalRoof", Vector3(x, 6.2, -5), Vector3(12.6, 0.5, 144), _dark_concrete, true)
		_external_water(Rect2(x - 3, -80, 6, 150), "SideRingWater", false)
		for z in range(-72, 68, 20):
			_box("CanalCeilingRib", Vector3(x, 5.9, float(z)), Vector3(12, 0.4, 0.3), _metal)
			_box("CanalStrip", Vector3(x + (4.5 if west else -4.5), 5.55, float(z)), Vector3(0.17, 0.08, 2.7), _cyan_emission)
			_lamp(Vector3(x + (4.5 if west else -4.5), 5.2, float(z)), Color(0.25, 0.48, 0.49), 2.4, 16.0)
	# End closures are outside the navigable corner water; inner decks join at each junction.
	for x in [-118.3, 190.3]:
		for z in [-83.0, 73.0]:
			_box("CanalEndWall", Vector3(x, 0, z), Vector3(0.6, 12, 12.6), _concrete, true)
	_filter_ladder(ladders[14], Rect2(-115, -80, 6, 150))
	_filter_ladder(ladders[15], Rect2(181, -80, 6, 150))
	for point in [Vector3(-107.5, 0.65, -78.5), Vector3(179.5, 0.65, -78.5), Vector3(-107.5, 0.65, 68.5), Vector3(179.5, 0.65, 68.5)]:
		_box("CanalJunctionBeacon", point + Vector3.UP * 3.0, Vector3(0.3, 0.18, 0.3), _green_emission)
		_lamp(point + Vector3.UP * 2.6, Color(0.25, 0.67, 0.47), 1.2, 7.5)


func _external_water(bounds: Rect2, node_name: String, analytic_lamps: bool = true) -> void:
	var material := ShaderMaterial.new()
	material.shader = water_material.shader
	material.set_shader_parameter("pool_center", bounds.get_center())
	material.set_shader_parameter("pool_half_size", bounds.size * 0.5)
	material.set_shader_parameter("analytic_lamps", analytic_lamps)
	_basin_materials.append(material)
	var center := bounds.get_center()
	_water_plane(node_name, Vector3(center.x, 0, center.y), bounds.size, mini(160, int(bounds.size.x * 1.2)), mini(160, int(bounds.size.y * 1.2)), material)


func _make_outer_basins() -> void:
	_large_basin(Rect2(-103, -13, 42, 58), -24.0, "西侧阶梯浴场", {"west": [Vector2(12, 18)]}, Vector3(-82, -5, 13), 8)
	_large_basin(Rect2(76, -77, 64, 50), -12.0, "北侧溢流池", {"north": [Vector2(132, 140)], "south": [Vector2(135.5, 140)]}, Vector3(108, -6, -49), 10)
	_large_basin(Rect2(98, 19, 78, 48), -22.0, "黑水地下水库", {"north": [Vector2(171.5, 176)], "south": [Vector2(171.5, 176)]}, Vector3(137, -7, 43), 12)
	# The tiered baths have shallow shelves around a 24 m black-water well.
	for z in [-4.0, 34.0]:
		_box("BathShallowShelf", Vector3(-96.6, -2.4, z), Vector3(6.8, 0.4, 12), _pool_tile, true)
		_box("BathShelfStep", Vector3(-94.1, -4.1, z), Vector3(1.8, 3.0, 12), _pool_tile, true)
	# A true walkable sloping pier reaches a raised diving platform over the overflow basin.
	# The sloping top meets the platform's front edge, so both directions have no step face.
	_beam("DivingTowerRamp", Vector3(137.25, 0.52, -49), Vector3(125.5, 3.2678, -49), 1.8, 0.16, _metal, true)
	_box("DivingTowerPlatform", Vector3(123, 3.25, -49), Vector3(5, 0.2, 5), _metal, true)
	for z in [-50.0, -48.0]:
		_rail(Vector3(137.25, 0.60, z), Vector3(125.5, 3.35, z))
	for x in [121.0, 125.0]:
		for z in [-51.0, -47.0]:
			_pipe("DivingTowerLeg", Vector3(x, -11.8, z), Vector3(x, 3.2, z), 0.12, _rust, true)
	_rail(Vector3(120.6, 3.35, -51.3), Vector3(125.4, 3.35, -51.3))
	_rail(Vector3(120.6, 3.35, -46.7), Vector3(125.4, 3.35, -46.7))
	_label("3 M / 禁止跳水", Vector3(123, 3.65, -46.65), Vector3(0, PI, 0), 0.0037, Color(0.75, 0.58, 0.26))
	# Reservoir catwalks stop short of each other: the missing span makes water entry unavoidable.
	_box("ReservoirEastCatwalk", Vector3(160, -0.1, 43), Vector3(26, 1.5, 2.3), _metal, true)
	_box("ReservoirWestCatwalk", Vector3(110.5, -0.1, 43), Vector3(19, 1.5, 2.3), _metal, true)
	for z in [41.85, 44.15]:
		_rail(Vector3(150, 0.65, z), Vector3(172.5, 0.65, z))
		_rail(Vector3(101.5, 0.65, z), Vector3(117, 0.65, z))
	for x in [119.8, 147.2]:
		_box("ReservoirCollapseWarning", Vector3(x, 1.6, 43), Vector3(0.12, 0.18, 1.6), _warm_emission)
		_label("断桥 / 水下旁通阀", Vector3(x, 2.4, 43), Vector3(0, PI * 0.5, 0), 0.0032, Color(0.67, 0.59, 0.32))


func _large_basin(bounds: Rect2, floor_level: float, title: String, openings: Dictionary, objective: Vector3, first_ladder: int) -> void:
	var center := bounds.get_center()
	var water := bounds.grow(-3.0)
	var ceiling: float = 20.0 if floor_level < -20.0 else 14.0
	_box("OuterBasinFloor", Vector3(center.x, floor_level - 0.4, center.y), Vector3(bounds.size.x, 0.8, bounds.size.y), _pool_tile, true)
	_box("OuterBasinRoof", Vector3(center.x, ceiling + 0.25, center.y), Vector3(bounds.size.x + 0.6, 0.5, bounds.size.y + 0.6), _dark_concrete, true)
	for x in [bounds.position.x + 1.5, bounds.end.x - 1.5]:
		_box("OuterBasinSideDeck", Vector3(x, -0.1, center.y), Vector3(3, 1.5, bounds.size.y), _tile, true)
	for z in [bounds.position.y + 1.5, bounds.end.y - 1.5]:
		_box("OuterBasinEndDeck", Vector3(center.x, -0.1, z), Vector3(water.size.x, 1.5, 3), _tile, true)
	for side_name in ["west", "east", "north", "south"]:
		var horizontal: bool = side_name == "north" or side_name == "south"
		var wall_center := Vector3(center.x, (ceiling + 0.65) * 0.5, bounds.position.y - 0.3 if side_name == "north" else bounds.end.y + 0.3) if horizontal else Vector3(bounds.position.x - 0.3 if side_name == "west" else bounds.end.x + 0.3, (ceiling + 0.65) * 0.5, center.y)
		var gaps: Array[Vector2] = []
		if openings.has(side_name):
			for gap: Vector2 in openings[side_name]:
				gaps.append(gap)
		_wall_openings("OuterBasinWall", wall_center, bounds.size.x if horizontal else bounds.size.y, ceiling - 0.65, horizontal, gaps)
	for x in [water.position.x - 0.15, water.end.x + 0.15]:
		_box("OuterBasinSideLiner", Vector3(x, (floor_level + 0.65) * 0.5, center.y), Vector3(0.3, 0.65 - floor_level, water.size.y), _pool_tile, true)
	for z in [water.position.y - 0.15, water.end.y + 0.15]:
		_box("OuterBasinEndLiner", Vector3(center.x, (floor_level + 0.65) * 0.5, z), Vector3(water.size.x, 0.65 - floor_level, 0.3), _pool_tile, true)
	_external_water(water, "OuterBasinWater")
	for index in range(first_ladder, first_ladder + 2):
		_filter_ladder(ladders[index], water)
	for z in [water.position.y + 5, center.y, water.end.y - 5]:
		_box("OuterVaultRib", Vector3(center.x, ceiling - 0.6, z), Vector3(bounds.size.x, 0.5, 0.5), _metal)
		for x in [water.position.x + 3, water.end.x - 3]:
			_box("OuterBasinLampHousing", Vector3(x, 11.1, z), Vector3(0.35, 0.16, 3.2), _metal)
			_box("OuterBasinLampTube", Vector3(x, 10.97, z), Vector3(0.13, 0.08, 2.8), _cyan_emission)
			_pipe("OuterLampChain", Vector3(x, 11.2, z), Vector3(x, ceiling - 0.5, z), 0.025, _rust)
			_lamp(Vector3(x, 10.5, z), Color(0.28, 0.52, 0.55), 3.0, 24.0)
	for x in [water.position.x + 5, water.end.x - 5]:
		for z in [water.position.y + 8, water.end.y - 8]:
			_box("OuterSubmergedColumn", Vector3(x, (floor_level + 2.5) * 0.5, z), Vector3(1.4, 2.5 - floor_level, 1.4), _pool_tile, true)
			_box("OuterColumnFoot", Vector3(x, floor_level + 0.8, z), Vector3(3.4, 1.6, 3.4), _dark_concrete, true)
	# Each task bay is open overhead and to the pool; no full-width barrier traps the animal.
	for x_offset in [-4.3, 4.3]:
		_box("OuterTaskBaffle", objective + Vector3(x_offset, -0.2, 0), Vector3(0.4, 5.6, 6.8), _dark_concrete, true)
	_box("OuterTaskPlatform", objective + Vector3(0, -3.2, 0), Vector3(8.2, 0.3, 6.8), _metal, true)
	_pipe("OuterValveRiser", objective + Vector3(0, -0.6, 0), objective + Vector3(0, 1.0, 0), 0.23, _rust)
	_box("OuterValvePlate", objective + Vector3(0, 1.7, 0.45), Vector3(1.8, 0.6, 0.08), _metal)
	_lamp(objective + Vector3(0, 1.7, 1.0), Color(0.16, 0.49, 0.42), 1.3, 9.0)
	_bubbles(objective + Vector3(1.5, -1.6, 1.0))
	_label(title, Vector3(center.x, 7.4, bounds.position.y + 0.04), Vector3.ZERO, 0.009, Color(0.43, 0.60, 0.53))
	_label("DEPTH %d M / 应急输水系统" % int(-floor_level), Vector3(center.x, 5.7, bounds.position.y + 0.04), Vector3.ZERO, 0.0040, Color(0.41, 0.57, 0.49))
	_add_local_reflection("OuterBasinReflection", Vector3(center.x, 3, center.y), Vector3(bounds.size.x, ceiling - floor_level, bounds.size.y), 0.45)


func _nav_point(point: Vector3) -> int:
	var existing := navigation_points.find(point)
	if existing >= 0:
		return existing
	navigation_points.append(point)
	return navigation_points.size() - 1


func _nav_connect(a: Vector3, b: Vector3, ladder_edge: bool = false) -> void:
	var a_id := _nav_point(a)
	var b_id := _nav_point(b)
	if a_id == b_id:
		return
	var edge := Vector2i(mini(a_id, b_id), maxi(a_id, b_id))
	if not navigation_edges.has(edge):
		navigation_edges.append(edge)
	if ladder_edge and not navigation_ladder_edges.has(edge):
		navigation_ladder_edges.append(edge)


func _nav_chain(points: Array[Vector3], step_length: float = 20.0) -> void:
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var segments := maxi(1, int(ceil(a.distance_to(b) / step_length)))
		for segment in range(segments):
			_nav_connect(a.lerp(b, float(segment) / float(segments)), a.lerp(b, float(segment + 1) / float(segments)))


func _make_navigation_metadata() -> void:
	# Nodes are feet positions. Each segment follows an authored walkway or a clear swim lane.
	_nav_chain([Vector3(-21, 0.65, 44), Vector3(-21, 0.65, 36), Vector3(-21, 0.65, 22), Vector3(-21, 0.65, -20), Vector3(-21, 0.65, -25), Vector3(-21, 0.65, -44)])
	_nav_chain([Vector3(-21, 0.65, 44), Vector3(21, 0.65, 44), Vector3(21, 0.65, 25), Vector3(21, 0.65, 12), Vector3(21, 0.65, 7)])
	_nav_chain([Vector3(-21, 0.65, -44), Vector3(-1.4, 0.65, -43.4), Vector3(1.4, 0.65, -43.4), Vector3(21, 0.65, -44), Vector3(21, 0.65, -22), Vector3(21, 0.65, -5)])
	_nav_chain([Vector3(-1.4, 0.65, -43.4), nav_targets["exit"], Vector3(-1.4, 0.65, -46.5), Vector3(0, 0.65, -54)])
	_nav_chain([Vector3(-21, 0.65, -25), Vector3(-26, 0.65, -24), Vector3(-35, 0.65, -24), Vector3(-46, 0.65, -24), Vector3(-54, 0.65, -24), Vector3(-60, 0.65, -25), Vector3(-107.5, 0.65, -25)])
	_nav_connect(Vector3(-26, 0.65, -24), nav_targets["pump"])
	_nav_connect(Vector3(-46, 0.65, -24), nav_targets["archive"])
	_nav_chain([Vector3(21, 0.65, 25), Vector3(26, 0.65, 26.8), nav_targets["breaker"], Vector3(31, 0.65, 25), Vector3(35.5, 0.65, 25), Vector3(35.5, 0.65, 19.5), Vector3(35.5, 0.65, 8), Vector3(35.5, 0.65, -8), Vector3(35.5, 0.65, -15.5), Vector3(67.5, 0.65, -15.5), Vector3(67.5, 0.65, -8), Vector3(67.5, 0.65, 8), Vector3(67.5, 0.65, 19.5), Vector3(35.5, 0.65, 19.5)])
	_nav_chain([Vector3(67.5, 0.65, -8), Vector3(75, 0.65, -8), Vector3(138.5, 0.65, -8), Vector3(174.5, 0.65, -8), Vector3(179.5, 0.65, -8)])
	_nav_chain([Vector3(-107.5, 0.65, -25), Vector3(-107.5, 0.65, 15), Vector3(-107.5, 0.65, 68.5), Vector3(174.5, 0.65, 68.5), Vector3(179.5, 0.65, 68.5), Vector3(179.5, 0.65, -8), Vector3(179.5, 0.65, -78.5), Vector3(138.5, 0.65, -78.5), Vector3(-107.5, 0.65, -78.5), Vector3(-107.5, 0.65, -25)])
	_nav_chain([Vector3(-112, -1.43, -25), Vector3(-112, -1.43, -83), Vector3(184, -1.43, -83), Vector3(184, -1.43, -8), Vector3(184, -1.43, 73), Vector3(-112, -1.43, 73), Vector3(-112, -1.43, -25)])
	_nav_chain([Vector3(-107.5, 0.65, 15), Vector3(-101.5, 0.65, 15)])
	_nav_chain([Vector3(138.5, 0.65, -8), Vector3(138.5, 0.65, -28.5)])
	_nav_chain([Vector3(138.5, 0.65, -78.5), Vector3(138.5, 0.65, -75.5)])
	_nav_chain([Vector3(174.5, 0.65, -8), Vector3(174.5, 0.65, 20.5)])
	_nav_chain([Vector3(174.5, 0.65, 65.5), Vector3(174.5, 0.65, 68.5)])
	_nav_chain([Vector3(-18.3, -1.43, 22), Vector3(-18.3, -1.43, -20), Vector3(18.3, -1.43, -22), Vector3(18.3, -1.43, 12), Vector3(-18.3, -1.43, 22)])
	_nav_chain([Vector3(-18.3, -1.43, 22), Vector3(-10, -1.43, 20), Vector3(-10, -7.62, 20), nav_targets["valve_south"]])
	_nav_chain([Vector3(18.3, -1.43, -22), Vector3(10, -1.43, -21), Vector3(10, -9.62, -21), nav_targets["valve_north"]])
	for index in range(4):
		var ladder := ladders[index]
		var dry := Vector3(ladder.x, 0.65, ladder.z)
		var walkway := Vector3(signf(ladder.x) * 21, 0.65, ladder.z)
		var wet := Vector3(signf(ladder.x) * 18.3, -1.43, ladder.z)
		_nav_connect(walkway, dry)
		_nav_connect(dry, wet, true)
	_basin_navigation(Rect2(34, -17, 35, 38), 4, "annex_valve")
	_basin_navigation(Rect2(-103, -13, 42, 58), 8, "tier_valve", [Vector3(-101.5, 0.65, 15)])
	_basin_navigation(Rect2(76, -77, 64, 50), 10, "overflow_valve", [Vector3(138.5, 0.65, -75.5), Vector3(138.5, 0.65, -28.5), Vector3(138.5, 0.65, -49)])
	_basin_navigation(Rect2(98, 19, 78, 48), 12, "reservoir_valve", [Vector3(174.5, 0.65, 20.5), Vector3(174.5, 0.65, 65.5), Vector3(174.5, 0.65, 43)])
	_nav_chain([Vector3(138.5, 0.65, -49), Vector3(137.25, 0.65, -49), Vector3(125.5, 3.36, -49), Vector3(123, 3.35, -49)])
	_nav_chain([Vector3(174.5, 0.65, 43), Vector3(147.5, 0.65, 43)])
	_nav_connect(Vector3(-107.5, 0.65, -25), Vector3(-110, -1.43, -25), true)
	_nav_connect(Vector3(-110, -1.43, -25), Vector3(-112, -1.43, -25))
	_nav_connect(Vector3(179.5, 0.65, -8), Vector3(182, -1.43, -8), true)
	_nav_connect(Vector3(182, -1.43, -8), Vector3(184, -1.43, -8))


func _basin_navigation(bounds: Rect2, first_ladder: int, objective_id: String, extra_dry: Array[Vector3] = []) -> void:
	var left := bounds.position.x + 1.5
	var right := bounds.end.x - 1.5
	var north := bounds.position.y + 1.5
	var south := bounds.end.y - 1.5
	var west_points: Array[Vector3] = [Vector3(left, 0.65, north), Vector3(left, 0.65, south)]
	var east_points: Array[Vector3] = [Vector3(right, 0.65, north), Vector3(right, 0.65, south)]
	var ladder_count := 4 if first_ladder == 4 else 2
	for index in range(first_ladder, first_ladder + ladder_count):
		var ladder := ladders[index]
		var dry := Vector3(ladder.x, 0.65, ladder.z)
		(west_points if ladder.x < bounds.get_center().x else east_points).append(dry)
		var wet := Vector3(bounds.position.x + 4.0 if ladder.x < bounds.get_center().x else bounds.end.x - 4.0, -1.43, ladder.z)
		_nav_connect(dry, wet, true)
		var approach := nav_targets[objective_id]
		var surface_goal := Vector3(approach.x, -1.43, approach.z + 4.6)
		if objective_id == "reservoir_valve" and ladder.x < bounds.get_center().x:
			_nav_chain([wet, Vector3(125, -1.43, 36), surface_goal])
		else:
			_nav_connect(wet, surface_goal)
		_nav_chain([surface_goal, Vector3(approach.x, approach.y, surface_goal.z), approach])
	for extra in extra_dry:
		(west_points if extra.x < bounds.get_center().x else east_points).append(extra)
	west_points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	east_points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	_nav_chain(west_points)
	_nav_chain(east_points)
	_nav_chain([west_points[0], east_points[0]])
	_nav_chain([west_points[-1], east_points[-1]])


func _make_submerged_structures() -> void:
	# A side-facing U of baffles hides the swimmer without bisecting the pool.
	_filter_shelter(Vector3(-10, -6, 16), -1.0, "SouthFilter")
	_filter_shelter(Vector3(10, -8, -17), 1.0, "NorthFilter")
	for side in [-1.0, 1.0]:
		for z in [-32.0, 31.0]:
			_box("SubmergedSupportFoot", Vector3(side * 15.9, -12.3, z), Vector3(3.8, 1.4, 3.8), _dark_concrete, true)
			_box("SubmergedTower", Vector3(side * 15.9, -6.7, z), Vector3(1.5, 10.2, 1.5), _pool_tile, true)
			_pipe("SiltedPipe", Vector3(side * 16.9, -10.8, z), Vector3(side * 16.9, -2.0, z), 0.18, _rust)
	# Sparse intake trenches give the floor scale. No solid floor-to-surface wall crosses navigation.
	for z in [-8.0, 8.0]:
		_box("IntakeTrench", Vector3(0, -12.93, z), Vector3(12, 0.06, 1.3), _black)
		for x in range(-6, 7):
			_box("IntakeBar", Vector3(float(x), -12.88, z), Vector3(0.04, 0.06, 1.3), _metal)
	_pipe("ValvePipeSouth", Vector3(-18.6, -6.6, 16), Vector3(-10, -6.6, 16), 0.33, _rust)
	_pipe("ValvePipeNorth", Vector3(18.6, -8.6, -17), Vector3(10, -8.6, -17), 0.33, _rust)
	for pos in [Vector3(-10, -6, 16), Vector3(10, -8, -17)]:
		_pipe("ValveRiser", pos + Vector3(0, -0.6, 0), pos + Vector3(0, 1.0, 0), 0.25, _rust)
		_box("SubmergedServicePlate", pos + Vector3(0, 1.9, 0.5), Vector3(1.6, 0.7, 0.08), _metal)
		_lamp(pos + Vector3(0, 1.7, -0.6), Color(0.18, 0.50, 0.47), 0.95, 7.0)
		_bubbles(pos + Vector3(0.8, -1.4, 1.2))
	_label("南  /  S-01", Vector3(-10, -4.1, 16.43), Vector3(0, PI, 0), 0.0035, Color(0.47, 0.73, 0.61))
	_label("北  /  N-02", Vector3(10, -6.1, -16.57), Vector3(0, 0, 0), 0.0035, Color(0.47, 0.73, 0.61))


func _filter_shelter(center: Vector3, side: float, structure_name: String) -> void:
	_box(structure_name + "OuterBaffle", center + Vector3(side * 2.8, 0, 0), Vector3(0.45, 5.4, 7), _dark_concrete, true)
	_box(structure_name + "RearBaffle", center + Vector3(0, 0, side * 3.1), Vector3(5.8, 5.4, 0.45), _dark_concrete, true)
	_box(structure_name + "HalfBaffle", center + Vector3(-side * 2.3, -0.6, side * 1.6), Vector3(0.38, 4.2, 2.8), _dark_concrete, true)
	for z_offset in [-2.4, 0.0, 2.4]:
		_pipe("FilterStrut", center + Vector3(side * 2.5, -2.6, z_offset), center + Vector3(side * 2.5, 2.9, z_offset), 0.06, _metal)
	# Open roof: the player can rise directly to breathable water above either objective.
	_box("FilterPlatform", center + Vector3(0, -2.8, 0), Vector3(5.5, 0.3, 6.8), _metal, true)
	for z_offset in [-2.8, 2.8]:
		_box("FilterLip", center + Vector3(0, -2.55, z_offset), Vector3(5.5, 0.14, 0.14), _rust)


func _make_lighting() -> void:
	for side in [-1.0, 1.0]:
		for z in [-34.0, -10.0, 14.0, 38.0]:
			_box("FluorescentHousing", Vector3(side * 16.0, 11.1, z), Vector3(0.44, 0.18, 3.2), _metal)
			_box("FluorescentTube", Vector3(side * 16.0, 10.97, z), Vector3(0.18, 0.09, 2.95), _cyan_emission)
			_pipe("LampChain", Vector3(side * 16, 11.2, z - 1.1), Vector3(side * 16, 21.6, z - 1.1), 0.019, _metal)
			var light := _lamp(Vector3(side * 16.0, 10.7, z), Color(0.42, 0.66, 0.68), 3.1, 22.0)
			light.omni_attenuation = 1.25
			light.set_meta("base_energy", 3.1)
			_pulse_lights.append(light)
	for z in [-35.0, 35.0]:
		var spot := SpotLight3D.new()
		spot.name = "ShadowCastingPoolLight"
		spot.position = Vector3(0, 12, z)
		spot.rotation_degrees.x = -90.0
		spot.light_color = Color(0.51, 0.67, 0.68)
		spot.light_energy = 3.6
		spot.spot_range = 31.0
		spot.spot_angle = 62.0
		spot.spot_attenuation = 1.0
		spot.shadow_enabled = true
		spot.shadow_blur = 1.8
		add_child(spot)
		_box("CentralPoolLight", Vector3(0, 12.2, z), Vector3(1.2, 0.15, 1.2), _cyan_emission)
	var start_light := _lamp(Vector3(-22.5, 4.4, 37), Color(0.70, 0.54, 0.33), 2.2, 13.0)
	start_light.shadow_enabled = true
	start_light.shadow_blur = 1.6
	_lamp(Vector3(0, 3.6, -44.8), Color(0.24, 0.72, 0.51), 1.8, 10.0)
	_box("ExitLight", Vector3(0, 4.0, -46.5), Vector3(1.6, 0.18, 0.12), _green_emission)
	# The low shelf lights are useful navigation cues under water, not flat global illumination.
	for pos in [Vector3(-17.5, -9.5, 24), Vector3(17.5, -10.5, -25), Vector3(0, -12.0, 36)]:
		_box("SubmergedBulkheadLight", pos, Vector3(0.25, 0.16, 0.34), _cyan_emission)
		_lamp(pos + Vector3.UP * 0.15, Color(0.14, 0.43, 0.44), 1.1, 9.0)


func _make_signage() -> void:
	_label("第 七 蓄 水 厅", Vector3(0, 11.0, 46.65), Vector3(0, PI, 0), 0.012, Color(0.45, 0.57, 0.54))
	_label("RESERVOIR 07  ·  MAXIMUM DEPTH 13 M", Vector3(0, 9.2, 46.62), Vector3(0, PI, 0), 0.0042, Color(0.39, 0.52, 0.49))
	_label("应 急 出 口\nEMERGENCY EGRESS", Vector3(0, 4.8, -46.64), Vector3.ZERO, 0.0045, Color(0.42, 0.78, 0.60))
	_label("通道塌陷\n从池梯上岸", Vector3(21.5, 2.45, 7.3), Vector3.ZERO, 0.0035, Color(0.77, 0.57, 0.22))
	_label("禁止奔跑\n声响可传播至水下", Vector3(-23.69, 2.4, 32), Vector3(0, PI * 0.5, 0), 0.0033, Color(0.61, 0.66, 0.54))
	_label("深 水\n13 M", Vector3(-23.68, 2.4, 6), Vector3(0, PI * 0.5, 0), 0.006, Color(0.46, 0.61, 0.57))
	for z in [-34.0, -10.0, 14.0, 38.0]:
		_label("07 / %02d" % int((z + 42.0) / 4.0), Vector3(23.69, 5.2, z), Vector3(0, -PI * 0.5, 0), 0.005, Color(0.39, 0.49, 0.45))
	# Distressed paint strips at the tide line emphasize the pool's absurd depth.
	for side in [-1.0, 1.0]:
		for depth in [-2.0, -5.0, -8.0, -11.0]:
			_label("%02d m" % int(-depth), Vector3(side * 18.97, depth, 35.0), Vector3(0, -side * PI * 0.5, 0), 0.004, Color(0.39, 0.53, 0.48))


func _make_surface_debris() -> void:
	var stains := _plain(Color(0.085, 0.13, 0.10), 0.94)
	var positions: Array[Vector3] = [Vector3(-17.7, 0.04, 30), Vector3(16.9, 0.04, 8.1), Vector3(-15.8, 0.04, -35)]
	for i in range(positions.size()):
		var debris := Node3D.new()
		debris.name = "FloatingDebris"
		debris.position = positions[i]
		debris.rotation.y = float(i) * 1.1
		add_child(debris)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.7, 0.04, 0.3)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = stains
		debris.add_child(instance)
		_floaters.append(debris)


func _batch_static_boxes() -> void:
	# Local groups preserve Compatibility's per-object light selection and useful culling.
	# Large shell slabs stay separate. Moving debris and non-box meshes are excluded.
	var groups: Dictionary[String, Array] = {}
	for child in get_children():
		var instance := child as MeshInstance3D
		if instance == null or not instance.mesh is BoxMesh:
			continue
		var box := instance.mesh as BoxMesh
		if maxf(box.size.x, maxf(box.size.y, box.size.z)) > 12.0:
			continue
		var cell := Vector3i(floori(instance.position.x / 10.0), floori(instance.position.y / 8.0), floori(instance.position.z / 12.0))
		var key := "%d/%d/%s" % [instance.material_override.get_instance_id(), instance.cast_shadow, cell]
		if not groups.has(key):
			var members: Array[MeshInstance3D] = []
			groups[key] = members
		groups[key].append(instance)
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	for key in groups:
		var members: Array[MeshInstance3D] = groups[key]
		if members.size() < 3:
			continue
		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = unit_box
		multi_mesh.instance_count = members.size()
		for i in range(members.size()):
			var source := members[i]
			var size_value := (source.mesh as BoxMesh).size
			multi_mesh.set_instance_transform(i, source.transform * Transform3D(Basis.from_scale(size_value), Vector3.ZERO))
			for descendant in source.get_children():
				if descendant is StaticBody3D or descendant is OccluderInstance3D:
					descendant.reparent(self, true)
			# Rendering alone is replaced; the original collision shape and transform survive.
			source.queue_free()
		var batch := MultiMeshInstance3D.new()
		batch.name = "StaticBoxBatch"
		batch.multimesh = multi_mesh
		batch.material_override = members[0].material_override
		batch.cast_shadow = members[0].cast_shadow
		add_child(batch)


func _bubbles(pos: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.name = "FilterLeakBubbles"
	particles.position = pos
	particles.amount = 18
	particles.lifetime = 7.0
	particles.preprocess = 6.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.28
	particles.direction = Vector3.UP
	particles.spread = 8.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.23
	particles.initial_velocity_max = 0.51
	particles.scale_amount_min = 0.55
	particles.scale_amount_max = 1.6
	var sphere := SphereMesh.new()
	sphere.radius = 0.023
	sphere.height = 0.046
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _metal
	particles.mesh = sphere
	add_child(particles)


func _box(node_name: String, pos: Vector3, size_value: Vector3, material: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size_value
		_collision(instance, shape)
		_occlude_static_box(instance, size_value)
	return instance


func _occlude_static_box(instance: MeshInstance3D, size_value: Vector3) -> void:
	var quad := QuadOccluder3D.new()
	var angles := Vector3.ZERO
	if size_value.x <= 0.9 and size_value.y >= 4.0 and size_value.z >= 8.0:
		quad.size = Vector2(size_value.z, size_value.y)
		angles.y = PI * 0.5
	elif size_value.z <= 0.9 and size_value.y >= 4.0 and size_value.x >= 8.0:
		quad.size = Vector2(size_value.x, size_value.y)
	elif size_value.y <= 1.5 and size_value.x >= 8.0 and size_value.z >= 8.0:
		quad.size = Vector2(size_value.x, size_value.z)
		angles.x = -PI * 0.5
	else:
		return
	var occluder := OccluderInstance3D.new()
	occluder.name = "ArchitectureOccluder"
	occluder.occluder = quad
	occluder.rotation = angles
	instance.add_child(occluder)


func _beam(node_name: String, a: Vector3, b: Vector3, width: float, height: float, material: Material, solid: bool = false) -> MeshInstance3D:
	var instance := _box(node_name, (a + b) * 0.5, Vector3(width, height, a.distance_to(b)), material, solid)
	instance.look_at(b, Vector3.UP)
	return instance


func _pipe(node_name: String, a: Vector3, b: Vector3, radius: float, material: Material, solid: bool = false) -> MeshInstance3D:
	var length_value := a.distance_to(b)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length_value
	mesh.radial_segments = 12
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = (a + b) * 0.5
	instance.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	add_child(instance)
	if solid:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = length_value
		_collision(instance, shape)
	return instance


func _collision(parent_node: Node3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	var surface := "concrete"
	if parent_node is MeshInstance3D:
		var material := (parent_node as MeshInstance3D).material_override
		if material == _metal or material == _rust:
			surface = "metal"
		elif material == _tile or material == _pool_tile:
			surface = "dry_tile"
			for water_bounds: Rect2 in water_regions:
				if water_bounds.grow(2.0).has_point(Vector2(parent_node.position.x, parent_node.position.z)):
					surface = "wet_tile"
					break
	body.set_meta("audio_surface", surface)
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent_node.add_child(body)


func _lamp(pos: Vector3, color: Color, energy: float, range_value: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "MaintenanceLight"
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.omni_attenuation = 1.45
	light.shadow_enabled = false
	add_child(light)
	return light


func _label(text_value: String, pos: Vector3, angles: Vector3, pixel_value: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = "EnvironmentalSign"
	label.text = text_value
	label.font = _font
	label.font_size = 72
	label.pixel_size = pixel_value
	label.position = pos
	label.rotation = angles
	label.modulate = color
	label.outline_modulate = Color(0.02, 0.05, 0.05)
	label.outline_size = 3
	label.shaded = false
	label.no_depth_test = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)
	return label
