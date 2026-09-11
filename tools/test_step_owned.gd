extends Node
## Стенд листания в гараже (10.09.2026): стрелки/клавиши влево-вправо ходят
## только по КУПЛЕННЫМ машинам по кругу (стартовые + owned_cars), чужие из
## магазина пропускаются; счётчик — «k / n» среди купленных. Профиль не
## сохраняем — owned_cars правим только в памяти.

func _ready() -> void:
	GameState.owned_cars = ["ac1"]
	var sel: Node = (load("res://scenes/CarSelect.tscn")
			as PackedScene).instantiate()
	add_child(sel)
	await get_tree().process_frame
	var ids: Array[String] = CarModelLibrary.CAR_IDS
	var fails := 0
	sel._set_index(0)
	var got: Array[String] = []
	for _n in range(5):
		sel._step_owned(1)
		got.append(ids[sel._index])
	var want: Array[String] = ["vz02", "vz21", "ac1", "vz01", "vz02"]
	print("вправо: %s %s" % [got, "ok" if got == want else "FAIL, ждали %s" % [want]])
	if got != want: fails += 1
	got = []
	for _n in range(4):
		sel._step_owned(-1)
		got.append(ids[sel._index])
	want = ["vz01", "ac1", "vz21", "vz02"]
	print("влево: %s %s" % [got, "ok" if got == want else "FAIL, ждали %s" % [want]])
	if got != want: fails += 1
	# С чужой машины (выбрана на доске) стрелка уводит к ближайшей своей.
	sel._set_index(ids.find("vz05"))
	var cnt_alien: String = sel._count_label.text
	sel._step_owned(1)
	var ok3: bool = ids[sel._index] == "ac1" and sel._count_label.text == "4 / 4"
	print("с чужой vz05 (%s) → %s, счётчик %s %s" % [cnt_alien, ids[sel._index],
			sel._count_label.text, "ok" if ok3 else "FAIL"])
	if not ok3: fails += 1
	sel._step_owned(-1)
	var ok4: bool = ids[sel._index] == "vz21" and sel._count_label.text == "3 / 4"
	print("назад → %s, счётчик %s %s" % [ids[sel._index], sel._count_label.text,
			"ok" if ok4 else "FAIL"])
	if not ok4: fails += 1
	print("TestStepOwned TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(0 if fails == 0 else 1)
