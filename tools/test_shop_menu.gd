extends Node3D
## Стенд главного меню гаража (09.09, вечер — просьба игрока «слишком
## загромождён интерфейс»): три кнопки «АВТОПАРК» / «ОРУЖИЕ» / «ТЮНИНГ»
## убраны под одну «МАГАЗИН», подсказки управления с экрана убраны,
## имя машины стоит без таблички (раньше — такая же стальная плашка, как
## у соседней кнопки «СТАТИСТИКА», и имя читалось кнопкой).
## Проверяем:
##   1) на экране НЕТ подсказки «листать» и кнопки «АВТОПАРК» в ряду;
##   2) закрытое меню: все три пункта скрыты, «МАГАЗИН» на месте;
##   3) раскрытое у купленной машины: три пункта столбиком, без наложений;
##   4) у закрытой машины пункта «ТЮНИНГ» нет, столбик не рвётся;
##   5) выбор пункта открывает свою панель и гасит меню;
##   6) открытие любой панели (и Esc в _process) гасит меню;
##   7) имя машины — надпись, а не табличка-кнопка;
##   8) кнопка «ЗАКРЫТЬ» панелей (оружие, статистика, тюнинг) закреплена:
##      живёт ВНЕ прокрутки и не уезжает, когда список прокручен донизу
##      (жалоба игрока 09.09 про магазин оружия).
##
## Запуск: godot --headless --path . res://tools/TestShopMenu.tscn

var _pass := 0
var _fail := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _ready() -> void:
	var sel: Node = (load("res://scenes/CarSelect.tscn")
			as PackedScene).instantiate()
	add_child(sel)
	for i in 5:
		await get_tree().process_frame

	# 1. Подсказок на экране нет, отдельной кнопки «АВТОПАРК» в ряду — тоже.
	_ok(not _has_text(sel, "листать"), "подсказка «листать» убрана")
	_ok(not _has_text(sel, "Esc — закрыть"), "подсказка про Esc убрана")
	_ok(_visible_button(sel, "МАГАЗИН") != null, "кнопка «МАГАЗИН» на экране")
	_ok(_visible_button(sel, "АВТОПАРК") == null,
			"«АВТОПАРК» отдельной кнопкой не торчит")
	_ok(_visible_button(sel, "ОРУЖИЕ") == null, "«ОРУЖИЕ» убрано в меню")
	_ok(_visible_button(sel, "ТЮНИНГ") == null, "«ТЮНИНГ» убран в меню")
	_ok(_visible_button(sel, "СТАТИСТИКА") != null, "«СТАТИСТИКА» осталась")

	# 7. Имя машины — надпись прямо в колонке, без плашки-родителя.
	var nl: Label = sel._name_label
	_ok(nl != null and not (nl.get_parent() is NinePatchRect),
			"имя машины — надпись, а не табличка")

	# Машина в фокусе — купленная (стартовая): в меню все три пункта.
	var owned_i := _find_car(sel, true)
	_ok(owned_i >= 0, "в списке есть купленная машина")
	sel._set_index(owned_i)
	sel._set_shop_menu(true)
	await get_tree().process_frame
	var items: Array = sel._shop_items
	_ok(items.size() == 3, "пунктов меню три: %d" % items.size())
	_ok(_all_visible(items), "у купленной машины видны все три пункта")
	_ok(_column_ok(items), "пункты стоят столбиком без наложений")
	_ok(_above_button(sel, items), "столбик — над кнопкой «МАГАЗИН»")

	# 4. Закрытая машина: тюнинга нет, столбик из двух — без дыры.
	var locked_i := _find_car(sel, false)
	_ok(locked_i >= 0, "в списке есть закрытая машина")
	sel._set_index(locked_i)
	await get_tree().process_frame
	_ok(not sel._tuning_btn.visible, "у закрытой машины «ТЮНИНГ» скрыт")
	_ok(sel._board_btn.visible and sel._weapons_btn.visible,
			"остальные два пункта на месте")
	_ok(_column_ok([sel._board_btn, sel._weapons_btn]),
			"столбик из двух не рвётся")

	# 5. Выбор пункта: панель открылась, меню погасло.
	sel._board_btn.emit_signal("pressed")
	await get_tree().process_frame
	_ok(sel._grid_panel.visible, "«АВТОПАРК» открыл доску")
	_ok(not sel._shop_open and not _all_visible(items),
			"после выбора пункта меню закрыто")

	# 6. Открытие панели гасит меню само (пункты и панели зовут друг друга).
	sel._close_board()
	sel._set_shop_menu(true)
	await get_tree().process_frame
	sel._open_weapons()
	await get_tree().process_frame
	_ok(not sel._shop_open, "магазин оружия погасил меню")
	sel._weapons.close()
	await get_tree().process_frame

	# Кнопка «МАГАЗИН» работает как переключатель.
	sel._toggle_shop()
	_ok(sel._shop_open, "нажатие «МАГАЗИН» раскрывает меню")
	sel._toggle_shop()
	_ok(not sel._shop_open, "повторное нажатие закрывает")

	# 8. Шапка панелей с «ЗАКРЫТЬ» закреплена (жалоба 09.09).
	sel._set_index(owned_i)
	await get_tree().process_frame
	for spec in [["магазин оружия", sel._weapons], ["статистика", sel._stats],
			["тюнинг", sel._tuning]]:
		var panel: Control = spec[1]
		if panel == sel._tuning:
			panel.open(CarModelLibrary.CAR_IDS[owned_i])
		else:
			panel.open()
		for i in 3:
			await get_tree().process_frame
		var btn := _visible_button(panel, "ЗАКРЫТЬ")
		_ok(btn != null, "%s: кнопка «ЗАКРЫТЬ» на экране" % spec[0])
		if btn == null:
			continue
		_ok(not _in_scroll(btn, panel),
				"%s: «ЗАКРЫТЬ» вне прокрутки" % spec[0])
		var was := btn.global_position
		var sc := _find_scroll(panel)
		if sc != null:
			sc.scroll_vertical = 100000
			await get_tree().process_frame
			await get_tree().process_frame
			_ok(btn.global_position.is_equal_approx(was)
					and _inside(btn, panel),
					"%s: после прокрутки донизу «ЗАКРЫТЬ» на месте" % spec[0])
		panel.close()
		await get_tree().process_frame

	print("SHOPMENU TEST: %s (%d/%d)" % ["PASS" if _fail == 0 else "FAIL",
			_pass, _pass + _fail])
	get_tree().quit(0 if _fail == 0 else 1)


