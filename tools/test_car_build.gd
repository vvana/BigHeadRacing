# Проверка сборки всех машин из CarModelLibrary: каждая должна найтись,
# иметь детали и разумные габариты. Советский пак проверяется во ВСЕХ
# 10 цветах (150 сборок) + у него обязаны быть 4 пивота колёс. Запуск:
# godot --headless --path . --script tools/test_car_build.gd
extends SceneTree

var _failed := 0
var _total := 0

func _init() -> void:
	for id in CarModelLibrary.CAR_IDS:
		if CarModelLibrary.has_skins(id):
			for color in CarModelLibrary.SOVIET_COLORS:
				_check(CarModelLibrary.skin_id(id, color), true,
						color == CarModelLibrary.default_color(id))
		else:
			_check(id, false, true)
	print("RESULT: %d/%d ok" % [_total - _failed, _total])
	quit(1 if _failed > 0 else 0)


func _check(full_id: String, soviet: bool, verbose: bool) -> void:
	_total += 1
	var model := CarModelLibrary.build(full_id)
	if model == null:
		print("FAIL %s: не найдена" % full_id)
		_failed += 1
		return
	var parts := model.get_child_count()
	var wheels := 0
	for child in model.get_children():
		if child is Node3D and child.has_meta("wheel_radius"):
			wheels += 1
	# Советский пак: кузов + 4 колеса-пивота; одиночные Unity-файлы —
	# машина цельным мешем: одна деталь, колёс нет.
	var min_parts := 5 if soviet else 1
	var need_wheels := 4 if soviet else 0
	if parts < min_parts or wheels < need_wheels:
		print("FAIL %s: деталей=%d колёс=%d (надо ≥%d/≥%d)" % [
				full_id, parts, wheels, min_parts, need_wheels])
		_failed += 1
	elif verbose:
		print("ok   %-16s деталей=%2d колёс=%d scale=%.2f rot_y=%.0f°" % [
			full_id, parts, wheels, model.scale.x,
			rad_to_deg(model.rotation.y)
		])
	model.free()
