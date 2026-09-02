# Проверка сборки всех машин из CarModelLibrary: каждая должна найтись,
# иметь детали и разумные габариты. Советский пак проверяется во ВСЕХ
# 10 цветах (150 сборок) + у него обязаны быть 4 пивота колёс. Аркадный
# конструктор: 8 кузовов в стоке + каждая деталь каждого слота хотя бы раз
# (10 колёс, 10 моторов, 10 спойлеров, 10 выхлопов, 10 наклеек, полоса,
# металлик, 36 красок) + разбор/сборка id туда-обратно. Запуск:
# godot --headless --path . --script tools/test_car_build.gd
extends SceneTree

var _failed := 0
var _total := 0

func _init() -> void:
	for id in CarModelLibrary.CAR_IDS:
		if CarModelLibrary.is_arcade(id):
			_check_arcade(id)
		elif CarModelLibrary.has_skins(id):
			for color in CarModelLibrary.SOVIET_COLORS:
				_check(CarModelLibrary.skin_id(id, color), true,
						color == CarModelLibrary.default_color(id))
		else:
			_check(id, false, true)
	_check_arcade_ids()
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


## Аркадный кузов: сток (кузов + 4 колеса = 5 деталей) и полный обвес
## (8 деталей) с деталями по номеру кузова; на первом кузове — перебор
## всех 10 вариантов каждого слота и всех красок.
func _check_arcade(base: String) -> void:
	var n := int(base.substr(2))
	_check_cfg(base, {}, 5, true)
	_check_cfg(base, {"wheel": n + 1, "engine": n, "spoiler": n,
			"exhaust": n, "sticker": n, "line": 1, "glitter": 1}, 8, true)
	if n != 1:
		return
	for i in range(1, CarModelLibrary.PART_COUNT + 1):
		_check_cfg(base, {"wheel": i}, 5, false)
		_check_cfg(base, {"engine": i}, 6, false)
		_check_cfg(base, {"spoiler": i}, 6, false)
		_check_cfg(base, {"exhaust": i}, 6, false)
		_check_cfg(base, {"sticker": i}, 5, false)
	for color in CarModelLibrary.ARCADE_COLORS:
		for shade in [1, 2, 3]:
			_check_cfg(base, {"color": color, "shade": shade}, 5, false)


func _check_cfg(base: String, cfg: Dictionary, want_parts: int,
		verbose: bool) -> void:
	_total += 1
	var id := CarModelLibrary.arcade_id(base, cfg)
	var model := CarModelLibrary.build(id)
	if model == null:
		print("FAIL %s: не собралась" % id)
		_failed += 1
		return
	var parts := model.get_child_count()
	var wheels := 0
	for child in model.get_children():
		if child is Node3D and child.has_meta("wheel_radius"):
			wheels += 1
	if parts != want_parts or wheels != 4:
		print("FAIL %s: деталей=%d колёс=%d (надо %d/4)" % [
				id, parts, wheels, want_parts])
		_failed += 1
	elif verbose:
		print("ok   %-40s деталей=%d scale=%.2f" % [id, parts, model.scale.x])
	model.free()


## id аркадной машины: разбор ↔ сборка, база, зажим битых значений.
func _check_arcade_ids() -> void:
	_total += 1
	var cfg := {"color": "cyan", "shade": 3, "glitter": 1, "wheel": 7,
			"engine": 10, "spoiler": 4, "exhaust": 9, "sticker": 2, "line": 1}
	var id := CarModelLibrary.arcade_id("ac5", cfg)
	var back := CarModelLibrary.arcade_parse(id)
	var ok := CarModelLibrary.base_id(id) == "ac5" \
			and CarModelLibrary.color_of_id(id) == "cyan"
	for k in cfg:
		ok = ok and back[k] == cfg[k]
	# Битый id с чужого клиента: не падает, лишнее зажато.
	var bad := CarModelLibrary.arcade_parse("ac2-zzz9-w99-e-7-qq-s3")
	ok = ok and bad["color"] == "red" and bad["wheel"] == 10 \
			and bad["engine"] == 0 and bad["spoiler"] == 3
	ok = ok and CarModelLibrary.part_tier("wheel", 1) == 0 \
			and CarModelLibrary.part_tier("wheel", 4) == 1 \
			and CarModelLibrary.part_tier("wheel", 10) == 3 \
			and CarModelLibrary.part_tier("engine", 3) == 1 \
			and CarModelLibrary.part_tier("engine", 7) == 3
	if ok:
		print("ok   id: %s → %s" % [id, back])
	else:
		print("FAIL id: %s → %s / bad=%s" % [id, back, bad])
		_failed += 1
