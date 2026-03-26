@tool
extends RefCounted

const SUPPORTED_SOURCE_EXTS: Array[String] = ["fbx", "glb", "gltf", "dae", "blend"]
const IMPORT_EXT: String = "import"
const SECTION_PARAMS: String = "params"
const KEY_SUBRESOURCES: String = "_subresources"
const KEY_ANIMATIONS: String = "animations"


func configure_persistent_animation_import_paths(paths: PackedStringArray, editor_iface: EditorInterface = null) -> Dictionary:
	var import_files: PackedStringArray = _collect_import_files(paths)
	var scanned: int = 0
	var updated: int = 0
	var unchanged: int = 0
	var failed: int = 0
	var changed_source_paths: PackedStringArray = PackedStringArray()
	var failures: PackedStringArray = PackedStringArray()

	for import_path in import_files:
		scanned += 1
		var update_result: Dictionary = _update_single_import_file(import_path)
		var ok: bool = bool(update_result.get("ok", false))
		if not ok:
			failed += 1
			failures.append(str(update_result.get("error", "Unknown error")) + " :: " + import_path)
			continue
		var changed: bool = bool(update_result.get("changed", false))
		if changed:
			updated += 1
			var source_path: String = _source_from_import_path(import_path)
			if not source_path.is_empty() and not changed_source_paths.has(source_path):
				changed_source_paths.append(source_path)
		else:
			unchanged += 1

	_reimport_sources(changed_source_paths, editor_iface)

	return {
		"ok": failed == 0,
		"scanned": scanned,
		"updated": updated,
		"unchanged": unchanged,
		"failed": failed,
		"changed_sources": changed_source_paths,
		"failures": failures
	}


func _update_single_import_file(import_path: String) -> Dictionary:
	var cfg: ConfigFile = ConfigFile.new()
	var load_err: int = cfg.load(import_path)
	if load_err != OK:
		return {
			"ok": false,
			"changed": false,
			"error": "Failed to load import config (code %d)" % load_err
		}

	var source_path: String = _source_from_import_path(import_path)
	var subresources_any: Variant = cfg.get_value(SECTION_PARAMS, KEY_SUBRESOURCES, {})
	var subresources: Dictionary = {}
	if subresources_any is Dictionary:
		subresources = (subresources_any as Dictionary).duplicate(true)
	var animations_src: Dictionary = {}
	var animations_any: Variant = subresources.get(KEY_ANIMATIONS, null)
	if animations_any is Dictionary:
		animations_src = (animations_any as Dictionary).duplicate(true)
	if animations_src.is_empty():
		animations_src = _build_animation_entries_from_scene(source_path)
		if animations_src.is_empty():
			return {
				"ok": true,
				"changed": false
			}

	var animations_out: Dictionary = animations_src.duplicate(true)
	var changed: bool = false

	for anim_key_any in animations_src.keys():
		var anim_key: String = str(anim_key_any)
		var anim_entry_any: Variant = animations_src.get(anim_key_any, null)
		var anim_entry: Dictionary = {}
		if anim_entry_any is Dictionary:
			anim_entry = (anim_entry_any as Dictionary).duplicate(true)
		var entry_changed: bool = _patch_animation_entry(anim_entry, source_path, anim_key)
		if entry_changed:
			changed = true
		animations_out[anim_key_any] = anim_entry

	if not changed:
		return {
			"ok": true,
			"changed": false
		}

	subresources[KEY_ANIMATIONS] = animations_out
	cfg.set_value(SECTION_PARAMS, KEY_SUBRESOURCES, subresources)
	var save_err: int = cfg.save(import_path)
	if save_err != OK:
		return {
			"ok": false,
			"changed": false,
			"error": "Failed to save import config (code %d)" % save_err
		}

	return {
		"ok": true,
		"changed": true
	}


