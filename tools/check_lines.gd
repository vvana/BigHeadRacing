extends Node
## Проверка «двойная полоса есть на всех машинах»: для каждой НЕаркадной
## машины строим модель с "-l1" и считаем дубли кузова "<имя>_line"
## (их вешает CarModelLibrary._attach_line); ноль — полосы нет.
## Запуск: godot --headless --path . res://tools/CheckLines.tscn

func _ready() -> void:
	var bad := 0
	for id in CarModelLibrary.CAR_IDS:
		if CarModelLibrary.is_arcade(id):
			continue
		var full: String = id + "-l1"
		var model := CarModelLibrary.build(full)
		if model == null:
			print("%-10s МОДЕЛИ НЕТ (%s)" % [id, full])
			bad += 1
			continue
		var dups := 0
		var meshes := PackedStringArray()
		for c in model.get_children():
			if c is MeshInstance3D:
				meshes.append(String(c.name))
			if String(c.name).ends_with("_line"):
				dups += 1
		var flag := "" if dups > 0 else "  ПОЛОСЫ НЕТ"
		if dups == 0:
			bad += 1
		print("%-10s id=%s дублей полосы: %d, меши: %s%s" % [id, full, dups, ", ".join(meshes), flag])
		model.free()
	print("ИТОГО без полосы: %d" % bad)
	get_tree().quit()
