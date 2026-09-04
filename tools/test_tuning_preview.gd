extends Node3D
## Стенд примерки в панели тюнинга (03.09.2026, вечер): клик по
## некупленной детали НЕ покупает — надевает на подиум; «КУПИТЬ» покупает
## всё примеренное разом; закрытие панели примерку снимает. Профиль НЕ
## трогается: покупки идут в памяти, в конце профиль восстанавливается
## из копии. Запуск (headless):
##   godot --headless --path . res://tools/TestTuningPreview.tscn
## Вердикт — строка «TestTuningPreview TEST: PASS|FAIL».

var _frame := 0
var _select: Node
var _failed := 0
var _checks := 0
var _saved: Dictionary = {}


func _ready() -> void:
	# Снимок профиля — вернуть в конце (GameState пишет profile.cfg при
	# каждой покупке).
	for k in ["money", "xp", "owned_cars", "car_items", "car_tuning",
			"car_colors", "selected_car_id"]:
		var v: Variant = GameState.get(k)
		_saved[k] = v.duplicate(true) if v is Dictionary or v is Array else v
	GameState.money = 5000
	GameState.xp = 2400   # ~10 уровень: ярусы I и II
	GameState.car_items["vz01"] = {}
	GameState.car_tuning["vz01"] = {}
	GameState.car_colors["vz01"] = "red"
	GameState.selected_car_id = GameState.full_id("vz01")
	_select = (load("res://scenes/CarSelect.tscn") as PackedScene).instantiate()
	add_child(_select)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL ", what)
	else:
		print("ok   ", what)


## Первая кнопка (рекурсивно) с текстом, начинающимся на what.
func _find_button(root: Node, what: String) -> Button:
	if root is Button and (root as Button).text.begins_with(what):
		return root
	for c in root.get_children():
		var b := _find_button(c, what)
		if b != null:
			return b
	return null


## Первая подпись (рекурсивно), содержащая what.
func _find_label(root: Node, what: String) -> Label:
	if root is Label and (root as Label).text.contains(what):
		return root
	for c in root.get_children():
		var l := _find_label(c, what)
		if l != null:
			return l
	return null


