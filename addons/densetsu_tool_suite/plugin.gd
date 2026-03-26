@tool
extends EditorPlugin

const STATIC_PACK_PLUGIN_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/static_pack_helper.gd"
const ARRAY_EXTRACT_PLUGIN_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/arraymesh_extract_helper.gd"
const TEXTURE_RESIZE_PLUGIN_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/texture_resize_helper.gd"
const IMAGE_TRANSFORM_HELPER_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/image_transform_helper.gd"
const PIVOT_REASSIGN_HELPER_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/pivot_reassign_helper.gd"
const MESH_OBJ_HELPER_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/mesh_obj_helper.gd"
const OCCLUSION_PRUNE_HELPER_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/occlusion_prune_helper.gd"
const SELECT_SAME_MESH_HELPER_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/select_same_mesh_helper.gd"
const SELECT_INTERSECTING_MESH_HELPER_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/select_intersecting_mesh_helper.gd"
const MESH_SUBDIVIDE_HELPER_SCRIPT: String = "res://addons/densetsu_tool_suite/helpers/mesh_subdivide_helper.gd"
const DENSETSU_TOOL_MENU_ROOT: String = "Densetsu"
const MOVE_HELPER_METADATA_SECTION: String = "densetsu_tool_suite"
const MOVE_HELPER_METADATA_KEY_LAST_FOLDER: String = "move_last_folder"

enum ToolMenuId {
	SPREAD_SELECTED_ON_FLOOR,
	SELECT_SAME_MESH,
	SELECT_INTERSECTING_MESH,
	PRUNE_OCCLUDED,
	PACK_STATIC_MESH,
	EXTRACT_ARRAY_PER_FILE,
	EXTRACT_ARRAY_COMMON,
	EXTRACT_MATERIAL_PER_FILE,
	EXTRACT_MATERIAL_COMMON,
	EXTRACT_COMBINED_PER_FILE,
	EXTRACT_COMBINED_COMMON,
	PIVOT_CENTER_MASS,
	PIVOT_CENTER_BOTTOM,
	CONVERT_MESH_RES_TO_OBJ,
	SUBDIVIDE_MESH_TO_OBJ,
	REPLACE_MESH_REFS_WITH_OBJ,
	REPLACE_MESH_REFS_WITH_OBJ_PROJECT,
	RESIZE_OVERWRITE,
	RESIZE_COPY,
	FLIP_IMAGE_H,
	FLIP_IMAGE_V,
	ROTATE_IMAGE_90,
	ROTATE_IMAGE_180,
	ROTATE_IMAGE_270,
	FORCE_THUMBNAIL_REFRESH,
	FORCE_THUMBNAIL_REFRESH_SELECTED,
	MOVE_SELECTED_TO_FOLDER,
}

const PIVOT_MODE_CENTER_MASS := 0
const PIVOT_MODE_CENTER_BOTTOM := 1
const IMAGE_TRANSFORM_FLIP_H := 0
const IMAGE_TRANSFORM_FLIP_V := 1
const IMAGE_TRANSFORM_ROT_90 := 2
const IMAGE_TRANSFORM_ROT_180 := 3
const IMAGE_TRANSFORM_ROT_270 := 4
const FLOOR_SPREAD_GAP: float = 0.25
const FLOOR_SPREAD_MIN_SIZE: float = 0.5
const FLOOR_SPREAD_RAY_HEIGHT: float = 4096.0
const FLOOR_SPREAD_RAY_DEPTH: float = 8192.0

var _ctx_plugin: EditorContextMenuPlugin
var _tool_root_menu: PopupMenu
var _tool_action_map: Dictionary = {}
var _static_pack_helper: Object
var _array_extract_helper: Object
var _texture_resize_helper: Object
var _image_transform_helper: Object
var _pivot_reassign_helper: Object
var _mesh_obj_helper: Object
var _occlusion_prune_helper: Object
var _select_same_mesh_helper: Object
var _select_intersecting_mesh_helper: Object
var _mesh_subdivide_helper: Object
var _mesh_ref_replace_dialog: ConfirmationDialog
var _mesh_ref_replace_scope_current_folder_check: CheckBox
var _mesh_ref_replace_dry_run_check: CheckBox
var _mesh_ref_replace_same_folder_check: CheckBox
var _mesh_ref_replace_allow_fallback_check: CheckBox
var _mesh_ref_replace_report_dialog: AcceptDialog
var _mesh_ref_replace_report_text: TextEdit
var _tool_log_dialog: AcceptDialog
var _tool_log_text: TextEdit
var _move_dialog: ConfirmationDialog
var _move_destination_edit: LineEdit
var _move_folder_dialog: FileDialog
var _move_pending_paths: PackedStringArray = PackedStringArray()
var _filesystem_refresh_pending: bool = false

class _DensetsuSuiteContextMenuPlugin:
	extends EditorContextMenuPlugin
	var _owner: EditorPlugin

	func _init(owner: EditorPlugin) -> void:
		_owner = owner

	func _popup_menu(paths: PackedStringArray) -> void:
		if paths.is_empty():
			return
		add_context_menu_item("Densetsu: Pack to Static Mesh", Callable(_owner, "_on_ctx_static_pack"))
		add_context_menu_item("Densetsu: Extract ArrayMeshes (Per File)", Callable(_owner, "_on_ctx_extract_mesh_per_file"))
		add_context_menu_item("Densetsu: Extract ArrayMeshes (Common)", Callable(_owner, "_on_ctx_extract_mesh_common"))
		add_context_menu_item("Densetsu: Extract Material Meshes (Per File)", Callable(_owner, "_on_ctx_extract_material_per_file"))
		add_context_menu_item("Densetsu: Extract Material Meshes (Common)", Callable(_owner, "_on_ctx_extract_material_common"))
		add_context_menu_item("Densetsu: Extract Combined Mesh (Per File)", Callable(_owner, "_on_ctx_extract_combined_per_file"))
		add_context_menu_item("Densetsu: Extract Combined Mesh (Common)", Callable(_owner, "_on_ctx_extract_combined_common"))
		add_context_menu_item("Densetsu: Resize Textures POT (Overwrite)", Callable(_owner, "_on_ctx_resize_overwrite"))
		add_context_menu_item("Densetsu: Resize Textures POT (Copy)", Callable(_owner, "_on_ctx_resize_copy"))
		add_context_menu_item("Densetsu: Flip Image Horizontal (Copy)", Callable(_owner, "_on_ctx_flip_image_h"))
		add_context_menu_item("Densetsu: Flip Image Vertical (Copy)", Callable(_owner, "_on_ctx_flip_image_v"))
		add_context_menu_item("Densetsu: Rotate Image 90 (Copy)", Callable(_owner, "_on_ctx_rotate_image_90"))
		add_context_menu_item("Densetsu: Rotate Image 180 (Copy)", Callable(_owner, "_on_ctx_rotate_image_180"))
		add_context_menu_item("Densetsu: Rotate Image 270 (Copy)", Callable(_owner, "_on_ctx_rotate_image_270"))
		add_context_menu_item("Densetsu: Reassign Pivot (Center Mass)", Callable(_owner, "_on_ctx_pivot_center_mass"))
		add_context_menu_item("Densetsu: Reassign Pivot (Center Bottom)", Callable(_owner, "_on_ctx_pivot_center_bottom"))
		add_context_menu_item("Densetsu: Convert Mesh TRES/RES to OBJ", Callable(_owner, "_on_ctx_convert_mesh_res_to_obj"))
		add_context_menu_item("Densetsu: Subdivide Mesh -> OBJ (1x/2x/4x)", Callable(_owner, "_on_ctx_subdivide_mesh_to_obj"))
		add_context_menu_item("Densetsu: Replace Scene TRES/RES Refs with Selected OBJ", Callable(_owner, "_on_ctx_replace_mesh_refs_with_obj"))
		add_context_menu_item("Densetsu: Move Selected To Folder...", Callable(_owner, "_on_ctx_move_selected_to_folder"))
		add_context_menu_item("Densetsu: Force Thumbnail Refresh (Selected)", Callable(_owner, "_on_ctx_force_thumbnail_refresh_selected"))

