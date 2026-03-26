# Densetsu Toolkit

Standalone extraction of the Densetsu editor toolkit from the main Densetsu project.

Included:
- `addons/densetsu_tool_suite`
- helper exporter dependency: `addons/densetsu_geometry_obj_export/scene_geometry_obj_exporter.gd`
- related automation scripts under `engine3d/tools`
- supporting scripts/templates used directly by the toolkit

Notes:
- This is extracted from the main project and still contains project-specific paths and assumptions.
- It is intended to be used from a project root preserving the same relative layout.
- Git/release publishing scripts may need retargeting for a different host.
