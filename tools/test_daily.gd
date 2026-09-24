extends Node
## Стенд ежедневной награды за вход (23.09). Учёт — в GameState
## (DAILY_REWARDS, ЭКОНОМИКА.md, раздел 1): зашёл в гараж — забрал монеты
## за сегодняшний день цепочки, завтра больше, седьмой день самый крупный;
## пропустил день — неделя сначала. Проверяем и учёт, и окно гаража:
##   1) первый заход — доступна, день 1, повтор в тот же день — нет;
##   2) каждый следующий день — следующая сумма, после седьмого неделя
##      идёт по кругу;
##   3) пропуск дня и переведённые назад часы;
##   4) окно в гараже: семь табличек, «ЗАБРАТЬ +300», монеты в кошельке,
##      окно закрылось и само больше не всплывает.
## Профиль на диске подменяется и в конце ВОССТАНАВЛИВАЕТСЯ (claim_daily
## сохраняет профиль). Запуск:
## godot --headless --path . res://tools/TestDaily.tscn

var _fails := 0


func _check(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


## Поставить учёт «забрано N дней, последний раз ago дней назад».
func _set_chain(days: int, ago: int) -> void:
	GameState._daily_day = days
	GameState._daily_last = 0 if days <= 0 else GameState._day_number() - ago


func _ready() -> void:
	var had := FileAccess.file_exists(GameState.PROFILE_PATH)
	var orig := FileAccess.get_file_as_bytes(GameState.PROFILE_PATH) \
			if had else PackedByteArray()
	var money0: int = GameState.money
	var day0: int = GameState._daily_day
	var last0: int = GameState._daily_last
	var r: Array = GameState.DAILY_REWARDS

	print("— учёт —")
	_check(r.size() == 7, "неделя из семи дней (%d)" % r.size())
	var grows := true
	for i in range(1, r.size()):
		if int(r[i]) <= int(r[i - 1]):
			grows = false
	_check(grows, "каждый день больше предыдущего: %s" % str(r))

	GameState.money = 1000
	_set_chain(0, 0)
	_check(GameState.daily_available(), "новый профиль: награда ждёт")
	_check(GameState.daily_index() == 0 and GameState.daily_reward() == int(r[0]),
			"первый день: %d монет" % GameState.daily_reward())
	var got: int = GameState.claim_daily()
	_check(got == int(r[0]) and GameState.money == 1000 + int(r[0]),
			"забрал день 1: +%d, в кошельке %d" % [got, GameState.money])
	_check(not GameState.daily_available() and GameState.claim_daily() == 0
			and GameState.money == 1000 + int(r[0]),
			"в тот же день второй раз — ничего")

	_set_chain(1, 1)
	_check(GameState.daily_available() and GameState.daily_index() == 1
			and GameState.daily_reward() == int(r[1]),
			"назавтра: день 2, %d монет" % GameState.daily_reward())

	_set_chain(3, 2)
	_check(GameState.daily_index() == 0,
			"пропустил день — неделя сначала (день %d)"
			% (GameState.daily_index() + 1))

	_set_chain(6, 1)
	_check(GameState.daily_index() == 6
			and GameState.daily_reward() == int(r[6]),
			"седьмой день: %d монет" % GameState.daily_reward())
	GameState.money = 0
	_check(GameState.claim_daily() == int(r[6]) and GameState._daily_day == 7,
			"забрал седьмой: %d монет" % GameState.money)
	_set_chain(7, 1)
	_check(GameState.daily_index() == 0
			and GameState.daily_reward() == int(r[0]),
			"неделя пройдена — новая с первого дня")

	# Часы, переведённые НАЗАД: награда ждёт, пока дата не догонит.
	_set_chain(2, -3)
	_check(not GameState.daily_available(),
			"часы назад: награды нет")

	# Цепочка переживает перезапуск игры (пишется в профиль).
	_set_chain(4, 0)
	GameState._save_profile()
	var cf := ConfigFile.new()
	cf.load(GameState.PROFILE_PATH)
	_check(int(cf.get_value("profile", "daily_day", -1)) == 4
			and int(cf.get_value("profile", "daily_last", -1))
					== GameState._daily_last,
			"цепочка сохранена в профиль")

	print("— окно в гараже —")
	GameState.money = 1000
	_set_chain(0, 0)
	# На профиле стенда окно само не всплывает (иначе закрыло бы гараж во
	# всех снимках) — просим его флагом, как это делает screenshot_select.
	GameState.debug_daily = true
	var sel: Node = (load("res://scenes/CarSelect.tscn")
			as PackedScene).instantiate()
	add_child(sel)
	await get_tree().process_frame
	_check(sel._daily_box != null, "окно награды всплыло само")
	var btn: Button = sel._daily_btn
	_check(btn != null and btn.text.contains(str(int(r[0]))),
			"кнопка «%s»" % ("нет" if btn == null else btn.text))
	var cards := 0
	if sel._daily_box != null:
		for n in sel._daily_box.get_child(0).get_children():
			if n is NinePatchRect:
				cards += 1
	_check(cards == r.size(), "табличек по числу дней (%d)" % cards)

	btn.pressed.emit()
	await get_tree().process_frame
	_check(GameState.money == 1000 + int(r[0]),
			"забрал в гараже: в кошельке %d" % GameState.money)
	_check(sel._daily_box == null, "окно закрылось")
	_check(sel._coins_label.text == "1 300",
			"кошелёк на табличке обновился: «%s»" % sel._coins_label.text)
	sel._show_daily()
	_check(sel._daily_box == null, "в тот же день окно больше не всплывает")

	# Вернуть профиль и память как были.
	GameState.money = money0
	GameState.debug_daily = false
	GameState._daily_day = day0
	GameState._daily_last = last0
	if had:
		var f := FileAccess.open(GameState.PROFILE_PATH, FileAccess.WRITE)
		f.store_buffer(orig)
	else:
		DirAccess.remove_absolute(GameState.PROFILE_PATH)

	print("DAILY TEST: %s" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0 if _fails == 0 else 1)
