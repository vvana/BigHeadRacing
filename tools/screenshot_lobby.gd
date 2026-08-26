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
	_lobby = Lobby.new()
	add_child(_lobby)
	_lobby.show_screen()
	# Ровно то, что видит игрок, когда людей на все слоты не нашлось:
	# два человека, свободные слоты забрали боты (см. Main._rx_bots).
	_lobby.set_status("Больше игроков не нашлось.\nПустые слоты заняли боты (2) — поехали!")
	_lobby.set_slot(0, true, "sharky", true)
	_lobby.set_slot(1, true, "twinmill", false)
	_lobby.set_slot(2, false, "invader", false, true)
	_lobby.set_slot(3, false, "dakar", false, true)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 40:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out + "/lobby.png")
		print("SHOT lobby.png")
		get_tree().quit(0)
