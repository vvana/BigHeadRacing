# Отладочный дамп новых пропсов декора (palmov/city): для каждого FBX —
# общий AABB, число мешей и имена материалов поверхностей.
# Запуск: godot --headless --path . --script tools/dump_props.gd
extends SceneTree

const DIRS := [
	"res://assets/models/track_env/palmov/",
	"res://assets/models/track_env/city/",
]


func _init() -> void:
	for dir_path in DIRS:
		var da := DirAccess.open(dir_path)
		if da == null:
			print("NO DIR ", dir_path)
			continue
		for f in da.get_files():
			if not f.ends_with(".fbx"):
				continue
			var scene: PackedScene = load(dir_path + f)
			if scene == null:
				print(f, "  LOAD FAILED")
				continue
			var root := scene.instantiate()
			var merged := AABB()
			var first := true
			var meshes := 0
			var mats := {}
			for mi: MeshInstance3D in root.find_children(
					"*", "MeshInstance3D", true, false):
				meshes += 1
				var ab := mi.transform * mi.mesh.get_aabb()
				merged = ab if first else merged.merge(ab)
				first = false
				for s in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(s)
					mats[m.resource_name if m != null else "<null>"] = true
			print("%s  meshes=%d  pos=%v size=%v  mats=%s"
					% [f, meshes, merged.position, merged.size, mats.keys()])
			root.free()
	quit(0)
