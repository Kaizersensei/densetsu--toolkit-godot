@tool
extends EditorPlugin

const MESH_OBJ_HELPER_SCRIPT: Script = preload("res://addons/densetsu_tool_suite/helpers/mesh_obj_helper.gd")
var SUPPORTED_EXTS: PackedStringArray = PackedStringArray(["fbx", "glb", "gltf", "blend", "obj", "dae", "tres", "res"])
const OUT_SUBDIR: String = "_arraymeshes"
const OUTPUT_PER_FILE := 0
const OUTPUT_COMMON := 1
const MODE_BY_MESH := 0
const MODE_BY_MATERIAL := 1
const MODE_COMBINED := 2

var bake_transforms: bool = true
var overwrite_existing: bool = true
var use_subdir: bool = true
var _ctx_plugin: EditorContextMenuPlugin
var _mesh_obj_helper: RefCounted


class _ArrayMeshContextMenuPlugin:
	extends EditorContextMenuPlugin
	var _owner: EditorPlugin

	func _init(owner: EditorPlugin) -> void:
		_owner = owner

	func _popup_menu(paths: PackedStringArray) -> void:
		if paths.is_empty():
			return
		add_context_menu_item("Extract ArrayMeshes (Per File Folder)", Callable(_owner, "_on_extract_paths_from_context"))
		add_context_menu_item("Extract ArrayMeshes (Common Folder)", Callable(_owner, "_on_extract_paths_from_context_common"))
		add_context_menu_item("Extract Material Meshes (Per File Folder)", Callable(_owner, "_on_extract_material_paths_from_context"))
		add_context_menu_item("Extract Material Meshes (Common Folder)", Callable(_owner, "_on_extract_material_paths_from_context_common"))
		add_context_menu_item("Extract Combined ArrayMesh (Per File Folder)", Callable(_owner, "_on_extract_combined_paths_from_context"))
		add_context_menu_item("Extract Combined ArrayMesh (Common Folder)", Callable(_owner, "_on_extract_combined_paths_from_context_common"))


func _enter_tree() -> void:
	add_tool_menu_item("Extract ArrayMeshes (Selected)", _on_extract_selected)
	add_tool_menu_item("Extract ArrayMeshes (Common Folder)", _on_extract_selected_common)
	add_tool_menu_item("Extract Material Meshes (Selected)", _on_extract_selected_materials)
	add_tool_menu_item("Extract Material Meshes (Common Folder)", _on_extract_selected_materials_common)
	add_tool_menu_item("Extract Combined ArrayMesh (Selected)", _on_extract_selected_combined)
	add_tool_menu_item("Extract Combined ArrayMesh (Common Folder)", _on_extract_selected_combined_common)
	_ctx_plugin = _ArrayMeshContextMenuPlugin.new(self)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _ctx_plugin)


func _exit_tree() -> void:
	remove_tool_menu_item("Extract ArrayMeshes (Selected)")
	remove_tool_menu_item("Extract ArrayMeshes (Common Folder)")
	remove_tool_menu_item("Extract Material Meshes (Selected)")
	remove_tool_menu_item("Extract Material Meshes (Common Folder)")
	remove_tool_menu_item("Extract Combined ArrayMesh (Selected)")
	remove_tool_menu_item("Extract Combined ArrayMesh (Common Folder)")
	if _ctx_plugin:
		remove_context_menu_plugin(_ctx_plugin)
		_ctx_plugin = null


func _on_extract_selected() -> void:
	var paths: PackedStringArray = _get_filesystem_selection()
	_extract_paths(paths, MODE_BY_MESH, OUTPUT_PER_FILE)


func _on_extract_selected_common() -> void:
	var paths: PackedStringArray = _get_filesystem_selection()
	_extract_paths(paths, MODE_BY_MESH, OUTPUT_COMMON)


func _on_extract_paths_from_context(paths: PackedStringArray = PackedStringArray()) -> void:
	_extract_paths(paths, MODE_BY_MESH, OUTPUT_PER_FILE)


func _on_extract_paths_from_context_common(paths: PackedStringArray = PackedStringArray()) -> void:
	_extract_paths(paths, MODE_BY_MESH, OUTPUT_COMMON)


func _on_extract_selected_materials() -> void:
	var paths: PackedStringArray = _get_filesystem_selection()
	_extract_paths(paths, MODE_BY_MATERIAL, OUTPUT_PER_FILE)


