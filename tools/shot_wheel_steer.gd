extends Node3D
## Снимки ПЕРЕДНИХ КОЛЁС машины игрока с гоночной камеры (09.09, жалоба
## «передние диски по-прежнему иногда пропадают»): машина стоит на
## трассе, ей задаются 8 курсов и 3 положения руля (−0.45 / 0 / +0.45),
## на каждый — кадр; PIL потом склеивает центры кадров в лист.
## Запуск С ОКНОМ: godot --path . res://tools/ShotWheelSteer.tscn -- <папка> [id] [--track snow]

var _main: Node3D
var _frame := 0
var _out := "user://shots"
var _car: Car
var _base := Transform3D.IDENTITY
var _shots: Array = []   # [yaw_idx, steer]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.selected_car_id = args[1] if args.size() > 1 else "gz21_red-w8"
	# Ключ `--track <вид>` (15.09): трасса стенда, по умолчанию классика.
	var ti := args.find("--track")
	GameState.track_kind = args[ti + 1] if ti >= 0 and ti + 1 < args.size() else "grass"
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	for y in 8:
		for st in [-0.45, 0.0, 0.45]:
			_shots.append([y, st])


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# Вырезка вокруг машины (по проекции камеры), увеличенная втрое.
	var cam := get_viewport().get_camera_3d()
	var c := cam.unproject_position(_car.global_position + Vector3.UP * 0.4)
	var r := Rect2i(int(c.x) - 90, int(c.y) - 70, 180, 140)
	r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var cut := img.get_region(r)
	cut.resize(cut.get_width() * 3, cut.get_height() * 3, Image.INTERPOLATE_LANCZOS)
	cut.save_png(_out + "/" + file)
	print("SHOT ", file)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame < 260:
		return
	if _frame == 260:
		var cars: Array = _main._cars
		_car = cars[_main._my_index()]
		for c: Car in cars:
			c.controls_enabled = false
		_base = _car.global_transform
		_car.freeze = true
		return
	# Каждые 6 кадров — новая поза, кадр через 4 кадра после неё (камера
	# и картинка успевают встать).
	var k := (_frame - 261) / 6
	var ph := (_frame - 261) % 6
	if k >= _shots.size():
		get_tree().quit(0)
		return
	if ph == 0:
		var yaw: float = float(_shots[k][0]) * TAU / 8.0
		_car.global_transform = Transform3D(Basis(Vector3.UP, yaw), _base.origin)
		_car._steer_visual = _shots[k][1]
	elif ph == 4:
		_shot("ws_%d_%s.png" % [_shots[k][0],
				"l" if _shots[k][1] < 0.0 else ("r" if _shots[k][1] > 0.0 else "c")])
