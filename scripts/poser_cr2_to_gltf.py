import bpy
import sys
import os
import re


def _arg_after(flag: str):
    if flag in sys.argv:
        i = sys.argv.index(flag)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None


def _runtime_root_from_cr2(cr2_path: str) -> str:
    parts = os.path.normpath(cr2_path).split(os.sep)
    if "Runtime" in parts:
        idx = parts.index("Runtime")
        return os.sep.join(parts[: idx + 1])
    return os.path.dirname(cr2_path)


def _poser_path_to_os(poser_path: str, runtime_root: str) -> str:
    if not poser_path:
        return ""
    path = poser_path.strip()
    if path.startswith("GetStringRes"):
        return ""  # unresolved string resource
    if path.startswith(":"):
        path = path[1:]
    parts = path.split(":")
    if not parts:
        return ""
    base = os.path.dirname(runtime_root)
    return os.path.normpath(os.path.join(base, *parts))


def parse_cr2(cr2_path: str):
    with open(cr2_path, "r", errors="ignore") as f:
        lines = f.read().splitlines()

    figure_res = None
    for line in lines:
        m = re.match(r"^\s*figureResFile\s+(.+)$", line)
        if m:
            figure_res = m.group(1).strip()
            break

    # actors
    actors = {}
    i = 0
    while i < len(lines):
        m = re.match(r"^\s*actor\s+([^\s:]+)", lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1).strip()
        depth = 0
        started = False
        block = []
        i += 1
        while i < len(lines):
            line = lines[i]
            if "{" in line:
                depth += line.count("{")
                started = True
            if started:
                block.append(line)
            if "}" in line and started:
                depth -= line.count("}")
                if depth <= 0:
                    break
            i += 1
        parent = None
        origin = None
        endp = None
        for bl in block:
            pm = re.match(r"^\s*parent\s+([^\s]+)", bl)
            if pm:
                parent = pm.group(1).split(":")[0]
            om = re.match(r"^\s*origin\s+([\-0-9eE\.]+)\s+([\-0-9eE\.]+)\s+([\-0-9eE\.]+)", bl)
            if om:
                origin = (float(om.group(1)), float(om.group(2)), float(om.group(3)))
            em = re.match(r"^\s*endPoint\s+([\-0-9eE\.]+)\s+([\-0-9eE\.]+)\s+([\-0-9eE\.]+)", bl)
            if em:
                endp = (float(em.group(1)), float(em.group(2)), float(em.group(3)))
        actors[name] = {"parent": parent, "origin": origin, "end": endp}
        i += 1

    # morphs
    morphs = {}
    i = 0
    while i < len(lines):
        m = re.match(r"^\s*targetGeom\s+([^\s]+)", lines[i])
        if not m:
            i += 1
            continue
        mname = m.group(1).strip()
        depth = 0
        started = False
        block = []
        i += 1
        while i < len(lines):
            line = lines[i]
            if "{" in line:
                depth += line.count("{")
                started = True
            if started:
                block.append(line)
            if "}" in line and started:
                depth -= line.count("}")
                if depth <= 0:
                    break
            i += 1
        deltas = []
        in_deltas = False
        for bl in block:
            if re.match(r"^\s*deltas\b", bl):
                in_deltas = True
                continue
            if in_deltas:
                if "}" in bl:
                    in_deltas = False
                    continue
                dm = re.match(r"^\s*d\s+(\d+)\s+([\-0-9eE\.]+)\s+([\-0-9eE\.]+)\s+([\-0-9eE\.]+)", bl)
                if dm:
                    idx = int(dm.group(1)) - 1
                    dx = float(dm.group(2))
                    dy = float(dm.group(3))
                    dz = float(dm.group(4))
                    deltas.append((idx, dx, dy, dz))
        if deltas:
            morphs[mname] = deltas
        i += 1

    return figure_res, actors, morphs


