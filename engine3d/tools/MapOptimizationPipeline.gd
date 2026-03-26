@tool
extends SceneTree

const OPT_EDITING: String = "OPT_EDITING"
const OPT_RUNTIME: String = "OPT_RUNTIME"

const DEFAULT_MODE: String = "editing" # editing | runtime
const DEFAULT_UV_TEMPLATE_DEST: String = "res://artifacts/uv_templates"
const DEFAULT_REPORT_PATH: String = "res://artifacts/optimization/report.json"
const DEFAULT_UV_TEMPLATE_FORMAT: String = "PNG"
const DEFAULT_UV_TEMPLATE_RESOLUTION: int = 2048
const DEFAULT_UV_TEMPLATE_PER_OBJECT: bool = true
const DEFAULT_UV_TEMPLATE_INCLUDE_LODS: bool = false

const SUPPORTED_BLENDER_EXTS: Dictionary = {
	"obj": true,
	"fbx": true,
	"gltf": true,
	"glb": true,
	"dae": true,
}


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var config: Dictionary = _parse_args(args)
	var exit_code: int = _run(config)
	quit(exit_code)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var mode: String = DEFAULT_MODE
	var scene_path: String = ""
	var input_path: String = ""
	var report_path: String = DEFAULT_REPORT_PATH
	var staging_dir: String = ""
	var export_uv_templates: Variant = null
	var uv_template_format: String = DEFAULT_UV_TEMPLATE_FORMAT
	var uv_template_resolution: int = DEFAULT_UV_TEMPLATE_RESOLUTION
	var uv_template_per_object: bool = DEFAULT_UV_TEMPLATE_PER_OBJECT
	var uv_template_include_lods: bool = DEFAULT_UV_TEMPLATE_INCLUDE_LODS
	var uv_template_destination: String = DEFAULT_UV_TEMPLATE_DEST
	var uv_template_stage: String = "after"
	var blender_exe: String = ""
	var blender_script: String = ""

	for arg in args:
		if arg.begins_with("--mode="):
			mode = arg.substr("--mode=".length()).strip_edges().to_lower()
			continue
		if arg.begins_with("--scene="):
			scene_path = arg.substr("--scene=".length()).strip_edges()
			continue
		if arg.begins_with("--input="):
			input_path = arg.substr("--input=".length()).strip_edges()
			continue
		if arg.begins_with("--report="):
			report_path = arg.substr("--report=".length()).strip_edges()
			continue
		if arg.begins_with("--staging-dir="):
			staging_dir = arg.substr("--staging-dir=".length()).strip_edges()
			continue
		if arg == "--export-uv-templates":
			export_uv_templates = true
			continue
		if arg == "--no-export-uv-templates":
			export_uv_templates = false
			continue
		if arg.begins_with("--uv-template-format="):
			uv_template_format = arg.substr("--uv-template-format=".length()).strip_edges().to_upper()
			continue
		if arg.begins_with("--uv-template-resolution="):
			uv_template_resolution = int(arg.substr("--uv-template-resolution=".length()).strip_edges())
			continue
		if arg == "--uv-template-per-object":
			uv_template_per_object = true
			continue
		if arg == "--uv-template-per-asset":
			uv_template_per_object = false
			continue
		if arg == "--uv-template-include-lods":
			uv_template_include_lods = true
			continue
		if arg == "--uv-template-exclude-lods":
			uv_template_include_lods = false
			continue
		if arg.begins_with("--uv-template-destination="):
			uv_template_destination = arg.substr("--uv-template-destination=".length()).strip_edges()
			continue
		if arg.begins_with("--uv-template-stage="):
			uv_template_stage = arg.substr("--uv-template-stage=".length()).strip_edges().to_lower()
			continue
		if arg.begins_with("--blender="):
			blender_exe = arg.substr("--blender=".length()).strip_edges()
			continue
		if arg.begins_with("--blender-script="):
			blender_script = arg.substr("--blender-script=".length()).strip_edges()
			continue

	return {
		"mode": mode if not mode.is_empty() else DEFAULT_MODE,
		"scene_path": scene_path,
		"input_path": input_path,
		"report_path": report_path if not report_path.is_empty() else DEFAULT_REPORT_PATH,
		"staging_dir": staging_dir,
		"export_uv_templates": export_uv_templates,
		"uv_template_format": uv_template_format,
		"uv_template_resolution": uv_template_resolution,
		"uv_template_per_object": uv_template_per_object,
		"uv_template_include_lods": uv_template_include_lods,
		"uv_template_destination": uv_template_destination,
		"uv_template_stage": uv_template_stage,
		"blender_exe": blender_exe,
		"blender_script": blender_script,
	}


