class_name WaterhouseStalker
extends CharacterBody3D
## Imported Tripo rigs from the reference game, driven by native animation/physics.
## Each animal owns one territory; neither can follow a player through a wall.

signal threat_changed(amount: float)
signal attack_started
signal omen(position: Vector3, strength: float)

enum State { DORMANT, PATROL, INVESTIGATE, SEARCH, CHASE, RETREAT }

@export_enum("angler", "crab") var species: String = "angler"

var encounter_director: Node
var player: CharacterBody3D
var enabled: bool = false
var pressure: float = 0.0
var awareness: float = 0.0
var state: State = State.DORMANT
var detection_multiplier: float = 1.0
var speed_multiplier: float = 1.0
var attack_damage: float = 100.0
var attack_windup: float = 0.9
var quiet_multiplier: float = 1.0

var _rng := RandomNumberGenerator.new()
var _graph := AStar3D.new()
var _shape: Shape3D
var _path := PackedVector3Array()
var _path_index: int = 0
var _path_clock: float = 0.0
var _goal := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _heading := Vector3.FORWARD
var _state_age: float = 0.0
var _quiet_left: float = 0.0
var _sense_clock: float = 0.0
var _last_saw_player: bool = false
var _lost_seconds: float = 0.0
var _attack_left: float = -1.0
var _attack_cooldown: float = 0.0
var _noise_cooldown: float = 0.0
var _blocked_seconds: float = 0.0
var _omen_clock: float = 0.0
var _navigation_ready: bool = false
var _player_properties: Dictionary[StringName, bool] = {}
var _known_player_id: int = 0
var _skeleton: Skeleton3D
var _animation: AnimationPlayer
var _walk_clip: StringName
var _skin_materials: Array[ShaderMaterial] = []
var _legs: Array[Dictionary] = []
var _gait_phase: float = 0.0

@onready var _visual: Node3D = $Visual
@onready var _lure: OmniLight3D = get_node_or_null("Lure") as OmniLight3D


func _ready() -> void:
	_rng.randomize()
	motion_mode = MOTION_MODE_GROUNDED if species == "crab" else MOTION_MODE_FLOATING
	_shape = ($BodyCollision as CollisionShape3D).shape
	_configure_model()
	reset_creature()
	_build_navigation.call_deferred()


func _configure_model() -> void:
	_visual.scale = Vector3.ONE * (6.1 if species == "angler" else 5.1)
	_visual.rotation.y = PI if species == "angler" else PI * 0.5
	_visual.position.y = -1.85 if species == "angler" else -2.3
	for candidate in _visual.find_children("*", "Skeleton3D", true, false):
		_skeleton = candidate as Skeleton3D
		break
	for candidate in _visual.find_children("*", "AnimationPlayer", true, false):
		_animation = candidate as AnimationPlayer
		break
	if _animation != null:
		for clip in _animation.get_animation_list():
			if String(clip).contains("preset"):
				_walk_clip = clip
				var animation := _animation.get_animation(clip)
				animation.loop_mode = Animation.LOOP_LINEAR
				_animation.play(clip)
				break
		_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	if species == "crab" and _skeleton != null:
		# The source octopod preset folds this particular imported rig vertically.
		# Keep its skin/rest skeleton, but plant its eight original walking chains.
		if _animation != null:
			_animation.active = false
		_skeleton.reset_bone_poses()
		_configure_crab_legs()
	var shader := load("res://shaders/stalker_skin.gdshader") as Shader
	for candidate in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_instance.extra_cull_margin = 5.0
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var skin := ShaderMaterial.new()
			skin.shader = shader
			skin.set_shader_parameter("skin_texture", original.albedo_texture)
			skin.set_shader_parameter("skin_normal", original.normal_texture)
			skin.set_shader_parameter("tint", Vector3(0.43, 0.53, 0.49) if species == "angler" else Vector3(0.57, 0.52, 0.44))
			skin.set_shader_parameter("lure_species", species == "angler")
			mesh_instance.set_surface_override_material(surface, skin)
			_skin_materials.append(skin)


func apply_difficulty(config: Dictionary) -> void:
	detection_multiplier = _difficulty_value(config, "detection_multiplier", 1.0, 0.3, 2.0)
	speed_multiplier = _difficulty_value(config, "speed_multiplier", 1.0, 0.4, 1.6)
	attack_damage = _difficulty_value(config, "attack_damage", 100.0, 1.0, 100.0)
	attack_windup = _difficulty_value(config, "attack_windup", 0.9, 0.35, 2.5)
	quiet_multiplier = _difficulty_value(config, "quiet_multiplier", 1.0, 0.5, 2.0)


