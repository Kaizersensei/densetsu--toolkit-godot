@tool
extends RefCounted

const _EPS: float = 0.00001


func prune_occluded_mesh_instances(
	editor_iface: EditorInterface,
	occlusion_threshold_percent: float = 100.0,
	dry_run: bool = true,
	use_selection_scope: bool = true
) -> Dictionary:
	var threshold: float = clampf(occlusion_threshold_percent, 0.0, 100.0)
	var scope_root: Node = _resolve_scope_root(editor_iface, use_selection_scope)
	if scope_root == null:
		return {
			"ok": false,
			"error": "No edited scene root or selection scope found."
		}

	var mesh_entries: Array[Dictionary] = []
	var has_scene_bounds: bool = false
	var scene_bounds: AABB = AABB()

	var meshes: Array[Node] = scope_root.find_children("*", "MeshInstance3D", true, false)
	for mesh_node in meshes:
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		if mesh_instance == null:
			continue
		if mesh_instance.mesh == null:
			continue
		if not mesh_instance.visible:
			continue

		var local_aabb: AABB = mesh_instance.get_aabb()
		if local_aabb.size.length_squared() <= _EPS:
			continue
		var world_aabb: AABB = _transform_aabb(mesh_instance.global_transform, local_aabb)
		if world_aabb.size.length_squared() <= _EPS:
			continue

		var volume: float = absf(world_aabb.size.x * world_aabb.size.y * world_aabb.size.z)
		mesh_entries.append({
			"node": mesh_instance,
			"aabb": world_aabb,
			"volume": volume
		})
		if not has_scene_bounds:
			scene_bounds = world_aabb
			has_scene_bounds = true
		else:
			scene_bounds = scene_bounds.merge(world_aabb)

	if mesh_entries.size() <= 1:
		return {
			"ok": true,
			"scope_path": str(scope_root.get_path()),
			"scanned": mesh_entries.size(),
			"total_rays": 0,
			"prunable": 0,
			"deleted": 0,
			"threshold_percent": threshold,
			"dry_run": dry_run,
			"entries": []
		}

	var sample_dirs: Array[Vector3] = _build_sample_directions()
	var sample_points: Array[Vector3] = _build_sample_point_weights()
	var rays_per_mesh: int = sample_dirs.size() * sample_points.size()
	var ray_distance: float = maxf(10.0, scene_bounds.size.length() * 1.5)
	var required_occluded_rays: int = int(ceili((threshold / 100.0) * float(rays_per_mesh)))

	var report_entries: Array[Dictionary] = []
	var prunable_nodes: Array[Node] = []
	var total_rays: int = 0

	for i in mesh_entries.size():
		var candidate: Dictionary = mesh_entries[i]
		var candidate_aabb: AABB = candidate.get("aabb", AABB())
		var occluded_rays: int = 0
		var tested_rays: int = 0

		var occluder_aabbs: Array[AABB] = []
		for j in mesh_entries.size():
			if i == j:
				continue
			var other_aabb: AABB = mesh_entries[j].get("aabb", AABB())
			if other_aabb.size.length_squared() <= _EPS:
				continue
			# Broad-phase reject for distant nodes.
			if not _aabb_maybe_relevant(candidate_aabb, other_aabb, ray_distance):
				continue
			occluder_aabbs.append(other_aabb)

		for point_weights in sample_points:
			var sample_point: Vector3 = _aabb_point(candidate_aabb, point_weights)
			for ray_dir in sample_dirs:
				tested_rays += 1
				total_rays += 1
				var ray_start: Vector3 = sample_point + ray_dir * ray_distance
				if _segment_occluded_by_aabbs(ray_start, sample_point, occluder_aabbs):
					occluded_rays += 1

				# Early out: cannot reach threshold anymore.
				var remaining: int = rays_per_mesh - tested_rays
				if occluded_rays + remaining < required_occluded_rays:
					break
			if tested_rays >= rays_per_mesh:
				break
			var remaining_outer: int = rays_per_mesh - tested_rays
			if occluded_rays + remaining_outer < required_occluded_rays:
				break

		var occlusion_percent: float = 0.0
		if tested_rays > 0:
			occlusion_percent = (float(occluded_rays) / float(tested_rays)) * 100.0
		var is_prunable: bool = occlusion_percent + 0.0001 >= threshold
		var node_obj: Node = candidate.get("node", null)
		var node_path: String = ""
		if node_obj != null:
			node_path = str(node_obj.get_path())
		report_entries.append({
			"path": node_path,
			"occlusion_percent": occlusion_percent,
			"occluded_rays": occluded_rays,
			"tested_rays": tested_rays,
			"prunable": is_prunable
		})
		if is_prunable and node_obj != null:
			prunable_nodes.append(node_obj)

	var deleted: int = 0
	if not dry_run:
		for node_obj in prunable_nodes:
			if not is_instance_valid(node_obj):
				continue
			var parent: Node = node_obj.get_parent()
			if parent == null:
				continue
			parent.remove_child(node_obj)
			node_obj.queue_free()
			deleted += 1

	return {
		"ok": true,
		"scope_path": str(scope_root.get_path()),
		"scanned": mesh_entries.size(),
		"total_rays": total_rays,
		"rays_per_mesh": rays_per_mesh,
		"prunable": prunable_nodes.size(),
		"deleted": deleted,
		"threshold_percent": threshold,
		"dry_run": dry_run,
		"entries": report_entries
	}


