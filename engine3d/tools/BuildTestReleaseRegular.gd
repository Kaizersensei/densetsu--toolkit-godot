@tool
extends SceneTree

const EXPORT_HELPER = preload("res://engine3d/tools/TestReleaseExportHelper.gd")
const GITEA_PUBLISHER = preload("res://engine3d/tools/GiteaReleasePublisher.gd")
const RUNTIME_MANIFEST = preload("res://engine3d/tools/RuntimeExportManifest.gd")

const DEFAULT_OUT_DIR: String = "D:/Test"
const DEFAULT_POWERSHELL: String = "powershell.exe"
const DEFAULT_PRESET_NAME: String = "Windows Desktop"
const DEFAULT_RELEASE_TAG: String = "test-build-regular"
const DEFAULT_RELEASE_TITLE: String = "Test Build - Regular"


func _init() -> void:
	var cfg: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if bool(cfg.get("help", false)):
		_print_usage()
		quit(0)
		return
	quit(_run(cfg))


func _parse_args(args: PackedStringArray) -> Dictionary:
	var cfg: Dictionary = {
		"help": false,
		"out_dir": DEFAULT_OUT_DIR,
		"godot_exe": "",
		"powershell_exe": DEFAULT_POWERSHELL,
		"zip_output": true,
		"use_runtime_manifest": true,
		"preflight_only": false,
		"runtime_manifest_path": RUNTIME_MANIFEST.DEFAULT_MANIFEST_PATH,
		"publish": false,
		"gitea_base_url": GITEA_PUBLISHER.DEFAULT_BASE_URL,
		"gitea_owner": GITEA_PUBLISHER.DEFAULT_OWNER,
		"gitea_repo": GITEA_PUBLISHER.DEFAULT_REPO,
		"gitea_token": "",
		"gitea_token_file": GITEA_PUBLISHER.DEFAULT_TOKEN_FILE,
		"gitea_token_env": GITEA_PUBLISHER.DEFAULT_TOKEN_ENV,
	}
	for arg: String in args:
		if arg == "--help" or arg == "-h":
			cfg["help"] = true
		elif arg == "--no-zip":
			cfg["zip_output"] = false
		elif arg == "--use-runtime-manifest":
			cfg["use_runtime_manifest"] = true
		elif arg == "--full-export":
			cfg["use_runtime_manifest"] = false
		elif arg == "--preflight-only":
			cfg["preflight_only"] = true
		elif arg == "--publish":
			cfg["publish"] = true
		elif arg.begins_with("--out="):
			cfg["out_dir"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(6))
		elif arg.begins_with("--godot-exe="):
			cfg["godot_exe"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(12))
		elif arg.begins_with("--powershell="):
			cfg["powershell_exe"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(13))
		elif arg.begins_with("--runtime-manifest="):
			cfg["runtime_manifest_path"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(19))
		elif arg.begins_with("--gitea-base-url="):
			cfg["gitea_base_url"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(18))
		elif arg.begins_with("--gitea-owner="):
			cfg["gitea_owner"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(14))
		elif arg.begins_with("--gitea-repo="):
			cfg["gitea_repo"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(13))
		elif arg.begins_with("--gitea-token="):
			cfg["gitea_token"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(14))
		elif arg.begins_with("--gitea-token-file="):
			cfg["gitea_token_file"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(19))
		elif arg.begins_with("--gitea-token-env="):
			cfg["gitea_token_env"] = EXPORT_HELPER.strip_wrapped_quotes(arg.substr(18))
	return cfg


func _print_usage() -> void:
	print("BuildTestReleaseRegular (Godot CLI)")
	print("Builds a runnable Windows test release (exe + pck).")


