@tool
extends RefCounted

const _EPS: float = 0.00001


func select_intersecting_mesh_nodes(editor_iface: EditorInterface, clear_existing: bool = true) -> Dictionary:
	if editor_iface == null:
		return {"ok": false, "error": "Editor interface unavailable."}

	var scene_root: Node = editor_iface.get_edited_scene_root()
	if scene_root == null:
		return {"ok": false, "error": "No edited scene root."}

	var selection: EditorSelection = editor_iface.get_selection()
	if selection == null:
		return {"ok": false, "error": "Editor selection unavailable."}

	var selected_nodes: Array[Node] = selection.get_selected_nodes()
	var reference_node: MeshInstance3D = _resolve_reference_mesh_node(selected_nodes)
	if reference_node == null or reference_node.mesh == null:
		return {"ok": false, "error": "Select a MeshInstance3D (or parent containing one) first."}

	var ref_world_aabb: AABB = _compute_world_aabb(reference_node)
	if ref_world_aabb.size.length_squared() <= _EPS:
		return {"ok": false, "error": "Selected mesh has invalid bounds."}

	var intersectors: Array[MeshInstance3D] = []
	var all_mesh_nodes: Array[Node] = scene_root.find_children("*", "MeshInstance3D", true, false)
	for node_obj in all_mesh_nodes:
		var mesh_node: MeshInstance3D = node_obj as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if mesh_node == reference_node:
			continue
		if not mesh_node.visible:
			continue
		var world_aabb: AABB = _compute_world_aabb(mesh_node)
		if world_aabb.size.length_squared() <= _EPS:
			continue
		if ref_world_aabb.intersects(world_aabb):
			intersectors.append(mesh_node)

	if clear_existing:
		selection.clear()
	for node_match in intersectors:
		selection.add_node(node_match)

	return {
		"ok": true,
		"reference_node_path": str(reference_node.get_path()),
		"matched_count": intersectors.size()
	}


func _resolve_reference_mesh_node(selected_nodes: Array[Node]) -> MeshInstance3D:
	for node_obj in selected_nodes:
		var direct: MeshInstance3D = node_obj as MeshInstance3D
		if direct != null and direct.mesh != null:
			return direct
		if node_obj == null:
			continue
		var descendants: Array[Node] = node_obj.find_children("*", "MeshInstance3D", true, false)
		for desc in descendants:
			var mesh_desc: MeshInstance3D = desc as MeshInstance3D
			if mesh_desc != null and mesh_desc.mesh != null:
				return mesh_desc
	return null


func _compute_world_aabb(mesh_node: MeshInstance3D) -> AABB:
	var local_aabb: AABB = mesh_node.get_aabb()
	return _transform_aabb(mesh_node.global_transform, local_aabb)


func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var center: Vector3 = aabb.position + aabb.size * 0.5
	var extents: Vector3 = aabb.size * 0.5
	var basis: Basis = xform.basis
	var abs_basis: Basis = Basis(
		Vector3(absf(basis.x.x), absf(basis.x.y), absf(basis.x.z)),
		Vector3(absf(basis.y.x), absf(basis.y.y), absf(basis.y.z)),
		Vector3(absf(basis.z.x), absf(basis.z.y), absf(basis.z.z))
	)
	var world_center: Vector3 = xform * center
	var world_extents: Vector3 = Vector3(
		abs_basis.x.dot(extents),
		abs_basis.y.dot(extents),
		abs_basis.z.dot(extents)
	)
	return AABB(world_center - world_extents, world_extents * 2.0)
