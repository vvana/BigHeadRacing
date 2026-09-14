extends Node3D
## Стенд гаража под команду друзей (09.09, вечер). Просьбы игрока:
## «кнопка ГОТОВ должна быть не только в меню команды, а ещё вместо кнопки
## СТАРТ; СТАРТ работает, только когда ты не в команде» и «если добавлял
## друга в команду, он должен остаться в списке, чтобы заново не искать».
## Без сети: ростер команды подкладываем в Social.party руками.
## Проверяем:
##   1) вне команды главная кнопка — «СТАРТ»;
##   2) в команде — «ГОТОВ»; при своей готовности — «ГОТОВ ✓ · ЖДЁМ…»,
##      при поиске заезда — «ИЩЕМ ЗАЕЗД…» (выключена);
##   3) нажатие в команде НЕ уводит из гаража (сцена на месте);
##   4) GameState.remember_friend: свежие первыми, без дублей (регистр),
##      себя не запоминаем, потолок FRIENDS_MAX; forget_friend убирает;
##   5) панель «КОМАНДА»: раздел «ДРУЗЬЯ» — по строке на друга, без связи
##      «ПРИГЛАСИТЬ» выключена; со статусами от сервера — у того, кто в
##      сети, кнопка включена, у остальных нет; «✕» убирает из списка;
##   6) ростер команды (party) сам пополняет список друзей.
##
## Запуск: godot --headless --path . res://tools/TestPartyGarage.tscn

var _pass := 0
var _fail := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _rows(box: VBoxContainer) -> Array:
	var out: Array = []
	for c in box.get_children():
		if c is HBoxContainer:
			out.append(c)
	return out


func _btn(row: HBoxContainer, text: String) -> Button:
	for c in row.get_children():
		if c is Button and (c as Button).text == text:
			return c
	return null


