# Дамп поверхностей мешей по пакам: имена материалов каждой поверхности.
# Нужен, чтобы понять, где полоса ("sticker line") и где стёкла.
extends SceneTree

func _init() -> void:
	var paths := {
		"arcade": CarModelLibrary.ARCADE_PATH,
		"unity Car-1": "res://assets/models/unitycars/source/Car-1.fbx",
		"unity Car-5": "res://assets/models/unitycars/source/Car-5.fbx",
		"soviet vz08 red": "res://assets/models/sovietcars/source/vz08/vz08_red.fbx",
		"soviet vz05r red": "res://assets/models/sovietcars/source/vz05r/vz05r_red.fbx",
	}
	for label: String in paths:
		var scene: PackedScene = load(paths[label])
		if scene == null:
			print("== %s: НЕ ЗАГРУЗИЛСЯ" % label)
			continue
		var root := scene.instantiate()
		print("== %s" % label)
		_dump(root, 1)
		root.free()
	quit(0)

func _dump(n: Node, depth: int) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		var names: Array[String] = []
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			names.append(m.resource_name if m else "?")
		var nm := String(n.name)
		if nm.begins_with("Car") or nm.begins_with("Wheel 1") or not nm.begins_with("Wheel") \
				and not nm.begins_with("Engine") and not nm.begins_with("Spoiler") \
				and not nm.begins_with("Exhaust"):
			print("%s%s  [%d] %s" % ["  ".repeat(depth), nm, mesh.get_surface_count(), ", ".join(names)])
	for c in n.get_children():
		_dump(c, depth + 1)
