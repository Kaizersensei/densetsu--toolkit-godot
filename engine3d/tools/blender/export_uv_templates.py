import argparse
import os
import sys

import bpy


def _clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False, confirm=False)
    for block in bpy.data.meshes:
        bpy.data.meshes.remove(block, do_unlink=True)


def _import_file(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".obj":
        bpy.ops.import_scene.obj(filepath=path, axis_forward="-Z", axis_up="Y")
        return True
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
        return True
    if ext in (".gltf", ".glb"):
        bpy.ops.import_scene.gltf(filepath=path)
        return True
    if ext == ".dae":
        bpy.ops.wm.collada_import(filepath=path)
        return True
    return False


def _iter_mesh_objects():
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def _sanitize(name):
    return "".join(ch if ch.isalnum() or ch in ("_", "-") else "_" for ch in name)


def _export_uv_layout(filepath, resolution, export_all):
    bpy.ops.uv.export_layout(
        filepath=filepath,
        check_existing=False,
        export_all=export_all,
        modified=False,
        size=(resolution, resolution),
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--format", default="PNG")
    parser.add_argument("--resolution", type=int, default=2048)
    parser.add_argument("--per-object", default="1")
    parser.add_argument("--include-lods", default="0")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])

    input_path = os.path.abspath(args.input)
    output_path = os.path.abspath(args.output)
    output_dir = os.path.dirname(output_path)
    fmt = args.format.upper()
    resolution = max(64, min(args.resolution, 8192))
    per_object = args.per_object not in ("0", "false", "False")

    os.makedirs(output_dir, exist_ok=True)

    _clear_scene()
    if not _import_file(input_path):
        print("Unsupported input format:", input_path)
        return 1

    mesh_objects = _iter_mesh_objects()
    if not mesh_objects:
        print("No mesh objects found:", input_path)
        return 1

    if not per_object:
        bpy.ops.object.select_all(action="SELECT")
        _export_uv_layout(output_path, resolution, export_all=True)
        return 0

    base = os.path.splitext(os.path.basename(output_path))[0]
    for obj in mesh_objects:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        safe_name = _sanitize(obj.name)
        file_name = f"{base}_{safe_name}.{fmt.lower()}"
        per_obj_path = os.path.join(output_dir, file_name)
        _export_uv_layout(per_obj_path, resolution, export_all=False)

    return 0


if __name__ == "__main__":
    sys.exit(main())