func _podium_has(node_name: String) -> bool:
	var model: Node = _select.get("_model")
	return model != null and model.has_node(node_name)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_select.call("_open_tuning")
	if _frame != 40:
		return
	var panel: TuningPanel = _select.get("_tuning")
	var engine: int = CarModelLibrary.slot_options("vz01", "engine")[1]
	var wheel: int = CarModelLibrary.slot_options("vz01", "wheel")[1]
	var money0: int = GameState.money
	_ok(panel.visible and panel.base() == "vz01", "панель открыта на Копейке")
	_ok(not _podium_has("Engine"), "на подиуме сток")

	# Примерка: деньги и профиль целы, подиум с мотором и дисками.
	panel._try_on("engine", engine)
	panel._try_on("wheel", wheel)
	_ok(panel.has_preview() and GameState.money == money0,
			"примерка не списала монет")
	_ok(int(GameState.tuning_of("vz01")["engine"]) == 0
			and not GameState.item_owned("vz01", "engine:%d" % engine),
			"профиль без мотора")
	_ok(panel.preview_id() == "vz01_red-w%d-e%d" % [wheel, engine],
			"preview_id: %s" % panel.preview_id())
	_ok(_podium_has("Engine"), "на подиуме примеренный мотор")
	_ok(GameState.full_id("vz01") == "vz01_red", "полный id без примерки")
	# Повторный клик — снять с примерки.
	panel._try_on("wheel", wheel)
	_ok(not panel._preview.has("wheel") and panel._preview.has("engine"),
			"второй клик снял диски, мотор остался")

	# Покупка всего примеренного: списано, поставлено, примерка пуста.
	var price: int = GameState.item_price("vz01", "engine:%d" % engine)
	var buy := Button.new()
	panel._buy_preview(buy)
	_ok(GameState.money == money0 - price, "списано %d" % price)
	_ok(GameState.item_owned("vz01", "engine:%d" % engine)
			and int(GameState.tuning_of("vz01")["engine"]) == engine,
			"мотор куплен и стоит")
	_ok(not panel.has_preview(), "примерка пуста после покупки")
	_ok(GameState.full_id("vz01") == "vz01_red-e%d" % engine,
			"полный id с мотором: %s" % GameState.full_id("vz01"))

	# Не хватает монет — ничего не куплено, примерка осталась.
	GameState.money = 0
	panel._try_on("wheel", wheel)
	panel._buy_preview(buy)
	_ok(panel.has_preview() and not GameState.item_owned("vz01", "wheel:%d" % wheel),
			"без монет покупки нет, примерка осталась")
	_ok(buy.text == "НЕ ХВАТАЕТ МОНЕТ", "кнопка мигнула: %s" % buy.text)

	# Закрыли панель — примерка снята, подиум по профилю.
	panel.close()
	_ok(not panel.has_preview() and _podium_has("Engine")
			and not _podium_has("WheelPivot_wheel_fl/Wheel"),
			"после закрытия: мотор (куплен) есть, примеренных дисков нет")

	# Цвет деталей — бесплатно и сразу.
	_ok(GameState.set_tuning("vz01", "color_engine", "cyan2")
			and GameState.full_id("vz01").ends_with("-pecyan2"), "цвет мотора в id")
	# Вкладки: у Копейки мотор/колёса/спойлер/выхлоп/краска, у аркадной
	# ещё полоса и наклейки; выбор вкладки перестраивает панель.
	panel.open("vz01")
	_ok(panel._tabs() == ["engine", "wheel", "spoiler", "exhaust", "paint", "line", "fx"]
			and panel._tab == "engine", "вкладки Копейки: %s" % [panel._tabs()])
	panel._select_tab("paint")
	_ok(panel._tab == "paint", "вкладка «КРАСКА» выбрана")

	# Смена вкладки снимает непокупленную примерку (просьба 03.09, ночь):
	# выбор живёт только в своей вкладке, пока его не купили.
	panel._select_tab("wheel")
	panel._try_on("wheel", wheel)
	_ok(panel.has_preview(), "диски примерены на вкладке КОЛЁСА")
	panel._select_tab("spoiler")
	_ok(not panel.has_preview() and not GameState.item_owned("vz01", "wheel:%d" % wheel),
			"уход на другую вкладку снял примерку, покупки нет")
	_ok(panel.preview_id() == GameState.full_id("vz01"),
			"подиум вернулся к настоящему виду: %s" % panel.preview_id())

	# Кнопка «КУПИТЬ» — в подвале панели (_foot), а не в меню (_box):
	# появляясь сверху, она сдвигала всё меню вниз.
	panel._select_tab("engine")
	panel._try_on("engine", CarModelLibrary.slot_options("vz01", "engine")[2])
	_ok(_find_button(panel._foot, "КУПИТЬ") != null
			and _find_button(panel._box, "КУПИТЬ") == null,
			"кнопка «КУПИТЬ» внизу панели")
	var buy_btn := _find_button(panel._foot, "КУПИТЬ")
	_ok(_find_label(panel._foot, "итого") == null
			and _find_label(panel._foot, "ПРИМЕРКА:") != null,
			"строка примерки без «итого»")
	_ok(buy_btn != null and buy_btn.text.contains("·"),
			"цена на самой кнопке: %s" % [buy_btn.text if buy_btn else "нет"])
	panel.close()

	# Эффекты (04.09): вкладка «ЭФФЕКТЫ» у всех машин; дым и неон
	# примеряются (подиум — с неоном), покупаются «КУПИТЬ», попадают в id.
	panel.open("vz01")
	_ok(panel._tabs()[-1] == "fx", "последняя вкладка Копейки — ЭФФЕКТЫ: %s" % [panel._tabs()])
	panel._select_tab("fx")
	GameState.money = 1000
	var money_fx: int = GameState.money
	panel._try_on("smoke", "cyan")
	panel._try_on("neon", "pink")
	_ok(panel.has_preview() and GameState.money == money_fx
			and panel.preview_id().ends_with("-mcyan-npink"),
			"дым и неон примерены, не куплены: %s" % panel.preview_id())
	_ok(_podium_has("Underglow"), "на подиуме примеренный неон")
	_ok(_find_button(panel._foot, "КУПИТЬ") != null
			and _find_label(panel._foot, "дым голубой") != null,
			"строка примерки с дымом и неоном")
	var fx_price: int = GameState.item_price("vz01", "smoke:cyan") \
			+ GameState.item_price("vz01", "neon:pink")
	panel._buy_preview(buy)
	_ok(GameState.money == money_fx - fx_price
			and GameState.item_owned("vz01", "smoke:cyan")
			and GameState.item_owned("vz01", "neon:pink"),
			"куплены дым и неон, списано %d" % fx_price)
	_ok(GameState.full_id("vz01").ends_with("-mcyan-npink"),
			"id с эффектами: %s" % GameState.full_id("vz01"))
	_ok(not panel.has_preview() and _podium_has("Underglow"),
			"после покупки неон на подиуме уже по профилю")
	# Дым на подиуме — только пока открыта вкладка ЭФФЕКТЫ (04.09: «не
	# всегда в гараже, только когда выбираешь»).
	_ok(not _select._podium_smoke.is_empty(),
			"на вкладке ЭФФЕКТЫ с купленным дымом подиум дымит")
	panel._select_tab("engine")
	_ok(_select._podium_smoke.is_empty(),
			"на вкладке МОТОР дыма на подиуме нет")
	panel._select_tab("fx")
	_ok(not _select._podium_smoke.is_empty(), "вернулись на ЭФФЕКТЫ — дым снова идёт")
	# Unity-машина без слотов: вкладки КРАСКА и ЭФФЕКТЫ.
	panel.open("fastback")
	_ok(panel._tabs() == ["paint", "line", "fx"], "вкладки Unity-машины: %s" % [panel._tabs()])
	panel.close()

	# Вернуть профиль.
	for k in _saved:
		GameState.set(k, _saved[k])
	GameState._save_profile()
	print("TestTuningPreview TEST: %s (%d/%d)" % [
			"PASS" if _failed == 0 else "FAIL", _checks - _failed, _checks])
	get_tree().quit(0 if _failed == 0 else 1)
