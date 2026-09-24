extends Node3D
## Снимок ДЫМА при низкой частоте кадров (22.09: на телефоне «дым выглядит
## иначе, пробелы между облачками слишком большие»). Грузит Main оффлайн,
## режет рендер до N кадров/с (Engine.max_fps, как на слабом телефоне),
## машина игрока дымит без заноса (Car.debug_smoke) и едет прямо по газу;
## снимок сверху-сбоку через 2 с езды: шлейф должен быть сплошным, а не
## «кучками через метр». Запуск С ОКНОМ:
## godot --path . res://tools/ShotSmokeFps.tscn -- <папка_вывода> [--fps 20]
## [--no-smoke-spread]   (последний — картинка «как было», для сравнения)

var _main: Node3D
var _frame := 0
var _out := "user://shots"
var _cam: Camera3D
var _car: Node3D
var _fps := 20


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var i := args.find("--fps")
	if i >= 0 and i + 1 < args.size():
		_fps = int(args[i + 1])
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.track_kind = "grass"
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _suffix() -> String:
	return "_%dfps%s" % [_fps,
			"_old" if OS.get_cmdline_user_args().has("--no-smoke-spread") else ""]


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 12:
		var cars: Array = _main.get("_cars")
		var pi: int = _main.call("_my_index")
		_car = cars[pi]
		_car.set("debug_smoke", true)
		_cam = Camera3D.new()
		_cam.fov = 50
		add_child(_cam)
		_cam.current = true
		Engine.max_fps = _fps
	if _frame == 250:   # отсчёт прошёл — газ в пол; боты стоят и не стреляют
		Input.action_press("accelerate")
		for c in (_main.get("_cars") as Array):
			if c != _car:
				c.set("controls_enabled", false)
		# Щит на всю езду: первый прогон боты взорвали машину на второй секунде.
		_car.call("apply_shield", 3, 30.0)
	if _frame >= 250 and _cam != null:
		var fwd := -_car.global_transform.basis.z
		var right := _car.global_transform.basis.x
		var at: Vector3 = _car.call("visual_origin")
		# Сверху-сбоку на ШЛЕЙФ позади машины — там и видны пробелы.
		_cam.look_at_from_position(at + right * 11.0 + Vector3.UP * 7.0 - fwd * 7.0,
				at - fwd * 7.0)
	if _frame == 380:   # ~2 с езды — шлейф набрался
		var v: Vector3 = _car.get("linear_velocity")
		print("SMOKE speed %.1f m/s, fps cap %d" % [v.length(), _fps])
		_shot("smoke%s.png" % _suffix())
	if _frame == 386:
		get_tree().quit(0)