func _on_extract_selected_materials_common() -> void:
	var paths: PackedStringArray = _get_filesystem_selection()
	_extract_paths(paths, MODE_BY_MATERIAL, OUTPUT_COMMON)


func _on_extract_material_paths_from_context(paths: PackedStringArray = PackedStringArray()) -> void:
	_extract_paths(paths, MODE_BY_MATERIAL, OUTPUT_PER_FILE)


func _on_extract_material_paths_from_context_common(paths: PackedStringArray = PackedStringArray()) -> void:
	_extract_paths(paths, MODE_BY_MATERIAL, OUTPUT_COMMON)


func _on_extract_selected_combined() -> void:
	var paths: PackedStringArray = _get_filesystem_selection()
	_extract_paths(paths, MODE_COMBINED, OUTPUT_PER_FILE)


func _on_extract_selected_combined_common() -> void:
	var paths: PackedStringArray = _get_filesystem_selection()
	_extract_paths(paths, MODE_COMBINED, OUTPUT_COMMON)


func _on_extract_combined_paths_from_context(paths: PackedStringArray = PackedStringArray()) -> void:
	_extract_paths(paths, MODE_COMBINED, OUTPUT_PER_FILE)


func _on_extract_combined_paths_from_context_common(paths: PackedStringArray = PackedStringArray()) -> void:
	_extract_paths(paths, MODE_COMBINED, OUTPUT_COMMON)


func _extract_paths(paths: PackedStringArray, mode: int, output_mode: int) -> void:
	if paths.is_empty():
		push_warning("Select model files or folders in the FileSystem dock first.")
		return
	print("ArrayMesh extract: selected paths:", paths, "mode=", mode, "output_mode=", output_mode)
	var files: PackedStringArray = _expand_paths(paths)
	for path in files:
		if not _is_supported(path):
			print("ArrayMesh extract: skip unsupported:", path)
			continue
		_extract_from_file(path, mode, output_mode)


func _get_filesystem_selection() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var iface := get_editor_interface()
	if iface and iface.has_method("get_selected_paths"):
		var sel_any := iface.call("get_selected_paths")
		if sel_any is PackedStringArray:
			out = sel_any
		elif sel_any is Array:
			for p in sel_any:
				out.append(String(p))
	if out.size() > 0:
		return out
	var dock := iface.get_file_system_dock() if iface else null
	if dock == null:
		return out
	if dock.has_method("get_selected_paths"):
		var sel_paths: Variant = dock.get_selected_paths()
		if sel_paths is PackedStringArray:
			return sel_paths
		if sel_paths is Array:
			for p in sel_paths:
				out.append(String(p))
			return out
	if dock.has_method("get_selected_files"):
		var sel_files: Variant = dock.get_selected_files()
		if sel_files is PackedStringArray:
			return sel_files
		if sel_files is Array:
			for p in sel_files:
				out.append(String(p))
			return out
	if dock.has_method("get_selected_file"):
		var single: Variant = dock.get_selected_file()
		if single is String and single != "":
			out.append(single)
	return out


