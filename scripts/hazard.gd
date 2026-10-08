class_name WaterhouseHazard
extends CharacterBody3D
## Three native organic creatures: canal hunter, fixed needle-mouth and jelly colony.
## They share hearing/raycast plumbing, while their attacks and movement differ.

signal threat_changed(amount: float)
signal attack_started
signal omen(position: Vector3, strength: float)

enum State { DORMANT, PATROL, INVESTIGATE, SEARCH, CHASE, RETREAT }
var species: String = "hunter"
var world: Node3D
var player: CharacterBody3D
var enabled: bool = false
var pressure: float = 0.0
var awareness: float = 0.0
var state: State = State.PATROL
var home := Vector3.ZERO
var patrol_points: Array[Vector3] = []
var detection_multiplier: float = 1.0
var speed_multiplier: float = 1.0
var attack_damage: float = 100.0
var attack_windup: float = 0.9
var quiet_multiplier: float = 1.0
var _graph := AStar3D.new()
var _shape := SphereShape3D.new()
var _route := PackedVector3Array()
var _route_index: int = 0
var _patrol_index: int = 1
var _age: float = 0.0
var _lost: float = 0.0
var _noise_left: float = 0.0
var _cooldown: float = 0.0
var _windup: float = -1.0
var _sense_clock: float = 0.0
var _search_left: float = 0.0
var _pursuit_left: float = 0.0
var _quiet: float = 0.0
var _last_seen := Vector3.ZERO
var _seen: bool = false
var _colony: Array[Node3D] = []
var _mouth: Node3D
var _visual: Node3D
var _ready_graph: bool = false


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = 16
	collision_mask = 1
	_shape.radius = 1.35 if species == "drifter" else 1.0
	var body_shape := CollisionShape3D.new()
	body_shape.shape = _shape
	add_child(body_shape)
	_visual = Node3D.new()
	add_child(_visual)
	_build_body()
	reset_creature()
	_prepare_graph.call_deferred()


