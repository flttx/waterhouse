extends RigidBody3D
## A real ballistic object: sound is emitted at its collision / water impact.

signal landed(position: Vector3)
var age: float = 0.0
var sounded: bool = false


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 2
	collision_layer = 8
	collision_mask = 1
	mass = 0.3
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.09
	shape.shape = sphere
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.075
	cylinder.bottom_radius = 0.075
	cylinder.height = 0.2
	mesh.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.57, 0.62, 0.58)
	material.metallic = 0.85
	material.roughness = 0.26
	mesh.material_override = material
	add_child(mesh)
	body_entered.connect(func(_body: Node) -> void: _impact())


func _physics_process(delta: float) -> void:
	age += delta
	if global_position.y <= 0.0 and absf(global_position.x) < 19.0 and absf(global_position.z) < 42.0:
		_impact()
		linear_damp = 3.0
		apply_central_force(Vector3.UP * 3.1)
	if age > 10.0:
		queue_free()


func _impact() -> void:
	if sounded:
		return
	sounded = true
	landed.emit(global_position)