## Индекс машины: купленной (owned=true) или закрытой.
func _find_car(sel: Node, owned: bool) -> int:
	for i in CarModelLibrary.CAR_IDS.size():
		if GameState.car_owned(CarModelLibrary.CAR_IDS[i]) == owned:
			return i
	return -1


func _all_visible(items: Array) -> bool:
	for b in items:
		if not (b as Button).visible:
			return false
	return true


## Видимые пункты не налезают друг на друга и идут снизу вверх.
func _column_ok(items: Array) -> bool:
	var prev := 10000.0
	for b in items:
		var btn := b as Button
		if not btn.visible:
			continue
		if btn.offset_bottom > prev:
			return false
		prev = btn.offset_top
	return true


## Столбик пунктов — выше кнопки «МАГАЗИН» и той же ширины.
func _above_button(sel: Node, items: Array) -> bool:
	var m: Button = sel._shop_btn
	for b in items:
		var btn := b as Button
		if btn.offset_bottom > m.offset_top:
			return false
		if not is_equal_approx(btn.offset_left, m.offset_left) \
				or not is_equal_approx(btn.offset_right, m.offset_right):
			return false
	return true


## Лежит ли узел внутри прокрутки (до самой панели)?
func _in_scroll(node: Node, stop: Node) -> bool:
	var n := node.get_parent()
	while n != null and n != stop:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


## Первая прокрутка внутри панели.
func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node as ScrollContainer
	for c in node.get_children():
		var f := _find_scroll(c)
		if f != null:
			return f
	return null


## Кнопка целиком внутри рамки панели?
func _inside(btn: Control, panel: Control) -> bool:
	return panel.get_global_rect().encloses(btn.get_global_rect())


## Есть ли на экране видимая кнопка ровно с такой надписью?
func _visible_button(node: Node, txt: String) -> Button:
	if node is Button:
		var b := node as Button
		if b.text == txt and b.is_visible_in_tree():
			return b
	for c in node.get_children():
		var found := _visible_button(c, txt)
		if found != null:
			return found
	return null


## Встречается ли такой кусок текста в надписях экрана?
func _has_text(node: Node, part: String) -> bool:
	if node is Label and (node as Label).text.find(part) >= 0:
		return true
	if node is Button and (node as Button).text.find(part) >= 0:
		return true
	for c in node.get_children():
		if _has_text(c, part):
			return true
	return false