func _run(config: Dictionary) -> int:
	var mode: String = str(config.get("mode", DEFAULT_MODE)).to_lower()
	if mode != "editing" and mode != "runtime":
		mode = DEFAULT_MODE
	var opt_id: String = OPT_EDITING if mode == "editing" else OPT_RUNTIME

	var scene_path: String = str(config.get("scene_path", "")).strip_edges()
	var input_path: String = str(config.get("input_path", "")).strip_edges()
	var report_path: String = str(config.get("report_path", DEFAULT_REPORT_PATH)).strip_edges()
	var staging_dir: String = str(config.get("staging_dir", "")).strip_edges()
	var export_uv_templates_any: Variant = config.get("export_uv_templates", null)
	var export_uv_templates: bool = false
	var uv_template_format: String = str(config.get("uv_template_format", DEFAULT_UV_TEMPLATE_FORMAT)).to_upper()
	var uv_template_resolution: int = int(config.get("uv_template_resolution", DEFAULT_UV_TEMPLATE_RESOLUTION))
	var uv_template_per_object: bool = bool(config.get("uv_template_per_object", DEFAULT_UV_TEMPLATE_PER_OBJECT))
	var uv_template_include_lods: bool = bool(config.get("uv_template_include_lods", DEFAULT_UV_TEMPLATE_INCLUDE_LODS))
	var uv_template_destination: String = str(config.get("uv_template_destination", DEFAULT_UV_TEMPLATE_DEST)).strip_edges()
	var uv_template_stage: String = str(config.get("uv_template_stage", "after")).to_lower()
	var blender_exe: String = str(config.get("blender_exe", "")).strip_edges()
	var blender_script: String = str(config.get("blender_script", "")).strip_edges()

	if uv_template_format != "PNG" and uv_template_format != "SVG":
		uv_template_format = DEFAULT_UV_TEMPLATE_FORMAT
	if uv_template_resolution < 64:
		uv_template_resolution = DEFAULT_UV_TEMPLATE_RESOLUTION
	if uv_template_destination.is_empty():
		uv_template_destination = DEFAULT_UV_TEMPLATE_DEST
	if uv_template_stage != "before" and uv_template_stage != "after":
		uv_template_stage = "after"

	if export_uv_templates_any == null:
		export_uv_templates = true if mode == "editing" else false
	else:
		export_uv_templates = bool(export_uv_templates_any)

	if mode == "runtime":
		if staging_dir.is_empty():
			push_error("MapOptimizationPipeline: runtime mode requires --staging-dir.")
			return 2
		var staging_abs: String = ProjectSettings.globalize_path(staging_dir)
		if not DirAccess.dir_exists_absolute(staging_abs):
			push_error("MapOptimizationPipeline: staging dir does not exist: %s" % staging_dir)
			return 2

	var target_path: String = scene_path
	if target_path.is_empty():
		target_path = input_path

	if target_path.is_empty():
		push_error("MapOptimizationPipeline: No scene or input path supplied.")
		return 1

	var report: Dictionary = {
		"mode": mode,
		"opt_id": opt_id,
		"timestamp": Time.get_datetime_string_from_system(),
		"scene": scene_path,
		"input": input_path,
		"staging_dir": staging_dir,
		"steps": [],
		"artifacts": {
			"uv_templates": []
		},
		"warnings": [],
		"errors": []
	}

	var mesh_entries: Array[Dictionary] = _collect_mesh_entries(target_path)
	if export_uv_templates:
		var export_result: Dictionary = _export_uv_templates(mesh_entries, uv_template_destination, uv_template_format, uv_template_resolution, uv_template_per_object, uv_template_include_lods, uv_template_stage, blender_exe, blender_script)
		if not bool(export_result.get("ok", false)):
			report["warnings"].append(str(export_result.get("warning", "UV template export skipped.")))
		report["artifacts"]["uv_templates"] = export_result.get("entries", [])

	_write_report(report_path, report)
	print("MapOptimizationPipeline: finished %s. Report: %s" % [opt_id, report_path])
	return 0