func _skin(color: Color, phase: float = 0.0, jelly: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/jelly_skin.gdshader" if jelly else "res://shaders/hazard_skin.gdshader")
	material.set_shader_parameter("skin_color", color)
	material.set_shader_parameter("phase", phase)
	material.set_shader_parameter("flexible", 1.0)
	material.set_shader_parameter("translucent", 1.0 if jelly else 0.0)
	material.set_shader_parameter("glow", 0.38 if jelly else 0.02)
	return material


func _mesh(mesh: Mesh, pos: Vector3, scale_value: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.scale = scale_value
	part.material_override = material
	part.extra_cull_margin = 0.5
	parent.add_child(part)
	return part


func _tube(length_value: float, radius: float, phase: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 24
	var sides := 10
	for segment in steps:
		for side in sides:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]:
				var t: float = float(segment + corner.x) / float(steps)
				var angle: float = float(side + corner.y) / float(sides) * TAU
				var width: float = radius * pow(1.0 - t, 0.75) + 0.008
				var center := Vector3(sin(t * 5.0 + phase) * t * 0.4, -t * t * length_value, t * 0.4)
				surface.set_uv(Vector2(t, angle / TAU))
				surface.add_vertex(center + Vector3(cos(angle) * width, 0, sin(angle) * width))
	surface.generate_normals()
	return surface.commit()


func _organic_body(kind: String) -> ArrayMesh:
	var profile: Array[Vector2] = []
	profile.assign([Vector2(-2.6, 0.69), Vector2(-2.1, 0.82), Vector2(-1.2, 0.86), Vector2(0, 0.65), Vector2(1.4, 0.47), Vector2(2.4, 0.29), Vector2(3.8, 0.03)] if kind == "hunter" else [Vector2(-2.15, 0.83), Vector2(-1.7, 1.14), Vector2(-0.7, 1.18), Vector2(0.3, 0.92), Vector2(1.3, 0.42), Vector2(1.9, 0.04)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 60:
		for side in 32:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]:
				var t: float = float(ring + corner.x) / 60.0
				var z: float = lerpf(profile[0].x, profile[-1].x, t)
				var radius := profile[-1].y
				for segment in profile.size() - 1:
					if z <= profile[segment + 1].x:
						var f := smoothstep(profile[segment].x, profile[segment + 1].x, z)
						radius = lerpf(profile[segment].y, profile[segment + 1].y, f)
						break
				var angle: float = float(side + corner.y) * TAU / 32.0
				var folds: float = 1.0 + sin(z * 11.0 + angle * 3.0) * 0.023 + sin(angle * 9.0 - z * 4.0) * 0.018
				var vertical: float = 0.78 if kind == "hunter" else 0.54
				var keel: float = maxf(0.0, sin(angle)) * sin(t * PI) * 0.18
				surface.set_uv(Vector2(t, angle / TAU))
				var point := Vector3(cos(angle) * radius * folds, sin(angle) * radius * vertical * folds + keel, z)
				for sign_value: float in [-1.0, 1.0]:
					var eye_center := Vector3(sign_value * (0.67 if kind == "hunter" else 0.89), 0.23, -1.95 if kind == "hunter" else -1.65)
					var socket_depth: float = exp(-point.distance_squared_to(eye_center) / 0.032) * 0.105
					point.x -= sign_value * socket_depth
					point.y -= socket_depth * 0.25
				surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()


func _lip_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 48:
		for side in 8:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]:
				var angle: float = float(ring + corner.x) * TAU / 48.0
				var tube: float = float(side + corner.y) * TAU / 8.0
				var irregular: float = sin(angle * 7.0) * 0.015 + sin(angle * 3.0) * 0.026
				surface.add_vertex(Vector3(cos(angle) * (0.65 + cos(tube) * 0.075 + irregular), sin(angle) * (0.43 + cos(tube) * 0.075 + irregular), sin(tube) * 0.08))
	surface.generate_normals()
	return surface.commit()


func _bell_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 16:
		for side in 28:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]:
				var t: float = float(ring + corner.x) / 16.0 * PI / 2.0
				var angle: float = float(side + corner.y) * TAU / 28.0
				var radius := sin(t) * (0.62 + sin(angle * 10.0) * 0.017)
				surface.add_vertex(Vector3(cos(angle) * radius, cos(t) * 0.37 - 0.16, sin(angle) * radius))
	surface.generate_normals()
	return surface.commit()


func _build_body() -> void:
	var skin := _skin(Color(0.12, 0.24, 0.22) if species == "hunter" else Color(0.23, 0.19, 0.14))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 36
	sphere.rings = 20
	if species == "drifter":
		for i in 5:
			var bell := Node3D.new()
			bell.position = Vector3(sin(float(i) * 2.4) * 1.15, float(i % 2) * 0.35, cos(float(i) * 2.4) * 0.8)
			bell.set_meta("rest", bell.position)
			_visual.add_child(bell)
			_colony.append(bell)
			var jelly_skin := _skin(Color(0.20, 0.46, 0.43), float(i), true)
			_mesh(_bell_mesh(), Vector3.ZERO, Vector3.ONE, jelly_skin, bell)
			for j in 5:
				var a: float = float(j) * TAU / 5.0
				_mesh(_tube(1.9 + float(j) * 0.13, 0.045, a), Vector3(cos(a) * 0.35, -0.18, sin(a) * 0.35), Vector3.ONE, jelly_skin, bell)
		return
	_mesh(_organic_body(species), Vector3.ZERO, Vector3.ONE, skin, _visual)
	if species == "hunter":
		for sign_value: float in [-1.0, 1.0]:
			var fin := _mesh(_tube(2.2, 0.3, sign_value), Vector3(sign_value * 0.6, -0.2, 0.1), Vector3.ONE, skin, _visual)
			fin.rotation.z = sign_value * 0.78
	else:
		for i in 6:
			var angle: float = float(i) * TAU / 6.0
			var tendril := _mesh(_tube(3.0, 0.14, angle), Vector3(cos(angle) * 0.65, sin(angle) * 0.35, 0.6), Vector3.ONE, skin, _visual)
			tendril.rotation.z = angle
	_mouth = Node3D.new()
	_mouth.position = Vector3(0, -0.04, -2.63 if species == "hunter" else -2.18)
	_visual.add_child(_mouth)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.012, 0.018, 0.017)
	_mesh(sphere, Vector3(0, 0, 0.48), Vector3(0.60, 0.39, 0.20), dark, _mouth)
	_mesh(_lip_mesh(), Vector3(0, 0, 0.04), Vector3.ONE, skin, _mouth)
	var tooth_material := StandardMaterial3D.new()
	tooth_material.albedo_color = Color(0.53, 0.59, 0.49)
	tooth_material.roughness = 0.38
	for i in 40:
		var angle: float = float(i % 20) * TAU / 20.0 + sin(float(i % 20) * 2.41) * 0.045 + (0.08 if i >= 20 else 0.0)
		var tooth := CylinderMesh.new()
		tooth.top_radius = 0.006
		tooth.bottom_radius = 0.023 + absf(sin(float(i) * 1.71)) * 0.018
		tooth.height = (0.24 if i < 20 else 0.17) + absf(sin(float(i) * 2.13)) * 0.15
		var piece := _mesh(tooth, Vector3(cos(angle) * (0.55 + sin(float(i) * 2.0) * 0.018), sin(angle) * 0.36, 0.10 if i >= 20 else 0.02), Vector3.ONE, tooth_material, _mouth)
		piece.rotation.z = angle + PI / 2.0 + sin(float(i) * 1.7) * 0.18
		piece.rotation.x = sin(float(i) * 0.7) * 0.18
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(0.71, 0.64, 0.39)
	eye_material.roughness = 0.2
	var iris := StandardMaterial3D.new()
	iris.albedo_color = Color(0.018, 0.026, 0.021)
	iris.roughness = 0.17
	for side: float in [-1.0, 1.0]:
		var center := Vector3(side * (0.67 if species == "hunter" else 0.89), 0.23, -1.95 if species == "hunter" else -1.65)
		_mesh(sphere, center, Vector3.ONE * 0.11, eye_material, _visual)
		_mesh(sphere, center + Vector3(side * 0.035, 0, -0.09), Vector3(0.038, 0.065, 0.021), iris, _visual)


