@tool
extends EditorScript

# Builds a shared AnimationLibrary from selected packs.

const INPUT_ROOT := "res://assets/animations/fbx animations"
const OUTPUT_LIBRARY := "res://assets/characters/biped/anim/BipedAnimations_ActionAdventure.tres"
const OUTPUT_REPORT := "res://assets/characters/biped/anim/BipedAnimations_ActionAdventure_report.txt"
const SKIP_EXISTING_ANIMATIONS := false
var ONLY_ANIMATIONS: PackedStringArray = PackedStringArray([])
const FORCE_REIMPORT_ONLY := true
var PACK_FILTER: PackedStringArray = PackedStringArray([])
const REFERENCE_RIG_SCENE := "res://assets/animations/fbx animations/michio_full_1p.tscn"
const MODEL_DATA_PATH := "res://data3d/models/MODEL_Player_Michio_ActionAdventure.tres"

const INCLUDE_TPOSE := false
const STRIP_ROOT_TRANSLATION := true
const TRACK_PATH_PREFIX := "Armature/"

var SKIP_PATTERNS: PackedStringArray = PackedStringArray([
	"tpose",
	"t-pose",
	"t_pose",
])

var SKIP_FILES: PackedStringArray = PackedStringArray([
	"michio full",
	"michio rigged",
])

var ROOT_BONE_NAMES: PackedStringArray = PackedStringArray([
	"root",
	"hips",
	"pelvis",
	"armature",
	"mixamorig:hips",
	"mixamorig_hips",
])

var _skeleton_path := ""
var _bone_map := {}
var _node_paths := {}


func _run() -> void:
	_ensure_output_dir()
	_build_skeleton_cache()
	var lib := _load_or_create_library()
	if lib == null:
		push_error("Failed to create animation library.")
		return
	var files: Array[String] = []
	_collect_fbx(INPUT_ROOT, files)
	files.sort()
	var report: Array[String] = []
	report.append("Animation Library Build (Selected Packs)")
	report.append("Input root: " + INPUT_ROOT)
	report.append("Output library: " + OUTPUT_LIBRARY)
	_purge_empty_clips(lib, report)
	_remove_legacy_prefixed_clips(lib, report)
	report.append("Clips:")
	var added := 0
	for path in files:
		if _should_skip(path):
			report.append("- SKIP " + path)
			continue
		var preimported := _find_preimported_anim_files(path)
		if not preimported.is_empty():
			var added_pre := _add_preimported_anims(preimported, path, lib, report)
			added += added_pre
			if added_pre == 0:
				report.append("- SKIP no valid anims " + path)
			continue
		if not _is_import_valid(path):
			report.append("- SKIP invalid import " + path)
			continue
		var scene_res := ResourceLoader.load(path)
		if scene_res == null or not (scene_res is PackedScene):
			report.append("- FAIL load " + path)
			continue
		var inst := (scene_res as PackedScene).instantiate()
		if inst == null:
			report.append("- FAIL instance " + path)
			continue
		var anim_player := _find_anim_player(inst)
		if anim_player == null:
			report.append("- FAIL no AnimationPlayer " + path)
			inst.free()
			continue
		var anim_names := anim_player.get_animation_list()
		if anim_names.is_empty():
			report.append("- FAIL no animations " + path)
			inst.free()
			continue
		var selected_anim_names: PackedStringArray = _select_source_animation_names(anim_player, anim_names)
		for anim_name in selected_anim_names:
			var anim := anim_player.get_animation(anim_name)
			if anim == null:
				continue
			var out_name := _build_anim_name(path, anim_name, anim_names.size())
			if not ONLY_ANIMATIONS.is_empty() and not ONLY_ANIMATIONS.has(out_name):
				continue
			if FORCE_REIMPORT_ONLY and not ONLY_ANIMATIONS.is_empty() and lib.has_animation(out_name):
				lib.remove_animation(out_name)
			if lib.has_animation(out_name):
				if SKIP_EXISTING_ANIMATIONS:
					report.append("- KEEP " + out_name + " (already exists)")
					continue
				lib.remove_animation(out_name)
				report.append("- REPLACE " + out_name)
			var out_anim: Animation = anim.duplicate(true)
			_make_animation_tracks_editable(out_anim)
			_sanitize_animation_tracks(out_anim)
			if STRIP_ROOT_TRANSLATION:
				_strip_root_translation(out_anim)
			if out_anim.get_track_count() == 0:
				report.append("- DROP empty " + out_name + " <= " + path + " [" + anim_name + "]")
				continue
			lib.add_animation(out_name, out_anim)
			report.append("- ADD " + out_name + " <= " + path + " [" + anim_name + "]")
			added += 1
		inst.free()
	var save_err := ResourceSaver.save(lib, OUTPUT_LIBRARY)
	if save_err != OK:
		push_error("Failed to save AnimationLibrary: " + OUTPUT_LIBRARY)
		report.append("ERROR: Failed to save library.")
	else:
		report.append("Saved: " + OUTPUT_LIBRARY)
		report.append("Total animations added: " + str(added))
		_update_model_data_library(lib, report)
	_write_report(report)
	print("Action Adventure library build complete. Added: " + str(added))


