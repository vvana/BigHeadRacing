extends Node3D
## Панели гаража НЕ ВЫЛЕЗАЮТ ЗА ЭКРАН (жалоба 11.09 «кнопки уходят за
## экран» — снимок панели «КОМАНДА ДРУЗЕЙ» с командой 4/8: ряд «ГОТОВ» /
## «ВЫЙТИ» обрезан нижней кромкой; и «когда появляется рамка принять
## приглашение в команду или отменить, кнопки находятся на границе рамки»).
## Замер до правки: панель 741 px при отведённых 594 (при команде 8 — 919),
## кнопки приглашения ростом 70 не влезали в плиту высотой 112.
## Проверяем:
##   1) панель команды не перерастает доску ни с полным составом, ни с
##      длинным списком друзей — и кнопки видны на экране;
##   2) состав команды в прокрутке идёт ПЕРВЫМ, когда команда есть;
##   3) кнопки «ПРИНЯТЬ» / «ОТКЛОНИТЬ» лежат внутри плиты, не залезая на
##      её рамку (поля девятислайса — 20 px).
##
## Запуск: godot --headless --path . res://tools/TestPanelFit.tscn

const PLATE_MARGIN := 20.0   # поля текстуры плиты (UiKit.plate, small)

var _pass := 0
var _fail := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _members(n: int) -> Array:
	var ms: Array = []
	for i in n:
		ms.append({uid = "u%d" % i, name = "Игрок%d" % i, ready = i % 2 == 0,
				leader = i == 0, online = true, status = "garage",
				car = "vz01_red"})
	return ms


func _ready() -> void:
	GameState.player_name = "Стенд"
	GameState.friends = ["Пельмень", "Настя", "Жека_777", "Вован", "Сеня",
			"Гриша", "Толик", "Петя"]
	Social.go_offline()
	Social.party = {}
	var sel: Node = (load("res://scenes/CarSelect.tscn")
			as PackedScene).instantiate()
	add_child(sel)
	Social.go_offline()
	Social.connected = false
	for i in 5:
		await get_tree().process_frame

	var screen: Vector2 = get_viewport().get_visible_rect().size
	# Сколько места отведено доске в гараже (CarSelect.BOARD_H).
	var board_h: float = sel.get_script().get_script_constant_map()["BOARD_H"]
	var panel: PartyPanel = sel._party
	panel.open()
	# Найденные по имени игроки — ещё один ряд, который раньше тянул панель.
	Social.search_result.emit([
		{name = "Витебск Питерскв", online = true, party = false,
				status = "garage"}])
	for n in [4, 8]:
		Social._on_message({t = "party", id = "p1", me = "u0",
				launching = false, members = _members(n)})
		for i in 8:
			await get_tree().process_frame
		_ok(panel.size.y <= board_h + 1.0,
				"команда %d: панель в пределах доски (%.0f из %.0f)"
				% [n, panel.size.y, board_h])
		for btn: Button in [panel._ready_btn, panel._leave_btn]:
			var bottom: float = btn.global_position.y + btn.size.y
			_ok(bottom <= screen.y, "команда %d: «%s» на экране (низ %.0f из %.0f)"
					% [n, btn.text, bottom, screen.y])
		_ok(panel._sec_members.get_index() < panel._sec_find.get_index(),
				"команда %d: состав в прокрутке выше поиска" % n)

	# Приглашение: кнопки внутри плиты, не на рамке.
	sel._show_invite("Витебск Питерскв", 3)
	for i in 5:
		await get_tree().process_frame
	var plate: Control = sel._invite_box
	_ok(plate != null, "плашка приглашения построена")
	if plate != null:
		var buttons: Array[Button] = []
		for c in plate.get_children():
			if c is Button:
				buttons.append(c as Button)
		_ok(buttons.size() == 2, "в плашке две кнопки (%d)" % buttons.size())
		for b in buttons:
			_ok(b.position.y >= PLATE_MARGIN
					and b.position.y + b.size.y <= plate.size.y - PLATE_MARGIN,
					"«%s» внутри рамки плиты (%.0f…%.0f из %.0f)"
					% [b.text, b.position.y, b.position.y + b.size.y,
					plate.size.y])
			_ok(b.position.x >= PLATE_MARGIN
					and b.position.x + b.size.x <= plate.size.x - PLATE_MARGIN,
					"«%s» внутри рамки по ширине" % b.text)
		_ok(plate.position.y + plate.size.y <= screen.y,
				"плашка целиком на экране (низ %.0f из %.0f)"
				% [plate.position.y + plate.size.y, screen.y])

	GameState.friends = []
	GameState._save_profile()
	print("RESULT: %d/%d ok" % [_pass, _pass + _fail])
	print("PANEL FIT TEST: %s" % ("PASS" if _fail == 0 else "FAIL"))
	get_tree().quit(0 if _fail == 0 else 1)
