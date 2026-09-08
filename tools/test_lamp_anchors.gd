extends Node3D
## Автотест ЯКОРЕЙ ФАР (08.09): тюнинг не должен двигать лампы. Для каждой
## машины парка строим две модели — голую базу и ту же базу С ПОЛНЫМ
## ТЮНИНГОМ (детали во всех слотах, полоса, неон) — и сравниваем
## Car.headlight_anchor: расхождение больше TOL — FAIL. Ловит грабли
## 08.09: квад неоновой подсветки (2.7 × 4.3 м под машиной) выступал
## перед бампером, «нос» считался по нему, и у Малыша с неоном лампы
## лежали на дороге перед машиной. Заодно проверяем, что лампа не на
## полу (y > 0.15) и не дальше 0.5 м за кончиком носа.
## Запуск: godot --headless --path . res://tools/TestLampAnchors.tscn
## Вердикт — «LAMP ANCHORS TEST: PASS|FAIL».

const TOL := 0.08


func _ready() -> void:
	var failed := 0
	var checked := 0
	for base: String in CarModelLibrary.CAR_IDS:
		var plain := CarModelLibrary.build(base)
		if plain == null:
			print("  %s: модель не собралась" % base)
			failed += 1
			continue
		add_child(plain)
		var a0 := Car.headlight_anchor(plain, plain.transform)
		var cfg := {"neon": "orange", "line": 1}
		if CarModelLibrary.has_parts(base):
			for slot in ["engine", "spoiler", "exhaust", "wheel"]:
				var opts: Array = CarModelLibrary.slot_options(base, slot)
				if not opts.is_empty():
					cfg[slot] = opts[opts.size() - 1]
		var full_id := CarModelLibrary.tuned_id(base, cfg)
		var tuned := CarModelLibrary.build(full_id)
		if tuned == null:
			print("  %s: тюнингованная модель не собралась (%s)" % [base, full_id])
			failed += 1
			continue
		add_child(tuned)
		var a1 := Car.headlight_anchor(tuned, tuned.transform)
		checked += 1
		var pts := Car.model_points(tuned, tuned.transform)
		var tip := 1e9
		var floor_y := 1e9
		for p in pts:
			tip = minf(tip, p.z)
			floor_y = minf(floor_y, p.y)
		var ok := not a0.is_empty() and not a1.is_empty()
		var why := ""
		if ok:
			var d := Vector3(a0["x"] - a1["x"], a0["y"] - a1["y"], a0["z"] - a1["z"])
			if d.length() > TOL:
				ok = false
				why = "тюнинг сдвинул лампу на %.2f м (голая %s, тюнинг %s)" % [
						d.length(), _fmt(a0), _fmt(a1)]
			elif a1["y"] - floor_y < 0.15:
				# Высота — от НИЗА кузова (модель тут вне машины, её начало
				# координат у разных паков на разной высоте).
				ok = false
				why = "лампа на полу: y=%.2f при низе %.2f" % [a1["y"], floor_y]
			# До 0.8 м за кончиком: у драгстера нос — острый клин, и лампа
			# честно сидит там, где кузов уже достаточно широк (0.7 м).
			elif a1["z"] < tip - 0.5 or a1["z"] > tip + 0.8:
				ok = false
				why = "лампа далеко от носа: z=%.2f, нос %.2f" % [a1["z"], tip]
		else:
			why = "якорь пустой (голая %s, тюнинг %s)" % [a0.is_empty(), a1.is_empty()]
		if not ok:
			failed += 1
			print("  %s (%s): FAIL — %s" % [base, full_id, why])
		plain.queue_free()
		tuned.queue_free()
	print("проверено машин: %d, провалов: %d" % [checked, failed])
	print("LAMP ANCHORS TEST: %s" % ("PASS" if failed == 0 else "FAIL"))
	get_tree().quit(0 if failed == 0 else 1)


func _fmt(a: Dictionary) -> String:
	return "(%.2f, %.2f, %.2f)" % [a["x"], a["y"], a["z"]]