func _run(cfg: Dictionary) -> int:
	var out_dir: String = str(cfg.get("out_dir", DEFAULT_OUT_DIR)).strip_edges()
	var zip_output: bool = bool(cfg.get("zip_output", true))
	var use_runtime_manifest: bool = bool(cfg.get("use_runtime_manifest", false))
	var preflight_only: bool = bool(cfg.get("preflight_only", false))
	var publish_requested: bool = bool(cfg.get("publish", false))
	var godot_exe: String = str(cfg.get("godot_exe", "")).strip_edges()
	var powershell_exe: String = str(cfg.get("powershell_exe", DEFAULT_POWERSHELL)).strip_edges()
	var runtime_manifest_path: String = str(cfg.get("runtime_manifest_path", RUNTIME_MANIFEST.DEFAULT_MANIFEST_PATH)).strip_edges()
	var project_root_abs: String = ProjectSettings.globalize_path("res://")
	var project_name: String = EXPORT_HELPER.sanitize_filename(EXPORT_HELPER.get_project_name(project_root_abs))
	var out_dir_abs: String = _resolve_output_path(out_dir)
	var exe_abs: String = out_dir_abs.path_join("%s.exe" % project_name)
	var pck_abs: String = out_dir_abs.path_join("%s.pck" % project_name)
	var zip_abs: String = "%s.zip" % out_dir_abs
	var summary_abs: String = out_dir_abs.path_join("regular_summary.txt")
	var preflight_summary_abs: String = out_dir_abs.path_join("regular_preflight_summary.txt")
	var manifest_report_abs: String = out_dir_abs.path_join("regular_runtime_manifest_report.json")

	if not _is_supported_output_path(out_dir):
		push_error("BuildTestReleaseRegular: out must be a res://, user://, or absolute path.")
		return 1
	if godot_exe.is_empty():
		godot_exe = _resolve_godot_cli_executable(OS.get_executable_path())
	if godot_exe.is_empty() or not FileAccess.file_exists(godot_exe):
		push_error("BuildTestReleaseRegular: could not resolve Godot executable path.")
		return 1
	var templates: Dictionary = EXPORT_HELPER.find_windows_export_templates()
	if not bool(templates.get("ok", false)):
		push_error("BuildTestReleaseRegular: %s" % str(templates.get("message", "Missing export templates.")))
		return 1
	var main_scene: String = EXPORT_HELPER.get_project_main_scene(project_root_abs).strip_edges()
	if main_scene.is_empty() or not ResourceLoader.exists(main_scene):
		push_error("BuildTestReleaseRegular: main scene is missing or invalid: %s" % main_scene)
		return 1
	var manifest_scan: Dictionary = RUNTIME_MANIFEST.collect_runtime_paths(PackedStringArray([main_scene]), runtime_manifest_path)
	if not bool(manifest_scan.get("ok", false)):
		push_error("BuildTestReleaseRegular: runtime manifest failed: %s" % str(manifest_scan.get("message", "unknown error")))
		return 1
	var missing_autoloads: PackedStringArray = EXPORT_HELPER.get_missing_autoload_paths(project_root_abs)
	if not missing_autoloads.is_empty():
		push_error("BuildTestReleaseRegular: missing autoload paths: %s" % ", ".join(missing_autoloads))
		return 1
	if not _reset_output_dir(out_dir_abs, powershell_exe):
		return 1
	RUNTIME_MANIFEST.write_scan_report_abs(manifest_report_abs, manifest_scan)
	if preflight_only:
		var preflight_summary: PackedStringArray = PackedStringArray([
			"generated=%s" % Time.get_datetime_string_from_system(),
			"mode=regular",
			"preflight_only=true",
			"main_scene=%s" % main_scene,
			"runtime_manifest=%s" % runtime_manifest_path,
			"runtime_manifest_enabled=%s" % str(use_runtime_manifest),
			"runtime_manifest_report=%s" % manifest_report_abs,
			"runtime_manifest_include_count=%d" % PackedStringArray(manifest_scan.get("include_paths", PackedStringArray())).size(),
			"runtime_manifest_missing_count=%d" % PackedStringArray(manifest_scan.get("missing_paths", PackedStringArray())).size(),
		])
		_write_lines_abs(preflight_summary_abs, preflight_summary)
		print("BuildTestReleaseRegular: preflight ok include_count=%d missing_count=%d" % [
			PackedStringArray(manifest_scan.get("include_paths", PackedStringArray())).size(),
			PackedStringArray(manifest_scan.get("missing_paths", PackedStringArray())).size(),
		])
		return 0

	var export_presets_abs: String = project_root_abs.path_join("export_presets.cfg")
	var export_presets_original: String = FileAccess.get_file_as_string(export_presets_abs)
	if export_presets_original.is_empty():
		push_error("BuildTestReleaseRegular: export_presets.cfg is missing or unreadable.")
		return 1
	var export_presets_patched: String = EXPORT_HELPER.set_embed_pck_text(export_presets_original, false)
	if use_runtime_manifest:
		export_presets_patched = RUNTIME_MANIFEST.apply_manifest_to_export_preset_text(export_presets_patched, PackedStringArray([main_scene]), manifest_scan)
	if not _write_text_file(export_presets_abs, export_presets_patched):
		return 1

	var export_ok: bool = _export_release(godot_exe, project_root_abs, exe_abs)
	var restore_ok: bool = _write_text_file(export_presets_abs, export_presets_original)
	if not restore_ok:
		push_error("BuildTestReleaseRegular: failed to restore export_presets.cfg")
		return 1
	if not export_ok:
		return 1
	if not FileAccess.file_exists(exe_abs):
		push_error("BuildTestReleaseRegular: export did not produce executable: %s" % exe_abs)
		return 1
	if not FileAccess.file_exists(pck_abs):
		push_error("BuildTestReleaseRegular: export did not produce data package: %s" % pck_abs)
		return 1

	var publish_result: Dictionary = {"ok": false, "message": "Publishing not requested."}
	if zip_output:
		if not _zip_directory(out_dir_abs, zip_abs, powershell_exe):
			return 1
		if not FileAccess.file_exists(zip_abs):
			push_error("BuildTestReleaseRegular: expected zip missing after compression: %s" % zip_abs)
			return 1
	if publish_requested:
		publish_result = _publish(zip_abs, cfg, project_name, main_scene)

	var summary: PackedStringArray = PackedStringArray([
		"generated=%s" % Time.get_datetime_string_from_system(),
		"mode=regular",
		"main_scene=%s" % main_scene,
		"runtime_manifest=%s" % runtime_manifest_path,
		"runtime_manifest_enabled=%s" % str(use_runtime_manifest),
		"runtime_manifest_report=%s" % manifest_report_abs,
		"runtime_manifest_include_count=%d" % PackedStringArray(manifest_scan.get("include_paths", PackedStringArray())).size(),
		"runtime_manifest_missing_count=%d" % PackedStringArray(manifest_scan.get("missing_paths", PackedStringArray())).size(),
		"out_dir=%s" % out_dir_abs,
		"exe=%s" % exe_abs,
		"exe_size_bytes=%d" % EXPORT_HELPER.get_file_size(exe_abs),
		"pck=%s" % pck_abs,
		"pck_size_bytes=%d" % EXPORT_HELPER.get_file_size(pck_abs),
		"zip_output=%s" % str(zip_output),
		"published=%s" % str(bool(publish_result.get("ok", false))),
	])
	if zip_output:
		var zip_size: int = EXPORT_HELPER.get_file_size(zip_abs)
		summary.append("zip=%s" % zip_abs)
		summary.append("zip_size_bytes=%d" % zip_size)
		summary.append("zip_size_human=%s" % EXPORT_HELPER.format_bytes(zip_size))
	if publish_requested:
		summary.append("publish_message=%s" % str(publish_result.get("message", "")))
		summary.append("release_url=%s" % str(publish_result.get("release_url", "")))
		summary.append("asset_url=%s" % str(publish_result.get("asset_url", "")))
	_write_lines_abs(summary_abs, summary)
	print("BuildTestReleaseRegular: success exe=%s pck=%s" % [exe_abs, pck_abs])
	return 0


