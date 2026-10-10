extends RefCounted
## Rebind imported rest geometry to local cross sections, preserving textures and topology.
## Imported limb rigs have distant pivots: rotating them does not follow a swim path.
const STEP := 0.75
var actor: Node3D
var skeleton: Skeleton3D
var bones: Array[int] = []
var radii: Array[float] = []
var length: float = 0.0
var radius: float = 0.0
var _capsule := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()

func configure(owner_node: Node3D) -> void:
	actor = owner_node
	skeleton = actor._skeleton
	_query.shape = _capsule
	_query.collision_mask = 1
	_query.exclude = [actor.get_rid()]
	_query.margin = 0.02
	if skeleton == null:
		return
	var inverse := actor.global_transform.affine_inverse()
	var baked: Array[Dictionary] = []
	for mesh: MeshInstance3D in actor._visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.skin == null:
			continue
		var matrices: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var bone: int = mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			matrices.append(skeleton.global_transform * skeleton.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(bind))
		var rest_to_model := (inverse * matrices[0]).affine_inverse()
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = indices.size() / vertices.size()
			for index in vertices.size():
				var point := Vector3.ZERO
				var normal := Vector3.ZERO
				for slot in influences:
					var offset := index * influences + slot
					var matrix := matrices[indices[offset]]
					point += (matrix * vertices[index]) * weights[offset]
					normal += (matrix.basis.inverse().transposed() * normals[index]) * weights[offset]
				point = inverse * point
				vertices[index] = point
				normals[index] = (inverse.basis.inverse().transposed() * normal).normalized()
				length = maxf(length, point.z)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			# Tangents must be regenerated after the imported bind transforms are baked.
			arrays[Mesh.ARRAY_TANGENT] = null
			var material := mesh.get_active_material(surface)
			if material is ShaderMaterial:
				material.set_shader_parameter("rest_to_model", rest_to_model)
			baked.append({"mesh": mesh, "arrays": arrays, "material": material})
	var count := ceili(length / STEP) + 1
	var skin := Skin.new()
	var inverse_skeleton := skeleton.global_transform.affine_inverse() * actor.global_transform
	for index in count:
		var bone := skeleton.get_bone_count()
		skeleton.add_bone("waterhouse_spine_%d" % index)
		var rest := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, float(index) * STEP))
		skeleton.set_bone_rest(bone, inverse_skeleton * rest)
		actor._bone_rest.append(rest)
		skin.add_bind(bone, rest.affine_inverse())
		bones.append(bone)
		radii.append(0.15)
	var rebuilt: Dictionary = {}
	for item in baked:
		var arrays: Array = item.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		var weights := PackedFloat32Array()
		indices.resize(vertices.size() * 4)
		weights.resize(vertices.size() * 4)
		for index in vertices.size():
			var point := vertices[index]
			var coordinate := clampf(point.z / STEP, 0.0, float(count - 1))
			var low := mini(floori(coordinate), count - 2)
			var weight := coordinate - float(low)
			indices[index * 4] = low
			indices[index * 4 + 1] = low + 1
			# Godot stores skin weights as UNORM16. Complement integer weights so
			# truncation cannot lose one unit and shrink the mesh toward world zero.
			var quantized := roundi(weight * 65535.0)
			weights[index * 4] = minf(1.0, float(65535 - quantized) / 65535.0 + 0.0000002)
			weights[index * 4 + 1] = minf(1.0, float(quantized) / 65535.0 + 0.0000002)
			var extent := Vector2(point.x, point.y).length() + 0.22
			# Include nose vertices slightly ahead of the first cross section.
			extent += maxf(0.0, -point.z)
			radii[low] = maxf(radii[low], extent)
			radii[low + 1] = maxf(radii[low + 1], extent)
			radius = maxf(radius, extent)
		arrays[Mesh.ARRAY_BONES] = indices
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var mesh: MeshInstance3D = item.mesh
		if not rebuilt.has(mesh):
			rebuilt[mesh] = ArrayMesh.new()
		var output: ArrayMesh = rebuilt[mesh]
		var surface_tool := SurfaceTool.new()
		var temporary := ArrayMesh.new()
		temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		surface_tool.create_from(temporary, 0)
		surface_tool.generate_tangents()
		surface_tool.commit(output)
		output.surface_set_material(output.get_surface_count() - 1, item.material)
	for mesh: MeshInstance3D in rebuilt:
		mesh.mesh = rebuilt[mesh]
		mesh.skin = skin
		mesh.extra_cull_margin = length + radius

func pose() -> void:
	var inverse := skeleton.global_transform.affine_inverse()
	var time := float(Time.get_ticks_msec()) * 0.001
	for index in bones.size():
		var distance := float(index) * STEP
		var center: Vector3 = actor._spine_sample(distance)
		var tangent: Vector3 = actor._spine_sample(maxf(0.0, distance - 0.2)) - actor._spine_sample(distance + 0.2)
		if tangent.length_squared() < 0.0001:
			tangent = actor._heading
		tangent = tangent.normalized()
		var frame := Basis.looking_at(tangent, Vector3.UP if absf(tangent.y) < 0.96 else Vector3.RIGHT)
		# A small travelling stroke stays inside the measured 0.22-metre reserve.
		var wave := sin(time * 1.5 - distance * 0.65) * 0.10 * clampf(distance / length, 0.0, 1.0)
		center += frame.y * wave if actor.get_script().resource_path.ends_with("whale.gd") else frame.x * wave
		skeleton.set_bone_global_pose_override(bones[index], inverse * Transform3D(frame, center), 1.0, true)

func sections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in bones.size():
		result.append({"center": actor._spine_sample(float(index) * STEP), "radius": radii[index], "distance": float(index) * STEP})
	return result

func is_clear() -> bool:
	var body := sections()
	var space := actor.get_world_3d().direct_space_state
	for index in range(1, body.size()):
		var start: Vector3 = body[index - 1].center
		var finish: Vector3 = body[index].center
		var segment := finish - start
		_capsule.radius = maxf(body[index - 1].radius, body[index].radius) + STEP
		_capsule.height = segment.length() + _capsule.radius * 2.0
		var direction := segment.normalized() if segment.length_squared() > 0.0001 else Vector3.UP
		_query.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction)), (start + finish) * 0.5)
		if not space.intersect_shape(_query, 1).is_empty():
			return false
	return true