func _prepare_graph() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_graph.clear()
	if patrol_points.size() < 2:
		return
	var points: Array[Vector3] = []
	for i in patrol_points.size():
		var a := patrol_points[i]
		var b := patrol_points[(i + 1) % patrol_points.size()]
		var count := maxi(1, ceili(a.distance_to(b) / 8.0))
		for step in count:
			points.append(a.lerp(b, float(step) / float(count)))
	for i in points.size():
		_graph.add_point(i, points[i])
	for i in points.size():
		var next := (i + 1) % points.size()
		if _clear_motion(points[i], points[next]):
			_graph.connect_points(i, next)
	_ready_graph = _graph.get_point_count() > 0


func _clear_motion(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = 1
	query.margin = 0.01
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.cast_motion(query)
	return result[0] > 0.99


func apply_difficulty(config: Dictionary) -> void:
	detection_multiplier = clampf(float(config.get("detection_multiplier", 1.0)), 0.4, 2.0)
	speed_multiplier = clampf(float(config.get("speed_multiplier", 1.0)), 0.5, 1.5)
	attack_damage = clampf(float(config.get("attack_damage", 100.0)), 10.0, 100.0)
	attack_windup = clampf(float(config.get("attack_windup", 0.9)), 0.5, 2.0)
	quiet_multiplier = clampf(float(config.get("quiet_multiplier", 1.0)), 0.5, 2.0)


func reset_creature() -> void:
	global_position = home
	velocity = Vector3.ZERO
	state = State.PATROL if species in ["hunter", "drifter"] else State.DORMANT
	awareness = 0.0
	_age = 0.0
	_lost = 0.0
	_cooldown = 0.0
	_windup = -1.0
	_quiet = 0.0
	_noise_left = 0.0
	_seen = false
	_sense_clock = 0.0
	_search_left = 0.0
	_pursuit_left = 0.0
	_last_seen = home
	_route.clear()
	_patrol_index = 1
	threat_changed.emit(0.0)


func hear_noise(pos: Vector3, loudness: float) -> void:
	if not enabled or species == "drifter" or _quiet > 0.0 or not pos.is_finite() or not is_finite(loudness) or loudness <= 0.0:
		return
	var hearing_range: float = (12.0 + clampf(loudness, 0.0, 2.0) * 23.0) * detection_multiplier
	var query := PhysicsRayQueryParameters3D.create(global_position, pos, 1)
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		hearing_range *= 0.22
	if pos.distance_to(global_position) > hearing_range:
		return
	_last_seen = pos
	_last_seen.y = clampf(pos.y, -4.6, -1.8)
	_noise_left = 9.0
	if species == "hunter":
		if state != State.CHASE:
			state = State.INVESTIGATE
		_plan(_last_seen)
	else:
		omen.emit(global_position, 0.7)


func _visible_player() -> bool:
	if player == null or not bool(player.get("in_water")):
		return false
	var target: Vector3 = (player.get("camera") as Camera3D).global_position
	var range_value: float = (15.0 if bool(player.get("light_on")) else 7.5) * detection_multiplier
	if target.distance_to(global_position) > range_value:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position, target, 1 | 2)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player


