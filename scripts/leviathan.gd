class_name WaterhouseCreature
extends CharacterBody3D
## The head is the physical body. The skinned body follows its traversed route.
## A submerged 3D graph avoids the planar assumptions of a walking NavMesh.

signal threat_changed(amount: float)
signal attack_started
signal omen(position: Vector3, strength: float)

enum State { DORMANT, PATROL, INVESTIGATE, SEARCH, CHASE, RETREAT }

const BODY_SCALE := 22.0
const MODEL_HEAD_Z := 0.49133
const MODEL_AXIS_Y := 0.075
const BODY_RADIUS := 1.7
const BODY_LENGTH := 21.62
const WORLD_MASK := 1
const PLAYER_MASK := 2
const GRID_STEP := 4.0
const SEARCH_SECONDS := 13.0
const ATTACK_WINDUP := 0.9

@export var patrol_speed: float = 2.25
@export var pursuit_speed: float = 5.15

var player: CharacterBody3D
var enabled: bool = false
var pressure: float = 0.0
var state: State = State.DORMANT
var awareness: float = 0.0
var detection_multiplier: float = 1.0
var speed_multiplier: float = 1.0
var attack_damage: float = 100.0
var attack_windup: float = ATTACK_WINDUP
var quiet_multiplier: float = 1.0

var _rng := RandomNumberGenerator.new()
var _graph := AStar3D.new()
var _probe := SphereShape3D.new()
var _grid_ids: Dictionary[Vector3i, int] = {}
var _path := PackedVector3Array()
var _path_index: int = 0
var _route_goal := Vector3.ZERO
var _goal := Vector3(10.0, -8.0, 30.0)
var _heading := Vector3.FORWARD
var _last_seen := Vector3.ZERO
var _last_saw_player: bool = false
var _player_properties: Dictionary[StringName, bool] = {}
var _known_player_id: int = 0
var _sense_clock: float = 0.0
var _path_clock: float = 0.0
var _state_age: float = 0.0
var _quiet_left: float = 52.0
var _lost_seconds: float = 0.0
var _attack_left: float = -1.0
var _attack_cooldown: float = 0.0
var _noise_cooldown: float = 0.0
var _omen_clock: float = 2.0
var _threat_clock: float = 0.0
var _blocked_seconds: float = 0.0
var _patrol_visits: int = 0
var _history: Array[Vector3] = []
var _history_distance: float = 0.0
var _skeleton: Skeleton3D
var _bone_rest: Array[Transform3D] = []
var _jaw_bones: Array[int] = []
var _skin_materials: Array[ShaderMaterial] = []
var _navigation_ready: bool = false

@onready var _visual: Node3D = $Visual


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	safe_margin = maxf(safe_margin, 0.04)
	_rng.randomize()
	_probe.radius = BODY_RADIUS
	_configure_model()
	reset_creature()
	_build_navigation.call_deferred()


func _configure_model() -> void:
	_visual.scale = Vector3.ONE * BODY_SCALE
	_visual.rotation.y = PI
	_visual.position = Vector3(0.0, -MODEL_AXIS_Y * BODY_SCALE, MODEL_HEAD_Z * BODY_SCALE)
	for candidate in _visual.find_children("*", "Skeleton3D", true, false):
		_skeleton = candidate as Skeleton3D
		break
	for candidate in _visual.find_children("*", "AnimationPlayer", true, false):
		# Imported preset is a march, unsuitable for this animal's waterborne gait.
		# Pose the existing native skeleton along the animal's travelled spine instead.
		(candidate as AnimationPlayer).active = false
	if _skeleton != null:
		for bone in _skeleton.get_bone_count():
			var rest_world := _skeleton.global_transform * _skeleton.get_bone_global_rest(bone)
			_bone_rest.append(global_transform.affine_inverse() * rest_world)
			if _skeleton.get_bone_name(bone) in ["bone_18", "bone_19", "bone_20", "bone_21"]:
				_jaw_bones.append(bone)
	var skin_shader := load("res://shaders/leviathan_skin.gdshader") as Shader
	for candidate in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_instance.extra_cull_margin = BODY_LENGTH
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var skin := ShaderMaterial.new()
			skin.shader = skin_shader
			skin.set_shader_parameter("skin_texture", original.albedo_texture)
			skin.set_shader_parameter("skin_normal", original.normal_texture)
			mesh_instance.set_surface_override_material(surface, skin)
			_skin_materials.append(skin)


