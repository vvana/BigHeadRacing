extends Node3D
## Снимок экрана выбора машины (баннер, панель имени, стрелки, кнопка,
## сетка миниатюр). Запуск С ОКНОМ:
## godot --path . res://tools/ScreenshotSelect.tscn -- <папка_вывода>

var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	add_child((load("res://scenes/CarSelect.tscn") as PackedScene).instantiate())


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 90:  # миниатюры успевают отрендериться
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out + "/carselect.png")
		print("SHOT carselect.png")
		get_tree().quit(0)
