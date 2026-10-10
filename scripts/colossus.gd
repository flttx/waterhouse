class_name WaterhouseColossus
extends CharacterBody3D
## A territorial many-eyed mass. It surfaces, aims, telegraphs a fixed strike,
## and sinks again. Its arms cannot damage through native world colliders.

signal threat_changed(amount: float)
signal attack_started
signal omen(position: Vector3, strength: float)

enum State { DORMANT, WATCH, SEARCH, WINDUP, STRIKE, RETREAT }
const HOME := Vector3(-88.0, -12.0, 27.0)
const POOL := Rect2(-103.0, -13.0, 42.0, 58.0)
const MOUTH := Vector3(0.0, -0.65, -3.25)
const SURFACED_Y: float = -5.5
const WORLD_MASK: int = 1

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
var _state_age: float = 0.0
var _quiet_left: float = 0.0
var _sense_clock: float = 0.0
var _last_seen := Vector3.ZERO
var _last_saw_player: bool = false
var _lost_seconds: float = 0.0
var _attack_left: float = -1.0
var _attack_target := Vector3.ZERO
var _did_damage: bool = false
var _noise_cooldown: float = 0.0
var _skin_materials: Array[ShaderMaterial] = []
var _arms: Array[MeshInstance3D] = []
var _player_properties: Dictionary[StringName, bool] = {}
var _known_player_id: int = 0
var _last_arm_extension: float = -2.0

@onready var _visual: Node3D = $Visual

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	_rng.randomize()
	_configure_model()
	reset_creature()

func _configure_model() -> void:
	_visual.scale = Vector3.ONE * 0.65
	_visual.rotation.y = PI
	var shader := load("res://shaders/colossus_skin.gdshader") as Shader
	for candidate in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		mesh_instance.extra_cull_margin = 2.0
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var skin := ShaderMaterial.new()
			skin.shader = shader
			skin.set_shader_parameter("skin_texture", source.albedo_texture)
			skin.set_shader_parameter("skin_normal", source.normal_texture)
			skin.set_shader_parameter("has_normal", source.normal_texture != null)
			mesh_instance.set_surface_override_material(surface, skin)
			_skin_materials.append(skin)
	var arm_skin := StandardMaterial3D.new()
	arm_skin.albedo_color = Color(0.055, 0.095, 0.075)
	arm_skin.roughness = 0.35
	for index in 2:
		var arm := MeshInstance3D.new()
		arm.material_override = arm_skin
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(arm)
		_arms.append(arm)

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
	global_position = HOME
	velocity = Vector3.ZERO
	state = State.DORMANT
	awareness = 0.0
	_state_age = 0.0
	_quiet_left = _rng.randf_range(24.0, 40.0) * quiet_multiplier
	_attack_left = -1.0
	_noise_cooldown = 0.0
	_sense_clock = 0.0
	_last_saw_player = false
	_lost_seconds = 0.0
	_did_damage = false
	if is_node_ready():
		_pose_arms()
	threat_changed.emit(0.0)

func state_name() -> String:
	return ["深潜", "浮现窥视", "水下搜寻", "蓄势", "触臂突袭", "下沉"][state]

func _physics_process(delta: float) -> void:
	if not enabled:
		velocity = Vector3.ZERO
		return
	_state_age += delta
	_noise_cooldown = maxf(0.0, _noise_cooldown - delta)
	_sense_clock -= delta
	if _sense_clock <= 0.0:
		_sense_player(0.16)
		_sense_clock = 0.16
	_update_state(delta)
	var target_y := HOME.y if state in [State.DORMANT, State.RETREAT] else SURFACED_Y
	velocity = Vector3(0.0, clampf((target_y - global_position.y) * 0.85, -1.2, 1.2) * speed_multiplier, 0.0)
	move_and_slide()
	_pose_arms()
	var arousal := clampf(awareness + (0.4 if state in [State.WINDUP, State.STRIKE] else 0.0), 0.0, 1.0)
	for skin in _skin_materials:
		skin.set_shader_parameter("arousal", arousal)
		var direction := _last_seen - global_position
		skin.set_shader_parameter("head_turn", clampf(atan2(-direction.x, -direction.z), -0.26, 0.26))
	threat_changed.emit(minf(arousal, 0.55) if encounter_director != null and not encounter_is_active() else arousal)

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

func _player_boolean(name: StringName, fallback: bool = false) -> bool:
	return bool(player.get(name)) if _player_properties.has(name) else fallback

func _can_hunt_player() -> bool:
	if not is_instance_valid(player) or _player_boolean(&"dead"):
		return false
	var point := player.global_position
	return POOL.grow(2.0).has_point(Vector2(point.x, point.z)) and point.y < 2.0 and point.y > -19.0

func _player_position() -> Vector3:
	return player.global_position + Vector3.UP * 0.75

func _has_line_of_sight(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + MOUTH, target, 1 | 2)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player

func _sense_player(delta: float) -> void:
	_refresh_player_properties()
	_last_saw_player = false
	if state == State.RETREAT or not _can_hunt_player():
		_lost_seconds += delta
		awareness = maxf(0.0, awareness - delta * 0.2)
		return
	var target := _player_position()
	var distance := (global_position + MOUTH).distance_to(target)
	var lamp := _player_boolean(&"light_on")
	var range_limit := (22.0 if lamp else 11.0) * detection_multiplier
	if distance < range_limit and _has_line_of_sight(target):
		_last_saw_player = true
		_last_seen = target
		_lost_seconds = 0.0
		awareness = minf(1.0, awareness + delta * (0.32 + (0.5 if lamp else 0.0)))
		if state == State.DORMANT and awareness > 0.25:
			_set_state(State.WATCH)
	else:
		_lost_seconds += delta
		awareness = maxf(0.0, awareness - delta * 0.12)

