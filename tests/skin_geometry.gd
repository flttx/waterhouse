extends RefCounted
## CPU counterpart of Godot skinning for audit-only use.
## Bind indices resolve by name because imported skins use bind_bone = -1.
static func vertices_world(actor: Node3D, rest: bool = false) -> PackedVector3Array:
	return vertices_from(actor._skeleton, actor._visual, rest)


static func vertices_from(skeleton: Skeleton3D, visual: Node3D, rest: bool = false) -> PackedVector3Array:
	var output := PackedVector3Array()
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.skin == null:
			continue
		var matrices: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var bone: int = mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			var pose := skeleton.get_bone_global_rest(bone) if rest else skeleton.get_bone_global_pose(bone)
			matrices.append(skeleton.global_transform * pose * mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = bones.size() / vertices.size()
			for index in vertices.size():
				var position := Vector3.ZERO
				for slot in influences:
					var influence: int = index * influences + slot
					position += (matrices[bones[influence]] * vertices[index]) * weights[influence]
				output.append(position)
	return output