func _difficulty_value(config: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	var value: Variant = config.get(key, fallback)
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), low, high)


func reset_creature() -> void:
	state = State.DORMANT
	awareness = 0.0
	global_position = Vector3(58.0, -5.5, 8.0) if species == "angler" else Vector3(-43.0, 2.98, -25.0)
	_heading = Vector3.FORWARD
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_goal = global_position
	_last_seen = global_position
	_state_age = 0.0
	_quiet_left = _rng.randf_range(13.0, 23.0) * quiet_multiplier
	_attack_left = -1.0
	_attack_cooldown = 0.0
	_noise_cooldown = 0.0
	_path_clock = 0.0
	_sense_clock = 0.0
	_lost_seconds = 0.0
	_blocked_seconds = 0.0
	_last_saw_player = false
	_path.clear()
	if _animation != null:
		_animation.seek(0.0, true)
	if species == "crab" and _skeleton != null:
		_skeleton.clear_bones_global_pose_override()
		_skeleton.reset_bone_poses()
		for leg in _legs:
			leg["foot"] = global_transform * (leg["tip"] as Vector3)
			leg["step"] = -1.0
	threat_changed.emit(0.0)


func state_name() -> String:
	return ["静伏", "巡逻", "调查", "搜寻", "追击", "退去"][state]


func _physics_process(delta: float) -> void:
	if not enabled:
		velocity = Vector3.ZERO
		if _animation != null:
			_animation.speed_scale = 0.0
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
	_update_omen(delta)


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
	return bool(player.get(property_name)) if _player_properties.has(property_name) else fallback


func _player_is_in_water() -> bool:
	return is_instance_valid(player) and _player_boolean(&"in_water", player.global_position.y < -0.1)


func _player_position() -> Vector3:
	return player.global_position + Vector3.UP * (0.75 if species == "angler" else 1.1)


func _within_territory(point: Vector3) -> bool:
	if species == "angler":
		return point.x >= 37.0 and point.x <= 66.0 and point.z >= -14.0 and point.z <= 18.0 and point.y < 0.0
	return point.x >= -57.0 and point.x <= -33.0 and point.z >= -36.0 and point.z <= -14.0 and point.y >= 0.4


func _can_hunt_player() -> bool:
	return is_instance_valid(player) and not _player_boolean(&"dead") and _within_territory(player.global_position) and (_player_is_in_water() == (species == "angler"))


func _sense_player(delta: float) -> void:
	_refresh_player_properties()
	_last_saw_player = false
	if not _can_hunt_player() or state == State.RETREAT:
		_lost_seconds += delta
		awareness = maxf(0.0, awareness - delta * 0.25)
		return
	var target := _player_position()
	var distance := global_position.distance_to(target)
	var lamp := _player_boolean(&"light_on")
	var range_limit := (17.0 if lamp else 10.0) if species == "crab" else (15.0 if lamp else 8.5)
	range_limit *= detection_multiplier
	var front := _heading.dot((target - global_position).normalized()) > 0.1 or distance < 3.5
	if distance <= range_limit and front and _has_line_of_sight(target):
		_last_saw_player = true
		_last_seen = _clamp_point(target)
		_lost_seconds = 0.0
		var proximity := 1.0 - clampf(distance / range_limit, 0.0, 1.0)
		var concealment := 0.55 if not lamp and player.velocity.length() < 2.6 else 1.0
		awareness = minf(1.0, awareness + delta * concealment * (0.32 + proximity * 0.9) * (1.45 if lamp else 1.0))
		if awareness >= 0.67 and _attack_cooldown <= 0.0:
			_set_state(State.CHASE)
		elif awareness > 0.2 and state in [State.DORMANT, State.PATROL]:
			_goal = _last_seen
			_set_state(State.INVESTIGATE)
	else:
		_lost_seconds += delta
		awareness = maxf(0.0, awareness - delta * 0.12)


func _has_line_of_sight(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, target, 1 | 2)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player


func hear_noise(position: Vector3, loudness: float) -> void:
	if not enabled or not is_finite(loudness) or not position.is_finite() or loudness <= 0.0 or _noise_cooldown > 0.0 or state == State.RETREAT:
		return
	var intensity := clampf(loudness, 0.0, 1.5)
	var query := PhysicsRayQueryParameters3D.create(global_position, position, 1)
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		intensity *= 0.22 # Concrete muffles sound; it never grants visual detection.
	var hearing_range := (3.0 + intensity * (21.0 if species == "crab" else 14.0)) * detection_multiplier
	if global_position.distance_to(position) > hearing_range:
		return
	if state == State.CHASE and (_last_saw_player or intensity < 0.85):
		return
	_noise_cooldown = 0.5
	_last_seen = _clamp_point(position)
	_goal = _last_seen
	awareness = minf(0.55, awareness + intensity * 0.18)
	_set_state(State.INVESTIGATE)