func _load_or_create_library() -> AnimationLibrary:
	var lib: AnimationLibrary = null
	if ResourceLoader.exists(OUTPUT_LIBRARY):
		var existing := ResourceLoader.load(OUTPUT_LIBRARY)
		if existing is AnimationLibrary:
			lib = existing
	if lib == null:
		lib = AnimationLibrary.new()
	return lib


func _collect_fbx(dir_path: String, out: Array[String], inside_allowed_pack: bool = false) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Missing input dir: " + dir_path)
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
			var child_inside_allowed_pack: bool = inside_allowed_pack or _is_pack_allowed(name)
			_collect_fbx(full, out, child_inside_allowed_pack)
			continue
		elif name.to_lower().ends_with(".fbx"):
			if not (inside_allowed_pack or _path_matches_pack_filter(full)):
				continue
			out.append(full)
	dir.list_dir_end()


func _is_pack_allowed(folder_name: String) -> bool:
	if PACK_FILTER.is_empty():
		return true
	for pack_name in PACK_FILTER:
		if folder_name == pack_name:
			return true
	return false


func _path_matches_pack_filter(path: String) -> bool:
	if PACK_FILTER.is_empty():
		return true
	var norm_path: String = path.replace("\\", "/")
	for pack_name in PACK_FILTER:
		var needle: String = "/" + pack_name + "/"
		if norm_path.find(needle) != -1:
			return true
	return false


func _should_skip(path: String) -> bool:
	if INCLUDE_TPOSE:
		return false
	var name := path.get_file().get_basename().to_lower()
	for exact_name in SKIP_FILES:
		if name == exact_name:
			return true
	for pattern in SKIP_PATTERNS:
		if name.find(pattern) != -1:
			return true
	return false


func _build_anim_name(path: String, anim_name: String, anim_count: int) -> String:
	var rel := path.replace(INPUT_ROOT + "/", "")
	var pack_path := _normalize_pack_path(rel.get_base_dir())
	var pack_slug := _slug(pack_path)
	var clip_name := path.get_file().get_basename()
	var clip_slug := _slug(clip_name)
	if anim_count > 1 and anim_name != "":
		clip_slug = _slug(anim_name)
	var name := clip_slug
	if pack_slug != "":
		name = pack_slug + "__" + clip_slug
	if name == "":
		name = "anim_" + str(abs(path.hash()))
	return name


func _select_source_animation_names(anim_player: AnimationPlayer, anim_names: PackedStringArray) -> PackedStringArray:
	var selected: PackedStringArray = PackedStringArray()
	if anim_names.is_empty():
		return selected
	if anim_names.has("mixamo_com"):
		selected.append("mixamo_com")
		return selected
	for name in anim_names:
		var anim: Animation = anim_player.get_animation(name)
		if _is_skeletal_animation(anim):
			selected.append(name)
	if not selected.is_empty():
		return selected
	for name in anim_names:
		selected.append(name)
	return selected


