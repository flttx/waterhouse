class_name WaterhouseDevice
extends Node3D
## Hold-to-use devices share one interaction contract and have physical presence.

signal activated(device: WaterhouseDevice)

var device_id: String = ""
var title: String = ""
var description: String = ""
var duration: float = 4.0
var required_stage: int = 0
var progress: float = 0.0
var completed: bool = false
var available: bool = false
var wheel: Node3D
var lamp: OmniLight3D
var glow_material: StandardMaterial3D
var is_valve: bool = false


func _ready() -> void:
	is_valve = device_id.begins_with("valve") or device_id.ends_with("_valve")
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.25, 0.24)
	metal.metallic = 0.75
	metal.roughness = 0.43
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.62, 0.36, 0.08)
	yellow.metallic = 0.65
	yellow.roughness = 0.55
	glow_material = StandardMaterial3D.new()
	glow_material.emission_enabled = true
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if is_valve:
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.18
		pipe.bottom_radius = 0.18
		pipe.height = 2.0
		_mesh(pipe, Vector3(0, -0.4, 0.18), metal)
		wheel = Node3D.new()
		add_child(wheel)
		var torus := TorusMesh.new()
		torus.inner_radius = 0.27
		torus.outer_radius = 0.36
		var ring := _mesh(torus, Vector3.ZERO, yellow, wheel)
		ring.rotation.x = PI / 2.0
		for i in 6:
			var spoke := BoxMesh.new()
			spoke.size = Vector3(0.055, 0.63, 0.06)
			var piece := _mesh(spoke, Vector3.ZERO, yellow, wheel)
			piece.rotation.z = float(i) * PI / 3.0
		var hub := SphereMesh.new()
		hub.radius = 0.09
		hub.height = 0.18
		_mesh(hub, Vector3.ZERO, metal, wheel)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 1.25, 0.35)
		_mesh(box, Vector3(0, -0.2, 0), metal)
		var face := BoxMesh.new()
		face.size = Vector3(0.7, 0.86, 0.025)
		_mesh(face, Vector3(0, -0.2, 0.19), yellow)
		var screen := BoxMesh.new()
		screen.size = Vector3(0.5, 0.2, 0.03)
		_mesh(screen, Vector3(0, 0.03, 0.22), glow_material)
		for i in 3:
			var button := CylinderMesh.new()
			button.top_radius = 0.048
			button.bottom_radius = 0.048
			button.height = 0.07
			var piece := _mesh(button, Vector3(float(i - 1) * 0.19, -0.45, 0.25), metal)
			piece.rotation.x = PI / 2.0
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("device", self)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var solid := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.8, 1.0, 0.3)
	solid.shape = box_shape
	solid.position = Vector3(0, -0.2, -0.05)
	body.add_child(solid)
	add_child(body)
	lamp = OmniLight3D.new()
	lamp.position = Vector3(0, 0.6, 0.4)
	lamp.omni_range = 4.0
	lamp.light_energy = 0.65
	add_child(lamp)
	var plate := Label3D.new()
	plate.text = title
	plate.font_size = 42
	plate.pixel_size = 0.007
	plate.position = Vector3(0, 1.02, 0)
	plate.modulate = Color(0.68, 0.84, 0.79)
	plate.outline_modulate = Color(0.01, 0.02, 0.025)
	plate.outline_size = 6
	add_child(plate)
	set_available(false)


func _mesh(mesh: Mesh, pos: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = material
	parent.add_child(instance)
	return instance


func set_available(value: bool) -> void:
	available = value
	if glow_material == null:
		return
	var color := Color(0.17, 0.53, 0.45) if completed else Color(0.76, 0.31, 0.06)
	if available and not completed:
		color = Color(0.43, 0.72, 0.64)
	glow_material.albedo_color = color
	glow_material.emission = color * 0.5
	lamp.light_color = color


func operate(delta: float) -> bool:
	if not available or completed:
		return false
	progress = minf(progress + delta / duration, 1.0)
	if wheel != null:
		wheel.rotation.z = -progress * TAU * 3.0
	if progress >= 1.0:
		completed = true
		set_available(false)
		activated.emit(self)
		return true
	return false


func reset_device() -> void:
	progress = 0.0
	completed = false
	set_available(false)
	if wheel != null:
		wheel.rotation.z = 0.0