func encounter_is_active() -> bool:
	return state == State.CHASE


func _set_state(next: State) -> void:
	if next == State.CHASE and state != State.CHASE and encounter_director != null and not encounter_director.request_pursuit(self):
		return
	if state == next:
		return
	state = next
	_state_age = 0.0
	_path_clock = 0.0
	_path.clear()
	if state != State.CHASE:
		_attack_left = -1.0
	if state == State.CHASE:
		omen.emit(global_position, 0.75)
	elif state == State.RETREAT:
		_attack_cooldown = maxf(_attack_cooldown, 9.0)
		_goal = _roam_point()
	elif state == State.DORMANT:
		_quiet_left = _rng.randf_range(15.0, 26.0) * quiet_multiplier
	elif state == State.PATROL:
		_goal = _roam_point()


func _update_state(delta: float) -> void:
	var reached := global_position.distance_to(_goal) < 1.5
	match state:
		State.DORMANT:
			_quiet_left -= delta
			if _quiet_left <= 0.0:
				_set_state(State.PATROL)
		State.PATROL:
			if reached:
				_goal = _roam_point()
			if _state_age > (24.0 if species == "angler" else 42.0):
				_set_state(State.RETREAT)
		State.INVESTIGATE:
			if reached or _state_age > 10.0:
				_set_state(State.SEARCH)
				_goal = _roam_point(true)
		State.SEARCH:
			if reached:
				_goal = _roam_point(true)
			if _state_age > 10.0:
				_set_state(State.RETREAT)
		State.CHASE:
			if not _can_hunt_player() or _lost_seconds > 3.1:
				_set_state(State.SEARCH)
				_goal = _last_seen
			elif _last_saw_player:
				_goal = _clamp_point(_player_position())
			else:
				_goal = _last_seen
			if _state_age > (13.0 if species == "angler" else 20.0):
				_set_state(State.RETREAT)
		State.RETREAT:
			if reached:
				_goal = _roam_point()
			if _state_age > 7.0:
				_set_state(State.DORMANT)


func _clamp_point(point: Vector3) -> Vector3:
	if species == "angler":
		return Vector3(clampf(point.x, 40.4, 62.6), clampf(point.y, -6.6, -3.4), clampf(point.z, -10.6, 14.6))
	return Vector3(clampf(point.x, -53.8, -36.2), 2.98, clampf(point.z, -31.8, -18.2))


func _roam_point(search: bool = false) -> Vector3:
	var point := Vector3(_rng.randf_range(42.0, 61.0), _rng.randf_range(-6.5, -4.0), _rng.randf_range(-8.0, 12.0))
	if species == "crab":
		point = Vector3(_rng.randf_range(-52.0, -38.0), 2.98, _rng.randf_range(-29.0, -21.0))
	if search:
		point = _clamp_point(_last_seen + Vector3(_rng.randf_range(-5.0, 5.0), 0.0, _rng.randf_range(-5.0, 5.0)))
	if _navigation_ready:
		var closest := _graph.get_closest_point(point)
		if closest >= 0:
			return _graph.get_point_position(closest)
	return _clamp_point(point)