func reset_creature() -> void:
	state = State.DORMANT
	awareness = 0.0
	_state_age = 0.0
	_quiet_left = _rng.randf_range(44.0, 65.0) * quiet_multiplier
	_lost_seconds = 0.0
	_attack_left = -1.0
	_attack_cooldown = 0.0
	_noise_cooldown = 0.0
	_blocked_seconds = 0.0
	_path_clock = 0.0
	_path.clear()
	global_position = Vector3(10.0, -8.3, 11.0)
	_goal = Vector3(8.0, -8.5, -25.0)
	_heading = Vector3.FORWARD
	velocity = Vector3.ZERO
	_history.clear()
	_history_distance = 0.0
	for sample in 100:
		_history.append(global_position - _heading * float(sample) * 0.3)
	if is_node_ready():
		_pose_body()
	threat_changed.emit(0.0)


func state_name() -> String:
	return ["潜伏", "巡游", "调查", "搜寻", "追击", "退去"][state]


func apply_difficulty(config: Dictionary) -> void:
	detection_multiplier = _difficulty_value(config, "detection_multiplier", 1.0, 0.3, 2.0)
	speed_multiplier = _difficulty_value(config, "speed_multiplier", 1.0, 0.4, 1.6)
	attack_damage = _difficulty_value(config, "attack_damage", 100.0, 1.0, 100.0)
	attack_windup = _difficulty_value(config, "attack_windup", ATTACK_WINDUP, 0.35, 2.5)
	quiet_multiplier = _difficulty_value(config, "quiet_multiplier", 1.0, 0.5, 2.0)


func _difficulty_value(config: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	var value: Variant = config.get(key, fallback)
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), low, high)


func hear_noise(position: Vector3, loudness: float) -> void:
	if not enabled or loudness <= 0.0 or _noise_cooldown > 0.0 or state == State.RETREAT:
		return
	var intensity := clampf(loudness, 0.0, 1.5)
	var hearing_range := (9.0 + intensity * 27.0 + clampf(pressure, 0.0, 1.0) * 6.0) * detection_multiplier
	if global_position.distance_to(position) > hearing_range:
		return
	_noise_cooldown = 0.45
	if state == State.CHASE:
		# A loud decoy can redirect a hunter after line of sight is broken.
		if _last_saw_player or intensity < 0.85:
			return
	_last_seen = _clamp_water_point(position)
	_last_seen.y = minf(_last_seen.y, -2.6)
	_goal = _last_seen
	awareness = minf(0.55, awareness + intensity * 0.12)
	_set_state(State.INVESTIGATE)


func stun_or_redirect(position: Vector3, seconds: float = 5.0) -> void:
	if not enabled:
		return
	_attack_left = -1.0
	_attack_cooldown = maxf(_attack_cooldown, seconds)
	_goal = _clamp_water_point(position)
	_last_seen = _goal
	awareness = minf(awareness, 0.35)
	_set_state(State.INVESTIGATE)


func _physics_process(delta: float) -> void:
	if not enabled:
		velocity = Vector3.ZERO
		return
	_state_age += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_noise_cooldown = maxf(0.0, _noise_cooldown - delta)
	_sense_clock -= delta
	if _sense_clock <= 0.0:
		_sense_player(0.16)
		_sense_clock = 0.16
	_update_state(delta)
	_update_movement(delta)
	_update_attack(delta)
	_record_history()
	_pose_body()
	_update_omens(delta)


func _refresh_player_properties() -> void:
	if not is_instance_valid(player):
		_known_player_id = 0
		_player_properties.clear()
		return
	if player.get_instance_id() == _known_player_id:
		return
	_known_player_id = player.get_instance_id()
	_player_properties.clear()
	for property in player.get_property_list():
		_player_properties[StringName(property["name"])] = true


func _player_boolean(property_name: StringName, fallback: bool = false) -> bool:
	if _player_properties.has(property_name):
		return bool(player.get(property_name))
	return fallback


func _player_is_in_water() -> bool:
	return is_instance_valid(player) and _player_boolean(&"in_water", player.global_position.y < -0.1)


func _player_position() -> Vector3:
	var target := player.global_position + Vector3.UP * 0.75
	if _player_properties.has(&"camera"):
		var camera := player.get("camera") as Camera3D
		if camera != null and camera.global_position.y < -0.15:
			target = camera.global_position
	if _player_is_in_water():
		target.y = minf(target.y, -0.3)
	return target


