extends Node3D
## Служебные снимки ФАР: ночной город, машины на решётке, крупный план
## носа с передне-бокового ракурса. Модели подставляются НАСИЛЬНО (в
## заезде они случайные), чтобы попали и проблемные — низкие (wildthing,
## twinmill, sweet16, roadrocket: на них старая фиксированная фара висела
## выше крыши), узконосая sharky и высокие motocrossed/redbaron.
## Запуск: godot --path . res://tools/ShotHeadlights.tscn -- <папка>

const CARS: Array[String] = [
	"wildthing", "twinmill", "sweet16", "roadrocket",
	"sharky", "motocrossed", "redbaron", "stock",
]

var _main: Node3D
var _cam: Camera3D
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.track_kind = TrackBuilder.KIND_NEON
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""
	_cam = Camera3D.new()
	add_child(_cam)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 40:
		_run()


func _run() -> void:
	var cars: Array = _main._cars
	for batch in range(0, CARS.size(), cars.size()):
		for i in cars.size():
			var k := batch + i
			if k < CARS.size():
				_main._set_car_model(cars[i], CARS[k])
		# Кадр рендера: держатель фар встаёт на место в Car._process.
		await RenderingServer.frame_post_draw
		for i in cars.size():
			var k := batch + i
			if k >= CARS.size():
				continue
			await _shot(cars[i], CARS[k])
	get_tree().quit(0)


## Крупный план носа: камера спереди-слева чуть выше фар. Все машины пака
## приведены к длине 3.2 м, поэтому нос — ровно 1.6 м вперёд от центра.
func _shot(car: Node3D, id: String) -> void:
	var basis := car.global_transform.basis
	var nose: Vector3 = car.global_position + basis * Vector3(0.0, 0.05, -1.6)
	_cam.global_position = nose - basis.z * 0.9 - basis.x * 0.7 \
			+ Vector3(0, 0.35, 0)
	_cam.look_at(nose)
	_cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/lights_%s.png" % [_out, id])
	print("SHOT ", id)
