class_name PlayerController
extends CharacterBody3D
## Native two-medium controller. The body's origin is always the feet.

signal died(reason: String)
signal noise_emitted(pos: Vector3, loudness: float)

const STANDING_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.12
const STANDING_EYE: float = 1.62
const CROUCH_EYE: float = 0.94
const WATER_LEVEL: float = 0.0
const SURFACE_FEET: float = -1.43
const GRAVITY: float = 14.0

@export var mouse_sensitivity: float = 0.0022
@export var head_bob_enabled: bool = true
@export_range(30.0, 180.0) var breath_seconds: float = 60.0
@export var invert_y: bool = false
@export_range(60.0, 100.0) var base_fov: float = 76.0

@onready var camera: Camera3D = $Head/Camera3D
@onready var _head: Node3D = $Head
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _flashlight: SpotLight3D = $Head/Camera3D/Flashlight

var world: Node3D
var enabled: bool = false
var submerged: bool = false
var in_water: bool = false
var oxygen: float = 100.0
var stamina: float = 100.0
var health: float = 100.0
var noise_level: float = 0.0
var light_on: bool = true
var crouching: bool = false

var _pitch: float = 0.0
var _eye_height: float = STANDING_EYE
var _noise_clock: float = 0.0
var _bob_clock: float = 0.0
var _landing_offset: float = 0.0
var _last_vertical_speed: float = 0.0
var _sprint_exhausted: bool = false
var _dead: bool = false
var _climbing: bool = false
var _climb_elapsed: float = 0.0
var _climb_start: Vector3
var _climb_corner: Vector3
var _climb_target: Vector3


func _ready() -> void:
	floor_snap_length = 0.28
	floor_max_angle = deg_to_rad(46.0)
	_collision.shape = _collision.shape.duplicate()
	_update_flashlight()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _dead or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var y_sign: float = 1.0 if invert_y else -1.0
		_pitch = clampf(_pitch + motion.relative.y * mouse_sensitivity * y_sign, -1.48, 1.48)
		_head.rotation.x = _pitch
	elif event.is_action_pressed("flashlight"):
		light_on = not light_on
		_update_flashlight()


func _physics_process(delta: float) -> void:
	if not enabled or _dead:
		noise_level = 0.0
		return
	var was_grounded: bool = is_on_floor()
	_update_medium()
	if _climbing:
		_update_climb(delta)
		_update_medium()
		_update_breath(delta)
		_update_camera(delta, false)
		return
	_update_crouch(delta)
	var movement: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var moving: bool = movement.length_squared() > 0.01
	if stamina <= 1.0:
		_sprint_exhausted = true
	elif stamina >= 22.0:
		_sprint_exhausted = false
	var sprinting: bool = Input.is_action_pressed("sprint") and moving and not crouching and not _sprint_exhausted
	if sprinting:
		stamina = maxf(0.0, stamina - (12.0 if in_water else 18.0) * delta)
	else:
		stamina = minf(100.0, stamina + 14.0 * delta)
	if in_water:
		_swim(delta, movement, sprinting)
	else:
		_walk(delta, movement, sprinting)
	_last_vertical_speed = velocity.y
	move_and_slide()
	_update_medium()
	if not was_grounded and is_on_floor() and not in_water:
		_landing_offset = -clampf(absf(_last_vertical_speed) * 0.015, 0.0, 0.2)
		if _last_vertical_speed < -4.0:
			noise_emitted.emit(global_position, clampf(absf(_last_vertical_speed) / 13.0, 0.3, 0.85))
	_update_breath(delta)
	_update_noise(delta, moving, sprinting)
	_update_camera(delta, sprinting)


func _walk(delta: float, movement: Vector2, sprinting: bool) -> void:
	var speed: float = 1.4 if crouching else (5.4 if sprinting else 3.0)
	var direction: Vector3 = global_basis * Vector3(movement.x, 0.0, movement.y)
	var acceleration: float = 18.0 if is_on_floor() else 5.0
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = 5.1
		noise_emitted.emit(global_position, 0.3)
	else:
		velocity.y = -0.3


