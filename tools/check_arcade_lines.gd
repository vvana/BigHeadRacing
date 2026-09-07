extends Node
## Проверка полосы у АРКАДНЫХ машин: у них полоса — поверхность
## «sticker line» в UV-развёртке кузова. Печатаем поверхности кузова
## каждой машины; нет «sticker line» — полосе негде рисоваться.
## Запуск: godot --headless --path . res://tools/CheckArcadeLines.tscn

func _ready() -> void:
	var bad := 0
	for id in CarModelLibrary.CAR_IDS:
		if not CarModelLibrary.is_arcade(id):
			continue
		var model := CarModelLibrary.build(id + "-l1")
		if model == null:
			print("%-6s МОДЕЛИ НЕТ" % id)
			bad += 1
			continue
		var body := model.get_node_or_null("Body") as MeshInstance3D
		if body == null:
			print("%-6s нет узла Body" % id)
			bad += 1
			continue
		var names := PackedStringArray()
		var has_line := false
		for i in body.mesh.get_surface_count():
			var m := body.mesh.surface_get_material(i)
			var nm := m.resource_name if m else "<без имени>"
			names.append(nm)
			if nm == "sticker line":
				has_line = true
		if not has_line:
			bad += 1
		print("%-6s поверхности: %s%s" % [id, ", ".join(names),
				"" if has_line else "   ПОЛОСЫ НЕТ (нет sticker line)"])
		model.free()
	print("ИТОГО аркадных без полосы: %d" % bad)
	get_tree().quit()
