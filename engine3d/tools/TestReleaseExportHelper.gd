@tool
extends RefCounted

const PROJECT_CONFIG_MAIN_SCENE_KEY: String = "run/main_scene"
const PROJECT_CONFIG_NAME_KEY: String = "config/name"
const PROJECT_CONFIG_AUTOLOAD_SECTION: String = "autoload"
const WINDOWS_EXPORT_PRESET_NAME: String = "Windows Desktop"
const EXPORT_FILTER_ALL_RESOURCES: String = "all_resources"
const EXPORT_FILTER_SELECTED_SCENES: String = "scenes"


static func get_project_name(project_root_abs: String) -> String:
	var project_text: String = FileAccess.get_file_as_string(project_root_abs.path_join("project.godot"))
	if project_text.is_empty():
		return "Densetsu"
	for line: String in project_text.split("\n"):
		if line.begins_with("%s=" % PROJECT_CONFIG_NAME_KEY):
			var value: String = line.get_slice("=", 1).strip_edges()
			value = value.trim_prefix("\"").trim_suffix("\"")
			if not value.is_empty():
				return value
	return "Densetsu"


static func get_project_main_scene(project_root_abs: String) -> String:
	var project_file: String = project_root_abs.path_join("project.godot")
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(project_file) != OK:
		return ""
	var main_scene: String = str(cfg.get_value("application", PROJECT_CONFIG_MAIN_SCENE_KEY, "")).strip_edges()
	if main_scene.is_empty():
		main_scene = str(cfg.get_value("application/run", "main_scene", "")).strip_edges()
	return main_scene


static func get_missing_autoload_paths(project_root_abs: String) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	var project_file: String = project_root_abs.path_join("project.godot")
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(project_file) != OK:
		return missing
	var section_keys: PackedStringArray = cfg.get_section_keys(PROJECT_CONFIG_AUTOLOAD_SECTION)
	for key: String in section_keys:
		var raw_path: String = str(cfg.get_value(PROJECT_CONFIG_AUTOLOAD_SECTION, key, "")).strip_edges()
		if raw_path.is_empty():
			continue
		var resource_path: String = raw_path.trim_prefix("*")
		if resource_path.begins_with("res://") and not FileAccess.file_exists(ProjectSettings.globalize_path(resource_path)):
			missing.append(resource_path)
	return missing


static func find_windows_export_templates() -> Dictionary:
	var version_string: String = str(Engine.get_version_info().get("string", "")).strip_edges()
	var version_dir: String = _derive_template_version_dir(version_string)
	if version_dir.is_empty():
		return {"ok": false, "message": "Could not derive Godot export template version from Engine.get_version_info()."}
	var base_dir: String = OS.get_environment("APPDATA").path_join("Godot").path_join("export_templates").path_join(version_dir).path_join("templates")
	var release_path: String = base_dir.path_join("windows_release_x86_64.exe")
	var debug_path: String = base_dir.path_join("windows_debug_x86_64.exe")
	if not FileAccess.file_exists(release_path) or not FileAccess.file_exists(debug_path):
		return {
			"ok": false,
			"message": "Missing Godot Windows export templates in %s" % base_dir,
			"version_dir": version_dir,
			"base_dir": base_dir,
			"release": release_path,
			"debug": debug_path,
		}
	return {
		"ok": true,
		"version_dir": version_dir,
		"base_dir": base_dir,
		"release": release_path,
		"debug": debug_path,
	}


static func set_export_template_paths(text: String, export_template_exe: String) -> String:
	var escaped: String = export_template_exe.replace("\\", "/").c_escape()
	var lines: PackedStringArray = text.split("\n")
	var found_debug: bool = false
	var found_release: bool = false
	for i: int in range(lines.size()):
		if lines[i].begins_with("custom_template/debug="):
			lines[i] = 'custom_template/debug="%s"' % escaped
			found_debug = true
		elif lines[i].begins_with("custom_template/release="):
			lines[i] = 'custom_template/release="%s"' % escaped
			found_release = true
	if not found_debug:
		lines.append('custom_template/debug="%s"' % escaped)
	if not found_release:
		lines.append('custom_template/release="%s"' % escaped)
	return "\n".join(lines)