func _collect_mesh_entries(target_path: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not target_path.begins_with("res://"):
		return entries
	var ext: String = target_path.get_extension().to_lower()
	if ext == "tscn" or ext == "scn":
		var packed: PackedScene = ResourceLoader.load(target_path) as PackedScene
		if packed == null:
			return entries
		var inst: Node = packed.instantiate()
		if inst == null:
			return entries
		var mesh_nodes: Array[Node] = inst.find_children("*", "MeshInstance3D", true, false)
		for node_obj in mesh_nodes:
			var mi: MeshInstance3D = node_obj as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var mesh_res_path: String = mi.mesh.resource_path
			var entry: Dictionary = {
				"object": mi.name,
				"mesh_path": mesh_res_path,
				"lod": "LOD0",
			}
			entries.append(entry)
		inst.queue_free()
		return entries

	# Direct mesh resource.
	entries.append({
		"object": target_path.get_file().get_basename(),
		"mesh_path": target_path,
		"lod": "LOD0",
	})
	return entries


func _export_uv_templates(
	mesh_entries: Array[Dictionary],
	destination: String,
	fmt: String,
	resolution: int,
	per_object: bool,
	include_lods: bool,
	stage_label: String,
	blender_exe: String,
	blender_script: String
) -> Dictionary:
	var entries: Array[Dictionary] = []
	if mesh_entries.is_empty():
		return {"ok": false, "warning": "No meshes found to export.", "entries": entries}

	var dest_res: String = destination
	if dest_res.is_empty():
		dest_res = DEFAULT_UV_TEMPLATE_DEST
	if not dest_res.begins_with("res://"):
		dest_res = "res://" + dest_res.trim_prefix("res://")
	var dest_abs: String = ProjectSettings.globalize_path(dest_res)
	DirAccess.make_dir_recursive_absolute(dest_abs)

	var can_run_blender: bool = not blender_exe.is_empty() and not blender_script.is_empty()
	if can_run_blender:
		if not FileAccess.file_exists(blender_exe):
			can_run_blender = false
		if not FileAccess.file_exists(ProjectSettings.globalize_path(blender_script)):
			can_run_blender = false

	for entry in mesh_entries:
		var mesh_path: String = str(entry.get("mesh_path", ""))
		var mesh_name: String = str(entry.get("object", "Mesh"))
		var lod_label: String = str(entry.get("lod", "LOD0"))
		var file_stub: String = "UV_%s_%s_%s_%s" % [
			mesh_path.get_file().get_basename(),
			mesh_name,
			lod_label,
			stage_label
		]
		var out_path: String = dest_res.path_join(file_stub + "." + fmt.to_lower())
		var item: Dictionary = {
			"object": mesh_name,
			"lod": lod_label,
			"stage": stage_label,
			"path": out_path,
			"mesh_path": mesh_path,
			"exported": false,
		}
		if can_run_blender and _can_export_mesh_path(mesh_path):
			var abs_in: String = ProjectSettings.globalize_path(mesh_path)
			var abs_out: String = ProjectSettings.globalize_path(out_path)
			var ok: bool = _run_blender_uv_export(blender_exe, blender_script, abs_in, abs_out, fmt, resolution, per_object, include_lods)
			item["exported"] = ok
		entries.append(item)

	if not can_run_blender:
		return {"ok": false, "warning": "Blender UV export not configured; entries recorded only.", "entries": entries}
	return {"ok": true, "entries": entries}


func _can_export_mesh_path(mesh_path: String) -> bool:
	if mesh_path.is_empty():
		return false
	var ext: String = mesh_path.get_extension().to_lower()
	return SUPPORTED_BLENDER_EXTS.has(ext)


func _run_blender_uv_export(
	blender_exe: String,
	blender_script: String,
	input_abs: String,
	output_abs: String,
	fmt: String,
	resolution: int,
	per_object: bool,
	include_lods: bool
) -> bool:
	var args: PackedStringArray = PackedStringArray([
		"--background",
		"--python",
		ProjectSettings.globalize_path(blender_script),
		"--",
		"--input=%s" % input_abs,
		"--output=%s" % output_abs,
		"--format=%s" % fmt,
		"--resolution=%d" % resolution,
		"--per-object=%s" % ("1" if per_object else "0"),
		"--include-lods=%s" % ("1" if include_lods else "0"),
	])
	var output: Array = []
	var code: int = OS.execute(blender_exe, args, output, true)
	if code != 0:
		return false
	return true


func _write_report(report_path: String, report: Dictionary) -> void:
	if report_path.is_empty():
		return
	var abs_dir: String = ProjectSettings.globalize_path(report_path.get_base_dir())
	if not abs_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("MapOptimizationPipeline: failed to write report: %s" % report_path)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.store_string("\n")
	file.close()