func hear_noise(position: Vector3, loudness: float) -> void:
	if not enabled or not position.is_finite() or not is_finite(loudness) or loudness <= 0.0 or _noise_cooldown > 0.0 or state == State.RETREAT:
		return
	if not POOL.grow(2.0).has_point(Vector2(position.x, position.z)):
		return
	var intensity := clampf(loudness, 0.0, 1.5)
	var query := PhysicsRayQueryParameters3D.create(global_position + MOUTH, position, WORLD_MASK)
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		intensity *= 0.22
	if (global_position + MOUTH).distance_to(position) > (4.0 + intensity * 25.0) * detection_multiplier:
		return
	_noise_cooldown = 0.6
	_last_seen = position
	_lost_seconds = 0.0
	awareness = minf(0.6, awareness + intensity * 0.25)
	if state in [State.DORMANT, State.SEARCH]:
		_set_state(State.WATCH)

func encounter_is_active() -> bool:
	return state in [State.WINDUP, State.STRIKE]


func _set_state(next: State) -> void:
	if next == State.WINDUP and encounter_director != null and not encounter_director.request_pursuit(self):
		return
	if state == next:
		return
	state = next
	_state_age = 0.0
	if state == State.WINDUP:
		_attack_left = attack_windup * 2.1
		_attack_target = _last_seen # Telegraph is locked, so lateral movement dodges it.
		attack_started.emit()
	elif state == State.STRIKE:
		_did_damage = false
	elif state == State.RETREAT:
		_attack_left = -1.0
	elif state == State.DORMANT:
		_quiet_left = _rng.randf_range(28.0, 42.0) * quiet_multiplier
	if state in [State.WATCH, State.WINDUP]:
		omen.emit(Vector3(global_position.x, 0.0, global_position.z), 0.7)

func _update_state(delta: float) -> void:
	match state:
		State.DORMANT:
			_quiet_left -= delta
			if _quiet_left <= 0.0:
				_set_state(State.WATCH)
		State.WATCH:
			if _can_hunt_player() and _last_saw_player and awareness > 0.65 and (global_position + MOUTH).distance_to(_last_seen) < 13.0 and global_position.y > -7.5:
				_set_state(State.WINDUP)
			elif _lost_seconds > 5.0:
				_set_state(State.SEARCH)
			elif _state_age > 23.0:
				_set_state(State.RETREAT)
		State.SEARCH:
			if _last_saw_player:
				_set_state(State.WATCH)
			elif _state_age > 8.0:
				_set_state(State.RETREAT)
		State.WINDUP:
			_attack_left -= delta
			if _attack_left <= 0.0:
				_set_state(State.STRIKE)
		State.STRIKE:
			if _state_age > 0.22 and not _did_damage:
				_did_damage = true
				if _can_hunt_player() and _player_position().distance_to(_attack_target) < 1.6 and _has_line_of_sight(_player_position()) and player.has_method("take_damage"):
					player.call("take_damage", attack_damage, "深井里的触臂击中了你。", self)
			if _state_age > 1.0:
				_set_state(State.RETREAT)
		State.RETREAT:
			awareness = maxf(0.0, awareness - delta * 0.2)
			if _state_age > 13.0:
				_set_state(State.DORMANT)

func _pose_arms() -> void:
	var extension: float = 0.0
	if state == State.WINDUP:
		extension = 0.15
	elif state == State.STRIKE:
		extension = sin(clampf(_state_age, 0.0, 1.0) * PI)
	if absf(extension - _last_arm_extension) < 0.005:
		return
	_last_arm_extension = extension
	for index in _arms.size():
		var side := -1.0 if index == 0 else 1.0
		var start := MOUTH + Vector3(side * 1.2, -0.5, 0.2)
		var idle_end := start + Vector3(side * 1.4, -4.2, 1.2)
		var target := to_local(_attack_target) + Vector3(side * 0.2, 0.0, 0.0)
		var end := idle_end.lerp(target, extension)
		var control := start.lerp(end, 0.5) + Vector3(side * 1.8, 0.7, 0.0)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for segment in 17:
			var t := float(segment) / 16.0
			var position := (1.0 - t) * (1.0 - t) * start + 2.0 * (1.0 - t) * t * control + t * t * end
			var tangent := ((control - start) * (1.0 - t) + (end - control) * t).normalized()
			var frame := Basis.looking_at(tangent, Vector3.UP if absf(tangent.y) < 0.95 else Vector3.RIGHT)
			var radius := lerpf(0.42, 0.035, t)
			for ring in 8:
				var angle := float(ring) * TAU / 8.0
				var normal := frame.x * cos(angle) + frame.y * sin(angle)
				vertices.append(position + normal * radius)
				normals.append(normal)
				if segment < 16:
					var a := segment * 8 + ring
					var b := segment * 8 + (ring + 1) % 8
					indices.append_array(PackedInt32Array([a, b, a + 8, b, b + 8, a + 8]))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_arms[index].mesh = mesh
