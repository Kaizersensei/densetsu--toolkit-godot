@tool
extends RefCounted

const MESH_OBJ_HELPER_SCRIPT: Script = preload("res://addons/densetsu_tool_suite/helpers/mesh_obj_helper.gd")
const NORMAL_SMOOTH_EPS: float = 0.0001
var SUPPORTED_EXTS: PackedStringArray = PackedStringArray(["obj", "glb", "gltf", "fbx", "dae", "tres", "res"])
var SUBDIV_FACTORS: PackedInt32Array = PackedInt32Array([1, 2, 4])


func subdivide_mesh_paths_to_obj(paths: PackedStringArray, editor_iface: EditorInterface = null) -> Dictionary:
	var files: PackedStringArray = _expand_paths(paths)
	var converted: int = 0
	var failed: int = 0
	var skipped: int = 0
	var outputs: PackedStringArray = PackedStringArray()

	var mesh_obj_helper: Object = _get_mesh_obj_helper()
	if mesh_obj_helper == null or not mesh_obj_helper.has_method("export_mesh_to_obj"):
		return {"ok": false, "error": "Mesh OBJ helper unavailable."}

	for file_path in files:
		var ext: String = file_path.get_extension().to_lower()
		if not SUPPORTED_EXTS.has(ext):
			skipped += 1
			continue

		var mesh: Mesh = _load_mesh_from_path(file_path)
		if mesh == null:
			skipped += 1
			continue

		var base_name: String = file_path.get_file().get_basename()
		for factor in SUBDIV_FACTORS:
			var subd_mesh: Mesh = _subdivide_mesh(mesh, factor, true)
			if subd_mesh == null:
				failed += 1
				continue
			var out_path: String = file_path.get_base_dir().path_join("%s_subd%d.obj" % [base_name, factor])
			var ok: bool = mesh_obj_helper.call("export_mesh_to_obj", subd_mesh, out_path, base_name + "_subd" + str(factor))
			if not ok:
				failed += 1
				continue
			_refresh_path(out_path, editor_iface)
			var mtl_path: String = out_path.get_base_dir().path_join(out_path.get_file().get_basename() + ".mtl")
			if FileAccess.file_exists(mtl_path):
				_refresh_path(mtl_path, editor_iface)
			converted += 1
			outputs.append(out_path)

	return {
		"ok": failed == 0 and converted > 0,
		"converted": converted,
		"failed": failed,
		"skipped": skipped,
		"paths": outputs
	}


func _load_mesh_from_path(path: String) -> Mesh:
	var res: Resource = ResourceLoader.load(path)
	if res == null:
		return null
	if res is Mesh:
		return res as Mesh
	if res is PackedScene:
		var scene: PackedScene = res as PackedScene
		var inst: Node = scene.instantiate()
		var mesh: Mesh = _extract_mesh_from_node(inst)
		inst.queue_free()
		return mesh
	return null


func _extract_mesh_from_node(root: Node) -> Mesh:
	if root == null:
		return null
	var direct: MeshInstance3D = root as MeshInstance3D
	if direct != null and direct.mesh != null:
		return direct.mesh
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	for node_obj in meshes:
		var mi: MeshInstance3D = node_obj as MeshInstance3D
		if mi != null and mi.mesh != null:
			return mi.mesh
	return null


func _subdivide_mesh(mesh: Mesh, iterations: int, smooth_normals: bool) -> Mesh:
	var current: Mesh = mesh
	for _i in range(max(iterations, 0)):
		current = _subdivide_mesh_once(current, smooth_normals)
		if current == null:
			return null
	return current


