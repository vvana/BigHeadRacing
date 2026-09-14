extends Node3D
## Снимок гаража. Без ключей — машина по центру, подменю закрыты
## (carselect.png); ключ `--board` — открыта доска «АВТОПАРК», машина
## слева (carselect_board.png); `--shop` — раскрыто меню кнопки
## «МАГАЗИН» (carselect_shop.png); `--bottom` — открытую панель перед
## снимком прокрутить донизу (шапка с «ЗАКРЫТЬ» обязана остаться);
## `--offline` (10.09) — прикинуться устройством без сети (Net.debug_offline):
## в гараже обязана появиться плашка «СЕТИ НЕТ · ЗАЕЗД С БОТАМИ». Запуск С ОКНОМ:
## godot --path . res://tools/ScreenshotSelect.tscn -- <папка_вывода> [--board]

var _frame := 0
var _out := "user://shots"
var _select: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	# На пустом стендовом профиле окно «КАК ТЕБЯ ЗОВУТ?» закрывало бы
	# подменю (как в ShotTuning) — имя задаём в памяти, профиль не трогаем.
	if GameState.player_name == "":
		GameState.player_name = "Стенд"
	# Плашку «СЕТИ НЕТ» иначе не снять: у машины разработчика сеть есть.
	Net.debug_offline = OS.get_cmdline_user_args().has("--offline")
	_select = (load("res://scenes/CarSelect.tscn") as PackedScene).instantiate()
	add_child(_select)


func _physics_process(_d: float) -> void:
	_frame += 1
	var board := OS.get_cmdline_user_args().has("--board")
	# `--weapons` (08.09) — открыт магазин ступеней оружия.
	var weapons := OS.get_cmdline_user_args().has("--weapons")
	var party := OS.get_cmdline_user_args().has("--party")
	var stats := OS.get_cmdline_user_args().has("--stats")
	# `--shop` (09.09, вечер) — раскрытое меню кнопки «МАГАЗИН».
	var shop := OS.get_cmdline_user_args().has("--shop")
	if _frame == 40 and shop:
		_select.call("_set_shop_menu", true)
	if _frame == 40 and board:
		_select.call("_open_board")
	if _frame == 40 and weapons:
		_select.call("_open_weapons")
	# `--party` / `--stats` (09.09) — панель команды друзей (с выдуманным
	# ростером, без сервера) и статистика.
	if _frame == 40 and party:
		Social.party = {id = "p1", me = "me", launching = false, members = [
			{uid = "me", name = GameState.display_name(), car = GameState.selected_car_id,
					ready = true, leader = true, online = true, status = "garage"},
			{uid = "u2", name = "Жека_777", car = "ac3-red", ready = false,
					leader = false, online = true, status = "garage"},
			{uid = "u3", name = "Настя", car = "vz21_green", ready = true,
					leader = false, online = true, status = "race"},
		]}
		Social.party_changed.emit()
		# Список друзей (09.09, вечер) — с выдуманными статусами «от сервера».
		GameState.friends = ["Пельмень", "Настя", "Жека_777", "Вован"]
		_select.call("_open_party")
		Social.connected = true
		Social.name_ok = true
		Social.friends_result.emit([
			{name = "Пельмень", online = true, party = false, status = "garage"},
			{name = "Настя", online = true, party = true, status = "race"},
			{name = "Жека_777", online = true, party = true, status = "garage"},
			{name = "Вован", online = false, party = false, status = "offline"}])
		_select.call("_show_invite", "Пельмень", 2)
	# `--outdated` (14.09) — сервер друзей сказал «обновите игру»: красная
	# плашка, «СТАРТ» → «ОБНОВИТЕ ИГРУ» (выключен), строка под именем.
	if _frame == 40 and OS.get_cmdline_user_args().has("--outdated"):
		Social.outdated = true
		Social.outdated_text = SocialServer.outdated_text(Net.PROTOCOL + 1,
				Net.PROTOCOL)
		Social.outdated_changed.emit()
	if _frame == 40 and stats:
		GameState.stats = {races = 37, net_races = 21, wins = 9, podiums = 19,
				place_sum = 118, best_place = 1, kills = 44, rating = 1187,
				cars = {vz01 = 5, ac3 = 20, vz21 = 12}, soccer_games = 6,
				soccer_wins = 4, soccer_goals = 11}
		_select.call("_open_stats")
	# `--bottom` (09.09, вечер) — прокрутить открытую панель в самый низ:
	# шапка с «ЗАКРЫТЬ» закреплена и обязана остаться на виду.
	if _frame == 80 and OS.get_cmdline_user_args().has("--bottom"):
		var sc := _find_scroll(_select)
		if sc:
			sc.scroll_vertical = 100000
	if _frame == 90:  # миниатюры успевают отрендериться, съезд — доехать
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var name := "carselect_board.png" if board else "carselect.png"
		if weapons:
			name = "carselect_weapons.png"
		if party:
			name = "carselect_party.png"
		if stats:
			name = "carselect_stats.png"
		if shop:
			name = "carselect_shop.png"
		if OS.get_cmdline_user_args().has("--offline"):
			name = "carselect_offline.png"
		if OS.get_cmdline_user_args().has("--outdated"):
			name = ("carselect_party_outdated.png" if party
					else "carselect_outdated.png")
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)


## Первая видимая прокрутка на экране (внутри открытой панели).
func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer and (node as ScrollContainer).is_visible_in_tree():
		return node as ScrollContainer
	for c in node.get_children():
		var f := _find_scroll(c)
		if f != null:
			return f
	return null
