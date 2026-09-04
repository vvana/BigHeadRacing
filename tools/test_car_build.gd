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
	_check_soviet_parts()
	_check_soviet_ids()
	print("RESULT: %d/%d ok" % [_total - _failed, _total])
	quit(1 if _failed > 0 else 0)


## Аркадные детали на советских (03.09 вечер): у каждой из 15 машин —
## каждый вариант каждого слота из её набора хотя бы раз (по кругу) +
## полный обвес последними вариантами: у модели прибавляются узлы
## Engine/Spoiler/Exhaust, родные колёса в пивотах спрятаны, аркадные
## добавлены; цвет деталей и полосы (pcolor) собираются без ошибок.
func _check_soviet_parts() -> void:
	for base in CarModelLibrary.SOVIET_IDS:
		var opts := {}
		var longest := 0
		for slot in CarModelLibrary.PART_SLOTS:
			opts[slot] = CarModelLibrary.slot_options(base, slot)
			longest = maxi(longest, (opts[slot] as Array).size())
		for i in range(1, longest):
			var cfg := CarModelLibrary.default_cfg(base)
			for slot in CarModelLibrary.PART_SLOTS:
				var o: Array = opts[slot]
				cfg[slot] = o[mini(i, o.size() - 1)]
			if i == longest - 1:
				cfg["color_wheel"] = "grey2"
				cfg["color_spoiler"] = "red1"
			_check_soviet_tuned(base, cfg)


func _check_soviet_tuned(base: String, cfg: Dictionary) -> void:
	_total += 1
	var id := CarModelLibrary.tuned_id(base, cfg)
	var model := CarModelLibrary.build(id)
	if model == null:
		print("FAIL %s: не собралась" % id)
		_failed += 1
		return
	var names: Array[String] = []
	var arcade_wheels := 0
	var hidden_native := 0
	for child in model.get_children():
		names.append(String(child.name))
		if child.has_meta("wheel_radius"):
			for w in child.get_children():
				if String(w.name) == "Wheel":
					arcade_wheels += 1
				elif w is Node3D and not (w as Node3D).visible:
					hidden_native += 1
	var ok := true
	for slot in ["engine", "spoiler", "exhaust"]:
		var want := int(cfg[slot]) > 0
		ok = ok and names.has(slot.capitalize()) == want
	var want_w := 4 if int(cfg["wheel"]) > 0 else 0
	ok = ok and arcade_wheels == want_w and hidden_native == want_w
	if not ok:
		print("FAIL %s: узлы=%s аркадных колёс=%d спрятано родных=%d" % [
				id, names, arcade_wheels, hidden_native])
		_failed += 1
	else:
		print("ok   %-34s узлов=%d колёс=%d" % [id, names.size(), arcade_wheels])
	model.free()


## id советской машины с деталями: сток остаётся коротким "vz01_red",
## детали — токенами; разбор ↔ сборка, база и цвет; битые токены зажаты;
## цвет деталей/полосы (pcolor/lcolor) в обоих форматах.
func _check_soviet_ids() -> void:
	_total += 1
	var stock := CarModelLibrary.tuned_id("vz01", CarModelLibrary.default_cfg("vz01"))
	var ok := stock == "vz01_red"
	var cfg := CarModelLibrary.default_cfg("gz24")
	cfg["color"] = "white"
	cfg["wheel"] = 7
	cfg["exhaust"] = 4
	cfg["color_exhaust"] = "cyan3"
	var id := CarModelLibrary.tuned_id("gz24", cfg)
	ok = ok and id == "gz24_white-w7-x4-pxcyan3"
	var back := CarModelLibrary.parse_cfg(id)
	ok = ok and CarModelLibrary.base_id(id) == "gz24" \
			and CarModelLibrary.color_of_id(id) == "white" \
			and back["wheel"] == 7 and back["exhaust"] == 4 \
			and back["engine"] == 0 and back["spoiler"] == 0 \
			and back["color_exhaust"] == "cyan3" and back["color_wheel"] == ""
	# Битые токены с чужого клиента: зажаты; чужой цвет в голове id —
	# машина просто не найдётся (бокс-заглушка, как и раньше).
	var bad := CarModelLibrary.parse_cfg("vz05_yellow-w99-pzzz9-pwzzz-e-3-qq")
	ok = ok and bad["color"] == "yellow" and bad["base"] == "vz05" \
			and bad["wheel"] == 10 and bad["color_wheel"] == "" \
			and bad["color_engine"] == "" and bad["engine"] == 0
	# Старые токены дня: "-p<цвет>" — на все детали, "-c<цвет>" — полоса.
	var old := CarModelLibrary.parse_cfg("vz01_red-e1-pgrey2-cred1")
	ok = ok and old["color_wheel"] == "grey2" and old["color_exhaust"] == "grey2" \
			and old["color_line"] == "red1" \
			and CarModelLibrary.tuned_id("vz01", old) \
				== "vz01_red-e1-pwgrey2-pegrey2-psgrey2-pxgrey2-plred1"
	# Аркадный id с цветом дисков и полосы.
	var acfg := {"color": "red", "color_wheel": "grey2", "color_line": "yellow2",
			"line": 1}
	var aid := CarModelLibrary.arcade_id("ac1", acfg)
	var aback := CarModelLibrary.arcade_parse(aid)
	ok = ok and aid.ends_with("-pwgrey2-plyellow2") and aback["color_wheel"] == "grey2" \
			and aback["color_line"] == "yellow2" and aback["line"] == 1 \
			and aback["color_engine"] == ""
	ok = ok and CarModelLibrary.has_parts("vz01") and CarModelLibrary.has_parts("ac3") \
			and not CarModelLibrary.has_parts("fastback") \
			and CarModelLibrary.slot_options("fastback", "engine").is_empty() \
			and CarModelLibrary.slot_options("vz01", "wheel")[0] == 0 \
			and CarModelLibrary.slot_options("ac1", "wheel")[0] == 1
	if ok:
		print("ok   советский id: %s → %s" % [id, back])
	else:
		print("FAIL советский id: stock=%s id=%s back=%s bad=%s aid=%s" % [
				stock, id, back, bad, aid])
		_failed += 1


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
