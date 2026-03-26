@tool
extends SceneTree

const DEFAULT_REPORT_PATH: String = "res://temp/force_scene_material_filtering_report.txt"

var _scene_path: String = ""
var _dry_run: bool = false
var _localize_materials: bool = true
var _localize_meshes: bool = true
var _mode: String = "linear_mipmap_aniso"
var _report_path: String = DEFAULT_REPORT_PATH
var _target_filter: int = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

var _material_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}

var _stats_nodes_scanned: int = 0
var _stats_material_slots_scanned: int = 0
var _stats_materials_changed: int = 0
var _stats_materials_unchanged: int = 0
var _stats_shader_skipped: int = 0
var _stats_other_skipped: int = 0
var _stats_meshes_localized: int = 0
var _stats_materials_localized: int = 0
var _stats_scene_changed: bool = false


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var code: int = _run(args)
	quit(code)


func _run(args: PackedStringArray) -> int:
	_parse_args(args)
	if _scene_path.is_empty():
		var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
		if not main_scene.is_empty():
			_scene_path = main_scene
	if _scene_path.is_empty():
		push_error("ForceSceneMaterialFiltering: missing --scene=res://path/to/scene.tscn")
		return 1
	if not ResourceLoader.exists(_scene_path):
		push_error("ForceSceneMaterialFiltering: scene not found: %s" % _scene_path)
		return 1

	_target_filter = _resolve_filter_mode(_mode)
	var packed: PackedScene = ResourceLoader.load(_scene_path) as PackedScene
	if packed == null:
		push_error("ForceSceneMaterialFiltering: failed loading scene: %s" % _scene_path)
		return 1
	var root: Node = packed.instantiate()
	if root == null:
		push_error("ForceSceneMaterialFiltering: failed instantiating scene: %s" % _scene_path)
		return 1

	_scan_node_recursive(root)

	if _stats_scene_changed and not _dry_run:
		var out_scene: PackedScene = PackedScene.new()
		var pack_err: Error = out_scene.pack(root)
		if pack_err != OK:
			push_error("ForceSceneMaterialFiltering: failed packing scene (%s): %s" % [_scene_path, error_string(pack_err)])
			root.free()
			return 1
		var save_err: Error = ResourceSaver.save(out_scene, _scene_path)
		if save_err != OK:
			push_error("ForceSceneMaterialFiltering: failed saving scene (%s): %s" % [_scene_path, error_string(save_err)])
			root.free()
			return 1

	root.free()
	_write_report()
	print("ForceSceneMaterialFiltering: scene=%s dry_run=%s mode=%s changed=%s nodes=%d slots=%d materials_changed=%d localized_materials=%d localized_meshes=%d shader_skipped=%d other_skipped=%d report=%s" % [
		_scene_path,
		str(_dry_run),
		_mode,
		str(_stats_scene_changed),
		_stats_nodes_scanned,
		_stats_material_slots_scanned,
		_stats_materials_changed,
		_stats_materials_localized,
		_stats_meshes_localized,
		_stats_shader_skipped,
		_stats_other_skipped,
		_report_path,
	])
	return 0


func _parse_args(args: PackedStringArray) -> void:
	for arg: String in args:
		if arg.begins_with("--scene="):
			_scene_path = arg.substr("--scene=".length()).strip_edges()
			continue
		if arg == "--dry-run":
			_dry_run = true
			continue
		if arg.begins_with("--mode="):
			_mode = arg.substr("--mode=".length()).strip_edges().to_lower()
			continue
		if arg.begins_with("--report="):
			var out_report: String = arg.substr("--report=".length()).strip_edges()
			if not out_report.is_empty():
				_report_path = out_report
			continue
		if arg == "--no-localize-materials":
			_localize_materials = false
			continue
		if arg == "--localize-materials":
			_localize_materials = true
			continue
		if arg == "--no-localize-meshes":
			_localize_meshes = false
			continue
		if arg == "--localize-meshes":
			_localize_meshes = true
			continue


func _resolve_filter_mode(mode_name: String) -> int:
	match mode_name:
		"linear":
			return BaseMaterial3D.TEXTURE_FILTER_LINEAR
		"linear_mipmap":
			return BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"linear_mipmap_aniso":
			return BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_:
			return BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func _scan_node_recursive(node: Node) -> void:
	_stats_nodes_scanned += 1

	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null:
		_process_mesh_instance(mesh_instance)

	var multi_mesh_instance: MultiMeshInstance3D = node as MultiMeshInstance3D
	if multi_mesh_instance != null:
		_process_multimesh_instance(multi_mesh_instance)

	var csg_shape: CSGShape3D = node as CSGShape3D
	if csg_shape != null:
		var fixed_csg_mat: Material = _process_material(csg_shape.material)
		if fixed_csg_mat != csg_shape.material:
			csg_shape.material = fixed_csg_mat
			_stats_scene_changed = true

	for child: Node in node.get_children():
		_scan_node_recursive(child)