func _plan(goal: Vector3) -> void:
	_route.clear()
	_route_index = 0
	if _clear_motion(global_position, goal):
		_route.append(goal)
	elif _ready_graph:
		var start := _graph.get_closest_point(global_position)
		var finish := _graph.get_closest_point(goal)
		_route = _graph.get_point_path(start, finish)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_age += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_quiet = maxf(0.0, _quiet - delta)
	_noise_left = maxf(0.0, _noise_left - delta)
	_sense_clock -= delta
	if _sense_clock <= 0.0:
		_seen = _visible_player()
		_sense_clock = 0.18
		if _seen:
			_last_seen = player.global_position
			_last_seen.y = clampf(_last_seen.y + 0.8, -4.6, -1.8)
			_lost = 0.0
			if species == "hunter" and _quiet <= 0.0:
				if state != State.CHASE:
					_pursuit_left = 20.0
				state = State.CHASE
				_plan(_last_seen)
		else:
			_lost += 0.18
	if species == "drifter":
		_update_colony(delta)
		return
	var distance: float = INF if player == null else global_position.distance_to(player.global_position + Vector3.UP * 0.6)
	awareness = move_toward(awareness, 1.0 if _seen and _quiet <= 0.0 else 0.0, delta * 0.9)
	threat_changed.emit(awareness)
	if _mouth != null:
		_mouth.scale.y = lerpf(_mouth.scale.y, 1.7 if _windup >= 0.0 else 1.0, delta * 4.0)
	if _windup >= 0.0:
		_windup -= delta
		if _windup <= 0.0:
			if _seen and distance < 3.8 and _visible_player():
				player.call("take_damage", attack_damage, "水道中的针齿在你身边合拢了。")
			_windup = -1.0
			_cooldown = 4.0
			_quiet = 8.0 * quiet_multiplier
			state = State.RETREAT
		return
	if _seen and distance < 3.5 and _cooldown <= 0.0 and _quiet <= 0.0:
		_windup = attack_windup * (1.35 if species == "lurker" else 1.0)
		attack_started.emit()
		omen.emit(global_position, 1.0)
		return
	if species == "lurker":
		if _seen:
			var direction := _last_seen - global_position
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 1.1)
		return
	if state == State.CHASE:
		_pursuit_left -= delta
		if _pursuit_left <= 0.0:
			state = State.RETREAT
			_quiet = 12.0 * quiet_multiplier
			_route.clear()
	if state == State.CHASE and _lost > 2.2:
		state = State.SEARCH
		_search_left = 8.0
	if state == State.SEARCH:
		_search_left -= delta
		if _search_left <= 0.0:
			state = State.RETREAT
			_quiet = 12.0 * quiet_multiplier
	if state == State.INVESTIGATE and _noise_left <= 0.0:
		state = State.SEARCH
		_search_left = 6.0
	if state == State.RETREAT and _quiet <= 0.0:
		state = State.PATROL
	if _route_index >= _route.size() and not patrol_points.is_empty():
		var next := patrol_points[_patrol_index % patrol_points.size()]
		_patrol_index += 1
		_plan(next)
	if _route_index < _route.size():
		var next := _route[_route_index]
		if global_position.distance_to(next) < 0.6:
			_route_index += 1
		else:
			var direction := (next - global_position).normalized()
			var speed: float = (4.7 if state == State.CHASE else 2.3) * speed_multiplier
			velocity = direction * speed
			move_and_slide()
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 2.5)
			if get_slide_collision_count() > 0:
				_route.clear()


func _update_colony(delta: float) -> void:
	var desired := home + Vector3(sin(_age * 0.15) * 1.5, sin(_age * 0.2) * 0.25, 0)
	move_and_collide((desired - global_position) * minf(1.0, delta * 0.5))
	for i in _colony.size():
		var bell := _colony[i]
		var rest: Vector3 = bell.get_meta("rest")
		bell.position = rest + Vector3(0, sin(_age * 1.0 + float(i)) * 0.15, 0)
	if player != null and bool(player.get("in_water")) and _visible_player() and global_position.distance_to(player.global_position + Vector3.UP) < 3.3:
		awareness = 0.9
		if _cooldown <= 0.0:
			omen.emit(global_position, 0.6)
			player.call("take_damage", attack_damage * 0.18, "漂浮群落的丝状触须夺走了你的呼吸。")
			_cooldown = 1.2
	else:
		awareness = move_toward(awareness, 0.0, delta)
	threat_changed.emit(awareness)


func state_name() -> String:
	return ["潜伏", "巡游", "调查", "搜寻", "追逐", "退去"][state]