func _export_release(godot_exe: String, project_root_abs: String, exe_abs: String) -> bool:
	return _exec_ok(godot_exe, PackedStringArray(["--headless", "--path", project_root_abs, "--export-release", DEFAULT_PRESET_NAME, exe_abs]), "BuildTestReleaseRegular")


func _publish(zip_abs: String, cfg: Dictionary, project_name: String, main_scene: String) -> Dictionary:
	if not FileAccess.file_exists(zip_abs):
		return {"ok": false, "message": "Zip archive missing; nothing to publish."}
	var token: String = GITEA_PUBLISHER.resolve_token(str(cfg.get("gitea_token", "")), str(cfg.get("gitea_token_file", GITEA_PUBLISHER.DEFAULT_TOKEN_FILE)), str(cfg.get("gitea_token_env", GITEA_PUBLISHER.DEFAULT_TOKEN_ENV)))
	if token.is_empty():
		return {"ok": false, "message": "Gitea token not found."}
	var commit: String = _get_git_head_commit()
	var zip_size: int = EXPORT_HELPER.get_file_size(zip_abs)
	var body_lines: PackedStringArray = PackedStringArray([
		"Generated: %s" % Time.get_datetime_string_from_system(),
		"Project: %s" % project_name,
		"Mode: Regular",
		"Main Scene: %s" % main_scene,
		"Commit: %s" % commit,
		"Archive Size: %s (%d bytes)" % [EXPORT_HELPER.format_bytes(zip_size), zip_size],
		"Output Path: %s" % zip_abs,
	])
	var result: Dictionary = GITEA_PUBLISHER.publish_release_asset({
		"powershell_exe": str(cfg.get("powershell_exe", DEFAULT_POWERSHELL)),
		"base_url": str(cfg.get("gitea_base_url", GITEA_PUBLISHER.DEFAULT_BASE_URL)),
		"owner": str(cfg.get("gitea_owner", GITEA_PUBLISHER.DEFAULT_OWNER)),
		"repo": str(cfg.get("gitea_repo", GITEA_PUBLISHER.DEFAULT_REPO)),
		"token": token,
		"tag": DEFAULT_RELEASE_TAG,
		"title": DEFAULT_RELEASE_TITLE,
		"body": "\n".join(body_lines),
		"asset_path": zip_abs,
		"asset_name": "%s-test-regular.zip" % project_name,
		"target_commitish": "main",
		"prerelease": true,
	})
	if bool(result.get("ok", false)):
		result["message"] = "Published successfully."
	return result