func _process_mesh_instance(mesh_instance: MeshInstance3D) -> void:
	_process_geometry_material_slots(mesh_instance)
	if mesh_instance.mesh == null:
		return
	var surface_count: int = mesh_instance.mesh.get_surface_count()
	var i: int = 0
	while i < surface_count:
		_stats_material_slots_scanned += 1
		var source_mat: Material = mesh_instance.get_surface_override_material(i)
		if source_mat == null:
			source_mat = mesh_instance.get_active_material(i)
		if source_mat != null:
			var fixed_mat: Material = _process_material(source_mat)
			if fixed_mat != mesh_instance.get_surface_override_material(i):
				mesh_instance.set_surface_override_material(i, fixed_mat)
				_stats_scene_changed = true
		i += 1


func _process_multimesh_instance(multi_mesh_instance: MultiMeshInstance3D) -> void:
	_process_geometry_material_slots(multi_mesh_instance)
	var mm: MultiMesh = multi_mesh_instance.multimesh
	if mm == null or mm.mesh == null:
		return
	var target_mesh: Mesh = mm.mesh
	if _localize_meshes:
		target_mesh = _get_localized_mesh(target_mesh)
		if target_mesh != mm.mesh:
			mm.mesh = target_mesh
			_stats_scene_changed = true
	var surface_count: int = target_mesh.get_surface_count()
	var i: int = 0
	while i < surface_count:
		_stats_material_slots_scanned += 1
		var source_mat: Material = target_mesh.surface_get_material(i)
		if source_mat != null:
			var fixed_mat: Material = _process_material(source_mat)
			if fixed_mat != source_mat:
				target_mesh.surface_set_material(i, fixed_mat)
				_stats_scene_changed = true
		i += 1


func _process_geometry_material_slots(geom: GeometryInstance3D) -> void:
	_stats_material_slots_scanned += 1
	var fixed_override: Material = _process_material(geom.material_override)
	if fixed_override != geom.material_override:
		geom.material_override = fixed_override
		_stats_scene_changed = true

	_stats_material_slots_scanned += 1
	var fixed_overlay: Material = _process_material(geom.material_overlay)
	if fixed_overlay != geom.material_overlay:
		geom.material_overlay = fixed_overlay
		_stats_scene_changed = true


func _process_material(material: Material) -> Material:
	if material == null:
		return null
	var cache_key: String = str(material.get_instance_id())
	var cached: Variant = _material_cache.get(cache_key, null)
	if cached is Material:
		return cached as Material

	var out: Material = material
	var base_material: BaseMaterial3D = material as BaseMaterial3D
	if base_material != null:
		var target_base: BaseMaterial3D = base_material
		if _localize_materials:
			target_base = _get_localized_material(base_material)
			if target_base != base_material:
				_stats_materials_localized += 1
		if int(target_base.texture_filter) != _target_filter:
			target_base.texture_filter = _target_filter
			_stats_materials_changed += 1
		else:
			_stats_materials_unchanged += 1
		out = target_base
	else:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		if shader_material != null:
			_stats_shader_skipped += 1
		else:
			_stats_other_skipped += 1

	_material_cache[cache_key] = out
	return out


func _get_localized_material(material: BaseMaterial3D) -> BaseMaterial3D:
	var key: String = "mat_%s" % str(material.get_instance_id())
	var cached: Variant = _material_cache.get(key, null)
	if cached is BaseMaterial3D:
		return cached as BaseMaterial3D
	var dup: BaseMaterial3D = material.duplicate(true) as BaseMaterial3D
	if dup == null:
		return material
	dup.resource_local_to_scene = true
	_material_cache[key] = dup
	return dup


func _get_localized_mesh(mesh: Mesh) -> Mesh:
	var key: String = str(mesh.get_instance_id())
	var cached: Variant = _mesh_cache.get(key, null)
	if cached is Mesh:
		return cached as Mesh
	var dup: Mesh = mesh.duplicate(true) as Mesh
	if dup == null:
		return mesh
	dup.resource_local_to_scene = true
	_mesh_cache[key] = dup
	_stats_meshes_localized += 1
	return dup


func _write_report() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("ForceSceneMaterialFiltering")
	lines.append("scene=%s" % _scene_path)
	lines.append("dry_run=%s" % str(_dry_run))
	lines.append("mode=%s" % _mode)
	lines.append("target_filter=%d" % _target_filter)
	lines.append("localize_materials=%s" % str(_localize_materials))
	lines.append("localize_meshes=%s" % str(_localize_meshes))
	lines.append("scene_changed=%s" % str(_stats_scene_changed))
	lines.append("nodes_scanned=%d" % _stats_nodes_scanned)
	lines.append("material_slots_scanned=%d" % _stats_material_slots_scanned)
	lines.append("materials_changed=%d" % _stats_materials_changed)
	lines.append("materials_unchanged=%d" % _stats_materials_unchanged)
	lines.append("materials_localized=%d" % _stats_materials_localized)
	lines.append("meshes_localized=%d" % _stats_meshes_localized)
	lines.append("shader_materials_skipped=%d" % _stats_shader_skipped)
	lines.append("other_materials_skipped=%d" % _stats_other_skipped)

	var file: FileAccess = FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		push_warning("ForceSceneMaterialFiltering: failed writing report %s" % _report_path)
		return
	for line: String in lines:
		file.store_line(line)
	file.close()

