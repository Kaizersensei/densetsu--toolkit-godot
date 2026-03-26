@tool
extends RefCounted

const MODE_FLIP_H: int = 0
const MODE_FLIP_V: int = 1
const MODE_ROT_90: int = 2
const MODE_ROT_180: int = 3
const MODE_ROT_270: int = 4

var SUPPORTED_EXTS: PackedStringArray = PackedStringArray(["png", "jpg", "jpeg", "webp", "bmp", "tga"])


func transform_image_paths(paths: PackedStringArray, mode: int, editor_iface: EditorInterface = null) -> Dictionary:
	var files: PackedStringArray = _expand_paths(paths)
	var images: PackedStringArray = PackedStringArray()
	for path in files:
		if _is_supported(path):
			images.append(path)

	if images.is_empty():
		return {"ok": false, "error": "No supported images found in selection.", "converted": 0, "failed": 0, "skipped": 0}

	var converted: int = 0
	var failed: int = 0
	var skipped: int = 0
	var outputs: PackedStringArray = PackedStringArray()

	for src_path in images:
		var out_path: String = _derive_output_path(src_path, mode)
		var result: int = _transform_single(src_path, out_path, mode)
		if result == 1:
			converted += 1
			outputs.append(out_path)
			_refresh_path(out_path, editor_iface)
		elif result == 0:
			skipped += 1
		else:
			failed += 1

	if editor_iface != null:
		var fs: EditorFileSystem = editor_iface.get_resource_filesystem()
		if fs != null:
			fs.scan()

	return {
		"ok": failed == 0 and converted > 0,
		"converted": converted,
		"failed": failed,
		"skipped": skipped,
		"paths": outputs
	}


func _transform_single(src_path: String, out_path: String, mode: int) -> int:
	var image: Image = Image.new()
	var err_load: int = image.load(src_path)
	if err_load != OK:
		push_warning("Image transform: failed to load " + src_path + " (err " + str(err_load) + ")")
		return -1
	if image.is_empty():
		push_warning("Image transform: empty image " + src_path)
		return -1

	match mode:
		MODE_FLIP_H:
			image.flip_x()
		MODE_FLIP_V:
			image.flip_y()
		MODE_ROT_90:
			if not image.has_method("rotate_90"):
				push_warning("Image transform: rotate_90 not available for " + src_path)
				return -1
			image.rotate_90(ClockDirection.CLOCKWISE)
		MODE_ROT_180:
			if not image.has_method("rotate_90"):
				push_warning("Image transform: rotate_90 not available for " + src_path)
				return -1
			image.rotate_90(ClockDirection.CLOCKWISE)
			image.rotate_90(ClockDirection.CLOCKWISE)
		MODE_ROT_270:
			if not image.has_method("rotate_90"):
				push_warning("Image transform: rotate_90 not available for " + src_path)
				return -1
			image.rotate_90(ClockDirection.CLOCKWISE)
			image.rotate_90(ClockDirection.CLOCKWISE)
			image.rotate_90(ClockDirection.CLOCKWISE)
		_:
			return 0

	var err_save: int = _save_image(image, out_path)
	if err_save != OK:
		push_warning("Image transform: failed to save " + out_path + " (err " + str(err_save) + ")")
		return -1
	return 1


func _save_image(image: Image, path: String) -> int:
	var ext: String = path.get_extension().to_lower()
	if ext == "png":
		return image.save_png(path)
	if ext == "jpg" or ext == "jpeg":
		return image.save_jpg(path)
	if ext == "webp":
		return image.save_webp(path)
	return image.save_png(path.get_basename() + ".png")


func _derive_output_path(src_path: String, mode: int) -> String:
	var base: String = src_path.get_basename()
	var ext: String = src_path.get_extension().to_lower()
	var suffix: String = ""
	match mode:
		MODE_FLIP_H:
			suffix = "_h"
		MODE_FLIP_V:
			suffix = "_V"
		MODE_ROT_90:
			suffix = "_90"
		MODE_ROT_180:
			suffix = "_180"
		MODE_ROT_270:
			suffix = "_270"
		_:
			suffix = "_out"
	if ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp":
		return base + suffix + "." + ext
	return base + suffix + ".png"


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


func _is_supported(path: String) -> bool:
	var ext: String = path.get_extension().to_lower()
	return SUPPORTED_EXTS.has(ext)


func _refresh_path(path: String, editor_iface: EditorInterface) -> void:
	if editor_iface == null:
		return
	var fs: EditorFileSystem = editor_iface.get_resource_filesystem()
	if fs == null:
		return
	fs.update_file(path)
