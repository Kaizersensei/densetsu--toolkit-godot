@tool
extends RefCounted


func select_same_mesh_nodes(editor_iface: EditorInterface, include_reference: bool = true, clear_existing: bool = true) -> Dictionary:
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

	var reference_mesh: Mesh = reference_node.mesh
	var reference_mesh_path: String = reference_mesh.resource_path

	var matches: Array[MeshInstance3D] = []
	var all_mesh_nodes: Array[Node] = scene_root.find_children("*", "MeshInstance3D", true, false)
	for node_obj in all_mesh_nodes:
		var mesh_node: MeshInstance3D = node_obj as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if not include_reference and mesh_node == reference_node:
			continue
		if _mesh_matches_reference(mesh_node.mesh, reference_mesh, reference_mesh_path):
			matches.append(mesh_node)

	if clear_existing:
		selection.clear()
	for mesh_node in matches:
		selection.add_node(mesh_node)

	return {
		"ok": true,
		"reference_node_path": str(reference_node.get_path()),
		"reference_mesh_path": reference_mesh_path,
		"matched_count": matches.size()
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


func _mesh_matches_reference(candidate: Mesh, reference: Mesh, reference_path: String) -> bool:
	if candidate == null or reference == null:
		return false
	if candidate == reference:
		return true
	if not reference_path.is_empty() and candidate.resource_path == reference_path:
		return true
	return false
