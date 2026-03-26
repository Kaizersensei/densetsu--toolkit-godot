@tool
extends SceneTree

const DEFAULT_REMOTE: String = "origin"
const DEFAULT_REMOTE_URL: String = "ssh://git@gitea.eventidemiles.com:2221/Retraissance/densetsu-dev.git"
const DEFAULT_BRANCH: String = "main"
const DEFAULT_COMMIT_MESSAGE: String = "Godot In-editor commit"


func _init() -> void:
	var cfg: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var code: int = _run(cfg)
	quit(code)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var cfg: Dictionary = {
		"remote": DEFAULT_REMOTE,
		"remote_url": DEFAULT_REMOTE_URL,
		"branch": DEFAULT_BRANCH,
		"commit_message": DEFAULT_COMMIT_MESSAGE,
	}

	for arg: String in args:
		if arg.begins_with("--remote="):
			cfg["remote"] = arg.substr("--remote=".length()).strip_edges()
			continue
		if arg.begins_with("--remote-url="):
			cfg["remote_url"] = arg.substr("--remote-url=".length()).strip_edges()
			continue
		if arg.begins_with("--branch="):
			cfg["branch"] = arg.substr("--branch=".length()).strip_edges()
			continue
		if arg.begins_with("--commit-message="):
			cfg["commit_message"] = arg.substr("--commit-message=".length()).strip_edges()
			continue
	return cfg


func _run(cfg: Dictionary) -> int:
	var remote: String = str(cfg.get("remote", DEFAULT_REMOTE)).strip_edges()
	var remote_url: String = str(cfg.get("remote_url", DEFAULT_REMOTE_URL)).strip_edges()
	var branch: String = str(cfg.get("branch", DEFAULT_BRANCH)).strip_edges()
	var commit_message: String = str(cfg.get("commit_message", DEFAULT_COMMIT_MESSAGE)).strip_edges()
	if remote.is_empty():
		remote = DEFAULT_REMOTE
	if branch.is_empty():
		branch = DEFAULT_BRANCH
	if commit_message.is_empty():
		commit_message = DEFAULT_COMMIT_MESSAGE

	print("GitPullMain: remote=%s branch=%s" % [remote, branch])

	if not _ensure_remote_target(remote, remote_url):
		return 1

	var current_branch: String = _git_capture_line(["rev-parse", "--abbrev-ref", "HEAD"], true)
	if current_branch.is_empty():
		push_error("GitPullMain: failed to resolve current branch.")
		return 1
	print("GitPullMain: current branch = %s" % current_branch)

	if _worktree_is_dirty():
		print("GitPullMain: worktree dirty; creating differentiating commit.")
		if not _git_ok(["add", "-A"], true):
			return 1
		if not _git_ok(["commit", "-m", commit_message], true):
			return 1
	else:
		print("GitPullMain: worktree clean.")

	if not _git_ok(["fetch", remote], true):
		return 1

	var local_branch_exists: bool = not _git_capture_line(["rev-parse", "--verify", branch], false).is_empty()
	if local_branch_exists:
		if current_branch != branch:
			if not _git_ok(["checkout", branch], true):
				return 1
	else:
		if not _git_ok(["checkout", "-b", branch, "--track", "%s/%s" % [remote, branch]], true):
			return 1

	if not _git_ok(["pull", "--no-edit", remote, branch], true):
		return 1

	print("GitPullMain: success")
	return 0


func _worktree_is_dirty() -> bool:
	var result: Dictionary = _exec_capture("git", PackedStringArray(["status", "--porcelain"]))
	var code: int = int(result.get("code", -1))
	var text: String = str(result.get("text", ""))
	if code != 0 and _try_fix_git_safe_directory(text):
		result = _exec_capture("git", PackedStringArray(["status", "--porcelain"]))
		code = int(result.get("code", -1))
	if code != 0:
		push_error("GitPullMain: git status failed.")
		return false
	return not str(result.get("text", "")).strip_edges().is_empty()


func _ensure_remote_target(remote: String, expected_remote_url: String) -> bool:
	if expected_remote_url.is_empty():
		return true
	var current_remote_url: String = _git_capture_line(["remote", "get-url", remote], true)
	if current_remote_url == expected_remote_url:
		print("GitPullMain: remote '%s' already targets %s" % [remote, expected_remote_url])
		return true
	print("GitPullMain: redirecting remote '%s' to %s" % [remote, expected_remote_url])
	if not _git_ok(["remote", "set-url", remote, expected_remote_url], true):
		return false
	var push_url_result: Dictionary = _exec_capture("git", PackedStringArray(["remote", "get-url", "--push", remote]))
	var push_url_text: String = str(push_url_result.get("text", "")).strip_edges()
	var push_url_code: int = int(push_url_result.get("code", -1))
	if push_url_code == 0 and push_url_text != expected_remote_url:
		if not _git_ok(["remote", "set-url", "--push", remote, expected_remote_url], true):
			return false
	return true


func _git_ok(args: PackedStringArray, print_output: bool) -> bool:
	var result: Dictionary = _exec_capture("git", args)
	var text: String = str(result.get("text", ""))
	var code: int = int(result.get("code", -1))
	if code != 0 and _try_fix_git_safe_directory(text):
		result = _exec_capture("git", args)
		text = str(result.get("text", ""))
		code = int(result.get("code", -1))
	if print_output and not text.strip_edges().is_empty():
		print(text)
	if code != 0:
		push_error("GitPullMain: command failed (%d): git %s" % [code, " ".join(args)])
		return false
	return true


func _git_capture_line(args: PackedStringArray, print_output: bool = false) -> String:
	var result: Dictionary = _exec_capture("git", args)
	var text: String = str(result.get("text", ""))
	var code: int = int(result.get("code", -1))
	if code != 0 and _try_fix_git_safe_directory(text):
		result = _exec_capture("git", args)
		text = str(result.get("text", ""))
		code = int(result.get("code", -1))
	if print_output and not text.strip_edges().is_empty():
		print(text)
	if code != 0:
		push_error("GitPullMain: git failed (%d): git %s" % [code, " ".join(args)])
		return ""
	return str(result.get("text", "")).strip_edges()


func _try_fix_git_safe_directory(stderr_text: String) -> bool:
	var lower: String = stderr_text.to_lower()
	if lower.find("safe.directory") == -1 and lower.find("dubious ownership") == -1:
		return false

	var repo_abs: String = ProjectSettings.globalize_path("res://")
	if repo_abs.is_empty():
		return false

	var existing: Dictionary = _exec_capture("git", PackedStringArray(["config", "--global", "--get-all", "safe.directory"]))
	var existing_text: String = str(existing.get("text", ""))
	if int(existing.get("code", -1)) == 0:
		for line: String in existing_text.split("\n"):
			if line.strip_edges() == repo_abs:
				return true

	var add_result: Dictionary = _exec_capture("git", PackedStringArray(["config", "--global", "--add", "safe.directory", repo_abs]))
	if int(add_result.get("code", -1)) == 0:
		print("GitPullMain: added git safe.directory %s" % repo_abs)
		return true
	return false


func _exec_capture(executable: String, args: PackedStringArray) -> Dictionary:
	var output_lines: Array = []
	var code: int = OS.execute(executable, args, output_lines, true)
	return {
		"code": code,
		"text": "\n".join(_stringify_exec_output(output_lines)),
	}


func _stringify_exec_output(chunks: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for chunk: Variant in chunks:
		out.append(str(chunk))
	return out