func _get_git_head_commit() -> String:
	var output: Array = []
	var code: int = OS.execute("git", PackedStringArray(["rev-parse", "HEAD"]), output, true)
	if code != 0 or output.is_empty():
		return "unknown"
	return str(output[0]).strip_edges()


func _zip_directory(source_dir_abs: String, zip_abs: String, powershell_exe: String) -> bool:
	if FileAccess.file_exists(zip_abs):
		DirAccess.remove_absolute(zip_abs)
	var tar_result: bool = _exec_ok("tar.exe", PackedStringArray(["-a", "-cf", zip_abs, "-C", source_dir_abs, "."]), "BuildTestReleaseRegular")
	if tar_result and FileAccess.file_exists(zip_abs):
		return true
	if powershell_exe.is_empty():
		return false
	var ps_script: String = "$ProgressPreference='SilentlyContinue'; Compress-Archive -Path '%s\\*' -DestinationPath '%s' -Force" % [source_dir_abs.replace("'", "''"), zip_abs.replace("'", "''")]
	return _exec_ok(powershell_exe, PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_script]), "BuildTestReleaseRegular")


func _reset_output_dir(out_dir_abs: String, powershell_exe: String) -> bool:
	if powershell_exe.is_empty():
		push_error("BuildTestReleaseRegular: powershell executable is empty.")
		return false
	var ps_script: String = "if (Test-Path -LiteralPath '%s') { Remove-Item -LiteralPath '%s' -Recurse -Force }; New-Item -ItemType Directory -Force -Path '%s' | Out-Null" % [out_dir_abs.replace("'", "''"), out_dir_abs.replace("'", "''"), out_dir_abs.replace("'", "''")]
	return _exec_ok(powershell_exe, PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_script]), "BuildTestReleaseRegular")


func _resolve_godot_cli_executable(preferred_path: String) -> String:
	var exe_path: String = preferred_path.strip_edges()
	if exe_path.is_empty():
		return exe_path
	var lower_name: String = exe_path.get_file().to_lower()
	if lower_name.ends_with("_console.exe"):
		return exe_path
	if lower_name.ends_with(".exe"):
		var sibling_console: String = exe_path.get_base_dir().path_join("%s_console.exe" % exe_path.get_basename().get_file())
		if FileAccess.file_exists(sibling_console):
			return sibling_console
	return exe_path


func _exec_ok(exe: String, args: PackedStringArray, label: String) -> bool:
	var out: Array = []
	var code: int = OS.execute(exe, args, out, true)
	var text: String = ""
	for part: Variant in out:
		text += str(part)
	if not text.strip_edges().is_empty():
		print(text.strip_edges())
	if code != 0:
		push_error("%s: command failed (%d): %s %s" % [label, code, exe, " ".join(args)])
		return false
	return true


func _write_text_file(abs_path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("BuildTestReleaseRegular: failed to write %s" % abs_path)
		return false
	f.store_string(text)
	f.close()
	return true


func _write_lines_abs(abs_path: String, lines: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("BuildTestReleaseRegular: failed to write %s" % abs_path)
		return
	for line: String in lines:
		f.store_line(line)
	f.close()


func _is_supported_output_path(path: String) -> bool:
	var trimmed: String = path.strip_edges()
	if trimmed.is_empty():
		return false
	if trimmed.begins_with("res://") or trimmed.begins_with("user://"):
		return true
	if trimmed.length() >= 3 and trimmed[1] == ":" and (trimmed[2] == "/" or trimmed[2] == "\\"):
		return true
	if trimmed.begins_with("/") or trimmed.begins_with("\\\\"):
		return true
	return false


func _resolve_output_path(path: String) -> String:
	var trimmed: String = path.strip_edges()
	if trimmed.begins_with("res://") or trimmed.begins_with("user://"):
		return ProjectSettings.globalize_path(trimmed)
	return trimmed