def parse_obj_groups(obj_path: str):
    groups = {}
    current = "default"
    groups.setdefault(current, set())
    with open(obj_path, "r", errors="ignore") as f:
        for line in f:
            if line.startswith("g "):
                parts = line.strip().split()
                if len(parts) > 1:
                    current = parts[1]
                    groups.setdefault(current, set())
            elif line.startswith("f "):
                parts = line.strip().split()[1:]
                for p in parts:
                    vi = p.split("/")[0]
                    if vi:
                        try:
                            idx = int(vi) - 1
                            groups.setdefault(current, set()).add(idx)
                        except ValueError:
                            pass
    return groups


def import_obj(obj_path: str):
    if hasattr(bpy.ops.wm, "obj_import"):
        bpy.ops.wm.obj_import(filepath=obj_path)
    else:
        bpy.ops.import_scene.obj(filepath=obj_path, use_split_objects=False, use_split_groups=False)


def ensure_single_mesh():
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        return None
    if len(meshes) == 1:
        return meshes[0]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def build_armature(actors: dict):
    arm = bpy.data.armatures.new("Armature")
    arm_obj = bpy.data.objects.new("Armature", arm)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    bones = {}
    # create bones
    for name, data in actors.items():
        b = arm.edit_bones.new(name)
        origin = data.get("origin") or (0.0, 0.0, 0.0)
        endp = data.get("end")
        if not endp or (endp[0] == origin[0] and endp[1] == origin[1] and endp[2] == origin[2]):
            endp = (origin[0], origin[1] + 0.1, origin[2])
        b.head = origin
        b.tail = endp
        bones[name] = b
    # set parents
    for name, data in actors.items():
        parent = data.get("parent")
        if parent and parent in bones:
            bones[name].parent = bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def apply_vertex_groups(obj, groups: dict, actors: dict):
    mesh = obj.data
    for gname, indices in groups.items():
        if gname not in actors:
            continue
        vg = obj.vertex_groups.new(name=gname)
        if indices:
            vg.add(list(indices), 1.0, "REPLACE")


def apply_morphs(obj, morphs: dict):
    if not morphs:
        return
    basis = obj.data.shape_keys
    if basis is None:
        obj.shape_key_add(name="Basis", from_mix=False)
    basis = obj.data.shape_keys.key_blocks["Basis"]
    base_coords = [v.co.copy() for v in basis.data]

    for name, deltas in morphs.items():
        sk = obj.shape_key_add(name=name, from_mix=False)
        for idx, dx, dy, dz in deltas:
            if 0 <= idx < len(sk.data):
                sk.data[idx].co = base_coords[idx] + bpy.mathutils.Vector((dx, dy, dz))


def main():
    cr2_path = _arg_after("--cr2")
    out_path = _arg_after("--out")
    runtime_root = _arg_after("--runtime")
    obj_override = _arg_after("--obj")

    if not cr2_path or not out_path:
        print("Usage: --cr2 <file.cr2> --out <file.gltf|file.glb> [--runtime <RuntimeRoot>] [--obj <base.obj>]")
        sys.exit(1)

    runtime_root = runtime_root or _runtime_root_from_cr2(cr2_path)

    figure_res, actors, morphs = parse_cr2(cr2_path)
    obj_path = obj_override or _poser_path_to_os(figure_res, runtime_root)

    if not obj_path or not os.path.exists(obj_path):
        print(f"ERROR: Could not resolve base OBJ. figureResFile={figure_res}")
        print("Provide --obj <base.obj> for figures that use GetStringRes or alternate geometry.")
        sys.exit(2)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_obj(obj_path)
    obj = ensure_single_mesh()
    if obj is None:
        print("ERROR: OBJ import produced no mesh.")
        sys.exit(3)

    groups = parse_obj_groups(obj_path)
    arm_obj = build_armature(actors)

    # parent mesh to armature
    obj.parent = arm_obj
    mod = obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm_obj

    apply_vertex_groups(obj, groups, actors)
    apply_morphs(obj, morphs)

    # export
    export_format = "GLB" if out_path.lower().endswith(".glb") else "GLTF_SEPARATE"
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format=export_format,
        export_morph=True,
        export_skins=True,
        export_materials="EXPORT",
    )
    print(f"Exported {out_path}")


if __name__ == "__main__":
    main()
