@tool
extends RefCounted

const OBJ_EXPORTER_SCRIPT: Script = preload("res://addons/densetsu_geometry_obj_export/scene_geometry_obj_exporter.gd")
const MESH_OBJ_HELPER_SCRIPT: Script = preload("res://addons/densetsu_tool_suite/helpers/mesh_obj_helper.gd")

var overwrite_existing: bool = true
var _exporter: RefCounted
var _mesh_obj_helper: RefCounted


func _pack_paths(paths: PackedStringArray) -> void:
	if paths.is_empty():
		push_warning("Select model files in the FileSystem dock first.")
		return
	print("DSM pack: selected paths:", paths)
	for path in paths:
		if path.ends_with(".import") or path.ends_with(".uid"):
			continue
		print("DSM pack: processing:", path)
		_pack_resource_path(path)


func _pack_resource_path(path: String) -> void:
	print("DSM pack: loading:", path)
	var res := ResourceLoader.load(path)
	if res == null:
		push_warning("Failed to load: " + path)
		return
	if res is PackedScene:
		_export_scene_to_obj(path, res)
		return
	if res is Mesh:
		_export_mesh_to_obj(path, res)
		return
	push_warning("Unsupported resource type for OBJ export: " + path)


func _export_scene_to_obj(path: String, scene_res: PackedScene) -> void:
	var inst: Node = scene_res.instantiate()
	if inst == null:
		push_warning("DSM pack: failed to instance: " + path)
		return
	var root_3d := inst as Node3D
	if root_3d == null:
		inst.free()
		push_warning("DSM pack: scene root is not Node3D: " + path)
		return
	var out_path := _derive_output_path(path)
	if out_path == "":
		inst.free()
		push_warning("DSM pack: could not derive output path for: " + path)
		return
	var exporter := _get_exporter()
	if exporter == null or not exporter.has_method("export_nodes_to_obj"):
		inst.free()
		push_warning("DSM pack: OBJ exporter unavailable.")
		return
	var options := {
		"include_mesh_instances": true,
		"include_csg": true,
		"include_multimesh": true,
		"apply_world_transform": true,
		"flip_v_texcoord": true,
		"enforce_outward_winding": true,
		"manifold_only": false,
		"remove_enclosed_faces": false
	}
	var result: Dictionary = exporter.call("export_nodes_to_obj", [root_3d], out_path, options)
	inst.free()
	if bool(result.get("ok", false)):
		print("DSM pack: exported OBJ:", out_path)
	else:
		push_warning("DSM pack: OBJ export failed: " + String(result.get("error", "Unknown error")))


func _export_mesh_to_obj(path: String, mesh_res: Mesh) -> void:
	var out_path := _derive_output_path(path)
	if out_path == "":
		push_warning("DSM pack: could not derive output path for: " + path)
		return
	var helper := _get_mesh_obj_helper()
	if helper == null or not helper.has_method("export_mesh_to_obj"):
		push_warning("DSM pack: Mesh OBJ helper unavailable.")
		return
	var base_name := path.get_file().get_basename()
	var ok: bool = bool(helper.call("export_mesh_to_obj", mesh_res, out_path, base_name))
	if ok:
		print("DSM pack: exported OBJ:", out_path)
	else:
		push_warning("DSM pack: Mesh OBJ export failed: " + out_path)


func _get_exporter() -> RefCounted:
	if _exporter == null and OBJ_EXPORTER_SCRIPT != null:
		_exporter = OBJ_EXPORTER_SCRIPT.new()
	return _exporter


func _get_mesh_obj_helper() -> RefCounted:
	if _mesh_obj_helper == null and MESH_OBJ_HELPER_SCRIPT != null:
		_mesh_obj_helper = MESH_OBJ_HELPER_SCRIPT.new()
	return _mesh_obj_helper


func _derive_output_path(src_path: String) -> String:
	if src_path == "":
		return ""
	var base_dir := src_path.get_base_dir()
	var base_name := src_path.get_file().get_basename()
	if base_name == "":
		base_name = "SceneExport"
	var out := base_dir.path_join(base_name + ".obj")
	if overwrite_existing:
		return out
	var idx := 1
	while ResourceLoader.exists(out):
		out = base_dir.path_join("%s_%d.obj" % [base_name, idx])
		idx += 1
	return out
