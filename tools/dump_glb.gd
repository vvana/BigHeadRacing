# Отладочный дамп структуры GLB: печатает дерево узлов с типами и AABB мешей.
# Запуск: godot --headless --path . --script tools/dump_glb.gd
extends SceneTree

func _init() -> void:
	var glb_path := "res://assets/models/hotwheels/source/Turbo Driver Cars.glb"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		glb_path = args[0]
	var scene: PackedScene = load(glb_path)
	if scene == null:
		print("FAILED TO LOAD GLB")
		quit(1)
		return
	var root := scene.instantiate()
	_dump(root, 0)
	root.free()
	quit(0)

func _dump(node: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + node.name + " [" + node.get_class() + "]"
	if node is MeshInstance3D and node.mesh != null:
		var aabb: AABB = node.mesh.get_aabb()
		line += " center=%s size=%s pos=%s" % [aabb.get_center(), aabb.size, (node as Node3D).position]
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)
