extends Control
## Снимок экрана сетевого лобби (без сети: слоты заполняются вручную).
## Запуск С ОКНОМ:
## godot --path . res://tools/ScreenshotLobby.tscn -- <папка_вывода>

var _frame := 0
var _out := "user://shots"
var _lobby: Lobby


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	# Ключ `--eight` (после `--`): лобби на 8 подиумов (двухрядная
	# раскладка, см. Lobby._build_slot) вместо обычных четырёх.
	if args.has("--eight"):
		Net.race_size = 8
	_lobby = Lobby.new()
	add_child(_lobby)
	_lobby.show_screen()
	# Ровно то, что видит игрок, когда людей на все слоты не нашлось: два
	# человека, свободные слоты забрали боты — с 01.09 бот на экране
	# неотличим от живого игрока (ник, машина, оранжевый цвет).
	_lobby.set_status("Все в сборе — поехали!")
	_lobby.set_slot(0, true, "fastback", true, false, "Андрей")
	_lobby.set_slot(1, true, "diablo", false, false, "Жека_777")
	_lobby.set_slot(2, false, "chevelle", false, true, "Шумахер")
	_lobby.set_slot(3, false, "safari", false, true, "Настя")
	if Net.race_size > 4:
		_lobby.set_slot(4, true, "dragster", false, false, "Nagibator2000")
		_lobby.set_slot(5, false, "godfather", false, true, "Пельмень")
		_lobby.set_slot(6, false, "roadster", false, true, "Молния74")


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 40:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var name := "lobby8.png" if Net.race_size > 4 else "lobby.png"
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)