func _resolve_scope_root(editor_iface: EditorInterface, use_selection_scope: bool) -> Node:
	if editor_iface == null:
		return null
	if use_selection_scope:
		var selection: EditorSelection = editor_iface.get_selection()
		if selection != null:
			var selected: Array[Node] = selection.get_selected_nodes()
			for node_obj in selected:
				if node_obj is Node3D:
					return node_obj
			if not selected.is_empty():
				return selected[0]
	return editor_iface.get_edited_scene_root()


func _build_sample_directions() -> Array[Vector3]:
	return [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, -1.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3(1.0, 1.0, 1.0).normalized(),
		Vector3(-1.0, 1.0, 1.0).normalized(),
		Vector3(1.0, -1.0, 1.0).normalized(),
		Vector3(1.0, 1.0, -1.0).normalized()
	]


func _build_sample_point_weights() -> Array[Vector3]:
	return [
		Vector3(0.5, 0.5, 0.5), # center
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 1.0, 0.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(0.0, 1.0, 1.0),
		Vector3(1.0, 1.0, 1.0)
	]


func _aabb_point(aabb: AABB, w: Vector3) -> Vector3:
	return aabb.position + aabb.size * w


func _aabb_maybe_relevant(a: AABB, b: AABB, extra: float) -> bool:
	return a.grow(extra).intersects(b.grow(extra))


func _segment_occluded_by_aabbs(from_pos: Vector3, to_pos: Vector3, occluders: Array[AABB]) -> bool:
	var nearest_t: float = 2.0
	var hit_any: bool = false
	for aabb in occluders:
		var hit: Dictionary = _segment_intersects_aabb(from_pos, to_pos, aabb)
		if not bool(hit.get("hit", false)):
			continue
		var t: float = float(hit.get("t", 2.0))
		if t < nearest_t:
			nearest_t = t
			hit_any = true
	return hit_any


func _segment_intersects_aabb(from_pos: Vector3, to_pos: Vector3, aabb: AABB) -> Dictionary:
	var dir: Vector3 = to_pos - from_pos
	var t_min: float = 0.0
	var t_max: float = 1.0

	var min_v: Vector3 = aabb.position
	var max_v: Vector3 = aabb.position + aabb.size

	var ok_x: Dictionary = _segment_axis_interval(from_pos.x, dir.x, min_v.x, max_v.x, t_min, t_max)
	if not bool(ok_x.get("ok", false)):
		return {"hit": false}
	t_min = float(ok_x.get("t_min", t_min))
	t_max = float(ok_x.get("t_max", t_max))

	var ok_y: Dictionary = _segment_axis_interval(from_pos.y, dir.y, min_v.y, max_v.y, t_min, t_max)
	if not bool(ok_y.get("ok", false)):
		return {"hit": false}
	t_min = float(ok_y.get("t_min", t_min))
	t_max = float(ok_y.get("t_max", t_max))

	var ok_z: Dictionary = _segment_axis_interval(from_pos.z, dir.z, min_v.z, max_v.z, t_min, t_max)
	if not bool(ok_z.get("ok", false)):
		return {"hit": false}
	t_min = float(ok_z.get("t_min", t_min))
	t_max = float(ok_z.get("t_max", t_max))

	if t_max < 0.0 or t_min > 1.0:
		return {"hit": false}
	return {"hit": true, "t": clampf(t_min, 0.0, 1.0)}


func _segment_axis_interval(
	origin: float,
	delta: float,
	min_v: float,
	max_v: float,
	in_t_min: float,
	in_t_max: float
) -> Dictionary:
	var t_min: float = in_t_min
	var t_max: float = in_t_max
	if absf(delta) <= _EPS:
		if origin < min_v or origin > max_v:
			return {"ok": false}
		return {"ok": true, "t_min": t_min, "t_max": t_max}

	var inv: float = 1.0 / delta
	var t1: float = (min_v - origin) * inv
	var t2: float = (max_v - origin) * inv
	if t1 > t2:
		var temp: float = t1
		t1 = t2
		t2 = temp
	t_min = maxf(t_min, t1)
	t_max = minf(t_max, t2)
	if t_min > t_max:
		return {"ok": false}
	return {"ok": true, "t_min": t_min, "t_max": t_max}


func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var center: Vector3 = aabb.position + aabb.size * 0.5
	var extents: Vector3 = aabb.size * 0.5
	var basis: Basis = xform.basis
	var abs_basis: Basis = Basis(
		Vector3(absf(basis.x.x), absf(basis.x.y), absf(basis.x.z)),
		Vector3(absf(basis.y.x), absf(basis.y.y), absf(basis.y.z)),
		Vector3(absf(basis.z.x), absf(basis.z.y), absf(basis.z.z))
	)
	var world_center: Vector3 = xform * center
	var world_extents: Vector3 = Vector3(
		abs_basis.x.dot(extents),
		abs_basis.y.dot(extents),
		abs_basis.z.dot(extents)
	)
	return AABB(world_center - world_extents, world_extents * 2.0)