func _enter_tree() -> void:
	_static_pack_helper = _instantiate_plugin(STATIC_PACK_PLUGIN_SCRIPT)
	_array_extract_helper = _instantiate_plugin(ARRAY_EXTRACT_PLUGIN_SCRIPT)
	_texture_resize_helper = _instantiate_plugin(TEXTURE_RESIZE_PLUGIN_SCRIPT)
	_image_transform_helper = _instantiate_plugin(IMAGE_TRANSFORM_HELPER_SCRIPT)
	_pivot_reassign_helper = _instantiate_plugin(PIVOT_REASSIGN_HELPER_SCRIPT)
	_mesh_obj_helper = _instantiate_plugin(MESH_OBJ_HELPER_SCRIPT)
	_occlusion_prune_helper = _instantiate_plugin(OCCLUSION_PRUNE_HELPER_SCRIPT)
	_select_same_mesh_helper = _instantiate_plugin(SELECT_SAME_MESH_HELPER_SCRIPT)
	_select_intersecting_mesh_helper = _instantiate_plugin(SELECT_INTERSECTING_MESH_HELPER_SCRIPT)
	_mesh_subdivide_helper = _instantiate_plugin(MESH_SUBDIVIDE_HELPER_SCRIPT)
	_build_mesh_ref_replace_dialog()
	_build_mesh_ref_replace_report_dialog()
	_build_tool_log_dialog()
	_build_move_dialog()
	_build_tool_menus()

	_ctx_plugin = _DensetsuSuiteContextMenuPlugin.new(self)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _ctx_plugin)

func _exit_tree() -> void:
	_clear_tool_menus()
	if _ctx_plugin:
		remove_context_menu_plugin(_ctx_plugin)
		_ctx_plugin = null
	_dispose_node(_mesh_ref_replace_dialog)
	_mesh_ref_replace_dialog = null
	_dispose_node(_mesh_ref_replace_report_dialog)
	_mesh_ref_replace_report_dialog = null
	_mesh_ref_replace_report_text = null
	_dispose_node(_tool_log_dialog)
	_tool_log_dialog = null
	_tool_log_text = null
	_dispose_node(_move_dialog)
	_move_dialog = null
	_move_destination_edit = null
	_dispose_node(_move_folder_dialog)
	_move_folder_dialog = null
	_move_pending_paths = PackedStringArray()
	_filesystem_refresh_pending = false

func _dispose_node(node: Variant) -> void:
	if not is_instance_valid(node):
		return
	if node.is_inside_tree():
		node.queue_free()
	else:
		node.free()

func _instantiate_plugin(path: String) -> Object:
	var script_res: Script = load(path)
	if script_res == null:
		push_warning("Densetsu Suite: failed to load helper plugin script: " + path)
		return null
	if script_res.has_method("can_instantiate") and not script_res.can_instantiate():
		push_warning("Densetsu Suite: helper script is not instantiable: " + path)
		return null
	var instance: Object = script_res.new()
	if instance == null:
		push_warning("Densetsu Suite: failed to instantiate helper plugin script: " + path)
	return instance

func _build_tool_menus() -> void:
	_clear_tool_menus()
	_tool_action_map.clear()

	_tool_root_menu = PopupMenu.new()
	_tool_root_menu.name = &"DensetsuToolsRootMenu"

	var scene_menu: PopupMenu = _create_tool_submenu("Scene")
	var geometry_menu: PopupMenu = _create_tool_submenu("Geometry")
	var textures_menu: PopupMenu = _create_tool_submenu("Textures")
	var maintenance_menu: PopupMenu = _create_tool_submenu("Maintenance")
	var assets_menu: PopupMenu = _create_tool_submenu("Assets")

	_register_tool_menu_item(scene_menu, ToolMenuId.SPREAD_SELECTED_ON_FLOOR, "Spread Selected On Floor", _on_tool_spread_selected_on_floor)
	scene_menu.add_separator()
	_register_tool_menu_item(scene_menu, ToolMenuId.SELECT_SAME_MESH, "Select Nodes With Same Mesh As Selected", _on_tool_select_same_mesh_nodes)
	_register_tool_menu_item(scene_menu, ToolMenuId.SELECT_INTERSECTING_MESH, "Select Nodes Intersecting Selected Mesh", _on_tool_select_intersecting_mesh_nodes)
	_register_tool_menu_item(scene_menu, ToolMenuId.PRUNE_OCCLUDED, "Prune Occluded MeshInstances (Current Scene/Selection)", _on_tool_prune_occluded_mesh_instances)

	_register_tool_menu_item(geometry_menu, ToolMenuId.PACK_STATIC_MESH, "Pack to Static Mesh (Selected)", _on_tool_static_pack)
	geometry_menu.add_separator()
	_register_tool_menu_item(geometry_menu, ToolMenuId.EXTRACT_ARRAY_PER_FILE, "Extract ArrayMeshes (Per File)", _on_tool_extract_mesh_per_file)
	_register_tool_menu_item(geometry_menu, ToolMenuId.EXTRACT_ARRAY_COMMON, "Extract ArrayMeshes (Common)", _on_tool_extract_mesh_common)
	_register_tool_menu_item(geometry_menu, ToolMenuId.EXTRACT_MATERIAL_PER_FILE, "Extract Material Meshes (Per File)", _on_tool_extract_material_per_file)
	_register_tool_menu_item(geometry_menu, ToolMenuId.EXTRACT_MATERIAL_COMMON, "Extract Material Meshes (Common)", _on_tool_extract_material_common)
	_register_tool_menu_item(geometry_menu, ToolMenuId.EXTRACT_COMBINED_PER_FILE, "Extract Combined Mesh (Per File)", _on_tool_extract_combined_per_file)
	_register_tool_menu_item(geometry_menu, ToolMenuId.EXTRACT_COMBINED_COMMON, "Extract Combined Mesh (Common)", _on_tool_extract_combined_common)
	geometry_menu.add_separator()
	_register_tool_menu_item(geometry_menu, ToolMenuId.PIVOT_CENTER_MASS, "Reassign Pivot (Center Mass)", _on_tool_pivot_center_mass)
	_register_tool_menu_item(geometry_menu, ToolMenuId.PIVOT_CENTER_BOTTOM, "Reassign Pivot (Center Bottom)", _on_tool_pivot_center_bottom)
	geometry_menu.add_separator()
	_register_tool_menu_item(geometry_menu, ToolMenuId.CONVERT_MESH_RES_TO_OBJ, "Convert Mesh TRES_RES to OBJ (Selected)", _on_tool_convert_mesh_res_to_obj)
	_register_tool_menu_item(geometry_menu, ToolMenuId.SUBDIVIDE_MESH_TO_OBJ, "Subdivide Mesh -> OBJ (1x/2x/4x)", _on_tool_subdivide_mesh_to_obj)
	_register_tool_menu_item(geometry_menu, ToolMenuId.REPLACE_MESH_REFS_WITH_OBJ, "Replace Scene TRES_RES Mesh Refs With Selected OBJ", _on_tool_replace_mesh_refs_with_obj)
	_register_tool_menu_item(geometry_menu, ToolMenuId.REPLACE_MESH_REFS_WITH_OBJ_PROJECT, "Replace TRES_RES Mesh Refs With OBJ (Project-Wide)", _on_tool_replace_mesh_refs_with_obj_project)

	_register_tool_menu_item(textures_menu, ToolMenuId.RESIZE_OVERWRITE, "Resize Textures POT (Overwrite)", _on_tool_resize_overwrite)
	_register_tool_menu_item(textures_menu, ToolMenuId.RESIZE_COPY, "Resize Textures POT (Copy)", _on_tool_resize_copy)
	textures_menu.add_separator()
	_register_tool_menu_item(textures_menu, ToolMenuId.FLIP_IMAGE_H, "Flip Image Horizontal (Copy)", _on_tool_flip_image_h)
	_register_tool_menu_item(textures_menu, ToolMenuId.FLIP_IMAGE_V, "Flip Image Vertical (Copy)", _on_tool_flip_image_v)
	_register_tool_menu_item(textures_menu, ToolMenuId.ROTATE_IMAGE_90, "Rotate Image 90 (Copy)", _on_tool_rotate_image_90)
	_register_tool_menu_item(textures_menu, ToolMenuId.ROTATE_IMAGE_180, "Rotate Image 180 (Copy)", _on_tool_rotate_image_180)
	_register_tool_menu_item(textures_menu, ToolMenuId.ROTATE_IMAGE_270, "Rotate Image 270 (Copy)", _on_tool_rotate_image_270)

	_register_tool_menu_item(maintenance_menu, ToolMenuId.FORCE_THUMBNAIL_REFRESH, "Force Thumbnail Refresh", _on_tool_force_thumbnail_refresh)
	_register_tool_menu_item(maintenance_menu, ToolMenuId.FORCE_THUMBNAIL_REFRESH_SELECTED, "Force Thumbnail Refresh (Selected)", _on_tool_force_thumbnail_refresh_selected)

	_register_tool_menu_item(assets_menu, ToolMenuId.MOVE_SELECTED_TO_FOLDER, "Move Selected To Folder...", _on_tool_move_selected_to_folder)

	add_tool_submenu_item(DENSETSU_TOOL_MENU_ROOT, _tool_root_menu)