func _is_skeletal_animation(anim: Animation) -> bool:
	if anim == null:
		return false
	for track_idx in anim.get_track_count():
		var tt: int = anim.track_get_type(track_idx)
		if tt != Animation.TYPE_POSITION_3D and tt != Animation.TYPE_ROTATION_3D and tt != Animation.TYPE_SCALE_3D and tt != Animation.TYPE_BLEND_SHAPE:
			continue
		var path_str: String = String(anim.track_get_path(track_idx))
		if path_str.find("Skeleton3D:") != -1:
			return true
	return false


func _normalize_pack_path(pack_path: String) -> String:
	var p: String = pack_path.replace("\\", "/")
	var lower_p: String = p.to_lower()
	if lower_p.begins_with("fbx animations/"):
		return p.substr("fbx animations/".length())
	return p


func _remove_legacy_prefixed_clips(lib: AnimationLibrary, report: Array[String]) -> void:
	if lib == null:
		return
	var names: PackedStringArray = lib.get_animation_list()
	var removed: int = 0
	for anim_name_any in names:
		var anim_name: String = String(anim_name_any)
		if not anim_name.begins_with("fbx_animations_"):
			continue
		lib.remove_animation(anim_name)
		removed += 1
		report.append("- PURGE legacy " + anim_name)
	if removed > 0:
		report.append("Purged legacy-prefixed clips: " + str(removed))


func _purge_empty_clips(lib: AnimationLibrary, report: Array[String]) -> void:
	if lib == null:
		return
	var names: PackedStringArray = lib.get_animation_list()
	var removed: int = 0
	for anim_name_any in names:
		var anim_name: String = String(anim_name_any)
		var anim: Animation = lib.get_animation(anim_name)
		if anim == null:
			continue
		if anim.get_track_count() > 0:
			continue
		lib.remove_animation(anim_name)
		removed += 1
		report.append("- PURGE empty " + anim_name)
	if removed > 0:
		report.append("Purged empty clips: " + str(removed))


func _slug(value: String) -> String:
	var out := value.strip_edges().to_lower()
	out = out.replace("\\", "/")
	out = out.replace("/", "_")
	out = out.replace(" ", "_")
	out = out.replace("-", "_")
	out = out.replace("__", "_")
	return out


func _find_anim_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		return players[0] as AnimationPlayer
	return null


func _strip_root_translation(anim: Animation) -> void:
	if anim == null:
		return
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		var path := anim.track_get_path(track_idx)
		if not _is_root_bone_path(path):
			continue
		var key_count := anim.track_get_key_count(track_idx)
		for i in range(key_count):
			var _t := anim.track_get_key_time(track_idx, i)
			anim.track_set_key_value(track_idx, i, Vector3.ZERO)
		break


func _is_root_bone_path(path: NodePath) -> bool:
	var name := ""
	if path.get_subname_count() > 0:
		name = String(path.get_subname(0))
	else:
		name = String(path).get_file()
	name = _normalize_bone_name(name)
	for candidate in ROOT_BONE_NAMES:
		if name == _normalize_bone_name(candidate):
			return true
	return false


func _sanitize_animation_tracks(anim: Animation) -> void:
	if anim == null:
		return
	# Safety fallback: never strip tracks if rig cache could not be built.
	if _bone_map.is_empty():
		return
	for track_idx in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(track_idx)
		var path_str := String(path)
		if path_str == "":
			continue
		var split_at := path_str.find(":")
		if split_at == -1:
			if not _node_exists(path_str):
				anim.remove_track(track_idx)
			continue
		var node_path := path_str.substr(0, split_at)
		var subname := path_str.substr(split_at + 1)
		if node_path.find("Skeleton3D") != -1:
			var bone_key := _normalize_bone_name(subname)
			if not _bone_map.has(bone_key):
				anim.remove_track(track_idx)
				continue
			var bone_name := String(_bone_map[bone_key])
			var target_path := _skeleton_path if _skeleton_path != "" else node_path
			anim.track_set_path(track_idx, NodePath(target_path + ":" + bone_name))
		else:
			if not _node_exists(node_path):
				anim.remove_track(track_idx)


