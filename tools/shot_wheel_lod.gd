extends Node3D
## Диски колёс на расстоянии (жалоба 09.09 «иногда пропадают диски»):
## машина под камерой на дистанции гоночного вида, два кадра — с авто-LOD
## как есть (lod_bias 1) и с отключённым (lod_bias 128). Если кадры
## различаются в области колёс — диски съедает LOD импорта. Запуск С ОКНОМ:
## godot --path . res://tools/ShotWheelLod.tscn -- <папка_вывода> [id] [--dist N]
var _out := "tools/shots_dbg"
var _model: Node3D
var _frame := 0
var _dist := 60.0

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_out = a[0]
	var id := "ac1-cyan2-g1-w2-e5-s10-x3-k0-l1"
	if a.size() > 1 and not a[1].begins_with("--"):
		id = a[1]
	var di := a.find("--dist")
	if di >= 0 and di + 1 < a.size():
		_dist = float(a[di + 1])
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	add_child(env)
	_model = CarModelLibrary.build(id)
	add_child(_model)
	var cam := Camera3D.new()
	add_child(cam)
	if a.has("--persp"):
		cam.fov = 45.0
		cam.position = Vector3(_dist * 0.75, _dist * 0.55, _dist * 0.35)
		cam.look_at(Vector3(0, 0.4, 0))
	else:
		# Ровно гоночная камера (IsoCamera): ортографика 26 м, наклон -32°,
		# поворот 45°, отступ 60 м; --dist меняет отступ.
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 26.0
		cam.rotation_degrees = Vector3(-32, 45, 0)
		cam.position = cam.global_transform.basis.z * _dist
	cam.current = true

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 10:
		_shot("wheel_lod_auto.png")
	elif _frame == 12:
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).lod_bias = 128.0
	elif _frame == 20:
		_shot("wheel_lod_off.png")
		get_tree().quit()

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name))
	print("SHOT ", name)