func _shape_query(point: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (0.035 if species == "crab" else 0.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	query.margin = 0.01
	return query


func _shape_is_clear(point: Vector3) -> bool:
	return get_world_3d().direct_space_state.intersect_shape(_shape_query(point), 1).is_empty()


func _clear_motion(from: Vector3, to: Vector3) -> bool:
	var query := _shape_query(from)
	query.motion = to - from
	return get_world_3d().direct_space_state.cast_motion(query)[0] > 0.99


func _build_navigation() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_graph.clear()
	var coordinates: Dictionary[Vector3i, int] = {}
	var dimensions := Vector3i(9, 1, 7) if species == "crab" else Vector3i(9, 3, 10)
	var origin := Vector3(-53.0, 2.98, -31.0) if species == "crab" else Vector3(40.4, -6.5, -10.0)
	var step := Vector3(2.0, 0.0, 2.0) if species == "crab" else Vector3(2.7, 1.5, 2.7)
	for x in dimensions.x:
		for y in dimensions.y:
			for z in dimensions.z:
				var point := origin + Vector3(x, y, z) * step
				if not _shape_is_clear(point):
					continue
				var id := _graph.get_available_point_id()
				_graph.add_point(id, point)
				coordinates[Vector3i(x, y, z)] = id
	var neighbors: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(0, 1, 0)]
	for coordinate in coordinates:
		for offset in neighbors:
			if not coordinates.has(coordinate + offset):
				continue
			var from: int = coordinates[coordinate]
			var to: int = coordinates[coordinate + offset]
			if _clear_motion(_graph.get_point_position(from), _graph.get_point_position(to)):
				_graph.connect_points(from, to)
	_navigation_ready = _graph.get_point_count() > 0
	_path_clock = 0.0


func _plan_route() -> void:
	_path.clear()
	_path_index = 0
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
	if _path.size() > 1 and _clear_motion(global_position, _path[1]):
		_path_index = 1
	if not _path.is_empty() and _clear_motion(_path[-1], _goal):
		_path.append(_goal)


func _update_movement(delta: float) -> void:
	_path_clock -= delta
	if _path_clock <= 0.0:
		_plan_route()
		_path_clock = 0.55 if state == State.CHASE else 1.6
	var target := _goal
	if not _path.is_empty():
		while _path_index < _path.size() - 1 and global_position.distance_to(_path[_path_index]) < 0.8:
			_path_index += 1
		target = _path[_path_index]
	var direction := target - global_position
	if species == "crab":
		direction.y = 0.0
	direction = direction.normalized()
	var speed := 1.0 if species == "angler" else 1.45
	if state == State.CHASE:
		speed = 4.7 if species == "angler" else 3.15
	elif state in [State.INVESTIGATE, State.SEARCH, State.RETREAT]:
		speed *= 1.25
	elif state == State.DORMANT:
		speed = 0.0
	if _attack_left >= 0.0:
		speed = 0.15
	speed *= speed_multiplier
	if global_position.distance_to(target) < 0.35:
		speed = 0.0
	if direction.length_squared() > 0.1:
		var blended := _heading.lerp(direction, minf(1.0, delta * 3.0))
		_heading = blended.normalized() if blended.length_squared() > 0.0001 else direction
		rotation.y = lerp_angle(rotation.y, atan2(-_heading.x, -_heading.z), minf(1.0, delta * 2.0))
	# Follow validated path edges directly, avoiding turn arcs through shelf corners.
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 8.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 8.0)
	if species == "crab":
		velocity.y = -0.3 if is_on_floor() else velocity.y - 18.0 * delta
	else:
		velocity.y = move_toward(velocity.y, direction.y * speed, delta * 5.0)
	var before := global_position
	move_and_slide()
	var moved := global_position.distance_to(before)
	if speed > 0.2 and moved < delta * 0.1:
		_blocked_seconds += delta
	else:
		_blocked_seconds = maxf(0.0, _blocked_seconds - delta)
	if _blocked_seconds > 1.2:
		_blocked_seconds = 0.0
		_goal = _roam_point(state == State.SEARCH)
		_path_clock = 0.0
		if state == State.CHASE:
			_set_state(State.SEARCH)
	if _animation != null:
		_animation.speed_scale = clampf(moved / maxf(delta, 0.001) / 1.7, 0.0, 2.1) if species == "crab" else (0.35 if state == State.DORMANT else 0.65 + speed * 0.18)
	if species == "crab":
		_pose_crab_legs(delta, moved)


func _configure_crab_legs() -> void:
	var chains := [
		["bone_32", "bone_35", Vector3(0.333, 0, -0.222)], ["bone_38", "bone_41", Vector3(0.333, 0, 0.222)],
		["bone_20", "bone_23", Vector3(0.082, 0.005, -0.49)], ["bone_26", "bone_29", Vector3(0.082, 0.005, 0.49)],
		["3_Right_Limb_1", "3_Right_Limb_4", Vector3(-0.174, 0, -0.43)], ["bone_15", "bone_18", Vector3(-0.174, 0, 0.43)],
		["bone_2", "bone_4", Vector3(-0.33, 0.003, -0.24)], ["bone_6", "bone_8", Vector3(-0.33, 0.003, 0.24)],
	]
	for chain in chains:
		var hip := _find_bone(String(chain[0]))
		var knee := _find_bone(String(chain[1]))
		if hip < 0 or knee < 0:
			continue
		var hip_rest := global_transform.affine_inverse() * _skeleton.global_transform * _skeleton.get_bone_global_rest(hip)
		var knee_rest := global_transform.affine_inverse() * _skeleton.global_transform * _skeleton.get_bone_global_rest(knee)
		var tip: Vector3 = _visual.transform * (chain[2] as Vector3)
		_legs.append({"hip": hip, "knee": knee, "hip_rest": hip_rest, "knee_rest": knee_rest, "tip": tip, "foot": Vector3.ZERO, "step": -1.0})