func _sense_player(delta: float) -> void:
	_refresh_player_properties()
	_last_saw_player = false
	if not is_instance_valid(player) or _player_boolean(&"dead"):
		awareness = maxf(0.0, awareness - delta * 0.2)
		return
	if state == State.RETREAT:
		awareness = maxf(0.0, awareness - delta * 0.18)
		return
	var target := _player_position()
	var distance := global_position.distance_to(target)
	var wet := _player_is_in_water()
	var lamp := _player_boolean(&"light_on")
	var range_limit := 31.0 if lamp else 17.5
	if not wet:
		range_limit = 15.0 if lamp else 8.0
	if state == State.DORMANT:
		range_limit = minf(range_limit, 9.0)
	range_limit *= detection_multiplier
	if distance <= range_limit and _has_line_of_sight(target) and (_heading.dot((target - global_position).normalized()) > -0.22 or distance < 5.0):
		_last_saw_player = true
		_last_seen = _clamp_water_point(target)
		_lost_seconds = 0.0
		var proximity := 1.0 - clampf(distance / range_limit, 0.0, 1.0)
		var gain := (0.22 + proximity * 0.82) * (1.55 if lamp else 1.0)
		awareness = clampf(awareness + delta * gain, 0.0, 1.0 if wet else 0.5)
		if wet and awareness >= 0.67 and _attack_cooldown <= 0.0:
			_set_state(State.CHASE)
		elif not wet and awareness > 0.25 and state in [State.DORMANT, State.PATROL]:
			_goal = _last_seen
			_goal.y = -3.4
			_set_state(State.INVESTIGATE)
	else:
		_lost_seconds += delta
		awareness = maxf(0.0, awareness - delta * (0.09 if state == State.CHASE else 0.12))


func _has_line_of_sight(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, target, WORLD_MASK | PLAYER_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	_state_age = 0.0
	_path_clock = 0.0
	_path.clear()
	if state != State.CHASE:
		_attack_left = -1.0
	if state == State.CHASE:
		omen.emit(Vector3(global_position.x, 0.0, global_position.z), 0.9)
	elif state == State.RETREAT:
		_goal = _choose_roam_point(true)
		_attack_cooldown = maxf(_attack_cooldown, 8.0)
	elif state == State.DORMANT:
		_quiet_left = _rng.randf_range(40.0, 70.0) * quiet_multiplier * lerpf(1.0, 0.65, clampf(pressure, 0.0, 1.0))
		_goal = _choose_roam_point(true)
	elif state == State.PATROL:
		_patrol_visits = 0
		_goal = _choose_roam_point()


func _update_state(delta: float) -> void:
	var reached := global_position.distance_to(_goal) < 2.6
	match state:
		State.DORMANT:
			_quiet_left -= delta
			if reached:
				_goal = _choose_roam_point(true)
			if _quiet_left <= 0.0:
				_set_state(State.PATROL)
		State.PATROL:
			if reached:
				_patrol_visits += 1
				_goal = _choose_roam_point()
			if _state_age > 35.0 or _patrol_visits >= 3:
				_set_state(State.RETREAT)
		State.INVESTIGATE:
			if reached or _state_age > 13.0:
				_set_state(State.SEARCH)
				_goal = _search_point()
		State.SEARCH:
			if reached:
				_goal = _search_point()
			if _state_age > SEARCH_SECONDS:
				_set_state(State.RETREAT)
		State.CHASE:
			if not _player_is_in_water():
				awareness = minf(awareness, 0.4)
				_goal = _last_seen
				_set_state(State.SEARCH)
			elif _last_saw_player:
				_goal = _clamp_water_point(_player_position())
			else:
				_goal = _last_seen
				if _lost_seconds > 4.2:
					_set_state(State.SEARCH)
			if _state_age > 22.0:
				_set_state(State.RETREAT)
		State.RETREAT:
			if reached:
				_goal = _choose_roam_point(true)
			if _state_age > 11.0:
				_set_state(State.DORMANT)


func _clamp_water_point(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, -16.5, 16.5), clampf(point.y, -10.9, -1.8), clampf(point.z, -38.5, 38.5))


func _choose_roam_point(away: bool = false) -> Vector3:
	var target_z := _rng.randf_range(-33.0, 33.0)
	if away and is_instance_valid(player):
		target_z = -31.0 if player.global_position.z > 0.0 else 31.0
	var point := Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-8.8, -4.4), target_z)
	if away:
		point.y = -9.3
	return _nearest_clear_point(point)


func _search_point() -> Vector3:
	var angle := _rng.randf_range(-PI, PI)
	var radius := _rng.randf_range(4.0, 9.0)
	return _nearest_clear_point(_clamp_water_point(_last_seen + Vector3(cos(angle) * radius, -1.0, sin(angle) * radius)))


func _nearest_clear_point(point: Vector3) -> Vector3:
	if _navigation_ready:
		var point_id := _graph.get_closest_point(point)
		if point_id >= 0:
			return _graph.get_point_position(point_id)
	return _clamp_water_point(point)


