extends Node3D
## Служебные снимки СЛЕДОВ ШИН: грузит Main, разгоняет машину игрока
## инжектом ввода и делает занос ручником — на асфальте должны остаться
## тёмные полосы от задних колёс, которые затем растворяются.
## Запуск С ОКНОМ (headless не рендерит):
## godot --path . res://tools/ShotSkid.tscn -- <папка_вывода>

var _main: Node3D
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


func _physics_process(_d: float) -> void:
	_frame += 1
	match _frame:
		240:   # отсчёт прошёл — разгон
			Input.action_press("accelerate")
		340:   # занос: ручник + руль влево на скорости
			Input.action_press("handbrake")
			Input.action_press("steer_left")
		365:
			_shot("skid_during.png")
		400:
			Input.action_release("handbrake")
			Input.action_release("steer_left")
		404:
			_shot("skid_done.png")
		470:
			Input.action_release("accelerate")
			_shot("skid_after.png")
		520:
			print("DONE")
			get_tree().quit()