func _patch_animation_entry(entry: Dictionary, source_path: String, anim_key: String) -> bool:
	var changed: bool = false
	var base_token: String = _sanitize_token(anim_key)
	var base_path: String = _build_anim_fallback_path(source_path, base_token)

	changed = _set_dict_value(entry, "save_to_file/enabled", true) or changed
	changed = _set_dict_value(entry, "save_to_file/keep_custom_tracks", true) or changed
	changed = _set_dict_value(entry, "save_to_file/path", base_path) or changed
	changed = _set_dict_value(entry, "save_to_file/fallback_path", base_path) or changed

	var slice_prefixes: PackedStringArray = _collect_slice_prefixes(entry)
	for prefix in slice_prefixes:
		var slice_changed: bool = _cleanup_slice_entry(entry, prefix, source_path, base_token)
		if slice_changed:
			changed = true

	return changed


func _build_animation_entries_from_scene(source_path: String) -> Dictionary:
	var entries: Dictionary = {}
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return entries
	var scene_res: Resource = ResourceLoader.load(source_path)
	if scene_res == null or not (scene_res is PackedScene):
		return entries
	var root: Node = (scene_res as PackedScene).instantiate()
	if root == null:
		return entries
	var anim_player: AnimationPlayer = _find_anim_player(root)
	if anim_player == null:
		root.free()
		return entries
	var anim_names: PackedStringArray = anim_player.get_animation_list()
	for anim_name in anim_names:
		var key: String = str(anim_name)
		if key.is_empty():
			continue
		entries[key] = {}
	root.free()
	return entries


func _find_anim_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	var players: Array[Node] = root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return null
	return players[0] as AnimationPlayer


func _collect_slice_prefixes(entry: Dictionary) -> PackedStringArray:
	var prefixes: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for key_any in entry.keys():
		var key: String = str(key_any)
		var slash_idx: int = key.find("/")
		if slash_idx <= 0:
			continue
		var prefix: String = key.substr(0, slash_idx)
		if not prefix.begins_with("slice_"):
			continue
		if seen.has(prefix):
			continue
		seen[prefix] = true
		prefixes.append(prefix)
	return prefixes


func _cleanup_slice_entry(entry: Dictionary, prefix: String, source_path: String, base_token: String) -> bool:
	var changed: bool = false
	var name_key: String = "%s/name" % prefix
	var start_key: String = "%s/start_frame" % prefix
	var end_key: String = "%s/end_frame" % prefix
	var name_val: String = str(entry.get(name_key, "")).strip_edges()
	var start_val: float = float(entry.get(start_key, 0.0))
	var end_val: float = float(entry.get(end_key, 0.0))
	var has_user_slice: bool = (not name_val.is_empty()) or (end_val > start_val)
	if not has_user_slice:
		changed = _remove_keys_with_prefix(entry, "%s/" % prefix) or changed
		return changed

	var slice_token: String = _sanitize_token("%s__%s" % [base_token, name_val if not name_val.is_empty() else prefix])
	var slice_path: String = _build_anim_fallback_path(source_path, slice_token)
	changed = _set_dict_value(entry, "%s/save_to_file/enabled" % prefix, true) or changed
	changed = _set_dict_value(entry, "%s/save_to_file/keep_custom_tracks" % prefix, true) or changed
	changed = _set_dict_value(entry, "%s/save_to_file/path" % prefix, slice_path) or changed
	changed = _set_dict_value(entry, "%s/save_to_file/fallback_path" % prefix, slice_path) or changed
	return changed


func _remove_keys_with_prefix(entry: Dictionary, prefix: String) -> bool:
	var remove_keys: PackedStringArray = PackedStringArray()
	for key_any in entry.keys():
		var key: String = str(key_any)
		if key.begins_with(prefix):
			remove_keys.append(key)
	if remove_keys.is_empty():
		return false
	for key in remove_keys:
		entry.erase(key)
	return true


func _set_dict_value(dict_obj: Dictionary, key: String, value: Variant) -> bool:
	if dict_obj.has(key) and dict_obj[key] == value:
		return false
	dict_obj[key] = value
	return true


