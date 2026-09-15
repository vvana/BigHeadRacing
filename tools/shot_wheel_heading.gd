extends Node3D
## Снимки машины игрока В ДВИЖЕНИИ на заданном курсе ОТНОСИТЕЛЬНО ЭКРАНА
## (жалоба 15.09 «еду вправо по экрану — передний левый диск чёрный»):
## машину ведёт ИИ, стенд каждые 0.4 с проверяет, куда смотрит нос машины
## в координатах камеры, и если курс в пределах ±25° от нужного —
## сохраняет вырезку вокруг машины (×3). До 10 кадров, не чаще раза в
## 1.5 с. Курс: --dir right|left|up|down (по умолчанию right).
## Запуск С ОКНОМ:
## godot --path . res://tools/ShotWheelHeading.tscn -- <папка> [id] [--track snow] [--dir right]

var _main: Node3D
var _out := "user://shots"
var _t := 0.0
var _shots := 0
var _cool := 0.0
var _car: Car
var _dir := "right"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	if args.size() > 1 and not args[1].begins_with("--"):
		GameState.selected_car_id = args[1]
	var ti := args.find("--track")
	GameState.track_kind = args[ti + 1] if ti >= 0 and ti + 1 < args.size() else "grass"
	var di := args.find("--dir")
	if di >= 0 and di + 1 < args.size():
		_dir = args[di + 1]
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""


func _cut(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var cam := get_viewport().get_camera_3d()
	var c := cam.unproject_position(_car.visual_origin() + Vector3.UP * 0.4)
	var r := Rect2i(int(c.x) - 110, int(c.y) - 80, 220, 160)
	r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var cut := img.get_region(r)
	cut.resize(cut.get_width() * 3, cut.get_height() * 3, Image.INTERPOLATE_LANCZOS)
	cut.save_png(_out + "/" + file)
	print("SHOT ", file)


## Курс носа машины на экране: угол в градусах, 0 — вправо, 90 — вверх.
func _screen_heading() -> float:
	var cam := get_viewport().get_camera_3d()
	var o := _car.visual_origin()
	var f: Vector3 = -_car.global_transform.basis.z
	var a := cam.unproject_position(o)
	var b := cam.unproject_position(o + f * 2.0)
	var d := b - a
	return rad_to_deg(atan2(-d.y, d.x))


func _process(delta: float) -> void:
	_t += delta
	_cool -= delta
	if _t < 6.0:
		return
	if _car == null:
		_car = _main._cars[_main._my_index()]
		_car.is_player = false
		_car.ai_skill = 1.0
	if _shots >= 10 or _t > 150.0:
		get_tree().quit(0)
		return
	if _cool > 0.0:
		return
	var want: float = {"right": 0.0, "up": 90.0, "left": 180.0, "down": -90.0}.get(_dir, 0.0)
	var h := _screen_heading()
	var diff := absf(fmod(h - want + 540.0, 360.0) - 180.0)
	if diff > 25.0:
		return
	_shots += 1
	_cool = 1.5
	print("[heading] t=%.1f курс %.0f° руль %.2f" % [_t, h, _car._steer_visual])
	await _cut("hd_%s_%d.png" % [_dir, _shots])
