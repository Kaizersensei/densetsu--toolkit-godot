@tool
extends RefCounted

const DEFAULT_BASE_URL: String = "https://gitea.eventidemiles.com"
const DEFAULT_OWNER: String = "Retraissance"
const DEFAULT_REPO: String = "densetsu-dev"
const DEFAULT_TOKEN_ENV: String = "DENSETSU_GITEA_TOKEN"
const DEFAULT_TOKEN_FILE: String = "res://temp/local/gitea_token.txt"
const DEFAULT_POWERSHELL: String = "powershell.exe"
const PUBLISH_SCRIPT_PATH: String = "res://engine3d/tools/publish_gitea_release.ps1"


static func resolve_token(explicit_token: String, token_file_path: String = DEFAULT_TOKEN_FILE, token_env_name: String = DEFAULT_TOKEN_ENV) -> String:
	var token: String = explicit_token.strip_edges()
	if not token.is_empty():
		return token
	token = _read_token_file(token_file_path)
	if not token.is_empty():
		return token
	var env_name: String = token_env_name.strip_edges()
	if env_name.is_empty():
		env_name = DEFAULT_TOKEN_ENV
	return OS.get_environment(env_name).strip_edges()


static func token_file_exists(token_file_path: String = DEFAULT_TOKEN_FILE) -> bool:
	var res_path: String = token_file_path.strip_edges()
	if res_path.is_empty():
		return false
	var abs_path: String = _resolve_local_path(res_path)
	return FileAccess.file_exists(abs_path)


static func publish_release_asset(cfg: Dictionary) -> Dictionary:
	var powershell_exe: String = str(cfg.get("powershell_exe", DEFAULT_POWERSHELL)).strip_edges()
	if powershell_exe.is_empty():
		powershell_exe = DEFAULT_POWERSHELL
	var publish_script_abs: String = ProjectSettings.globalize_path(PUBLISH_SCRIPT_PATH)
	if not FileAccess.file_exists(publish_script_abs):
		return {
			"ok": false,
			"message": "Publish helper script not found: %s" % PUBLISH_SCRIPT_PATH,
		}
	var asset_path: String = str(cfg.get("asset_path", "")).strip_edges()
	if asset_path.is_empty() or not FileAccess.file_exists(asset_path):
		return {
			"ok": false,
			"message": "Publish asset not found: %s" % asset_path,
		}
	var args: PackedStringArray = PackedStringArray([
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		publish_script_abs,
		"-BaseUrl",
		str(cfg.get("base_url", DEFAULT_BASE_URL)).strip_edges(),
		"-Owner",
		str(cfg.get("owner", DEFAULT_OWNER)).strip_edges(),
		"-Repo",
		str(cfg.get("repo", DEFAULT_REPO)).strip_edges(),
		"-Token",
		str(cfg.get("token", "")).strip_edges(),
		"-Tag",
		str(cfg.get("tag", "")).strip_edges(),
		"-Title",
		str(cfg.get("title", "")).strip_edges(),
		"-Body",
		str(cfg.get("body", "")).strip_edges(),
		"-AssetPath",
		asset_path,
		"-AssetName",
		str(cfg.get("asset_name", "")).strip_edges(),
		"-TargetCommitish",
		str(cfg.get("target_commitish", "")).strip_edges(),
	])
	if bool(cfg.get("prerelease", true)):
		args.append("-Prerelease")
	var output: Array = []
	var code: int = OS.execute(powershell_exe, args, output, true)
	var text: String = "\n".join(_stringify_output(output)).strip_edges()
	if code != 0:
		return {
			"ok": false,
			"message": "Publish script failed (%d)." % code,
			"code": code,
			"text": text,
		}
	if text.is_empty():
		return {
			"ok": false,
			"message": "Publish script returned no output.",
			"text": text,
		}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"message": "Publish script returned invalid JSON.",
			"text": text,
		}
	var data: Dictionary = parsed
	data["ok"] = bool(data.get("ok", false))
	data["text"] = text
	return data


static func _read_token_file(token_file_path: String) -> String:
	var res_path: String = token_file_path.strip_edges()
	if res_path.is_empty():
		return ""
	var abs_path: String = _resolve_local_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return ""
	return FileAccess.get_file_as_string(abs_path).strip_edges()


static func _resolve_local_path(path: String) -> String:
	var trimmed: String = path.strip_edges()
	if trimmed.begins_with("res://") or trimmed.begins_with("user://"):
		return ProjectSettings.globalize_path(trimmed)
	return trimmed


static func _stringify_output(chunks: Array) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for chunk: Variant in chunks:
		lines.append(str(chunk))
	return lines
