extends Node3D
## Снимок ЗАЕЗДА с советской машиной игрока в обвесе (03.09, ночь):
## жалоба «у советских машин запчасти висят в воздухе от тюнинга» —
## смотрим машину игрока в гонке, а не в гараже. Профиль не трогается
## (selected_car_id подменяется в памяти). Запуск С ОКНОМ:
## godot --path . res://tools/ShotRaceParts.tscn -- <папка_вывода> [id]

var _main: Node3D
var _frame := 0
var _out := "user://shots"
var _cam: Camera3D
var _car: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.selected_car_id = args[1] if args.size() > 1 \
			else "vz01_red-w8-e7-s3-x6"
	GameState.track_kind = "grass"
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _suffix() -> String:
	var a := OS.get_cmdline_user_args()
	return "_" + a[1].replace("-", "_") if a.size() > 1 else ""


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 12:
		# Что реально стоит на модели игрока: имена узлов и их позиции.
		var cars: Array = _main.get("_cars")
		var pi: int = _main.call("_my_index")
		var car: Node3D = cars[pi]
		var model: Node = car.get_node_or_null("CarModel")
		if model:
			for c in model.get_children():
				print("  узел %-22s pos=%s vis=%s" % [c.name, (c as Node3D).position,
						(c as Node3D).visible])
		# Камера вплотную: сзади-сбоку и спереди-сбоку.
		_cam = Camera3D.new()
		_cam.fov = 45
		add_child(_cam)
		_cam.current = true
		_car = car
	if _frame == 14 or _frame == 24:
		var fwd := -_car.global_transform.basis.z
		var right := _car.global_transform.basis.x
		var off := (-fwd * 4.0 + right * 3.0 + Vector3.UP * 2.0) if _frame == 270 				else (fwd * 4.0 - right * 3.0 + Vector3.UP * 2.0)
		_cam.look_at_from_position(_car.global_position + off,
				_car.global_position + Vector3.UP * 0.3)
	if _frame == 18:
		_shot("race_parts_rear%s.png" % _suffix())
	if _frame == 28:
		_shot("race_parts_front%s.png" % _suffix())
	if _frame == 32:
		get_tree().quit(0)
