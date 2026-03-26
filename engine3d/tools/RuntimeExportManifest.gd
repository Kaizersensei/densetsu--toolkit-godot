@tool
extends RefCounted

const DEFAULT_MANIFEST_PATH := "res://engine3d/tools/runtime_export_manifest.json"


static func load_manifest(manifest_path: String = DEFAULT_MANIFEST_PATH) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(manifest_path)
	if text.is_empty():
		return {
			"ok": false,
			"message": "Manifest missing or unreadable: %s" % manifest_path,
			"path": manifest_path,
		}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {
			"ok": false,
			"message": "Manifest JSON invalid: %s" % manifest_path,
			"path": manifest_path,
		}
	var manifest: Dictionary = parsed as Dictionary
	return {
		"ok": true,
		"path": manifest_path,
		"version": int(manifest.get("version", 0)),
		"hard_paths": _variant_to_string_array(manifest.get("hard_paths", [])),
		"slot_names": _variant_to_string_array(manifest.get("slot_names", [])),
		"exclude_patterns": _variant_to_string_array(manifest.get("exclude_patterns", [])),
	}


static func collect_runtime_paths(entry_scene_paths: PackedStringArray, manifest_path: String = DEFAULT_MANIFEST_PATH) -> Dictionary:
	var manifest_result: Dictionary = load_manifest(manifest_path)
	if not bool(manifest_result.get("ok", false)):
		return manifest_result

	var slot_lookup: Dictionary = {}
	for slot_name: String in manifest_result.get("slot_names", PackedStringArray()):
		slot_lookup[slot_name] = true

	var include_lookup: Dictionary = {}
	var discovered_lookup: Dictionary = {}
	var missing_lookup: Dictionary = {}
	var scanned_scene_lookup: Dictionary = {}
	var visited_resources: Dictionary = {}
	var visited_objects: Dictionary = {}

	for hard_path: String in manifest_result.get("hard_paths", PackedStringArray()):
		_register_path(hard_path, include_lookup)
		if not ResourceLoader.exists(hard_path):
			_register_path(hard_path, missing_lookup)
			continue
		_collect_from_path(hard_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)

	var project_settings_path: String = "res://project.godot"
	_register_path(project_settings_path, include_lookup)
	_collect_text_resource_dependencies(project_settings_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)

	for scene_path: String in entry_scene_paths:
		_register_path(scene_path, scanned_scene_lookup)
		_register_path(scene_path, include_lookup)
		if not ResourceLoader.exists(scene_path):
			_register_path(scene_path, missing_lookup)
			continue
		_collect_from_path(scene_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)

	return {
		"ok": true,
		"manifest_path": manifest_result.get("path", manifest_path),
		"hard_paths": manifest_result.get("hard_paths", PackedStringArray()),
		"slot_names": manifest_result.get("slot_names", PackedStringArray()),
		"exclude_patterns": manifest_result.get("exclude_patterns", PackedStringArray()),
		"entry_scenes": _dict_keys_to_array(scanned_scene_lookup),
		"include_paths": _dict_keys_to_array(include_lookup),
		"discovered_slot_paths": _dict_keys_to_array(discovered_lookup),
		"missing_paths": _dict_keys_to_array(missing_lookup),
	}


static func apply_manifest_to_export_preset_text(text: String, entry_scene_paths: PackedStringArray, scan_result: Dictionary) -> String:
	var patched: String = text
	var export_roots: PackedStringArray = _build_export_roots(entry_scene_paths, PackedStringArray(scan_result.get("include_paths", PackedStringArray())))
	patched = _set_export_filter_value(patched, "scenes")
	patched = _set_export_files_value(patched, export_roots)
	patched = _set_filter_value(patched, "include_filter", export_roots)
	patched = _set_filter_value(patched, "exclude_filter", PackedStringArray(scan_result.get("exclude_patterns", PackedStringArray())))
	return patched


static func write_scan_report_abs(abs_path: String, scan_result: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(scan_result, "\t"))
	file.close()
	return true