func _build_anim_fallback_path(source_path: String, token: String) -> String:
	if source_path.is_empty():
		return ""
	var dir_path: String = source_path.get_base_dir()
	var base_name: String = _sanitize_token(source_path.get_file().get_basename())
	var suffix: String = _sanitize_token(token)
	return dir_path.path_join("%s__%s.anim" % [base_name, suffix])


func _sanitize_token(raw: String) -> String:
	var src: String = raw.strip_edges()
	if src.is_empty():
		return "anim"
	var out_chars: PackedStringArray = PackedStringArray()
	for i in src.length():
		var ch: String = src.substr(i, 1)
		var code: int = ch.unicode_at(0)
		var is_lower: bool = code >= 97 and code <= 122
		var is_upper: bool = code >= 65 and code <= 90
		var is_digit: bool = code >= 48 and code <= 57
		var is_safe: bool = is_lower or is_upper or is_digit or ch == "_" or ch == "-"
		out_chars.append(ch if is_safe else "_")
	var token: String = "".join(out_chars)
	while token.find("__") != -1:
		token = token.replace("__", "_")
	token = token.strip_edges()
	token = token.trim_prefix("_")
	token = token.trim_suffix("_")
	if token.is_empty():
		return "anim"
	return token


func _collect_import_files(paths: PackedStringArray) -> PackedStringArray:
	var files_out: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for path in paths:
		_collect_import_files_from_path(path, files_out, seen)
	return files_out


func _collect_import_files_from_path(path: String, out: PackedStringArray, seen: Dictionary) -> void:
	if path.is_empty():
		return
	if _is_dir(path):
		var dir: DirAccess = DirAccess.open(path)
		if dir == null:
			return
		dir.list_dir_begin()
		while true:
			var name: String = dir.get_next()
			if name.is_empty():
				break
			if name == "." or name == "..":
				continue
			var child_path: String = path.path_join(name)
			if dir.current_is_dir():
				_collect_import_files_from_path(child_path, out, seen)
			else:
				_try_add_import_file(child_path, out, seen)
		dir.list_dir_end()
		return
	_try_add_import_file(path, out, seen)


func _try_add_import_file(file_path: String, out: PackedStringArray, seen: Dictionary) -> void:
	var lower_path: String = file_path.to_lower()
	var import_path: String = ""
	if lower_path.ends_with("." + IMPORT_EXT):
		var source_ext: String = file_path.get_basename().get_extension().to_lower()
		if not SUPPORTED_SOURCE_EXTS.has(source_ext):
			return
		import_path = file_path
	else:
		var ext: String = file_path.get_extension().to_lower()
		if not SUPPORTED_SOURCE_EXTS.has(ext):
			return
		import_path = file_path + "." + IMPORT_EXT
	if not FileAccess.file_exists(import_path):
		return
	var key: String = import_path.to_lower()
	if seen.has(key):
		return
	seen[key] = true
	out.append(import_path)


func _source_from_import_path(import_path: String) -> String:
	if import_path.to_lower().ends_with("." + IMPORT_EXT):
		return import_path.left(import_path.length() - (IMPORT_EXT.length() + 1))
	return import_path


func _reimport_sources(source_paths: PackedStringArray, editor_iface: EditorInterface) -> void:
	if source_paths.is_empty():
		return
	if editor_iface == null:
		return
	var fs: EditorFileSystem = editor_iface.get_resource_filesystem()
	if fs == null:
		return
	if fs.has_method("reimport_files"):
		fs.reimport_files(source_paths)
	for source_path in source_paths:
		fs.update_file(source_path)
		var import_path: String = source_path + "." + IMPORT_EXT
		if FileAccess.file_exists(import_path):
			fs.update_file(import_path)


func _is_dir(path: String) -> bool:
	var dir: DirAccess = DirAccess.open(path)
	return dir != null