func _create_tool_submenu(label: String) -> PopupMenu:
	var submenu := PopupMenu.new()
	submenu.name = StringName("%sMenu" % label)
	submenu.id_pressed.connect(_on_tool_menu_id_pressed)
	_tool_root_menu.add_child(submenu)
	_tool_root_menu.add_submenu_item(label, String(submenu.name))
	return submenu

func _register_tool_menu_item(menu: PopupMenu, id: int, label: String, callback: Callable) -> void:
	menu.add_item(label, id)
	_tool_action_map[id] = callback

func _on_tool_menu_id_pressed(id: int) -> void:
	var callback_variant: Variant = _tool_action_map.get(id, null)
	if callback_variant == null:
		push_warning("Densetsu Suite: Unhandled tool menu id %d" % id)
		return
	var callback: Callable = callback_variant
	if callback.is_valid():
		callback.call()

func _clear_tool_menus() -> void:
	remove_tool_menu_item(DENSETSU_TOOL_MENU_ROOT)
	_tool_action_map.clear()
	_dispose_node(_tool_root_menu)
	_tool_root_menu = null

func _build_mesh_ref_replace_dialog() -> void:
	_dispose_node(_mesh_ref_replace_dialog)

	_mesh_ref_replace_dialog = ConfirmationDialog.new()
	_mesh_ref_replace_dialog.title = "Replace Mesh References With OBJ"
	_mesh_ref_replace_dialog.ok_button_text = "Run"
	_mesh_ref_replace_dialog.confirmed.connect(_on_mesh_ref_replace_dialog_confirmed)
	add_child(_mesh_ref_replace_dialog)

	var root_box: VBoxContainer = VBoxContainer.new()
	root_box.custom_minimum_size = Vector2(640, 0)
	_mesh_ref_replace_dialog.add_child(root_box)

	var intro: Label = Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "Project-wide replacement with conflict controls. Recommended flow: keep Dry Run ON first, check report, then apply."
	root_box.add_child(intro)

	_mesh_ref_replace_scope_current_folder_check = CheckBox.new()
	_mesh_ref_replace_scope_current_folder_check.text = "Use Current Filesystem Folder as Candidate Scope"
	_mesh_ref_replace_scope_current_folder_check.button_pressed = true
	root_box.add_child(_mesh_ref_replace_scope_current_folder_check)

	_mesh_ref_replace_dry_run_check = CheckBox.new()
	_mesh_ref_replace_dry_run_check.text = "Dry Run (Preview Only)"
	_mesh_ref_replace_dry_run_check.button_pressed = true
	root_box.add_child(_mesh_ref_replace_dry_run_check)

	_mesh_ref_replace_same_folder_check = CheckBox.new()
	_mesh_ref_replace_same_folder_check.text = "Same Folder OBJ Only (Safe)"
	_mesh_ref_replace_same_folder_check.button_pressed = true
	_mesh_ref_replace_same_folder_check.toggled.connect(_on_mesh_ref_same_folder_toggled)
	root_box.add_child(_mesh_ref_replace_same_folder_check)

	_mesh_ref_replace_allow_fallback_check = CheckBox.new()
	_mesh_ref_replace_allow_fallback_check.text = "Allow Basename Fallback Across Scope (Use with care)"
	_mesh_ref_replace_allow_fallback_check.button_pressed = false
	_mesh_ref_replace_allow_fallback_check.disabled = true
	root_box.add_child(_mesh_ref_replace_allow_fallback_check)

	var note: Label = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Target scan is project-wide. Candidate scope limits which OBJ/TRES assets are considered. Missing same-folder OBJ is skipped. Ambiguous fallback is skipped and reported."
	root_box.add_child(note)

func _build_mesh_ref_replace_report_dialog() -> void:
	_dispose_node(_mesh_ref_replace_report_dialog)

	_mesh_ref_replace_report_dialog = AcceptDialog.new()
	_mesh_ref_replace_report_dialog.title = "OBJ Replacement Report"
	_mesh_ref_replace_report_dialog.ok_button_text = "Close"
	_mesh_ref_replace_report_dialog.min_size = Vector2i(420, 280)
	add_child(_mesh_ref_replace_report_dialog)

	_mesh_ref_replace_report_text = TextEdit.new()
	_mesh_ref_replace_report_text.custom_minimum_size = Vector2(360, 220)
	_mesh_ref_replace_report_text.editable = false
	_mesh_ref_replace_report_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mesh_ref_replace_report_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mesh_ref_replace_report_dialog.add_child(_mesh_ref_replace_report_text)

func _build_tool_log_dialog() -> void:
	_dispose_node(_tool_log_dialog)

	_tool_log_dialog = AcceptDialog.new()
	_tool_log_dialog.title = "Densetsu Tool Log"
	_tool_log_dialog.ok_button_text = "Close"
	_tool_log_dialog.min_size = Vector2i(540, 340)
	add_child(_tool_log_dialog)

	_tool_log_text = TextEdit.new()
	_tool_log_text.custom_minimum_size = Vector2(500, 300)
	_tool_log_text.editable = false
	_tool_log_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tool_log_dialog.add_child(_tool_log_text)

func _build_move_dialog() -> void:
	_dispose_node(_move_dialog)
	_dispose_node(_move_folder_dialog)

	_move_dialog = ConfirmationDialog.new()
	_move_dialog.title = "Move Selected To Folder"
	_move_dialog.ok_button_text = "Move"
	_move_dialog.confirmed.connect(_on_move_dialog_confirmed)
	_move_dialog.min_size = Vector2i(720, 140)
	add_child(_move_dialog)

	var root_box: VBoxContainer = VBoxContainer.new()
	root_box.custom_minimum_size = Vector2(680, 0)
	_move_dialog.add_child(root_box)

	var intro: Label = Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "Moves the current FileSystem selection without using the dock's built-in move flow. Intended to keep your current browsing context stable."
	root_box.add_child(intro)

	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(row)

	var label: Label = Label.new()
	label.text = "Destination Folder"
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	_move_destination_edit = LineEdit.new()
	_move_destination_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_move_destination_edit)

	var browse: Button = Button.new()
	browse.text = "..."
	browse.pressed.connect(_on_move_browse_pressed)
	row.add_child(browse)

	_move_folder_dialog = FileDialog.new()
	_move_folder_dialog.title = "Choose Destination Folder"
	_move_folder_dialog.access = FileDialog.ACCESS_RESOURCES
	_move_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_move_folder_dialog.dir_selected.connect(_on_move_destination_selected)
	_move_folder_dialog.canceled.connect(_on_move_destination_canceled)
	add_child(_move_folder_dialog)

func _on_move_dialog_confirmed() -> void:
	var destination_dir: String = ""
	if _move_destination_edit != null:
		destination_dir = _move_destination_edit.text.strip_edges()
	_run_move_selected_to_folder(_move_pending_paths, destination_dir)

