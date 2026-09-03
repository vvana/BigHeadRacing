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
	_select = (load("res://scenes/CarSelect.tscn") as PackedScene).instantiate()
	add_child(_select)


func _physics_process(_d: float) -> void:
	_frame += 1
	var board := OS.get_cmdline_user_args().has("--board")
	if _frame == 40 and board:
		_select.call("_open_board")
	if _frame == 90:  # миниатюры успевают отрендериться, съезд — доехать
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var name := "carselect_board.png" if board else "carselect.png"
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)
