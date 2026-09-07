extends Node3D
## Снимок КАЖДОЙ машины из аргументов отдельным кадром (07.09): полные id
## с комплектацией (vz05r_blue-l1-plgrey1, vz09-e8 …), вид сверху-спереди
## (--top, по умолчанию: полосы) или сбоку-спереди (--side: мотор на
## капоте и стекло). Файлы <папка>/<top|side>_<id>.png. Запуск С ОКНОМ:
##   godot --path . res://tools/ShotCars.tscn -- <папка> [--side|--top] id id ...
var _frame := 0
var _out := "user://shots"
var _cars: Array[Node3D] = []
var _ids: Array[String] = []
var _cam: Camera3D
var _mode := "top"
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	for a in args.slice(1):
		if a.begins_with("--"):
			_mode = a.substr(2)
		else:
			_ids.append(a)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	add_child(sun)
	for i in _ids.size():
		var car := CarModelLibrary.build(_ids[i], 3.2, 0.0)
		if car == null:
			print("НЕТ ", _ids[i]); continue
		car.position = Vector3(0, 0, -50.0 * i)
		add_child(car)
		_cars.append(car)
	_cam = Camera3D.new()
	_cam.fov = 40
	add_child(_cam)
	_aim(0)
func _aim(i: int) -> void:
	var p := _cars[i].position
	if _mode == "side":
		_cam.look_at_from_position(p + Vector3(4.2, 2.0, 1.2), p + Vector3(0, 0.6, 0.3))
	else:
		_cam.look_at_from_position(p + Vector3(1.5, 4.5, 3.5), p + Vector3(0, 0.4, 0))
func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame % 8 == 0:
		var i := _frame / 8 - 1
		if i >= _cars.size():
			get_tree().quit(0)
			return
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [_out, _mode, _cars[i].name.trim_prefix("CarModel_")])
		print("SHOT ", _cars[i].name)
		if i + 1 < _cars.size():
			_aim(i + 1)