func _find_bone(name: String) -> int:
	for bone in _skeleton.get_bone_count():
		var candidate := String(_skeleton.get_bone_name(bone))
		if candidate == name or candidate.ends_with("::" + name) or candidate.ends_with("_" + name):
			return bone
	return -1


func _pose_crab_legs(delta: float, moved: float) -> void:
	_gait_phase += moved * 1.25
	var inverse := _skeleton.global_transform.affine_inverse()
	for index in _legs.size():
		var leg := _legs[index]
		var hip_rest: Transform3D = global_transform * (leg["hip_rest"] as Transform3D)
		var knee_rest: Transform3D = global_transform * (leg["knee_rest"] as Transform3D)
		var ideal: Vector3 = global_transform * (leg["tip"] as Vector3)
		var foot: Vector3 = leg["foot"]
		var step: float = leg["step"]
		if step < 0.0 and (foot.distance_to(ideal) > 0.6 or (foot.distance_to(ideal) > 0.24 and fmod(_gait_phase + float(index % 2) * 0.5, 1.0) > 0.55)):
			leg["from"] = foot
			leg["to"] = ideal + _heading * 0.22
			step = 0.0
		if step >= 0.0:
			step = minf(1.0, step + delta * 4.5)
			foot = (leg["from"] as Vector3).lerp(leg["to"] as Vector3, smoothstep(0.0, 1.0, step))
			foot.y += sin(step * PI) * 0.26
			if step >= 1.0:
				step = -1.0
		leg["foot"] = foot
		leg["step"] = step
		var upper := hip_rest.origin.distance_to(knee_rest.origin)
		var lower := knee_rest.origin.distance_to(ideal)
		var vector := foot - hip_rest.origin
		var distance := clampf(vector.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
		var axis := vector.normalized()
		var bend := knee_rest.origin - hip_rest.origin
		bend = (bend - axis * bend.dot(axis)).normalized()
		var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
		var knee := hip_rest.origin + axis * along + bend * sqrt(maxf(0.0, upper * upper - along * along))
		var hip_rotation := Quaternion((knee_rest.origin - hip_rest.origin).normalized(), (knee - hip_rest.origin).normalized())
		var knee_rotation := Quaternion((ideal - knee_rest.origin).normalized(), (foot - knee).normalized())
		_skeleton.set_bone_global_pose_override(int(leg["hip"]), inverse * Transform3D(Basis(hip_rotation) * hip_rest.basis, hip_rest.origin), 1.0, true)
		_skeleton.set_bone_global_pose_override(int(leg["knee"]), inverse * Transform3D(Basis(knee_rotation) * knee_rest.basis, knee), 1.0, true)


func _update_attack(delta: float) -> void:
	if state != State.CHASE or not _can_hunt_player():
		_attack_left = -1.0
		return
	var target := _player_position()
	var distance := global_position.distance_to(target)
	var reach := 3.3 if species == "angler" else 3.2
	if _attack_left < 0.0:
		if distance < reach and _attack_cooldown <= 0.0 and _has_line_of_sight(target):
			_attack_left = attack_windup * (1.25 if species == "angler" else 1.0)
			attack_started.emit()
		return
	_attack_left -= delta
	if _attack_left <= 0.0:
		if distance < reach + 0.25 and _has_line_of_sight(target) and player.has_method("take_damage"):
			player.call("take_damage", attack_damage, "诱饵灯后的巨口闭合了。" if species == "angler" else "档案室的长足截断了去路。", self)
		_attack_left = -1.0
		_set_state(State.RETREAT)


func _update_omen(delta: float) -> void:
	var arousal := clampf(awareness + (0.25 if state == State.CHASE else 0.0), 0.0, 1.0)
	for skin in _skin_materials:
		skin.set_shader_parameter("arousal", arousal)
	if _lure != null:
		_lure.light_energy = 0.0 if state == State.RETREAT else 1.15 + sin(_state_age * 1.2) * 0.2 + arousal * 1.2
	_omen_clock -= delta
	if _omen_clock <= 0.0:
		_omen_clock = _rng.randf_range(7.0, 12.0)
		if state != State.DORMANT:
			omen.emit(Vector3(global_position.x, 0.0, global_position.z), 0.35 + arousal * 0.3)
	threat_changed.emit(minf(arousal, 0.55) if encounter_director != null and not encounter_is_active() else arousal)