func _build_navigation() -> void:
	# World geometry is created during ready(), before the first physics tick.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_graph.clear()
	_grid_ids.clear()
	var next_id := 0
	for depth in 4:
		for x in 9:
			for z in 20:
				var point := Vector3(-16.0 + float(x) * GRID_STEP, -2.0 - float(depth) * 3.0, -38.0 + float(z) * GRID_STEP)
				if not _sphere_is_clear(point):
					continue
				_grid_ids[Vector3i(x, depth, z)] = next_id
				_graph.add_point(next_id, point)
				next_id += 1
	var neighbors: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(0, 1, 0)]
	for coordinate in _grid_ids:
		var point_id := _grid_ids[coordinate]
		for offset in neighbors:
			var neighbor := coordinate + offset
			if not _grid_ids.has(neighbor):
				continue
			var neighbor_id := _grid_ids[neighbor]
			if _clear_motion(_graph.get_point_position(point_id), _graph.get_point_position(neighbor_id)):
				_graph.connect_points(point_id, neighbor_id)
	_navigation_ready = _graph.get_point_count() > 0
	_path_clock = 0.0


func _shape_query(point: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = WORLD_MASK
	query.exclude = [get_rid()]
	query.margin = 0.08
	return query


func _sphere_is_clear(point: Vector3) -> bool:
	return get_world_3d().direct_space_state.intersect_shape(_shape_query(point), 1).is_empty()


func _clear_motion(from: Vector3, to: Vector3) -> bool:
	var query := _shape_query(from)
	query.motion = to - from
	var sweep := get_world_3d().direct_space_state.cast_motion(query)
	return sweep[0] > 0.99


func _plan_route() -> void:
	_route_goal = _goal
	_path_index = 0
	_path.clear()
	if _clear_motion(global_position, _goal):
		_path.append(_goal)
		return
	if not _navigation_ready:
		return
	var start := _graph.get_closest_point(global_position)
	var finish := _graph.get_closest_point(_goal)
	if start < 0 or finish < 0:
		return
	_path = _graph.get_point_path(start, finish)
	# Retain the first node if the route to the second crosses an obstacle.
	if _path.size() > 1 and _clear_motion(global_position, _path[1]):
		_path_index = 1
	if not _path.is_empty() and _clear_motion(_path[-1], _goal):
		_path.append(_goal)


func _update_movement(delta: float) -> void:
	_path_clock -= delta
	if _path_clock <= 0.0 or _route_goal.distance_to(_goal) > 3.0:
		_plan_route()
		_path_clock = 1.1 if state == State.CHASE else 2.4
	var target := _goal
	if not _path.is_empty():
		while _path_index < _path.size() - 1 and global_position.distance_to(_path[_path_index]) < 1.4:
			_path_index += 1
		target = _path[_path_index]
	var desired := (target - global_position).normalized()
	if desired.length_squared() < 0.1:
		desired = _heading
	desired = _avoid_obstacle(desired)
	_heading = _heading.slerp(desired, minf(1.0, delta * (2.1 if state == State.CHASE else 1.2))).normalized()
	var speed := patrol_speed
	match state:
		State.DORMANT:
			speed = 1.05
		State.INVESTIGATE:
			speed = 2.8
		State.SEARCH:
			speed = 2.15
		State.CHASE:
			speed = pursuit_speed
		State.RETREAT:
			speed = 3.5
	if _attack_left >= 0.0:
		speed = 0.8
	speed *= speed_multiplier
	velocity = velocity.lerp(_heading * speed, minf(1.0, delta * 2.0))
	var before := global_position
	move_and_slide()
	if global_position.distance_to(before) < delta * 0.25:
		_blocked_seconds += delta
	else:
		_blocked_seconds = maxf(0.0, _blocked_seconds - delta * 2.0)
	if _blocked_seconds > 1.8:
		# A grid route may become obsolete when a moving gate closes.
		_blocked_seconds = 0.0
		_goal = _nearest_clear_point(global_position + Vector3(_rng.randf_range(-7.0, 7.0), -3.0, _rng.randf_range(-7.0, 7.0)))
		_path_clock = 0.0
		if state == State.CHASE:
			_set_state(State.SEARCH)


func _avoid_obstacle(desired: Vector3) -> Vector3:
	var lookahead := 3.5 if state != State.CHASE else 5.0
	if _clear_motion(global_position, global_position + desired * lookahead):
		return desired
	var best := Vector3.ZERO
	var best_score := -10.0
	for angle in [-1.15, -0.65, 0.65, 1.15, PI]:
		var candidate: Vector3 = desired.rotated(Vector3.UP, float(angle)).normalized()
		if _clear_motion(global_position, global_position + candidate * lookahead):
			var score := candidate.dot(desired) + candidate.dot(_heading) * 0.25
			if score > best_score:
				best = candidate
				best_score = score
	for vertical in [-0.65, 0.65]:
		var candidate: Vector3 = (desired + Vector3.UP * float(vertical)).normalized()
		if _clear_motion(global_position, global_position + candidate * lookahead) and candidate.dot(desired) > best_score:
			best = candidate
			best_score = candidate.dot(desired)
	return best if best.length_squared() > 0.1 else -_heading


func _update_attack(delta: float) -> void:
	if state != State.CHASE or not _player_is_in_water():
		_attack_left = -1.0
		return
	var target := _player_position()
	var distance := global_position.distance_to(target)
	if _attack_left < 0.0:
		if distance < 3.1 and _attack_cooldown <= 0.0 and _has_line_of_sight(target):
			_attack_left = attack_windup
			attack_started.emit()
		return
	_attack_left -= delta
	if _attack_left <= 0.0:
		if distance < 3.5 and _has_line_of_sight(target) and player.has_method("take_damage"):
			player.call("take_damage", attack_damage, "水下的巨影吞没了你。")
		_attack_left = -1.0
		_set_state(State.RETREAT)


func _record_history() -> void:
	if _history.is_empty():
		_history.push_front(global_position)
		return
	_history_distance += global_position.distance_to(_history[0])
	_history[0] = global_position
	if _history_distance >= 0.26:
		_history.push_front(global_position)
		_history_distance = 0.0
		while _history.size() > 170:
			_history.pop_back()


func _spine_sample(distance: float) -> Vector3:
	var remaining := maxf(distance, 0.0)
	for sample in range(1, _history.size()):
		var span := _history[sample - 1].distance_to(_history[sample])
		if span >= remaining and span > 0.0001:
			return _history[sample - 1].lerp(_history[sample], remaining / span)
		remaining -= span
	return _history[-1] - _heading * remaining


func _pose_body() -> void:
	if _skeleton == null or _history.is_empty():
		return
	var inverse_skeleton := _skeleton.global_transform.affine_inverse()
	var time := float(Time.get_ticks_msec()) * 0.001
	var arousal := clampf(awareness + (0.3 if state == State.CHASE else 0.0), 0.0, 1.0)
	for skin in _skin_materials:
		skin.set_shader_parameter("arousal", arousal)
	for bone in _bone_rest.size():
		var rest := _bone_rest[bone]
		var distance := maxf(0.0, rest.origin.z)
		var center := _spine_sample(distance)
		var ahead := _spine_sample(maxf(0.0, distance - 0.3))
		var behind := _spine_sample(distance + 0.3)
		var tangent := (ahead - behind).normalized()
		if tangent.length_squared() < 0.1:
			tangent = _heading
		var up := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.96 else Vector3.RIGHT
		var frame := Basis.looking_at(tangent, up)
		var ripple := sin(time * (2.4 if state == State.CHASE else 1.4) - distance * 0.75) * minf(distance / BODY_LENGTH, 1.0) * 0.18
		var offset := frame.x * (rest.origin.x + ripple) + frame.y * rest.origin.y
		var pose := Transform3D(frame * rest.basis, center + offset)
		if bone in _jaw_bones:
			pose.origin -= frame.y * (0.09 + arousal * 0.28) * float(_jaw_bones.find(bone) + 1) / 4.0
		_skeleton.set_bone_global_pose_override(bone, inverse_skeleton * pose, 1.0, true)


func _update_omens(delta: float) -> void:
	_omen_clock -= delta
	_threat_clock -= delta
	var distance := global_position.distance_to(_player_position()) if is_instance_valid(player) else 100.0
	var proximity := 1.0 - clampf(distance / 34.0, 0.0, 1.0)
	if _omen_clock <= 0.0:
		_omen_clock = _rng.randf_range(2.6, 5.2)
		if state != State.DORMANT or _quiet_left < 6.0:
			omen.emit(Vector3(global_position.x, 0.0, global_position.z), maxf(0.18, proximity * (0.9 if state == State.CHASE else 0.55)))
	if _threat_clock <= 0.0:
		_threat_clock = 0.2
		var threat := proximity * (0.25 + awareness * 0.65)
		if state == State.CHASE:
			threat = maxf(threat, 0.72)
		elif state == State.DORMANT:
			threat *= 0.2
		threat_changed.emit(clampf(threat, 0.0, 1.0))
