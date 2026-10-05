extends Node3D
## Снимок ЭКРАННОГО УПРАВЛЕНИЯ (09.09.2026): грузит Main как на телефоне
## (аргумент --touch), даёт заезду тронуться, «нажимает» пальцами газ и ▶
## и снимает кадр; затем кадр с кнопкой «В ГАРАЖ» (лобби/финиш).
## Запуск С ОКНОМ:
## godot --path . res://tools/ShotTouch.tscn -- <папка_вывода> --touch
## [--auto-gas] [--steer-right]

var _main: Node3D
var _frame := 0
var _out := "user://shots"
var _hold := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	GameState.auto_gas = args.has("--auto-gas")   # настройка «автоматический газ»
	GameState.steer_right = args.has("--steer-right")   # руль справа (как до 05.10)
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	# После Main._process — чтобы подсказка стенда пережила show_tap Main.
	process_priority = 100


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = _win(pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Полотно -> окно: parse_input_event ждёт ОКОННЫЕ координаты (в headless
## окно 64x64, полотно 1280x720 ужато в него), Window сам вернёт их в полотно.
func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _process(_d: float) -> void:
	_frame += 1
	var tc: TouchControls = _main._touch
	if tc != null and not _hold.is_empty():
		tc.show_tap(_hold)
	# Пальцы — в центры кнопок, где бы их ни поставила раскладка (сторона
	# руля, автогаз): педаль (газ или, при автогазе, тормоз) и ▶.
	var pedal := Vector2.ZERO
	var steer := Vector2.ZERO
	if tc != null:
		pedal = tc._by_kind["brake" if GameState.auto_gas else "gas"].center
		steer = tc._by_kind["right"].center
	match _frame:
		60:
			_shot("touch_countdown.png")
		250:
			_touch(0, pedal, true)
			_touch(1, steer, true)
		262:
			_shot("touch_race.png")
		270:
			_touch(0, pedal, false)
			_touch(1, steer, false)
			_hold = "В ГАРАЖ"
		276:
			_shot("touch_tap.png")
		282:
			get_tree().quit()