func _subdivide_mesh_once(mesh: Mesh, smooth_normals: bool) -> Mesh:
	if mesh == null:
		return null
	var out_mesh := ArrayMesh.new()
	var surface_count: int = mesh.get_surface_count()
	for surface_idx in range(surface_count):
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = _as_packed_vector3_array(_get_surface_array_slot(arrays, Mesh.ARRAY_VERTEX))
		if vertices.is_empty():
			continue
		var normals: PackedVector3Array = _as_packed_vector3_array(_get_surface_array_slot(arrays, Mesh.ARRAY_NORMAL))
		var uvs: PackedVector2Array = _as_packed_vector2_array(_get_surface_array_slot(arrays, Mesh.ARRAY_TEX_UV))
		var indices: PackedInt32Array = _as_packed_int32_array(_get_surface_array_slot(arrays, Mesh.ARRAY_INDEX))
		var primitive: int = _get_surface_primitive_type(mesh, surface_idx)
		var triangles: PackedInt32Array = _build_triangle_indices(primitive, vertices.size(), indices)
		if triangles.is_empty():
			continue

		var has_normals: bool = (not normals.is_empty()) and (normals.size() == vertices.size())
		var has_uvs: bool = (not uvs.is_empty()) and (uvs.size() == vertices.size())

		var new_vertices: PackedVector3Array = PackedVector3Array()
		var new_normals: PackedVector3Array = PackedVector3Array()
		var new_uvs: PackedVector2Array = PackedVector2Array()

		for i in range(0, triangles.size(), 3):
			var i0: int = triangles[i]
			var i1: int = triangles[i + 1]
			var i2: int = triangles[i + 2]

			var p0: Vector3 = vertices[i0]
			var p1: Vector3 = vertices[i1]
			var p2: Vector3 = vertices[i2]

			var n0: Vector3 = normals[i0] if has_normals else Vector3.ZERO
			var n1: Vector3 = normals[i1] if has_normals else Vector3.ZERO
			var n2: Vector3 = normals[i2] if has_normals else Vector3.ZERO

			var uv0: Vector2 = uvs[i0] if has_uvs else Vector2.ZERO
			var uv1: Vector2 = uvs[i1] if has_uvs else Vector2.ZERO
			var uv2: Vector2 = uvs[i2] if has_uvs else Vector2.ZERO

			var face_normal: Vector3 = Vector3.ZERO
			if not has_normals:
				face_normal = (p1 - p0).cross(p2 - p0).normalized()

			var p01: Vector3 = (p0 + p1) * 0.5
			var p12: Vector3 = (p1 + p2) * 0.5
			var p20: Vector3 = (p2 + p0) * 0.5

			var uv01: Vector2 = (uv0 + uv1) * 0.5
			var uv12: Vector2 = (uv1 + uv2) * 0.5
			var uv20: Vector2 = (uv2 + uv0) * 0.5

			var n01: Vector3 = (n0 + n1).normalized() if has_normals else face_normal
			var n12: Vector3 = (n1 + n2).normalized() if has_normals else face_normal
			var n20: Vector3 = (n2 + n0).normalized() if has_normals else face_normal

			_append_triangle(new_vertices, new_normals, new_uvs, p0, p01, p20, n0, n01, n20, uv0, uv01, uv20, has_normals, has_uvs, face_normal)
			_append_triangle(new_vertices, new_normals, new_uvs, p01, p1, p12, n01, n1, n12, uv01, uv1, uv12, has_normals, has_uvs, face_normal)
			_append_triangle(new_vertices, new_normals, new_uvs, p20, p12, p2, n20, n12, n2, uv20, uv12, uv2, has_normals, has_uvs, face_normal)
			_append_triangle(new_vertices, new_normals, new_uvs, p01, p12, p20, n01, n12, n20, uv01, uv12, uv20, has_normals, has_uvs, face_normal)

		if smooth_normals:
			new_normals = _compute_smooth_normals(new_vertices)

		var out_arrays: Array = []
		out_arrays.resize(Mesh.ARRAY_MAX)
		out_arrays[Mesh.ARRAY_VERTEX] = new_vertices
		if not new_normals.is_empty():
			out_arrays[Mesh.ARRAY_NORMAL] = new_normals
		if has_uvs and not new_uvs.is_empty():
			out_arrays[Mesh.ARRAY_TEX_UV] = new_uvs
		out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		var surf_mat: Material = mesh.surface_get_material(surface_idx)
		if surf_mat != null:
			out_mesh.surface_set_material(out_mesh.get_surface_count() - 1, surf_mat)
	return out_mesh


func _compute_smooth_normals(vertices: PackedVector3Array) -> PackedVector3Array:
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(vertices.size())
	if vertices.size() < 3:
		return normals

	var sums: Dictionary = {}
	for i in range(0, vertices.size(), 3):
		if i + 2 >= vertices.size():
			break
		var p0: Vector3 = vertices[i]
		var p1: Vector3 = vertices[i + 1]
		var p2: Vector3 = vertices[i + 2]
		var face: Vector3 = (p1 - p0).cross(p2 - p0)
		if face == Vector3.ZERO:
			continue
		var k0: Vector3i = _pos_key(p0)
		var k1: Vector3i = _pos_key(p1)
		var k2: Vector3i = _pos_key(p2)
		sums[k0] = (sums.get(k0, Vector3.ZERO) as Vector3) + face
		sums[k1] = (sums.get(k1, Vector3.ZERO) as Vector3) + face
		sums[k2] = (sums.get(k2, Vector3.ZERO) as Vector3) + face

	for i in range(vertices.size()):
		var key: Vector3i = _pos_key(vertices[i])
		var n: Vector3 = sums.get(key, Vector3.ZERO)
		if n == Vector3.ZERO:
			n = Vector3.UP
		normals[i] = n.normalized()
	return normals


