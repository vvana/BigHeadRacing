extends Node
## Служебный снимок СЕТЕВОГО клиента: подключается к серверу и снимает
## несколько кадров игры — видно, что реально рисуется на экране у игрока.
## Запуск С ОКНОМ (headless не рендерит):
##   godot --path . res://tools/ShotNet.tscn -- <адрес> <папка_вывода>
## Устройство сцены — как в TestNet: корень зовётся Main (RPC адресуются по
## пути узла), проверяльщик висит дочерним.

var _main: Node3D
var _t := 0.0
var _shots := 0
var _out := "user://shots"


func _ready() -> void:
	var addr := "127.0.0.1"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		addr = args[0]
	if args.size() > 1:
		_out = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = get_parent() as Node3D
	Net.join_server(addr, Net.PORT)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


func _process(delta: float) -> void:
	_t += delta
	# Кадры: до старта, сразу после GO и на ходу.
	if _shots == 0 and _t > 6.0:
		_shots = 1
		_shot("net_lobby.png")
	elif _shots == 1 and _t > 9.5:
		_shots = 2
		_shot("net_go.png")
	elif _shots == 2 and _t > 13.0:
		_shots = 3
		_shot("net_drive.png")
	elif _shots == 3 and _t > 16.0:
		_shots = 4
		print("слот: %d" % Net.my_slot)
		print("своя машина: %s" % [
				_main._car.global_position if _main._car else "нет"])
		print("камера: %s" % [
				(get_viewport().get_camera_3d().global_position
				if get_viewport().get_camera_3d() else "нет")])
		for i in _main._cars.size():
			var c: Car = _main._cars[i]
			var model: Node = c.get_node_or_null("CarModel")
			print("  машина %d: роль=%d модель=%s видима=%s y=%.2f (дорога y=%.2f)" % [
					i, c.net_role, "есть" if model else "НЕТ",
					c.visible, c.global_position.y,
					_main._track._curve.sample_baked(
						_main._track._curve.get_closest_offset(
							c.global_position)).y])
		var ground: Node = _main._track.get_node_or_null("Ground")
		var road: Node = _main._track.get_node_or_null("Road")
		print("Ground детей: %d, Road детей: %d" % [
				ground.get_child_count() if ground else -1,
				road.get_child_count() if road else -1])
		_shot("net_drive2.png")
	elif _shots == 4 and _t > 18.0:
		get_tree().quit(0)


func _physics_process(_d: float) -> void:
	# Газ через Input: своя машина клиент-авторитетна, физика локальная.
	if _main._car != null and _main._car.controls_enabled:
		Input.action_press("accelerate")