func _run_move_selected_to_folder(paths: PackedStringArray, destination_dir: String) -> void:
	if paths.is_empty():
		push_warning("Densetsu Suite: Nothing selected to move.")
		return
	if destination_dir.is_empty():
		push_warning("Densetsu Suite: Destination folder is empty.")
		return
	if not destination_dir.begins_with("res://"):
		push_warning("Densetsu Suite: Destination folder must be inside the project (res://...).")
		return
	_set_last_move_destination_folder(destination_dir)

	var destination_abs: String = ProjectSettings.globalize_path(destination_dir)
	DirAccess.make_dir_recursive_absolute(destination_abs)
	var expanded_paths: PackedStringArray = _expand_move_paths_with_obj_companions(paths)
	var obj_targets_to_rewrite: PackedStringArray = PackedStringArray()

	var moved: int = 0
	var skipped: int = 0
	var failed: int = 0
	var fail_lines: PackedStringArray = PackedStringArray()
	for raw_path: String in expanded_paths:
		var source_path: String = raw_path.strip_edges()
		if source_path.is_empty():
			continue
		var source_name: String = source_path.get_file()
		if source_name.is_empty():
			source_name = source_path.trim_suffix("/").get_file()
		var target_path: String = destination_dir.path_join(source_name)
		if source_path == target_path:
			skipped += 1
			continue
		var target_abs: String = ProjectSettings.globalize_path(target_path)
		if FileAccess.file_exists(target_abs) or DirAccess.dir_exists_absolute(target_abs):
			failed += 1
			fail_lines.append("Target exists: %s" % target_path)
			continue
		var err: int = DirAccess.rename_absolute(ProjectSettings.globalize_path(source_path), target_abs)
		if err == OK:
			moved += 1
			if source_path.get_extension().to_lower() == "obj":
				obj_targets_to_rewrite.append(target_path)
		else:
			failed += 1
			fail_lines.append("%s -> %s (err %d)" % [source_path, target_path, err])

	for obj_path: String in obj_targets_to_rewrite:
		if not _rewrite_obj_mtllibs_to_local(obj_path):
			fail_lines.append("Failed to normalize mtllib refs in %s" % obj_path)

	_request_filesystem_refresh()

	var summary: String = "Densetsu Suite: move complete moved=%d skipped=%d failed=%d dest=%s" % [moved, skipped, failed, destination_dir]
	print(summary)
	if failed > 0:
		push_warning(summary + "\n" + "\n".join(fail_lines))

func _expand_move_paths_with_obj_companions(paths: PackedStringArray) -> PackedStringArray:
	var expanded: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for raw_path: String in paths:
		var source_path: String = raw_path.strip_edges()
		if source_path.is_empty():
			continue
		if not seen.has(source_path):
			seen[source_path] = true
			expanded.append(source_path)
		if source_path.get_extension().to_lower() != "obj":
			continue
		for companion_path: String in _get_obj_companion_mtl_paths(source_path):
			if seen.has(companion_path):
				continue
			seen[companion_path] = true
			expanded.append(companion_path)
	return expanded

func _get_obj_companion_mtl_paths(obj_path: String) -> PackedStringArray:
	var companions: PackedStringArray = PackedStringArray()
	for raw_ref: String in _get_obj_mtllib_refs(obj_path):
		var source_path: String = _resolve_obj_mtllib_source_path(obj_path, raw_ref)
		if source_path.is_empty():
			continue
		if not FileAccess.file_exists(ProjectSettings.globalize_path(source_path)):
			continue
		companions.append(source_path)
	return companions

func _get_obj_mtllib_refs(obj_path: String) -> PackedStringArray:
	var refs: PackedStringArray = PackedStringArray()
	var file: FileAccess = FileAccess.open(obj_path, FileAccess.READ)
	if file == null:
		return refs
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.begins_with("mtllib "):
			refs.append(line.substr(7).strip_edges())
	return refs

func _decode_obj_mtllib_ref(raw_ref: String) -> String:
	return raw_ref.strip_edges().replace("\\ ", " ").replace("\\", "/")

func _resolve_obj_mtllib_source_path(obj_path: String, raw_ref: String) -> String:
	var decoded_ref: String = _decode_obj_mtllib_ref(raw_ref)
	if decoded_ref.is_empty():
		return ""
	if decoded_ref.contains(":/") or decoded_ref.begins_with("/"):
		if not FileAccess.file_exists(decoded_ref):
			return ""
		var localized: String = ProjectSettings.localize_path(decoded_ref)
		if localized.begins_with("res://"):
			return localized
		return ""
	return obj_path.get_base_dir().path_join(decoded_ref)