func _expand_paths(paths: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for path in paths:
		if path.ends_with(".import") or path.ends_with(".uid"):
			continue
		if _is_dir(path):
			_collect_files_recursive(path, out)
		else:
			out.append(path)
	return out


func _is_dir(path: String) -> bool:
	if path == "":
		return false
	var abs := ProjectSettings.globalize_path(path)
	return DirAccess.dir_exists_absolute(abs)


func _collect_files_recursive(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_files_recursive(full, out)
		else:
			out.append(full)
	dir.list_dir_end()


func _is_supported(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return SUPPORTED_EXTS.has(ext)


func _extract_from_file(path: String, mode: int, output_mode: int) -> void:
	print("ArrayMesh extract: loading:", path)
	var ext := path.get_extension().to_lower()
	var base_dir := path.get_base_dir()
	var out_dir := base_dir
	if use_subdir:
		if output_mode == OUTPUT_COMMON:
			out_dir = base_dir.path_join(OUT_SUBDIR)
		else:
			out_dir = base_dir.path_join(_sanitize(path.get_file().get_basename()))
		_ensure_dir(out_dir)
	print("ArrayMesh extract: out_dir:", out_dir)
	if ext == "obj" and mode == MODE_BY_MESH:
		if _extract_obj_groups(path, out_dir):
			return
	var res := ResourceLoader.load(path)
	if res == null:
		push_warning("Failed to load: " + path)
		print("ArrayMesh extract: load returned null for:", path)
		var fallback := _try_load_imported_resource(path)
		if fallback == null:
			print("ArrayMesh extract: no fallback import resource found for:", path)
			return
		print("ArrayMesh extract: using imported fallback for:", path)
		res = fallback
	if res is PackedScene:
		var inst: Node = res.instantiate()
		_extract_from_scene(inst, path, out_dir, mode)
		inst.free()
		return
	if res is Mesh:
		var mesh := res as Mesh
		if mode == MODE_BY_MATERIAL:
			_extract_mesh_by_material(mesh, path.get_file().get_basename(), out_dir, null, Transform3D.IDENTITY)
		elif mode == MODE_COMBINED:
			_extract_mesh_combined(mesh, path.get_file().get_basename(), out_dir, null, Transform3D.IDENTITY)
		else:
			var out_mesh := _mesh_to_arraymesh(mesh, Transform3D.IDENTITY, null)
			var out_name := _make_out_name(path.get_file().get_basename(), "mesh")
			_save_mesh(out_mesh, out_dir.path_join(out_name + ".obj"))
		return
	push_warning("Unsupported resource type for: " + path)


func _extract_obj_groups(src_obj_path: String, out_dir: String) -> bool:
	var file: FileAccess = FileAccess.open(src_obj_path, FileAccess.READ)
	if file == null:
		push_warning("Failed to read OBJ source: " + src_obj_path)
		return false
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		push_warning("OBJ source is empty: " + src_obj_path)
		return false

	var mtllibs: PackedStringArray = PackedStringArray()
	var vertex_lines: PackedStringArray = PackedStringArray()
	var uv_lines: PackedStringArray = PackedStringArray()
	var normal_lines: PackedStringArray = PackedStringArray()
	var param_uv_lines: PackedStringArray = PackedStringArray()
	var group_order: PackedStringArray = PackedStringArray()
	var group_lines: Dictionary = {}
	var current_group: String = ""
	var anonymous_idx: int = 0

	for raw_line in text.split("\n", false):
		var line: String = String(raw_line).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			continue
		if line.begins_with("mtllib "):
			var mtl_value: String = line.substr(7).strip_edges()
			if not mtl_value.is_empty():
				mtllibs.append(mtl_value)
			continue
		if line.begins_with("v "):
			vertex_lines.append(line)
			continue
		if line.begins_with("vt "):
			uv_lines.append(line)
			continue
		if line.begins_with("vn "):
			normal_lines.append(line)
			continue
		if line.begins_with("vp "):
			param_uv_lines.append(line)
			continue
		if line.begins_with("g ") or line == "g":
			current_group = _ensure_obj_group_name(line.substr(1).strip_edges(), anonymous_idx)
			anonymous_idx += 1
			if not group_lines.has(current_group):
				group_order.append(current_group)
				group_lines[current_group] = PackedStringArray()
			continue
		if line.begins_with("o ") or line == "o":
			var object_group: String = _ensure_obj_group_name(line.substr(1).strip_edges(), anonymous_idx)
			if current_group.is_empty():
				current_group = object_group
				anonymous_idx += 1
				if not group_lines.has(current_group):
					group_order.append(current_group)
					group_lines[current_group] = PackedStringArray()
			continue
		if current_group.is_empty():
			current_group = _ensure_obj_group_name("", anonymous_idx)
			anonymous_idx += 1
			group_order.append(current_group)
			group_lines[current_group] = PackedStringArray()
		var lines_for_group: PackedStringArray = group_lines.get(current_group, PackedStringArray())
		lines_for_group.append(line)
		group_lines[current_group] = lines_for_group

	var wrote_any: bool = false
	var src_dir: String = src_obj_path.get_base_dir()
	var src_base: String = src_obj_path.get_file().get_basename()
	for group_name in group_order:
		var lines_for_group: PackedStringArray = group_lines.get(group_name, PackedStringArray())
		if lines_for_group.is_empty():
			continue
		var has_faces: bool = false
		for group_line in lines_for_group:
			if String(group_line).begins_with("f "):
				has_faces = true
				break
		if not has_faces:
			continue
		var out_name: String = _make_out_name(src_base, group_name)
		var out_obj_path: String = out_dir.path_join(out_name + ".obj")
		var out_mtl_path: String = out_dir.path_join(out_name + ".mtl")
		var out_lines: PackedStringArray = PackedStringArray()
		out_lines.append("# Toolkit OBJ Group Extract")
		out_lines.append("o " + _sanitize(group_name))
		var source_mtl_paths: PackedStringArray = PackedStringArray()
		for mtllib in mtllibs:
			var src_mtl_path: String = src_dir.path_join(_unescape_obj_path(mtllib))
			if FileAccess.file_exists(src_mtl_path):
				source_mtl_paths.append(src_mtl_path)
		if not source_mtl_paths.is_empty():
			out_lines.append("mtllib " + _escape_obj_path_for_obj(out_mtl_path.get_file()))
		out_lines.append("g " + _sanitize(group_name))
		out_lines.append_array(vertex_lines)
		out_lines.append_array(param_uv_lines)
		out_lines.append_array(uv_lines)
		out_lines.append_array(normal_lines)
		out_lines.append_array(lines_for_group)
		if not source_mtl_paths.is_empty():
			var mtl_text: String = _build_group_mtl_text(source_mtl_paths, out_dir)
			if not mtl_text.is_empty():
				if not _write_text_file(out_mtl_path, mtl_text):
					push_warning("Failed to save OBJ group MTL: " + out_mtl_path)
				else:
					_refresh_output_path(out_mtl_path)
		if not _write_text_file(out_obj_path, "\n".join(out_lines) + "\n"):
			push_warning("Failed to save OBJ group extract: " + out_obj_path)
			continue
		_refresh_output_path(out_obj_path)
		wrote_any = true
	return wrote_any


func _ensure_obj_group_name(name: String, anonymous_idx: int) -> String:
	var clean: String = name.strip_edges()
	if clean.is_empty():
		return "group_%d" % anonymous_idx
	return clean


func _unescape_obj_path(path: String) -> String:
	return path.replace("\\ ", " ").replace("\\\\", "\\")


func _escape_obj_path_for_obj(path: String) -> String:
	return path.replace("\\", "/").replace(" ", "\\ ")


func _write_text_file(path: String, text: String) -> bool:
	_ensure_dir(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _build_group_mtl_text(source_mtl_paths: PackedStringArray, out_dir: String) -> String:
	var merged: PackedStringArray = PackedStringArray()
	merged.append("# Toolkit OBJ Group Extract")
	var wrote_any: bool = false
	var seen_paths: Dictionary = {}
	for source_mtl_path in source_mtl_paths:
		if seen_paths.has(source_mtl_path):
			continue
		seen_paths[source_mtl_path] = true
		var file: FileAccess = FileAccess.open(source_mtl_path, FileAccess.READ)
		if file == null:
			continue
		var source_text: String = file.get_as_text()
		file.close()
		if source_text.strip_edges().is_empty():
			continue
		merged.append("")
		merged.append("# source: %s" % source_mtl_path.get_file())
		var source_dir: String = source_mtl_path.get_base_dir()
		for raw_line in source_text.split("\n", false):
			merged.append(_rewrite_mtl_resource_line(String(raw_line), source_dir, out_dir))
		wrote_any = true
	if not wrote_any:
		return ""
	return "\n".join(merged).strip_edges() + "\n"


func _rewrite_mtl_resource_line(line: String, source_dir: String, out_dir: String) -> String:
	var trimmed: String = line.strip_edges()
	if trimmed.is_empty() or trimmed.begins_with("#"):
		return line
	var space_idx: int = trimmed.find(" ")
	var cmd: String = trimmed if space_idx < 0 else trimmed.substr(0, space_idx)
	if not _is_mtl_resource_command(cmd):
		return line
	var tokens: PackedStringArray = _split_obj_tokens(trimmed)
	if tokens.size() < 2:
		return line
	var path_idx: int = tokens.size() - 1
	var raw_path: String = _unescape_obj_path(tokens[path_idx])
	if raw_path.is_empty():
		return line
	var resolved: String = raw_path
	if not _is_absolute_or_res_path(raw_path):
		resolved = source_dir.path_join(raw_path)
	var rewritten: String = _make_relative_path(out_dir, resolved)
	tokens[path_idx] = _escape_obj_path_for_obj(rewritten)
	return " ".join(tokens)


func _is_mtl_resource_command(cmd: String) -> bool:
	match cmd:
		"map_Ka", "map_Kd", "map_Ks", "map_Ke", "map_bump", "bump", "norm", "map_d", "disp", "decal", "refl", "map_Pr", "map_Pm", "map_Ps":
			return true
	return false


func _split_obj_tokens(text: String) -> PackedStringArray:
	var tokens: PackedStringArray = PackedStringArray()
	var current: String = ""
	var escaping: bool = false
	for i in range(text.length()):
		var ch: String = text.substr(i, 1)
		if escaping:
			current += ch
			escaping = false
			continue
		if ch == "\\":
			current += ch
			escaping = true
			continue
		if ch == " " or ch == "\t":
			if not current.is_empty():
				tokens.append(current)
				current = ""
			continue
		current += ch
	if not current.is_empty():
		tokens.append(current)
	return tokens


func _is_absolute_or_res_path(path: String) -> bool:
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return true
	return path.length() > 1 and path.substr(1, 1) == ":"


func _make_relative_path(from_dir: String, to_path: String) -> String:
	var from_norm: String = from_dir.replace("\\", "/")
	var to_norm: String = to_path.replace("\\", "/")
	if from_norm.begins_with("res://"):
		from_norm = from_norm.trim_prefix("res://")
	if to_norm.begins_with("res://"):
		to_norm = to_norm.trim_prefix("res://")
	var from_parts: PackedStringArray = PackedStringArray()
	for part in from_norm.split("/", false):
		if not String(part).is_empty():
			from_parts.append(part)
	var to_parts: PackedStringArray = PackedStringArray()
	for part in to_norm.split("/", false):
		if not String(part).is_empty():
			to_parts.append(part)
	var shared: int = 0
	while shared < from_parts.size() and shared < to_parts.size() and from_parts[shared] == to_parts[shared]:
		shared += 1
	var rel_parts: PackedStringArray = PackedStringArray()
	for i in range(shared, from_parts.size()):
		rel_parts.append("..")
	for i in range(shared, to_parts.size()):
		rel_parts.append(to_parts[i])
	if rel_parts.is_empty():
		return "."
	return "/".join(rel_parts)


func _try_load_imported_resource(src_path: String) -> Resource:
	var import_path := src_path + ".import"
	if not FileAccess.file_exists(import_path):
		return null
	var cfg := ConfigFile.new()
	var err := cfg.load(import_path)
	if err != OK:
		return null
	var remap_path := cfg.get_value("remap", "path", "")
	if remap_path is String and String(remap_path) != "":
		return ResourceLoader.load(String(remap_path))
	var dest_files := cfg.get_value("remap", "dest_files", PackedStringArray())
	if dest_files is PackedStringArray and dest_files.size() > 0:
		return ResourceLoader.load(dest_files[0])
	if dest_files is Array and dest_files.size() > 0:
		return ResourceLoader.load(String(dest_files[0]))
	return null


func _extract_from_scene(inst: Node, src_path: String, out_dir: String, mode: int) -> void:
	var meshes: Array = inst.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		push_warning("No MeshInstance3D found in: " + src_path)
		return
	var base := src_path.get_file().get_basename()
	if mode == MODE_COMBINED:
		_extract_scene_combined(meshes, inst, base, out_dir)
		return
	var idx := 0
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		if mi.mesh == null:
			continue
		var local_xform := Transform3D.IDENTITY
		if bake_transforms and mi is Node3D:
			local_xform = _get_local_to_root(mi, inst)
		if mode == MODE_BY_MATERIAL:
			_extract_mesh_by_material(mi.mesh, base, out_dir, mi, local_xform)
		else:
			var out_mesh := _mesh_to_arraymesh(mi.mesh, local_xform, mi)
			var name := _make_out_name(base, mi.name)
			if meshes.size() > 1:
				name += "__" + str(idx)
			idx += 1
			_save_mesh(out_mesh, out_dir.path_join(name + ".obj"))


func _mesh_to_arraymesh(mesh: Mesh, xf: Transform3D, mi: MeshInstance3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	var surface_count := mesh.get_surface_count()
	var normal_basis := xf.basis
	if xf.basis.determinant() != 0.0:
		normal_basis = xf.basis.inverse().transposed()
	for i in range(surface_count):
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var norms := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var tangents := arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
		if bake_transforms:
			for v in range(verts.size()):
				verts[v] = xf * verts[v]
			if norms.size() > 0:
				for n in range(norms.size()):
					norms[n] = (normal_basis * norms[n]).normalized()
			if tangents.size() > 0:
				var t := 0
				while t + 3 < tangents.size():
					var tv := Vector3(tangents[t], tangents[t + 1], tangents[t + 2])
					tv = (normal_basis * tv).normalized()
					tangents[t] = tv.x
					tangents[t + 1] = tv.y
					tangents[t + 2] = tv.z
					t += 4
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TANGENT] = tangents
		var blend_shapes: Array = mesh.surface_get_blend_shape_arrays(i)
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays, blend_shapes)
		var mat: Material = null
		if mi:
			mat = mi.get_surface_override_material(i)
			if mat == null and mi.material_override != null:
				mat = mi.material_override
		if mat == null:
			mat = mesh.surface_get_material(i)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	if mi and mi.material_override and out.get_surface_count() > 0:
		for i in range(out.get_surface_count()):
			out.surface_set_material(i, mi.material_override)
	return out


func _extract_scene_combined(meshes: Array, root: Node, base: String, out_dir: String) -> void:
	var out := ArrayMesh.new()
	var groups: Array[String] = []
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local_xf := Transform3D.IDENTITY
		if bake_transforms and mi is Node3D:
			local_xf = _get_local_to_root(mi, root)
		_append_mesh_surfaces(out, mi.mesh, local_xf, mi, mi.name, groups)
	if out.get_surface_count() <= 0:
		push_warning("Combined extract produced no surfaces for: " + base)
		return
	out.set_meta("surface_groups", groups)
	var out_name := _make_out_name(base, "combined")
	_save_mesh(out, out_dir.path_join(out_name + ".obj"))


func _extract_mesh_combined(mesh: Mesh, base: String, out_dir: String, mi: MeshInstance3D, xf: Transform3D) -> void:
	var out := ArrayMesh.new()
	var groups: Array[String] = []
	_append_mesh_surfaces(out, mesh, xf, mi, "mesh", groups)
	if out.get_surface_count() <= 0:
		return
	out.set_meta("surface_groups", groups)
	var out_name := _make_out_name(base, "combined")
	_save_mesh(out, out_dir.path_join(out_name + ".obj"))


func _append_mesh_surfaces(out: ArrayMesh, mesh: Mesh, xf: Transform3D, mi: MeshInstance3D, group_name: String, groups: Array[String]) -> void:
	var surface_count := mesh.get_surface_count()
	var normal_basis := xf.basis
	if xf.basis.determinant() != 0.0:
		normal_basis = xf.basis.inverse().transposed()
	for i in range(surface_count):
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var norms := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var tangents := arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
		if bake_transforms:
			for v in range(verts.size()):
				verts[v] = xf * verts[v]
			if norms.size() > 0:
				for n in range(norms.size()):
					norms[n] = (normal_basis * norms[n]).normalized()
			if tangents.size() > 0:
				var t := 0
				while t + 3 < tangents.size():
					var tv := Vector3(tangents[t], tangents[t + 1], tangents[t + 2])
					tv = (normal_basis * tv).normalized()
					tangents[t] = tv.x
					tangents[t + 1] = tv.y
					tangents[t + 2] = tv.z
					t += 4
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TANGENT] = tangents
		var blend_shapes: Array = mesh.surface_get_blend_shape_arrays(i)
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays, blend_shapes)
		var mat: Material = null
		if mi:
			mat = mi.get_surface_override_material(i)
			if mat == null and mi.material_override != null:
				mat = mi.material_override
		if mat == null:
			mat = mesh.surface_get_material(i)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
		groups.append(group_name)
	if mi and mi.material_override and out.get_surface_count() > 0:
		for i in range(out.get_surface_count()):
			out.surface_set_material(i, mi.material_override)


func _extract_mesh_by_material(mesh: Mesh, base: String, out_dir: String, mi: MeshInstance3D, xf: Transform3D) -> void:
	var surface_count := mesh.get_surface_count()
	if surface_count <= 0:
		return
	var normal_basis := xf.basis
	if xf.basis.determinant() != 0.0:
		normal_basis = xf.basis.inverse().transposed()
	var by_label: Dictionary = {}
	var label_order: Array[String] = []
	for i in range(surface_count):
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var norms := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var tangents := arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
		if bake_transforms:
			for v in range(verts.size()):
				verts[v] = xf * verts[v]
			if norms.size() > 0:
				for n in range(norms.size()):
					norms[n] = (normal_basis * norms[n]).normalized()
			if tangents.size() > 0:
				var t := 0
				while t + 3 < tangents.size():
					var tv := Vector3(tangents[t], tangents[t + 1], tangents[t + 2])
					tv = (normal_basis * tv).normalized()
					tangents[t] = tv.x
					tangents[t + 1] = tv.y
					tangents[t + 2] = tv.z
					t += 4
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TANGENT] = tangents
		var mat: Material = null
		if mi:
			mat = mi.get_surface_override_material(i)
			if mat == null and mi.material_override != null:
				mat = mi.material_override
		if mat == null:
			mat = mesh.surface_get_material(i)
		var label := _material_label(mat, i)
		var out_mesh: ArrayMesh = by_label.get(label, null)
		if out_mesh == null:
			out_mesh = ArrayMesh.new()
			by_label[label] = out_mesh
			label_order.append(label)
		var blend_shapes: Array = mesh.surface_get_blend_shape_arrays(i)
		out_mesh.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays, blend_shapes)
		if mat != null:
			out_mesh.surface_set_material(out_mesh.get_surface_count() - 1, mat)
	for label in label_order:
		var out: ArrayMesh = by_label[label]
		var name := _make_out_name(base, label)
		_save_mesh(out, out_dir.path_join(name + ".obj"))