func _pos_key(pos: Vector3) -> Vector3i:
	var qx: int = int(round(pos.x / NORMAL_SMOOTH_EPS))
	var qy: int = int(round(pos.y / NORMAL_SMOOTH_EPS))
	var qz: int = int(round(pos.z / NORMAL_SMOOTH_EPS))
	return Vector3i(qx, qy, qz)


func _append_triangle(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	n0: Vector3,
	n1: Vector3,
	n2: Vector3,
	uv0: Vector2,
	uv1: Vector2,
	uv2: Vector2,
	has_normals: bool,
	has_uvs: bool,
	face_normal: Vector3
) -> void:
	verts.append(p0)
	verts.append(p1)
	verts.append(p2)
	if has_normals:
		norms.append(n0)
		norms.append(n1)
		norms.append(n2)
	elif face_normal != Vector3.ZERO:
		norms.append(face_normal)
		norms.append(face_normal)
		norms.append(face_normal)
	if has_uvs:
		uvs.append(uv0)
		uvs.append(uv1)
		uvs.append(uv2)


func _build_triangle_indices(primitive: int, vertex_count: int, indices: PackedInt32Array) -> PackedInt32Array:
	var source: PackedInt32Array = PackedInt32Array()
	if indices.is_empty():
		source.resize(vertex_count)
		for i in range(vertex_count):
			source[i] = i
	else:
		source = indices

	var out: PackedInt32Array = PackedInt32Array()
	match primitive:
		Mesh.PRIMITIVE_TRIANGLES:
			var tri_end: int = source.size() - (source.size() % 3)
			for i in range(0, tri_end, 3):
				out.push_back(source[i])
				out.push_back(source[i + 1])
				out.push_back(source[i + 2])
		Mesh.PRIMITIVE_TRIANGLE_STRIP:
			for i in range(2, source.size()):
				var a: int = source[i - 2]
				var b: int = source[i - 1]
				var c: int = source[i]
				if a == b or b == c or a == c:
					continue
				if (i % 2) == 0:
					out.push_back(a)
					out.push_back(b)
					out.push_back(c)
				else:
					out.push_back(b)
					out.push_back(a)
					out.push_back(c)
		_:
			return PackedInt32Array()
	return out


func _get_surface_primitive_type(mesh: Mesh, surface_idx: int) -> int:
	if mesh.has_method("surface_get_primitive_type"):
		return int(mesh.call("surface_get_primitive_type", surface_idx))
	return Mesh.PRIMITIVE_TRIANGLES


func _get_surface_array_slot(arrays: Array, slot_index: int) -> Variant:
	if slot_index < 0 or slot_index >= arrays.size():
		return null
	return arrays[slot_index]


func _as_packed_vector3_array(value: Variant) -> PackedVector3Array:
	if value is PackedVector3Array:
		return value as PackedVector3Array
	return PackedVector3Array()


func _as_packed_vector2_array(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return value as PackedVector2Array
	return PackedVector2Array()


func _as_packed_int32_array(value: Variant) -> PackedInt32Array:
	if value is PackedInt32Array:
		return value as PackedInt32Array
	return PackedInt32Array()


func _expand_paths(paths: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for p in paths:
		if p.ends_with(".import") or p.ends_with(".uid"):
			continue
		if _is_resource_dir(p):
			_collect_resource_files_recursive(p, out)
		else:
			out.append(p)
	return out


func _is_resource_dir(path: String) -> bool:
	if path.is_empty():
		return false
	var abs_path: String = ProjectSettings.globalize_path(path)
	return DirAccess.dir_exists_absolute(abs_path)


func _collect_resource_files_recursive(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name: String = dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var full_path: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_resource_files_recursive(full_path, out)
		else:
			if full_path.ends_with(".import") or full_path.ends_with(".uid"):
				continue
			out.append(full_path)
	dir.list_dir_end()


func _refresh_path(path: String, editor_iface: EditorInterface) -> void:
	if editor_iface == null:
		return
	var fs: EditorFileSystem = editor_iface.get_resource_filesystem()
	if fs == null:
		return
	fs.update_file(path)


func _get_mesh_obj_helper() -> RefCounted:
	if MESH_OBJ_HELPER_SCRIPT == null:
		return null
	return MESH_OBJ_HELPER_SCRIPT.new()