func _rewrite_obj_mtllibs_to_local(obj_path: String) -> bool:
	var source_text: String = FileAccess.get_file_as_string(obj_path)
	if source_text.is_empty() and not FileAccess.file_exists(obj_path):
		return false
	var lines: PackedStringArray = source_text.split("\n", false)
	var changed: bool = false
	for i: int in range(lines.size()):
		var line: String = lines[i]
		if not line.begins_with("mtllib "):
			continue
		var basename: String = _decode_obj_mtllib_ref(line.substr(7)).get_file()
		if basename.is_empty():
			continue
		var normalized_line: String = "mtllib %s" % basename
		if lines[i] != normalized_line:
			lines[i] = normalized_line
			changed = true
	if not changed:
		return true
	var file: FileAccess = FileAccess.open(obj_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("\n".join(lines))
	return true

func _get_last_move_destination_folder() -> String:
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if editor_settings == null:
		return ""
	var value: Variant = editor_settings.get_project_metadata(
		MOVE_HELPER_METADATA_SECTION,
		MOVE_HELPER_METADATA_KEY_LAST_FOLDER,
		""
	)
	var path: String = str(value).strip_edges()
	if path.begins_with("res://"):
		return path
	return ""

func _set_last_move_destination_folder(path: String) -> void:
	var trimmed: String = path.strip_edges()
	if not trimmed.begins_with("res://"):
		return
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if editor_settings == null:
		return
	editor_settings.set_project_metadata(
		MOVE_HELPER_METADATA_SECTION,
		MOVE_HELPER_METADATA_KEY_LAST_FOLDER,
		trimmed
	)

func _popup_window_fit_screen(win: Window, preferred_size: Vector2i, min_size: Vector2i) -> void:
	if win == null:
		return
	win.popup()
	_clamp_window_to_usable_screen(win, preferred_size, min_size)
	call_deferred("_clamp_window_to_usable_screen", win, preferred_size, min_size)

func _clamp_window_to_usable_screen(win: Window, preferred_size: Vector2i, min_size: Vector2i) -> void:
	if not is_instance_valid(win):
		return
	var usable: Rect2i = _get_editor_dialog_bounds_rect()
	var margin: int = 8
	var max_w: int = int(max(320, usable.size.x - (margin * 2)))
	var max_h: int = int(max(220, usable.size.y - (margin * 2)))
	win.max_size = Vector2i(max_w, max_h)

	var desired: Vector2i = win.size
	if desired.x <= 0 or desired.y <= 0:
		desired = preferred_size
	desired.x = int(max(min_size.x, desired.x))
	desired.y = int(max(min_size.y, desired.y))
	desired.x = int(min(desired.x, max_w))
	desired.y = int(min(desired.y, max_h))
	win.size = desired

	var pos: Vector2i = win.position
	var min_x: int = usable.position.x + margin
	var min_y: int = usable.position.y + margin
	var max_x: int = usable.position.x + usable.size.x - desired.x - margin
	var max_y: int = usable.position.y + usable.size.y - desired.y - margin
	if max_x < min_x:
		max_x = min_x
	if max_y < min_y:
		max_y = min_y
	pos.x = clampi(pos.x, min_x, max_x)
	pos.y = clampi(pos.y, min_y, max_y)
	win.position = pos

func _get_editor_dialog_bounds_rect() -> Rect2i:
	var screen: int = DisplayServer.window_get_current_screen()
	var screen_usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	if screen_usable.size.x <= 0 or screen_usable.size.y <= 0:
		var full_size: Vector2i = DisplayServer.screen_get_size(screen)
		screen_usable = Rect2i(Vector2i.ZERO, full_size)

	var iface: EditorInterface = get_editor_interface()
	if iface != null:
		var base: Control = iface.get_base_control()
		if base != null:
			var editor_window: Window = base.get_window()
			if editor_window != null:
				var editor_rect: Rect2i = Rect2i(editor_window.position, editor_window.size)
				if editor_rect.size.x > 0 and editor_rect.size.y > 0:
					var clipped: Rect2i = editor_rect.intersection(screen_usable)
					if clipped.size.x > 0 and clipped.size.y > 0:
						return clipped
					return screen_usable
	return screen_usable

func _get_filesystem_selection() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var iface: EditorInterface = get_editor_interface()
	if iface and iface.has_method("get_selected_paths"):
		var sel_any: Variant = iface.call("get_selected_paths")
		if sel_any is PackedStringArray:
			out = sel_any
		elif sel_any is Array:
			for p in sel_any:
				out.append(str(p))
	if out.size() > 0:
		return out

	var dock: Object = iface.get_file_system_dock() if iface else null
	if dock == null:
		return out

	if dock.has_method("get_selected_paths"):
		var sel_paths: Variant = dock.get_selected_paths()
		if sel_paths is PackedStringArray:
			return sel_paths
		if sel_paths is Array:
			for p in sel_paths:
				out.append(str(p))
			return out

	if dock.has_method("get_selected_files"):
		var sel_files: Variant = dock.get_selected_files()
		if sel_files is PackedStringArray:
			return sel_files
		if sel_files is Array:
			for p in sel_files:
				out.append(str(p))
			return out

	if dock.has_method("get_selected_file"):
		var sel_file: Variant = dock.get_selected_file()
		if sel_file is String and str(sel_file) != "":
			out.append(str(sel_file))
	return out

func _get_current_edited_scene_path() -> String:
	var iface: EditorInterface = get_editor_interface()
	if iface == null:
		return ""
	var root: Node = iface.get_edited_scene_root()
	if root != null:
		var path: String = str(root.scene_file_path)
		if not path.is_empty():
			return path
	if iface.has_method("get_open_scenes"):
		var scenes_any: Variant = iface.call("get_open_scenes")
		if scenes_any is PackedStringArray:
			var scenes: PackedStringArray = scenes_any as PackedStringArray
			if scenes.size() > 0:
				return scenes[0]
		elif scenes_any is Array:
			for s in scenes_any:
				var sp: String = str(s)
				if not sp.is_empty():
					return sp
	return ""

func _run_static_pack(paths: PackedStringArray) -> void:
	if _static_pack_helper == null:
		push_warning("Densetsu Suite: Static Pack helper unavailable.")
		return
	if _static_pack_helper.has_method("_pack_paths"):
		_static_pack_helper.call("_pack_paths", paths)
		_request_filesystem_refresh()
	else:
		push_warning("Densetsu Suite: Static Pack helper missing _pack_paths.")

func _request_filesystem_refresh() -> void:
	if _filesystem_refresh_pending:
		return
	_filesystem_refresh_pending = true
	call_deferred("_flush_filesystem_refresh")

func _flush_filesystem_refresh() -> void:
	_filesystem_refresh_pending = false
	var iface: EditorInterface = get_editor_interface()
	if iface == null:
		return
	var fs: EditorFileSystem = iface.get_resource_filesystem()
	if fs == null:
		return
	if fs.has_method("is_scanning") and fs.is_scanning():
		return
	if fs.has_method("scan"):
		fs.scan.call_deferred()

func _run_array_extract(paths: PackedStringArray, mode: int, output_mode: int) -> void:
	if _array_extract_helper == null:
		push_warning("Densetsu Suite: ArrayMesh Extract helper unavailable.")
		return
	if _array_extract_helper.has_method("_extract_paths"):
		_array_extract_helper.call("_extract_paths", paths, mode, output_mode)
	else:
		push_warning("Densetsu Suite: ArrayMesh Extract helper missing _extract_paths.")

func _run_texture_resize(paths: PackedStringArray, mode: int) -> void:
	if _texture_resize_helper == null:
		push_warning("Densetsu Suite: Texture Resize helper unavailable.")
		return
	if _texture_resize_helper.has_method("_resize_paths"):
		_texture_resize_helper.call("_resize_paths", paths, mode)
	else:
		push_warning("Densetsu Suite: Texture Resize helper missing _resize_paths.")

func _run_image_transform(paths: PackedStringArray, mode: int) -> void:
	if _image_transform_helper == null:
		_image_transform_helper = _instantiate_plugin(IMAGE_TRANSFORM_HELPER_SCRIPT)
	if _image_transform_helper == null:
		push_warning("Densetsu Suite: Image Transform helper unavailable.")
		return
	if not _image_transform_helper.has_method("transform_image_paths"):
		push_warning("Densetsu Suite: Image Transform helper missing transform_image_paths.")
		return
	var result: Dictionary = _image_transform_helper.call("transform_image_paths", paths, mode, get_editor_interface())
	var converted: int = int(result.get("converted", 0))
	var failed: int = int(result.get("failed", 0))
	var skipped: int = int(result.get("skipped", 0))
	print("Densetsu Suite: Image transform converted=%d failed=%d skipped=%d" % [converted, failed, skipped])

func _run_pivot_reassign(paths: PackedStringArray, mode: int) -> void:
	if _pivot_reassign_helper == null:
		push_warning("Densetsu Suite: Pivot Reassign helper unavailable.")
		return
	if _pivot_reassign_helper.has_method("reassign_pivot_paths"):
		_pivot_reassign_helper.call("reassign_pivot_paths", paths, mode, get_editor_interface())
	else:
		push_warning("Densetsu Suite: Pivot Reassign helper missing reassign_pivot_paths.")

func _run_convert_mesh_res_to_obj(paths: PackedStringArray) -> void:
	if not _ensure_mesh_obj_helper():
		push_warning("Densetsu Suite: Mesh OBJ helper unavailable.")
		return
	if not _mesh_obj_helper.has_method("convert_mesh_resource_paths_to_obj"):
		push_warning("Densetsu Suite: Mesh OBJ helper missing convert_mesh_resource_paths_to_obj.")
		return
	var result: Dictionary = _mesh_obj_helper.call("convert_mesh_resource_paths_to_obj", paths, get_editor_interface())
	var converted: int = int(result.get("converted", 0))
	var failed: int = int(result.get("failed", 0))
	var skipped: int = int(result.get("skipped", 0))
	print("Densetsu Suite: Mesh TRES/RES -> OBJ converted=%d failed=%d skipped=%d" % [converted, failed, skipped])

func _run_subdivide_mesh_to_obj(paths: PackedStringArray) -> void:
	if _mesh_subdivide_helper == null:
		_mesh_subdivide_helper = _instantiate_plugin(MESH_SUBDIVIDE_HELPER_SCRIPT)
	if _mesh_subdivide_helper == null:
		push_warning("Densetsu Suite: Mesh Subdivide helper unavailable.")
		return
	if not _mesh_subdivide_helper.has_method("subdivide_mesh_paths_to_obj"):
		push_warning("Densetsu Suite: Mesh Subdivide helper missing subdivide_mesh_paths_to_obj.")
		return
	var result: Dictionary = _mesh_subdivide_helper.call("subdivide_mesh_paths_to_obj", paths, get_editor_interface())
	var converted: int = int(result.get("converted", 0))
	var failed: int = int(result.get("failed", 0))
	var skipped: int = int(result.get("skipped", 0))
	print("Densetsu Suite: Mesh Subdivide -> OBJ converted=%d failed=%d skipped=%d" % [converted, failed, skipped])

func _run_prune_occluded_mesh_instances() -> void:
	if _occlusion_prune_helper == null:
		_occlusion_prune_helper = _instantiate_plugin(OCCLUSION_PRUNE_HELPER_SCRIPT)
	if _occlusion_prune_helper == null:
		push_warning("Densetsu Suite: Occlusion prune helper unavailable.")
		return
	if not _occlusion_prune_helper.has_method("prune_occluded_mesh_instances"):
		push_warning("Densetsu Suite: Occlusion prune helper missing prune_occluded_mesh_instances.")
		return
	var result: Dictionary = _occlusion_prune_helper.call(
		"prune_occluded_mesh_instances",
		get_editor_interface(),
		prune_occluded_threshold_percent,
		prune_occluded_dry_run,
		prune_occluded_use_selection_scope
	)
	if not bool(result.get("ok", false)):
		push_warning("Densetsu Suite: " + str(result.get("error", "Occlusion prune failed.")))
		return
	var scope_path: String = str(result.get("scope_path", ""))
	var scanned: int = int(result.get("scanned", 0))
	var removed: int = int(result.get("removed", 0))
	var retained: int = int(result.get("retained", 0))
	print("Densetsu Suite: Occlusion prune scope=%s scanned=%d removed=%d retained=%d" % [scope_path, scanned, removed, retained])

func _run_select_same_mesh_nodes() -> void:
	if _select_same_mesh_helper == null:
		_select_same_mesh_helper = _instantiate_plugin(SELECT_SAME_MESH_HELPER_SCRIPT)
	if _select_same_mesh_helper == null:
		push_warning("Densetsu Suite: Select Same Mesh helper unavailable.")
		return
	if not _select_same_mesh_helper.has_method("select_same_mesh_nodes"):
		push_warning("Densetsu Suite: Select Same Mesh helper missing select_same_mesh_nodes.")
		return
	var result: Dictionary = _select_same_mesh_helper.call("select_same_mesh_nodes", get_editor_interface())
	if not bool(result.get("ok", false)):
		push_warning("Densetsu Suite: " + str(result.get("error", "Select same mesh failed.")))
		return
	var selected: int = int(result.get("selected", 0))
	var skipped: int = int(result.get("skipped", 0))
	print("Densetsu Suite: Select same mesh selected=%d skipped=%d" % [selected, skipped])

func _run_select_intersecting_mesh_nodes() -> void:
	if _select_intersecting_mesh_helper == null:
		_select_intersecting_mesh_helper = _instantiate_plugin(SELECT_INTERSECTING_MESH_HELPER_SCRIPT)
	if _select_intersecting_mesh_helper == null:
		push_warning("Densetsu Suite: Select Intersecting Mesh helper unavailable.")
		return
	if not _select_intersecting_mesh_helper.has_method("select_intersecting_mesh_nodes"):
		push_warning("Densetsu Suite: Select Intersecting Mesh helper missing select_intersecting_mesh_nodes.")
		return
	var result: Dictionary = _select_intersecting_mesh_helper.call("select_intersecting_mesh_nodes", get_editor_interface())
	if not bool(result.get("ok", false)):
		push_warning("Densetsu Suite: " + str(result.get("error", "Select intersecting mesh failed.")))
		return
	var selected: int = int(result.get("selected", 0))
	var skipped: int = int(result.get("skipped", 0))
	print("Densetsu Suite: Select intersecting mesh selected=%d skipped=%d" % [selected, skipped])

func _run_editor_script(script_path: String, action_name: String) -> bool:
	var script_res: Script = load(script_path)
	if script_res == null:
		push_warning("Densetsu Suite: Missing script for " + action_name + ": " + script_path)
		return false
	if script_res.has_method("can_instantiate") and not script_res.can_instantiate():
		push_warning("Densetsu Suite: Script is not instantiable for " + action_name + ": " + script_path)
		return false
	var instance: Object = script_res.new()
	if instance == null:
		push_warning("Densetsu Suite: Failed to create script instance for " + action_name + ".")
		return false
	if not instance.has_method("_run"):
		push_warning("Densetsu Suite: Script has no _run() for " + action_name + ".")
		return false
	print("Densetsu Suite: Running " + action_name + "...")
	instance.call("_run")
	print("Densetsu Suite: Completed " + action_name + ".")
	return true

func _run_replace_mesh_refs_with_obj(paths: PackedStringArray) -> void:
	if not _ensure_mesh_obj_helper():
		push_warning("Densetsu Suite: Mesh OBJ helper unavailable.")
		return
	if not _mesh_obj_helper.has_method("replace_scene_mesh_references_with_obj"):
		push_warning("Densetsu Suite: Mesh OBJ helper missing replace_scene_mesh_references_with_obj.")
		return
	var result: Dictionary = _mesh_obj_helper.call("replace_scene_mesh_references_with_obj", paths, get_editor_interface())
	var updated_scenes: int = int(result.get("updated_scenes", 0))
	var replacements: int = int(result.get("replacements", 0))
	var failed: int = int(result.get("failed", 0))
	if not bool(result.get("ok", false)):
		var err_text: String = str(result.get("error", "No matching scene references updated."))
		push_warning("Densetsu Suite: " + err_text)
	print("Densetsu Suite: Scene mesh refs replaced scenes=%d refs=%d failed=%d" % [updated_scenes, replacements, failed])

func _run_replace_mesh_refs_with_obj_project(
	dry_run: bool = true,
	same_folder_only: bool = true,
	allow_basename_fallback: bool = false,
	scope_root: String = "res://",
	obj_scope_root: String = "res://"
) -> void:
	if not _ensure_mesh_obj_helper():
		push_warning("Densetsu Suite: Mesh OBJ helper unavailable.")
		return
	if not _mesh_obj_helper.has_method("replace_project_mesh_references_with_obj_with_options"):
		if not _mesh_obj_helper.has_method("replace_project_mesh_references_with_obj_auto"):
			push_warning("Densetsu Suite: Mesh OBJ helper missing project replacement methods.")
			return
		var legacy_result: Dictionary = _mesh_obj_helper.call("replace_project_mesh_references_with_obj_auto", get_editor_interface())
		_show_mesh_ref_replace_report(legacy_result)
		return
	var result: Dictionary = _mesh_obj_helper.call(
		"replace_project_mesh_references_with_obj_with_options",
		get_editor_interface(),
		dry_run,
		same_folder_only,
		allow_basename_fallback,
		scope_root,
		obj_scope_root
	)
	var scanned: int = int(result.get("scanned", 0))
	var updated_files: int = int(result.get("updated_files", 0))
	var replacements: int = int(result.get("replacements", 0))
	var failed: int = int(result.get("failed", 0))
	var obj_total: int = int(result.get("obj_total", 0))
	var obj_used: int = int(result.get("obj_used", 0))
	var obj_dupes: int = int(result.get("obj_duplicate_basenames", 0))
	var missing: int = int(result.get("conflicts_missing_obj", 0))
	var ambiguous: int = int(result.get("conflicts_ambiguous_fallback", 0))
	if not bool(result.get("ok", false)):
		var err_text: String = str(result.get("error", "No project references updated."))
		push_warning("Densetsu Suite: " + err_text)
	print(
		"Densetsu Suite: Project OBJ pass scope=%s obj_scope=%s dry_run=%s scanned=%d updated_files=%d refs=%d failed=%d obj_total=%d obj_used=%d dupes=%d missing=%d ambiguous=%d"
		% [
			str(result.get("scope_root", "res://")),
			str(result.get("obj_scope_root", "res://")),
			str(result.get("dry_run", dry_run)),
			scanned,
			updated_files,
			replacements,
			failed,
			obj_total,
			obj_used,
			obj_dupes,
			missing,
			ambiguous
		]
	)
	_show_mesh_ref_replace_report(result)

func _ensure_mesh_obj_helper() -> bool:
	if _mesh_obj_helper != null:
		return true
	_mesh_obj_helper = _instantiate_plugin(MESH_OBJ_HELPER_SCRIPT)
	return _mesh_obj_helper != null

func _run_force_thumbnail_refresh() -> void:
	var removed: int = 0
	removed += _clear_project_editor_cache()
	removed += _clear_user_thumbnail_cache()

	var iface: EditorInterface = get_editor_interface()
	_request_filesystem_refresh()
	print("Densetsu Suite: forced thumbnail refresh, removed cache files=", removed)

func _run_force_thumbnail_refresh_selected(paths: PackedStringArray) -> void:
	var files: PackedStringArray = _expand_selected_resource_paths(paths)
	if files.is_empty():
		push_warning("Densetsu Suite: No files selected for thumbnail refresh.")
		return
	var selected_names: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for p in files:
		if p.ends_with(".import") or p.ends_with(".uid"):
			continue
		var n: String = p.get_file()
		if n.is_empty():
			continue
		if seen.has(n):
			continue
		seen[n] = true
		selected_names.append(n)

	if selected_names.is_empty():
		push_warning("Densetsu Suite: Selected paths did not resolve to refreshable files.")
		return

	var removed: int = _clear_project_editor_cache_for_files(selected_names)
	var iface: EditorInterface = get_editor_interface()
	var fs: EditorFileSystem = null
	if iface != null:
		fs = iface.get_resource_filesystem()
	if fs != null:
		for p in files:
			fs.update_file(p)
	print("Densetsu Suite: selective thumbnail refresh files=%d removed_cache=%d" % [files.size(), removed])

func _resolve_godot_cli_executable(preferred_path: String) -> String:
	var exe_path: String = preferred_path.strip_edges()
	if exe_path.is_empty():
		return exe_path
	# Prefer sibling console build on Windows to avoid nested editor/GDExtension issues.
	var lower_name: String = exe_path.get_file().to_lower()
	if lower_name.ends_with("_console.exe"):
		return exe_path
	if lower_name.ends_with(".exe"):
		var sibling_console: String = exe_path.get_base_dir().path_join("%s_console.exe" % exe_path.get_basename().get_file())
		if FileAccess.file_exists(sibling_console):
			return sibling_console
	return exe_path

func _on_tool_static_pack() -> void:
	_run_static_pack(_get_filesystem_selection())

func _on_tool_move_selected_to_folder() -> void:
	_open_move_dialog(_get_filesystem_selection())

func _on_tool_extract_mesh_per_file() -> void:
	_run_array_extract(_get_filesystem_selection(), 0, 0)

func _on_tool_extract_mesh_common() -> void:
	_run_array_extract(_get_filesystem_selection(), 0, 1)

func _on_tool_extract_material_per_file() -> void:
	_run_array_extract(_get_filesystem_selection(), 1, 0)

func _on_tool_extract_material_common() -> void:
	_run_array_extract(_get_filesystem_selection(), 1, 1)

func _on_tool_extract_combined_per_file() -> void:
	_run_array_extract(_get_filesystem_selection(), 2, 0)

func _on_tool_extract_combined_common() -> void:
	_run_array_extract(_get_filesystem_selection(), 2, 1)

func _on_tool_resize_overwrite() -> void:
	_run_texture_resize(_get_filesystem_selection(), 0)

func _on_tool_resize_copy() -> void:
	_run_texture_resize(_get_filesystem_selection(), 1)

func _on_tool_flip_image_h() -> void:
	_run_image_transform(_get_filesystem_selection(), IMAGE_TRANSFORM_FLIP_H)

func _on_tool_flip_image_v() -> void:
	_run_image_transform(_get_filesystem_selection(), IMAGE_TRANSFORM_FLIP_V)

func _on_tool_rotate_image_90() -> void:
	_run_image_transform(_get_filesystem_selection(), IMAGE_TRANSFORM_ROT_90)

func _on_tool_rotate_image_180() -> void:
	_run_image_transform(_get_filesystem_selection(), IMAGE_TRANSFORM_ROT_180)

func _on_tool_rotate_image_270() -> void:
	_run_image_transform(_get_filesystem_selection(), IMAGE_TRANSFORM_ROT_270)

func _on_tool_pivot_center_mass() -> void:
	_run_pivot_reassign(_get_filesystem_selection(), PIVOT_MODE_CENTER_MASS)

func _on_tool_pivot_center_bottom() -> void:
	_run_pivot_reassign(_get_filesystem_selection(), PIVOT_MODE_CENTER_BOTTOM)

func _on_tool_convert_mesh_res_to_obj() -> void:
	_run_convert_mesh_res_to_obj(_get_filesystem_selection())

func _on_tool_subdivide_mesh_to_obj() -> void:
	_run_subdivide_mesh_to_obj(_get_filesystem_selection())

func _on_tool_replace_mesh_refs_with_obj() -> void:
	_run_replace_mesh_refs_with_obj(_get_filesystem_selection())

func _on_tool_replace_mesh_refs_with_obj_project() -> void:
	_open_mesh_ref_replace_dialog()

func _on_tool_force_thumbnail_refresh() -> void:
	_run_force_thumbnail_refresh()

func _on_tool_force_thumbnail_refresh_selected() -> void:
	_run_force_thumbnail_refresh_selected(_get_filesystem_selection())

func _on_tool_spread_selected_on_floor() -> void:
	var selected_nodes: Array[Node3D] = _get_selected_scene_nodes_3d()
	if selected_nodes.is_empty():
		push_warning("Densetsu Suite: Select one or more Node3D scene nodes first.")
		return
	var placements: Array[Dictionary] = _compute_floor_spread_placements(selected_nodes)
	if placements.is_empty():
		push_warning("Densetsu Suite: Could not compute floor spread placements for the selection.")
		return
	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Densetsu: Spread Selected On Floor")
	for item in placements:
		var node: Node3D = item.get("node", null)
		if node == null:
			continue
		undo_redo.add_do_property(node, "global_position", item.get("new_position", node.global_position))
		undo_redo.add_undo_property(node, "global_position", item.get("old_position", node.global_position))
	undo_redo.commit_action()

func _on_tool_prune_occluded_mesh_instances() -> void:
	_run_prune_occluded_mesh_instances()

func _on_tool_select_same_mesh_nodes() -> void:
	_run_select_same_mesh_nodes()

func _on_tool_select_intersecting_mesh_nodes() -> void:
	_run_select_intersecting_mesh_nodes()

func _get_selected_scene_nodes_3d() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var iface: EditorInterface = get_editor_interface()
	if iface == null:
		return out
	var selection: EditorSelection = iface.get_selection()
	if selection == null:
		return out
	var raw_nodes: Array = selection.get_selected_nodes()
	var selected_set: Dictionary = {}
	for raw_node in raw_nodes:
		if raw_node is Node3D:
			var node3d: Node3D = raw_node
			selected_set[node3d] = true
	for raw_node in raw_nodes:
		if not (raw_node is Node3D):
			continue
		var node: Node3D = raw_node
		var has_selected_ancestor: bool = false
		var current: Node = node.get_parent()
		while current != null:
			if selected_set.has(current):
				has_selected_ancestor = true
				break
			current = current.get_parent()
		if not has_selected_ancestor:
			out.append(node)
	return out

func _compute_floor_spread_placements(selected_nodes: Array[Node3D]) -> Array[Dictionary]:
	var scene_root: Node = get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return []
	var anchor_center: Vector3 = Vector3.ZERO
	var items: Array[Dictionary] = []
	var total_area: float = 0.0
	for node in selected_nodes:
		var world_aabb: AABB = _get_node_world_aabb(node)
		if world_aabb.size.length() <= 0.0001:
			world_aabb = AABB(node.global_position - Vector3.ONE * 0.25, Vector3.ONE * 0.5)
		var width: float = maxf(world_aabb.size.x, FLOOR_SPREAD_MIN_SIZE)
		var depth: float = maxf(world_aabb.size.z, FLOOR_SPREAD_MIN_SIZE)
		var bottom_offset: float = node.global_position.y - world_aabb.position.y
		anchor_center += node.global_position
		total_area += (width + FLOOR_SPREAD_GAP) * (depth + FLOOR_SPREAD_GAP)
		items.append({
			"node": node,
			"aabb": world_aabb,
			"width": width,
			"depth": depth,
			"bottom_offset": bottom_offset,
			"old_position": node.global_position,
		})
	if items.is_empty():
		return []
	anchor_center /= float(items.size())
	var row_width_limit: float = maxf(sqrt(total_area), FLOOR_SPREAD_MIN_SIZE * 4.0)
	var x_cursor: float = 0.0
	var z_cursor: float = 0.0
	var row_depth: float = 0.0
	var local_centers: Array[Vector2] = []
	for item in items:
		var width: float = float(item.get("width", FLOOR_SPREAD_MIN_SIZE))
		var depth: float = float(item.get("depth", FLOOR_SPREAD_MIN_SIZE))
		if x_cursor > 0.0 and x_cursor + width > row_width_limit:
			x_cursor = 0.0
			z_cursor += row_depth + FLOOR_SPREAD_GAP
			row_depth = 0.0
		local_centers.append(Vector2(x_cursor + width * 0.5, z_cursor + depth * 0.5))
		x_cursor += width + FLOOR_SPREAD_GAP
		row_depth = maxf(row_depth, depth)
	var layout_bounds: Rect2 = Rect2(local_centers[0], Vector2.ZERO)
	for i in range(local_centers.size()):
		var center: Vector2 = local_centers[i]
		var width: float = float(items[i].get("width", FLOOR_SPREAD_MIN_SIZE))
		var depth: float = float(items[i].get("depth", FLOOR_SPREAD_MIN_SIZE))
		var rect: Rect2 = Rect2(center - Vector2(width * 0.5, depth * 0.5), Vector2(width, depth))
		layout_bounds = layout_bounds.merge(rect)
	var selection_set: Dictionary = {}
	for node in selected_nodes:
		selection_set[node] = true
	var floor_aabbs: Array[AABB] = _collect_floor_surface_aabbs(scene_root, selection_set)
	var excluded_rids: Array[RID] = _collect_collision_exclude_rids(selected_nodes)
	var placements: Array[Dictionary] = []
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var center: Vector2 = local_centers[i]
		var target_x: float = anchor_center.x + center.x - layout_bounds.get_center().x
		var target_z: float = anchor_center.z + center.y - layout_bounds.get_center().y
		var node: Node3D = item.get("node", null)
		if node == null:
			continue
		var old_position: Vector3 = item.get("old_position", node.global_position)
		var floor_y: float = _find_floor_height(scene_root, floor_aabbs, excluded_rids, target_x, target_z, old_position.y)
		var new_position: Vector3 = Vector3(target_x, floor_y + float(item.get("bottom_offset", 0.0)), target_z)
		placements.append({
			"node": node,
			"old_position": old_position,
			"new_position": new_position,
		})
	return placements

func _collect_collision_exclude_rids(selected_nodes: Array[Node3D]) -> Array[RID]:
	var out: Array[RID] = []
	for node in selected_nodes:
		if node is CollisionObject3D:
			out.append((node as CollisionObject3D).get_rid())
		for child in node.find_children("*", "CollisionObject3D", true, false):
			if child is CollisionObject3D:
				out.append((child as CollisionObject3D).get_rid())
	return out

func _collect_floor_surface_aabbs(scene_root: Node, selection_set: Dictionary) -> Array[AABB]:
	var out: Array[AABB] = []
	for child in scene_root.find_children("*", "", true, false):
		if not (child is Node3D):
			continue
		var node: Node3D = child
		if selection_set.has(node):
			continue
		if _is_under_selected_parent(node, selection_set):
			continue
		var aabb: AABB = _get_node_world_aabb(node)
		if aabb.size.length() <= 0.0001:
			continue
		out.append(aabb)
	return out

func _is_under_selected_parent(node: Node, selection_set: Dictionary) -> bool:
	var current: Node = node.get_parent()
	while current != null:
		if selection_set.has(current):
			return true
		current = current.get_parent()
	return false

func _find_floor_height(scene_root: Node, floor_aabbs: Array[AABB], excluded_rids: Array[RID], x: float, z: float, fallback_y: float) -> float:
	for child in scene_root.find_children("*", "", true, false):
		if child is Node3D:
			var node3d: Node3D = child
			var world_3d: World3D = node3d.get_world_3d()
			if world_3d == null:
				break
			var direct_space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
			if direct_space != null:
				var ray_from: Vector3 = Vector3(x, fallback_y + FLOOR_SPREAD_RAY_HEIGHT, z)
				var ray_to: Vector3 = Vector3(x, fallback_y - FLOOR_SPREAD_RAY_DEPTH, z)
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
				query.collide_with_areas = true
				query.collide_with_bodies = true
				query.exclude = excluded_rids
				var hit: Dictionary = direct_space.intersect_ray(query)
				if not hit.is_empty():
					var hit_pos: Variant = hit.get("position", null)
					if hit_pos is Vector3:
						return (hit_pos as Vector3).y
			break
	var best_height: float = fallback_y
	var found: bool = false
	for world_aabb in floor_aabbs:
		if x < world_aabb.position.x or x > world_aabb.position.x + world_aabb.size.x:
			continue
		if z < world_aabb.position.z or z > world_aabb.position.z + world_aabb.size.z:
			continue
		var top_y: float = world_aabb.position.y + world_aabb.size.y
		if not found or top_y > best_height:
			best_height = top_y
			found = true
	return best_height if found else fallback_y

func _get_node_world_aabb(node: Node3D) -> AABB:
	var has_bounds: bool = false
	var merged: AABB = AABB()
	if node.has_method("get_aabb"):
		var node_aabb_any: Variant = node.call("get_aabb")
		if node_aabb_any is AABB:
			merged = _transform_aabb(node.global_transform, node_aabb_any)
			has_bounds = true
	for child in node.find_children("*", "", true, false):
		if not (child is Node3D):
			continue
		var child_node: Node3D = child
		if not child_node.has_method("get_aabb"):
			continue
		var child_aabb_any: Variant = child_node.call("get_aabb")
		if not (child_aabb_any is AABB):
			continue
		var child_world_aabb: AABB = _transform_aabb(child_node.global_transform, child_aabb_any)
		if not has_bounds:
			merged = child_world_aabb
			has_bounds = true
		else:
			merged = merged.merge(child_world_aabb)
	return merged if has_bounds else AABB(node.global_position, Vector3.ZERO)

func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size,
	]
	var world_min: Vector3 = xform * corners[0]
	var world_max: Vector3 = world_min
	for i in range(1, corners.size()):
		var point: Vector3 = xform * corners[i]
		world_min = world_min.min(point)
		world_max = world_max.max(point)
	return AABB(world_min, world_max - world_min)