func _material_label(mat: Material, idx: int) -> String:
	if mat != null:
		if mat.resource_name != "":
			return mat.resource_name
		if mat.resource_path != "":
			return mat.resource_path.get_file().get_basename()
	return "mat_" + str(idx)


func _get_local_to_root(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current: Node = node
	while current and current != root:
		if current is Node3D:
			xf = (current as Node3D).transform * xf
		current = current.get_parent()
	return xf


func _make_out_name(base: String, mesh_name: String) -> String:
	var safe_base := _sanitize(base)
	var safe_mesh := _sanitize(mesh_name)
	if safe_mesh == "":
		safe_mesh = "mesh"
	return safe_base + "_" + safe_mesh


func _sanitize(text: String) -> String:
	var out := text.replace(" ", "_")
	out = out.replace("/", "_")
	out = out.replace("\\", "_")
	out = out.replace(":", "_")
	out = out.replace(".", "-")
	return out


func _ensure_dir(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(abs):
		return
	DirAccess.make_dir_recursive_absolute(abs)


func _save_mesh(mesh: ArrayMesh, path: String) -> void:
	if mesh == null:
		return
	if not overwrite_existing and FileAccess.file_exists(path):
		print("ArrayMesh extract: exists, skip:", path)
		return
	var obj_path: String = path
	if obj_path.get_extension().to_lower() != "obj":
		obj_path = obj_path.get_base_dir().path_join(obj_path.get_file().get_basename() + ".obj")
	print("ArrayMesh extract: saving OBJ:", obj_path)
	var helper: RefCounted = _get_mesh_obj_helper()
	if helper == null:
		push_warning("ArrayMesh extract: OBJ helper unavailable.")
		return
	var ok: bool = bool(helper.call("export_mesh_to_obj", mesh, obj_path, obj_path.get_file().get_basename()))
	if not ok:
		push_warning("Failed to save OBJ: " + obj_path)
		return
	_refresh_output_path(obj_path)
	var mtl_path: String = obj_path.get_base_dir().path_join(obj_path.get_file().get_basename() + ".mtl")
	if FileAccess.file_exists(mtl_path):
		_refresh_output_path(mtl_path)
	print("ArrayMesh extract: saved:", obj_path)


func _get_mesh_obj_helper() -> RefCounted:
	if _mesh_obj_helper == null and MESH_OBJ_HELPER_SCRIPT != null:
		_mesh_obj_helper = MESH_OBJ_HELPER_SCRIPT.new()
	return _mesh_obj_helper


func _refresh_output_path(path: String) -> void:
	var iface: EditorInterface = get_editor_interface()
	if iface == null:
		return
	var fs: EditorFileSystem = iface.get_resource_filesystem()
	if fs == null:
		return
	fs.update_file(path)