func _ready() -> void:
	GameState.player_name = "Стенд"
	GameState.friends = []
	Social.go_offline()
	Social.party = {}
	var sel: Node = (load("res://scenes/CarSelect.tscn")
			as PackedScene).instantiate()
	add_child(sel)
	# Гараж при входе выходит на связь с сервером друзей — стенду связь не
	# нужна (настоящие статусы сломали бы проверки «без связи»).
	Social.go_offline()
	Social.connected = false
	Social.name_ok = false
	for i in 5:
		await get_tree().process_frame
	var btn: Button = sel._start_btn

	# 1. Вне команды — «СТАРТ».
	_ok(btn != null and btn.text == "СТАРТ" and not btn.disabled,
			"вне команды кнопка «СТАРТ» (%s)" % (btn.text if btn else "нет"))

	# 2. В команде — «ГОТОВ» и её состояния.
	# Ростер приходит сообщением party — через _on_message, как с сервера
	# (там же товарищи попадают в список друзей).
	Social._on_message({t = "party", id = "p1", me = "me1", launching = false,
		members = [
		{uid = "me1", name = "Стенд", ready = false, leader = true, online = true,
				status = "garage", car = "vz01_red"},
		{uid = "fr1", name = "Жека", ready = false, leader = false, online = true,
				status = "garage", car = "vz02_blue"}]})
	await get_tree().process_frame
	_ok(btn.text == "ГОТОВ" and not btn.disabled,
			"в команде кнопка «ГОТОВ» (%s)" % btn.text)
	_ok(GameState.friends == ["Жека"],
			"ростер команды пополнил друзей: %s" % str(GameState.friends))
	Social.party.members[0].ready = true
	Social.party_changed.emit()
	await get_tree().process_frame
	_ok(btn.text.begins_with("ГОТОВ ✓") and not btn.disabled,
			"своя готовность: «ГОТОВ ✓ · ЖДЁМ КОМАНДУ» (%s)" % btn.text)
	Social.party.launching = true
	Social.party_changed.emit()
	await get_tree().process_frame
	_ok(btn.text == "ИЩЕМ ЗАЕЗД…" and btn.disabled,
			"ищем заезд: кнопка занята (%s)" % btn.text)
	Social.party.launching = false
	Social.party.members[0].ready = false
	Social.party_changed.emit()
	await get_tree().process_frame

	# 3. Нажатие в команде не уводит из гаража.
	sel._start_race()
	for i in 3:
		await get_tree().process_frame
	_ok(is_instance_valid(sel) and sel.is_inside_tree(),
			"«ГОТОВ» в команде: остаёмся в гараже")
	_ok(Net.mode == Net.Mode.OFFLINE, "«ГОТОВ» не начинает подключение к заезду")

	# 4. Список друзей в профиле.
	GameState.friends = []
	GameState.remember_friend("Вася")
	GameState.remember_friend("Жека")
	GameState.remember_friend("вася")
	GameState.remember_friend("Стенд")
	_ok(GameState.friends == ["Вася", "Жека"],
			"свежий первым, дубль без регистра, себя нет: %s" % str(GameState.friends))
	for i in GameState.FRIENDS_MAX + 3:
		GameState.remember_friend("Друг%d" % i)
	_ok(GameState.friends.size() == GameState.FRIENDS_MAX
			and GameState.friends[0] == "Друг%d" % (GameState.FRIENDS_MAX + 2),
			"потолок %d, свежие держатся: %d" % [GameState.FRIENDS_MAX,
			GameState.friends.size()])
	GameState.friends = []
	GameState.remember_friend("Вася")
	GameState.remember_friend("Жека")
	GameState.forget_friend("ВАСЯ")
	_ok(GameState.friends == ["Жека"], "forget_friend без регистра: %s"
			% str(GameState.friends))

	# 5. Панель «КОМАНДА»: раздел «ДРУЗЬЯ».
	GameState.friends = ["Жека", "Вася"]
	Social.party = {}
	Social.party_changed.emit()
	var panel: PartyPanel = sel._party
	panel.open()
	await get_tree().process_frame
	var rows := _rows(panel._friends_box)
	_ok(rows.size() == 2, "две строки друзей (%d)" % rows.size())
	var inv0 := _btn(rows[0], "ПРИГЛАСИТЬ") if rows.size() > 0 else null
	_ok(inv0 != null and inv0.disabled, "без связи «ПРИГЛАСИТЬ» выключена")
	# Статусы «от сервера»: Жека в гараже, Вася не в сети.
	Social.connected = true
	Social.name_ok = true
	Social.friends_result.emit([
		{name = "Жека", online = true, party = false, status = "garage"},
		{name = "Вася", online = false, party = false, status = "offline"}])
	await get_tree().process_frame
	rows = _rows(panel._friends_box)
	inv0 = _btn(rows[0], "ПРИГЛАСИТЬ") if rows.size() > 0 else null
	var inv1 := _btn(rows[1], "ПРИГЛАСИТЬ") if rows.size() > 1 else null
	_ok(inv0 != null and not inv0.disabled, "Жека в сети — «ПРИГЛАСИТЬ» включена")
	_ok(inv1 != null and inv1.disabled, "Вася не в сети — выключена")
	var lbl := ""
	for c in rows[0].get_children():
		if c is Label and (c as Label).text.begins_with("в "):
			lbl = (c as Label).text
	_ok(lbl == "в гараже", "статус друга «в гараже» (%s)" % lbl)
	var del1 := _btn(rows[1], "✕")
	if del1:
		del1.pressed.emit()
	await get_tree().process_frame
	rows = _rows(panel._friends_box)
	_ok(GameState.friends == ["Жека"] and rows.size() == 1,
			"«✕» убирает друга: %s, строк %d" % [str(GameState.friends), rows.size()])
	Social.connected = false
	Social.name_ok = false

	# 6. Фокус поля «имя друга» (14.09: на телефоне после «ПРИНЯТЬ»
	# приглашение вылезала клавиатура — фокус в LineEdit). Обычное
	# открытие на столе фокус даёт, на телефоне (ключ --touch) — нет;
	# после «ПРИНЯТЬ» — нигде.
	var touch := TouchControls.wanted()
	panel.close()
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var focused := panel._search.has_focus()
	_ok(focused == (not touch), "open(): фокус поиска %s (touch=%s)"
			% [str(focused), str(touch)])
	panel._search.release_focus()
	panel.close()
	Social.invite_received.emit("Жека", 1)
	await get_tree().process_frame
	var accept: Button = null
	if sel._invite_box:
		for c in sel._invite_box.get_children():
			if c is Button and (c as Button).text == "ПРИНЯТЬ":
				accept = c
	_ok(accept != null, "плашка приглашения с «ПРИНЯТЬ»")
	if accept:
		accept.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(sel._invite_box == null and panel.visible,
			"после «ПРИНЯТЬ» плашка убрана, панель команды открыта")
	_ok(not panel._search.has_focus(),
			"после «ПРИНЯТЬ» поле поиска БЕЗ фокуса (клавиатура не вылезает)")
	panel.close()

	# Прибираем тестовый профиль.
	GameState.friends = []
	GameState._save_profile()
	print("RESULT: %d/%d ok" % [_pass, _pass + _fail])
	print("PARTY GARAGE TEST: %s" % ("PASS" if _fail == 0 else "FAIL"))
	get_tree().quit(0 if _fail == 0 else 1)