static func _collect_from_path(path: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var normalized_path: String = path.strip_edges()
	if normalized_path.is_empty():
		return
	if visited_resources.has(normalized_path):
		return
	visited_resources[normalized_path] = true
	_collect_import_sidecars(normalized_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
	var resource: Resource = ResourceLoader.load(normalized_path)
	if resource == null:
		_register_path(normalized_path, missing_lookup)
		return
	_collect_text_resource_dependencies(normalized_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
	_inspect_variant(resource, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _inspect_variant(value: Variant, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	match typeof(value):
		TYPE_OBJECT:
			_inspect_object(value as Object, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		TYPE_ARRAY:
			for item: Variant in value:
				_inspect_variant(item, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		TYPE_PACKED_STRING_ARRAY:
			for item_text: String in value:
				_inspect_string_path(item_text, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		TYPE_STRING:
			_inspect_string_path(String(value), include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _inspect_object(obj: Object, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	if obj == null:
		return
	var object_id: int = obj.get_instance_id()
	if visited_objects.has(object_id):
		return
	visited_objects[object_id] = true

	if obj is Resource:
		var resource: Resource = obj as Resource
		if not resource.resource_path.is_empty():
			_register_path(resource.resource_path, include_lookup)
			if resource is Script:
				_collect_script_dependencies(resource.resource_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)

	var attached_script: Script = obj.get_script() as Script
	if attached_script != null and not attached_script.resource_path.is_empty():
		_register_path(attached_script.resource_path, include_lookup)
		_register_path(attached_script.resource_path, discovered_lookup)
		_collect_script_dependencies(attached_script.resource_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)

	if obj is PackedScene:
		var packed: PackedScene = obj as PackedScene
		var root: Node = packed.instantiate()
		if root != null:
			_inspect_object(root, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
			root.free()
		return

	if obj is Node:
		var node: Node = obj as Node
		_scan_slot_properties(node, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		for child: Node in node.get_children():
			_inspect_object(child, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		return

	_scan_slot_properties(obj, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _scan_slot_properties(obj: Object, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	for prop_any: Variant in obj.get_property_list():
		if not (prop_any is Dictionary):
			continue
		var prop: Dictionary = prop_any as Dictionary
		var prop_name: String = str(prop.get("name", ""))
		if prop_name.is_empty():
			continue
		if not slot_lookup.has(prop_name):
			continue
		var prop_value: Variant = obj.get(prop_name)
		_collect_slot_value(prop_value, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _collect_slot_value(value: Variant, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	match typeof(value):
		TYPE_OBJECT:
			var obj: Object = value as Object
			if obj == null:
				return
			if obj is Resource:
				var res: Resource = obj as Resource
				if not res.resource_path.is_empty():
					_register_path(res.resource_path, include_lookup)
					_register_path(res.resource_path, discovered_lookup)
					_collect_from_path(res.resource_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
			_inspect_object(obj, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		TYPE_ARRAY:
			for item: Variant in value:
				_collect_slot_value(item, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		TYPE_PACKED_STRING_ARRAY:
			for item_text: String in value:
				_collect_slot_string(item_text, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		TYPE_STRING:
			_collect_slot_string(String(value), include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _collect_slot_string(text: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var path: String = text.strip_edges()
	if not path.begins_with("res://"):
		return
	_register_path(path, include_lookup)
	_register_path(path, discovered_lookup)
	if not ResourceLoader.exists(path):
		_register_path(path, missing_lookup)
		return
	_collect_from_path(path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _inspect_string_path(text: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var path: String = text.strip_edges()
	if not path.begins_with("res://"):
		return
	_register_path(path, include_lookup)
	if ResourceLoader.exists(path):
		_collect_from_path(path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
	else:
		_register_path(path, missing_lookup)


static func _collect_script_dependencies(script_path: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var normalized_script_path: String = _normalize_export_root(script_path)
	if normalized_script_path.is_empty():
		return
	var source_text: String = FileAccess.get_file_as_string(normalized_script_path)
	if source_text.is_empty():
		return
	for dependency_path: String in _extract_script_paths(source_text):
		_register_path(dependency_path, include_lookup)
		_register_path(dependency_path, discovered_lookup)
		if not ResourceLoader.exists(dependency_path):
			_register_path(dependency_path, missing_lookup)
			continue
		_collect_from_path(dependency_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _collect_text_resource_dependencies(resource_path: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	if not _is_text_dependency_source(resource_path):
		return
	var source_text: String = FileAccess.get_file_as_string(resource_path)
	if source_text.is_empty() or not source_text.contains("res://"):
		return
	for dependency_path: String in _extract_text_resource_paths(source_text):
		_register_path(dependency_path, include_lookup)
		_register_path(dependency_path, discovered_lookup)
		if not ResourceLoader.exists(dependency_path):
			_register_path(dependency_path, missing_lookup)
			continue
		_collect_from_path(dependency_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _collect_import_sidecars(resource_path: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var lower_path: String = resource_path.to_lower()
	if lower_path.ends_with(".fbx"):
		_collect_files_by_prefix(resource_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
	elif lower_path.ends_with(".glb") or lower_path.ends_with(".gltf"):
		_collect_model_directory_sidecars(resource_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
	elif lower_path.ends_with(".obj"):
		_collect_obj_material_dependencies(resource_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)


static func _collect_files_by_prefix(resource_path: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var dir_path: String = resource_path.get_base_dir()
	var base_name: String = resource_path.get_file().get_basename()
	var dir_abs: String = ProjectSettings.globalize_path(dir_path)
	var dir: DirAccess = DirAccess.open(dir_abs)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not file_name.begins_with(base_name):
			continue
		var dependency_path: String = dir_path.path_join(file_name)
		_register_path(dependency_path, include_lookup)
		_register_path(dependency_path, discovered_lookup)
		if ResourceLoader.exists(dependency_path):
			_collect_from_path(dependency_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
	dir.list_dir_end()


static func _collect_model_directory_sidecars(resource_path: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var dir_path: String = resource_path.get_base_dir()
	var dir_abs: String = ProjectSettings.globalize_path(dir_path)
	var dir: DirAccess = DirAccess.open(dir_abs)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower_name: String = file_name.to_lower()
		if not (lower_name.ends_with(".res") or lower_name.ends_with(".png") or lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg") or lower_name.ends_with(".webp")):
			continue
		var dependency_path: String = dir_path.path_join(file_name)
		_register_path(dependency_path, include_lookup)
		_register_path(dependency_path, discovered_lookup)
		if ResourceLoader.exists(dependency_path):
			_collect_from_path(dependency_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
	dir.list_dir_end()


static func _collect_obj_material_dependencies(resource_path: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var obj_text: String = FileAccess.get_file_as_string(resource_path)
	if obj_text.is_empty():
		return
	for line: String in obj_text.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("mtllib "):
			continue
		var mtl_name: String = stripped.substr(7).strip_edges().replace("\\ ", " ")
		if mtl_name.is_empty():
			continue
		var mtl_path: String = resource_path.get_base_dir().path_join(mtl_name)
		_register_path(mtl_path, include_lookup)
		_register_path(mtl_path, discovered_lookup)
		if ResourceLoader.exists(mtl_path) or FileAccess.file_exists(ProjectSettings.globalize_path(mtl_path)):
			_collect_mtl_texture_dependencies(mtl_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		else:
			_register_path(mtl_path, missing_lookup)


static func _collect_mtl_texture_dependencies(mtl_path: String, include_lookup: Dictionary, discovered_lookup: Dictionary, missing_lookup: Dictionary, visited_resources: Dictionary, visited_objects: Dictionary, slot_lookup: Dictionary) -> void:
	var mtl_text: String = FileAccess.get_file_as_string(mtl_path)
	if mtl_text.is_empty():
		return
	for line: String in mtl_text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue
		if not (stripped.begins_with("map_") or stripped.begins_with("norm ") or stripped.begins_with("disp ")):
			continue
		var tokens: PackedStringArray = stripped.split(" ", false)
		if tokens.size() < 2:
			continue
		var texture_name: String = tokens[tokens.size() - 1].replace("\\ ", " ").replace("\\", "/")
		var texture_path: String = _normalize_mtl_dependency_path(mtl_path.get_base_dir(), texture_name)
		_register_path(texture_path, include_lookup)
		_register_path(texture_path, discovered_lookup)
		if ResourceLoader.exists(texture_path):
			_collect_from_path(texture_path, include_lookup, discovered_lookup, missing_lookup, visited_resources, visited_objects, slot_lookup)
		elif FileAccess.file_exists(ProjectSettings.globalize_path(texture_path)):
			_register_path(texture_path, include_lookup)
		else:
			_register_path(texture_path, missing_lookup)


static func _extract_script_paths(source_text: String) -> PackedStringArray:
	var result_lookup: Dictionary = {}
	var path_regex: RegEx = RegEx.new()
	if path_regex.compile('res://[^"\\r\\n]+') != OK:
		return PackedStringArray()
	for line: String in source_text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			continue
		if stripped.begins_with("#"):
			continue
		if not _line_may_reference_dependency(stripped):
			continue
		for match: RegExMatch in path_regex.search_all(stripped):
			var dependency_path: String = match.get_string()
			if dependency_path.begins_with("res://"):
				result_lookup[dependency_path] = true
	return _dict_keys_to_array(result_lookup)


static func _extract_text_resource_paths(source_text: String) -> PackedStringArray:
	var result_lookup: Dictionary = {}
	var path_regex: RegEx = RegEx.new()
	if path_regex.compile('res://[^"\\r\\n]+') != OK:
		return PackedStringArray()
	for match: RegExMatch in path_regex.search_all(source_text):
		var dependency_path: String = match.get_string()
		if dependency_path.begins_with("res://"):
			result_lookup[dependency_path] = true
	return _dict_keys_to_array(result_lookup)


static func _line_may_reference_dependency(line: String) -> bool:
	return line.contains("preload(") or line.contains("load(") or line.begins_with("extends ") or line.contains("load_threaded_request(")


static func _is_text_dependency_source(path: String) -> bool:
	var lower_path: String = path.to_lower()
	return lower_path.ends_with(".tscn") or lower_path.ends_with(".tres") or lower_path.ends_with(".gdshader") or lower_path.ends_with(".shader") or lower_path.ends_with(".godot") or lower_path.ends_with(".cfg")


static func _normalize_mtl_dependency_path(base_dir: String, raw_texture_name: String) -> String:
	var texture_name: String = raw_texture_name.strip_edges().replace("\\", "/")
	if texture_name.begins_with("res://"):
		return texture_name
	var assets_index: int = texture_name.find("assets/")
	if assets_index >= 0:
		return "res://%s" % texture_name.substr(assets_index)
	return base_dir.path_join(texture_name)


static func _set_export_filter_value(text: String, export_filter: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var found: bool = false
	for i: int in range(lines.size()):
		if lines[i].begins_with("export_filter="):
			lines[i] = 'export_filter="%s"' % export_filter
			found = true
	if not found:
		lines.append('export_filter="%s"' % export_filter)
	return "\n".join(lines)


static func _set_export_files_value(text: String, scene_paths: PackedStringArray) -> String:
	var lines: Array = text.split("\n")
	var preset_section_start: int = -1
	var preset_section_end: int = lines.size()
	for i: int in range(lines.size()):
		var line: String = lines[i]
		if line == "[preset.0]":
			preset_section_start = i
			continue
		if preset_section_start != -1 and i > preset_section_start and line.begins_with("["):
			preset_section_end = i
			break
	if preset_section_start == -1:
		return text
	var export_files_line: String = "export_files=PackedStringArray(%s)" % ", ".join(_quote_paths(scene_paths))
	var found_files: bool = false
	for i: int in range(preset_section_start + 1, preset_section_end):
		if lines[i].begins_with("export_files="):
			lines[i] = export_files_line
			found_files = true
	if not found_files:
		lines.insert(preset_section_end, export_files_line)
	return "\n".join(lines)


static func _set_filter_value(text: String, key: String, patterns: PackedStringArray) -> String:
	var joined: String = ",".join(patterns)
	var lines: PackedStringArray = text.split("\n")
	var found: bool = false
	for i: int in range(lines.size()):
		if lines[i].begins_with("%s=" % key):
			lines[i] = '%s="%s"' % [key, joined.c_escape()]
			found = true
	if not found:
		lines.append('%s="%s"' % [key, joined.c_escape()])
	return "\n".join(lines)


static func _build_export_roots(entry_scene_paths: PackedStringArray, include_paths: PackedStringArray) -> PackedStringArray:
	var lookup: Dictionary = {}
	for path: String in entry_scene_paths:
		_register_export_root(path, lookup)
	for path: String in include_paths:
		_register_export_root(path, lookup)
	return _dict_keys_to_array(lookup)


static func _register_export_root(path: String, lookup: Dictionary) -> void:
	var normalized: String = _normalize_export_root(path)
	if normalized.is_empty():
		return
	if not ResourceLoader.exists(normalized):
		return
	lookup[normalized] = true


static func _normalize_export_root(path: String) -> String:
	var normalized: String = path.strip_edges()
	if normalized.is_empty():
		return ""
	var subresource_index: int = normalized.find("::")
	if subresource_index >= 0:
		normalized = normalized.substr(0, subresource_index)
	if not normalized.begins_with("res://"):
		return ""
	return normalized


static func _quote_paths(paths: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for path: String in paths:
		result.append('"%s"' % path.c_escape())
	return result


static func _variant_to_string_array(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	match typeof(value):
		TYPE_ARRAY:
			for item: Variant in value:
				result.append(str(item))
		TYPE_PACKED_STRING_ARRAY:
			for item_text: String in value:
				result.append(item_text)
	return result


static func _dict_keys_to_array(dict: Dictionary) -> PackedStringArray:
	var keys: Array = dict.keys()
	keys.sort()
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in keys:
		out.append(str(key))
	return out


static func _register_path(path: String, lookup: Dictionary) -> void:
	var normalized: String = path.strip_edges()
	if normalized.is_empty():
		return
	lookup[normalized] = true
