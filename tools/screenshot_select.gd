extends Node3D
## Снимок гаража. Без ключей — машина по центру, подменю закрыты
## (carselect.png); ключ `--board` — открыта доска «АВТОПАРК», машина
## слева (carselect_board.png). Запуск С ОКНОМ:
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
	_select = (load("res://scenes/CarSelect.tscn") as PackedScene).instantiate()
	add_child(_select)


func _physics_process(_d: float) -> void:
	_frame += 1
	var board := OS.get_cmdline_user_args().has("--board")
	# `--weapons` (08.09) — открыт магазин ступеней оружия.
	var weapons := OS.get_cmdline_user_args().has("--weapons")
	var party := OS.get_cmdline_user_args().has("--party")
	var stats := OS.get_cmdline_user_args().has("--stats")
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
		_select.call("_open_party")
		_select.call("_show_invite", "Пельмень", 2)
	if _frame == 40 and stats:
		GameState.stats = {races = 37, net_races = 21, wins = 9, podiums = 19,
				place_sum = 118, best_place = 1, kills = 44, rating = 1187,
				cars = {vz01 = 5, ac3 = 20, vz21 = 12}, soccer_games = 6,
				soccer_wins = 4, soccer_goals = 11}
		_select.call("_open_stats")
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
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)
