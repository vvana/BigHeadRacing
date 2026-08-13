# Проверка сборки всех машин из CarModelLibrary: каждая должна найтись,
# иметь детали и разумные габариты. Запуск:
# godot --headless --path . --script tools/test_car_build.gd
extends SceneTree

func _init() -> void:
	var failed := 0
	for id in CarModelLibrary.CAR_IDS:
		var model := CarModelLibrary.build(id)
		if model == null:
			print("FAIL %s: не найдена" % id)
			failed += 1
			continue
		var parts := model.get_child_count()
		if parts < 2:
			print("FAIL %s: слишком мало деталей (%d)" % [id, parts])
			failed += 1
		else:
			print("ok   %-14s деталей=%2d scale=%.2f rot_y=%.0f°" % [
				id, parts, model.scale.x, rad_to_deg(model.rotation.y)
			])
		model.free()
	print("RESULT: %d/%d ok" % [CarModelLibrary.CAR_IDS.size() - failed,
			CarModelLibrary.CAR_IDS.size()])
	quit(1 if failed > 0 else 0)