func _on_ctx_static_pack(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_static_pack(paths)

func _on_ctx_extract_mesh_per_file(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_array_extract(paths, 0, 0)

func _on_ctx_extract_mesh_common(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_array_extract(paths, 0, 1)

func _on_ctx_extract_material_per_file(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_array_extract(paths, 1, 0)

func _on_ctx_extract_material_common(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_array_extract(paths, 1, 1)

func _on_ctx_extract_combined_per_file(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_array_extract(paths, 2, 0)

func _on_ctx_extract_combined_common(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_array_extract(paths, 2, 1)

func _on_ctx_resize_overwrite(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_texture_resize(paths, 0)

func _on_ctx_resize_copy(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_texture_resize(paths, 1)

func _on_ctx_flip_image_h(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_image_transform(paths, IMAGE_TRANSFORM_FLIP_H)

func _on_ctx_flip_image_v(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_image_transform(paths, IMAGE_TRANSFORM_FLIP_V)

func _on_ctx_rotate_image_90(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_image_transform(paths, IMAGE_TRANSFORM_ROT_90)

func _on_ctx_rotate_image_180(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_image_transform(paths, IMAGE_TRANSFORM_ROT_180)

func _on_ctx_rotate_image_270(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_image_transform(paths, IMAGE_TRANSFORM_ROT_270)

func _on_ctx_pivot_center_mass(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_pivot_reassign(paths, PIVOT_MODE_CENTER_MASS)

func _on_ctx_pivot_center_bottom(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_pivot_reassign(paths, PIVOT_MODE_CENTER_BOTTOM)

func _on_ctx_convert_mesh_res_to_obj(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_convert_mesh_res_to_obj(paths)

func _on_ctx_subdivide_mesh_to_obj(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_subdivide_mesh_to_obj(paths)

func _on_ctx_replace_mesh_refs_with_obj(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_replace_mesh_refs_with_obj(paths)

func _on_ctx_move_selected_to_folder(paths: PackedStringArray = PackedStringArray()) -> void:
	_open_move_dialog(paths)

func _on_ctx_force_thumbnail_refresh_selected(paths: PackedStringArray = PackedStringArray()) -> void:
	_run_force_thumbnail_refresh_selected(paths)

func _clear_project_editor_cache() -> int:
	var removed: int = 0
	var editor_dir_abs: String = ProjectSettings.globalize_path("res://.godot/editor")
	if not DirAccess.dir_exists_absolute(editor_dir_abs):
		return removed
	var file_names: PackedStringArray = PackedStringArray()
	_collect_files_recursive_absolute(editor_dir_abs, file_names)
	for file_path in file_names:
		var file_name: String = file_path.get_file()
		if file_name.begins_with("filesystem_cache"):
			if DirAccess.remove_absolute(file_path) == OK:
				removed += 1
			continue
		if file_name.find(".mesh-folding-") != -1:
			if DirAccess.remove_absolute(file_path) == OK:
				removed += 1
	return removed

func _clear_project_editor_cache_for_files(file_names: PackedStringArray) -> int:
	var removed: int = 0
	var editor_dir_abs: String = ProjectSettings.globalize_path("res://.godot/editor")
	if not DirAccess.dir_exists_absolute(editor_dir_abs):
		return removed
	if file_names.is_empty():
		return removed

	var file_names_set: Dictionary = {}
	for n in file_names:
		file_names_set[n] = true

	var cache_files: PackedStringArray = PackedStringArray()
	_collect_files_recursive_absolute(editor_dir_abs, cache_files)
	for cache_file in cache_files:
		var cache_name: String = cache_file.get_file()
		for n in file_names_set.keys():
			var needle: String = str(n)
			if cache_name.begins_with(needle + "-"):
				if DirAccess.remove_absolute(cache_file) == OK:
					removed += 1
				break
	return removed

func _clear_user_thumbnail_cache() -> int:
	var removed: int = 0
	var appdata: String = OS.get_environment("APPDATA")
	if appdata.is_empty():
		return removed
	var candidate_dirs: PackedStringArray = PackedStringArray([
		appdata.path_join("Godot/editor/cache"),
		appdata.path_join("Godot/editor/thumbnails")
	])
	for dir_path in candidate_dirs:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var files: PackedStringArray = PackedStringArray()
		_collect_files_recursive_absolute(dir_path, files)
		for file_path in files:
			if DirAccess.remove_absolute(file_path) == OK:
				removed += 1
	return removed

func _collect_files_recursive_absolute(dir_path: String, out: PackedStringArray) -> void:
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
			_collect_files_recursive_absolute(full_path, out)
		else:
			out.append(full_path)
	dir.list_dir_end()

func _expand_selected_resource_paths(paths: PackedStringArray) -> PackedStringArray:
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