func _make_animation_tracks_editable(anim: Animation) -> void:
	if anim == null:
		return
	if not anim.has_method("track_set_imported"):
		return
	for track_idx in anim.get_track_count():
		anim.track_set_imported(track_idx, false)


func _ensure_output_dir() -> void:
	var dir_path := OUTPUT_LIBRARY.get_base_dir()
	var abs_path := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(abs_path)


func _write_report(lines: Array[String]) -> void:
	var file := FileAccess.open(OUTPUT_REPORT, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write report: " + OUTPUT_REPORT)
		return
	for line in lines:
		file.store_line(line)
	file.close()


func _update_model_data_library(lib: AnimationLibrary, report: Array[String]) -> void:
	if lib == null:
		return
	if not ResourceLoader.exists(MODEL_DATA_PATH):
		report.append("WARN: Model data not found: " + MODEL_DATA_PATH)
		return
	var res := ResourceLoader.load(MODEL_DATA_PATH)
	if res == null:
		report.append("WARN: Failed to load model data: " + MODEL_DATA_PATH)
		return
	if "animation_library" in res:
		res.animation_library = lib
		var save_err := ResourceSaver.save(res, MODEL_DATA_PATH)
		if save_err == OK:
			report.append("Updated model data library: " + MODEL_DATA_PATH)
		else:
			report.append("WARN: Failed to save model data: " + MODEL_DATA_PATH)


func _build_skeleton_cache() -> void:
	_skeleton_path = ""
	_bone_map.clear()
	_node_paths.clear()
	if not ResourceLoader.exists(REFERENCE_RIG_SCENE):
		push_warning("Reference rig not found: " + REFERENCE_RIG_SCENE)
		return
	var scene_res := ResourceLoader.load(REFERENCE_RIG_SCENE)
	if scene_res == null or not (scene_res is PackedScene):
		push_warning("Reference rig is not a PackedScene: " + REFERENCE_RIG_SCENE)
		return
	var inst := (scene_res as PackedScene).instantiate()
	if inst == null:
		push_warning("Failed to instance reference rig.")
		return
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		_skeleton_path = String(inst.get_path_to(skeleton))
		for i in range(skeleton.get_bone_count()):
			var name := skeleton.get_bone_name(i)
			_bone_map[_normalize_bone_name(name)] = name
		_cache_node_paths(inst)
	else:
		push_warning("Reference rig has no Skeleton3D: " + REFERENCE_RIG_SCENE)
	inst.free()


func _cache_node_paths(root: Node) -> void:
	if root == null:
		return
	_node_paths["."] = true
	for node in root.find_children("*", "", true, false):
		_node_paths[String(root.get_path_to(node))] = true


func _node_exists(path_str: String) -> bool:
	if _node_paths.is_empty():
		return true
	return _node_paths.has(path_str)


func _normalize_bone_name(name: String) -> String:
	var out := name.strip_edges().to_lower()
	out = out.replace(":", "_")
	return out


func _find_preimported_anim_files(fbx_path: String) -> PackedStringArray:
	var results: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var dir_path := fbx_path.get_base_dir()
	var base := fbx_path.get_file().get_basename()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return results
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if not name.to_lower().ends_with(".anim"):
			continue
		var name_base := name.get_basename()
		if name_base == base or name_base.begins_with(base + "__"):
			var full_path := dir_path.path_join(name)
			if not seen.has(full_path):
				seen[full_path] = true
				results.append(full_path)
	dir.list_dir_end()
	_append_import_anim_paths(fbx_path, results, seen)
	results.sort()
	return results


func _derive_anim_name_from_file(anim_path: String, fbx_path: String) -> String:
	var base := fbx_path.get_file().get_basename()
	var name_base := anim_path.get_file().get_basename()
	if name_base == base:
		return ""
	var prefix := base + "__"
	if name_base.begins_with(prefix):
		return name_base.substr(prefix.length())
	return name_base


func _add_preimported_anims(anim_paths: PackedStringArray, fbx_path: String, lib: AnimationLibrary, report: Array[String]) -> int:
	var added := 0
	var anim_count := anim_paths.size()
	for anim_path in anim_paths:
		if not _is_valid_anim_resource(anim_path):
			report.append("- SKIP invalid anim " + anim_path)
			continue
		var anim_res := ResourceLoader.load(anim_path)
		if anim_res == null or not (anim_res is Animation):
			report.append("- FAIL load anim " + anim_path)
			continue
		var anim_name := _derive_anim_name_from_file(anim_path, fbx_path)
		var out_name := _build_anim_name(fbx_path, anim_name, anim_count)
		if not ONLY_ANIMATIONS.is_empty() and not ONLY_ANIMATIONS.has(out_name):
			continue
		if FORCE_REIMPORT_ONLY and not ONLY_ANIMATIONS.is_empty() and lib.has_animation(out_name):
			lib.remove_animation(out_name)
		if lib.has_animation(out_name):
			if SKIP_EXISTING_ANIMATIONS:
				report.append("- KEEP " + out_name + " (already exists)")
				continue
			lib.remove_animation(out_name)
			report.append("- REPLACE " + out_name)
		var out_anim: Animation = (anim_res as Animation).duplicate(true)
		_make_animation_tracks_editable(out_anim)
		_sanitize_animation_tracks(out_anim)
		if STRIP_ROOT_TRANSLATION:
			_strip_root_translation(out_anim)
		if out_anim.get_track_count() == 0:
			report.append("- DROP empty " + out_name + " <= " + anim_path)
			continue
		lib.add_animation(out_name, out_anim)
		report.append("- ADD " + out_name + " <= " + anim_path)
		added += 1
	return added


func _is_valid_anim_resource(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var length := file.get_length()
	if length < 8:
		file.close()
		return false
	var sig_bytes := file.get_buffer(4)
	file.seek(length - 4)
	var tail_bytes := file.get_buffer(4)
	file.close()
	if sig_bytes.size() < 4:
		return false
	if tail_bytes.size() < 4:
		return false
	var sig := ""
	for b in sig_bytes:
		sig += char(b)
	var tail := ""
	for b in tail_bytes:
		tail += char(b)
	return sig == "RSRC" and tail == "RSRC"


func _is_import_valid(fbx_path: String) -> bool:
	var import_path := fbx_path + ".import"
	if not FileAccess.file_exists(import_path):
		return true
	var file := FileAccess.open(import_path, FileAccess.READ)
	if file == null:
		return true
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		return true
	var filtered := PackedByteArray()
	for b in bytes:
		if b == 0:
			continue
		filtered.append(b)
	var text := filtered.get_string_from_ascii()
	if text == "":
		return true
	return text.find("valid=false") == -1


func _append_import_anim_paths(fbx_path: String, results: PackedStringArray, seen: Dictionary) -> void:
	var import_path := fbx_path + ".import"
	if not FileAccess.file_exists(import_path):
		return
	var file := FileAccess.open(import_path, FileAccess.READ)
	if file == null:
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		return
	var filtered := PackedByteArray()
	for b in bytes:
		if b == 0:
			continue
		filtered.append(b)
	var text := filtered.get_string_from_ascii()
	if text == "":
		return
	var lines := text.split("\n", false)
	for line in lines:
		if line.find("save_to_file/fallback_path") == -1 and line.find("save_to_file/path") == -1:
			continue
		var colon := line.find(":")
		if colon == -1:
			continue
		var first_quote := line.find("\"", colon)
		if first_quote == -1:
			continue
		var second_quote := line.find("\"", first_quote + 1)
		if second_quote == -1:
			continue
		var value := line.substr(first_quote + 1, second_quote - first_quote - 1)
		if value == "" or value.begins_with("uid://"):
			continue
		if not FileAccess.file_exists(value):
			continue
		if seen.has(value):
			continue
		seen[value] = true
		results.append(value)