static func set_embed_pck_text(text: String, embed_pck: bool) -> String:
	var lines: PackedStringArray = text.split("\n")
	var found: bool = false
	for i: int in range(lines.size()):
		if lines[i].begins_with("binary_format/embed_pck="):
			lines[i] = "binary_format/embed_pck=%s" % ("true" if embed_pck else "false")
			found = true
	if not found:
		lines.append("binary_format/embed_pck=%s" % ("true" if embed_pck else "false"))
	return "\n".join(lines)


static func set_selected_scene_export_text(text: String, scene_paths: PackedStringArray) -> String:
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
	var found_filter: bool = false
	var found_files: bool = false
	for i: int in range(preset_section_start + 1, preset_section_end):
		if lines[i].begins_with("export_filter="):
			lines[i] = 'export_filter="%s"' % EXPORT_FILTER_SELECTED_SCENES
			found_filter = true
		elif lines[i].begins_with("export_files="):
			lines[i] = export_files_line
			found_files = true
	var insert_index: int = preset_section_end
	if not found_filter:
		lines.insert(insert_index, 'export_filter="%s"' % EXPORT_FILTER_SELECTED_SCENES)
		insert_index += 1
	if not found_files:
		lines.insert(insert_index, export_files_line)
	return "\n".join(lines)


static func override_project_main_scene_text(text: String, scene_path: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var replaced: bool = false
	for i: int in range(lines.size()):
		if lines[i].begins_with("%s=" % PROJECT_CONFIG_MAIN_SCENE_KEY):
			lines[i] = '%s="%s"' % [PROJECT_CONFIG_MAIN_SCENE_KEY, scene_path.c_escape()]
			replaced = true
			break
	if not replaced:
		lines.append('%s="%s"' % [PROJECT_CONFIG_MAIN_SCENE_KEY, scene_path.c_escape()])
	return "\n".join(lines)


static func strip_wrapped_quotes(value: String) -> String:
	var trimmed: String = value.strip_edges()
	if trimmed.length() >= 2:
		if (trimmed.begins_with("\"") and trimmed.ends_with("\"")) or (trimmed.begins_with("'") and trimmed.ends_with("'")):
			return trimmed.substr(1, trimmed.length() - 2)
	return trimmed


static func sanitize_filename(value: String) -> String:
	var result: String = value.strip_edges()
	for bad: String in PackedStringArray(["<", ">", ":", '"', "/", "\\", "|", "?", "*"]):
		result = result.replace(bad, "_")
	result = result.replace("\r", "_").replace("\n", "_")
	while result.find("  ") != -1:
		result = result.replace("  ", " ")
	result = result.strip_edges()
	if result.is_empty():
		return "Densetsu"
	return result


static func format_bytes(size_bytes: int) -> String:
	var units: PackedStringArray = PackedStringArray(["B", "KB", "MB", "GB", "TB"])
	var value: float = float(size_bytes)
	var unit_index: int = 0
	while value >= 1024.0 and unit_index < units.size() - 1:
		value /= 1024.0
		unit_index += 1
	if unit_index == 0:
		return "%d %s" % [size_bytes, units[unit_index]]
	return "%.2f %s" % [value, units[unit_index]]


static func get_file_size(abs_path: String) -> int:
	if not FileAccess.file_exists(abs_path):
		return -1
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return -1
	var size_bytes: int = f.get_length()
	f.close()
	return size_bytes


static func _quote_paths(paths: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for path: String in paths:
		result.append('"%s"' % path.c_escape())
	return result


static func _derive_template_version_dir(version_string: String) -> String:
	if version_string.is_empty():
		return ""
	var normalized: String = version_string.replace(" ", "").replace("(", ".").replace(")", "")
	normalized = normalized.replace("-", ".")
	var parts: PackedStringArray = normalized.split(".", false)
	if parts.size() < 4:
		return ""
	return "%s.%s.%s.%s" % [parts[0], parts[1], parts[2], parts[3]]