func _swim(delta: float, movement: Vector2, sprinting: bool) -> void:
	var speed: float = 3.8 if sprinting else 2.4
	var direction: Vector3 = camera.global_basis * Vector3(movement.x, 0.0, movement.y)
	var vertical_input: float = float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))
	var target_y: float = direction.y * speed
	if vertical_input != 0.0:
		target_y = vertical_input * speed
	# A spring holds the eyes just above water; it only acts in the surface band.
	# Deeper water keeps neutral buoyancy, so valves can be operated without drift.
	elif global_position.y > SURFACE_FEET - 0.35 and target_y > -0.3:
		target_y = clampf((SURFACE_FEET - global_position.y) * 4.5, -1.8, 1.4)
	if global_position.y > SURFACE_FEET and target_y > 0.0:
		target_y = maxf(-1.8, (SURFACE_FEET - global_position.y) * 5.0)
	velocity.x = move_toward(velocity.x, direction.x * speed, 5.5 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 5.5 * delta)
	velocity.y = move_toward(velocity.y, target_y, 6.0 * delta)


func _update_medium(emit_splash: bool = true) -> void:
	var previous_water: bool = in_water
	var previous_submerged: bool = submerged
	if not is_instance_valid(world) or not world.has_method("is_water"):
		in_water = false
		submerged = false
		return
	in_water = bool(world.call("is_water", global_position + Vector3.UP * 0.78))
	submerged = bool(world.call("is_water", camera.global_position)) and camera.global_position.y < WATER_LEVEL - 0.08
	if in_water != previous_water or submerged != previous_submerged:
		_update_flashlight()
	if emit_splash and enabled and in_water and not previous_water and not _climbing:
		noise_emitted.emit(global_position, clampf(absf(_last_vertical_speed) / 9.0, 0.45, 1.0))


func _update_crouch(delta: float) -> void:
	var wants_crouch: bool = not in_water and Input.is_action_pressed("crouch")
	if crouching and not wants_crouch and not _can_stand():
		wants_crouch = true
	crouching = wants_crouch
	var capsule := _collision.shape as CapsuleShape3D
	var target_height: float = CROUCH_HEIGHT if crouching else STANDING_HEIGHT
	capsule.height = target_height
	_collision.position.y = target_height * 0.5
	_eye_height = move_toward(_eye_height, CROUCH_EYE if crouching else STANDING_EYE, delta * 4.5)


func _can_stand() -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = STANDING_HEIGHT
	return _shape_clear(capsule, global_position + Vector3.UP * 0.025)


func _shape_clear(shape: Shape3D, feet_position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(global_basis, feet_position + Vector3.UP * STANDING_HEIGHT * 0.5)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.005
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _path_clear(start: Vector3, finish: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = STANDING_HEIGHT
	query.shape = capsule
	query.transform = Transform3D(global_basis, start + Vector3.UP * STANDING_HEIGHT * 0.5)
	query.motion = finish - start
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.008
	var fractions: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] > 0.999


func _nearest_ladder() -> Vector3:
	var unavailable := Vector3.INF
	if not is_instance_valid(world) or not in_water or _climbing or camera.global_position.y < -1.25:
		return unavailable
	var ladder_list: Variant = world.get("ladders")
	if not ladder_list is Array:
		return unavailable
	var nearest_distance: float = 2.8
	var nearest: Vector3 = unavailable
	for entry: Variant in ladder_list:
		if not entry is Vector3:
			continue
		var ladder: Vector3 = entry
		var horizontal_distance: float = Vector2(ladder.x - global_position.x, ladder.z - global_position.z).length()
		if horizontal_distance < nearest_distance and absf(ladder.y - global_position.y) < 3.4:
			nearest = ladder
			nearest_distance = horizontal_distance
	return nearest


func get_climb_prompt() -> String:
	if not enabled or _dead or _nearest_ladder() == Vector3.INF:
		return ""
	return "E · 攀上检修梯"


func climb_nearest() -> bool:
	if not enabled or _dead:
		return false
	var ladder: Vector3 = _nearest_ladder()
	if ladder == Vector3.INF:
		return false
	var target: Vector3 = ladder + Vector3.UP * 0.06
	var corner := Vector3(global_position.x, target.y, global_position.z)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = STANDING_HEIGHT
	if not _shape_clear(capsule, target) or not _path_clear(global_position, corner) or not _path_clear(corner, target):
		return false
	crouching = false
	var body_shape := _collision.shape as CapsuleShape3D
	body_shape.height = STANDING_HEIGHT
	_collision.position.y = STANDING_HEIGHT * 0.5
	_climb_start = global_position
	_climb_corner = corner
	_climb_target = target
	_climb_elapsed = 0.0
	_climbing = true
	velocity = Vector3.ZERO
	noise_level = 0.45
	noise_emitted.emit(global_position, noise_level)
	return true


func _update_climb(delta: float) -> void:
	_climb_elapsed += delta
	var position_goal: Vector3
	if _climb_elapsed < 0.35:
		position_goal = _climb_start.lerp(_climb_corner, smoothstep(0.0, 0.35, _climb_elapsed))
	else:
		position_goal = _climb_corner.lerp(_climb_target, smoothstep(0.35, 0.7, _climb_elapsed))
	var collision: KinematicCollision3D = move_and_collide(position_goal - global_position)
	if collision != null or _climb_elapsed >= 0.7:
		_climbing = false
		velocity = Vector3.ZERO
		noise_level = 0.0


func _update_breath(delta: float) -> void:
	if submerged:
		oxygen = maxf(0.0, oxygen - delta * (100.0 / clampf(breath_seconds, 30.0, 180.0)))
		if oxygen <= 0.0:
			take_damage(delta * 11.0, "你在浑水里失去了最后一口气。")
	else:
		oxygen = minf(100.0, oxygen + delta * 28.0)


func _update_noise(delta: float, moving: bool, sprinting: bool) -> void:
	noise_level = 0.0
	if moving:
		if in_water:
			noise_level = 0.85 if sprinting else 0.38
		elif is_on_floor():
			noise_level = 0.78 if sprinting else (0.07 if crouching else 0.27)
	elif in_water and absf(velocity.y) > 0.5:
		noise_level = 0.3
	_noise_clock -= delta
	if noise_level > 0.0 and _noise_clock <= 0.0:
		noise_emitted.emit(global_position, noise_level)
		_noise_clock = 0.48 if sprinting else (0.85 if in_water else 0.62)


func _update_camera(delta: float, sprinting: bool) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var bob: Vector3 = Vector3.ZERO
	if head_bob_enabled and horizontal_speed > 0.2 and is_on_floor() and not in_water and not _climbing:
		_bob_clock += delta * horizontal_speed * 2.3
		var amplitude: float = 0.013 if crouching else (0.028 if sprinting else 0.02)
		bob = Vector3(cos(_bob_clock * 0.5) * amplitude * 0.4, sin(_bob_clock) * amplitude, 0.0)
	_landing_offset = move_toward(_landing_offset, 0.0, delta * 0.5)
	_head.position = Vector3(bob.x, _eye_height + bob.y + _landing_offset, 0.0)
	camera.fov = lerpf(camera.fov, base_fov + (5.0 if sprinting else 0.0), 1.0 - exp(-delta * 5.0))
	_flashlight.light_energy = lerpf(_flashlight.light_energy, 1.35 if submerged else 2.25, 1.0 - exp(-delta * 4.0))
	_flashlight.spot_range = 9.0 if submerged else 19.0
	_flashlight.light_color = Color(0.48, 0.77, 0.84) if submerged else Color(0.82, 0.88, 0.82)


func _update_flashlight() -> void:
	_flashlight.visible = light_on


func apply_settings(values: Dictionary) -> void:
	if values.has("mouse_sensitivity"):
		mouse_sensitivity = clampf(float(values["mouse_sensitivity"]), 0.0005, 0.008)
	if values.has("head_bob_enabled"):
		head_bob_enabled = bool(values["head_bob_enabled"])
	if values.has("invert_y"):
		invert_y = bool(values["invert_y"])
	if values.has("fov"):
		base_fov = clampf(float(values["fov"]), 60.0, 100.0)


func take_damage(amount: float, reason: String) -> void:
	if not enabled or _dead:
		return
	health = maxf(0.0, health - maxf(amount, 0.0))
	if health <= 0.0:
		_dead = true
		enabled = false
		velocity = Vector3.ZERO
		noise_level = 0.0
		died.emit(reason)


func reset_at(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	_pitch = 0.0
	_head.rotation = Vector3.ZERO
	_eye_height = STANDING_EYE
	_head.position = Vector3(0.0, STANDING_EYE, 0.0)
	var capsule := _collision.shape as CapsuleShape3D
	capsule.height = STANDING_HEIGHT
	_collision.position.y = STANDING_HEIGHT * 0.5
	oxygen = 100.0
	stamina = 100.0
	health = 100.0
	noise_level = 0.0
	_noise_clock = 0.0
	_bob_clock = 0.0
	_landing_offset = 0.0
	_last_vertical_speed = 0.0
	_sprint_exhausted = false
	_dead = false
	_climbing = false
	crouching = false
	light_on = true
	camera.fov = base_fov
	_update_medium(false)
	_update_flashlight()
