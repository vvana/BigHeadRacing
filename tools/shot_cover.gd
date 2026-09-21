extends Node3D
## Рендер машин на ПРОЗРАЧНОМ фоне для обложки Яндекс Игр (17.09.2026).
## Это НЕ скриншот игры (п. 5.6 требований площадки запрещает скриншот на
## обложке): голые модели без интерфейса, фон и надпись собирает
## tools/gen_cover.py. Кадр пишется через SubViewport с transparent_bg —
## окно движка альфу в PNG не отдаёт.
##
## Запуск С ОКНОМ (headless не рендерит):
##   godot --path . res://tools/ShotCover.tscn -- <папка> <id> [<id> …]

const SIZE := Vector2i(1100, 800)
## Ракурс «три четверти спереди»: у моделей пака нос смотрит в -Z
## (проверено снимком: с +Z в кадр попадала корма), камера справа-спереди.
const CAM_OFF := Vector3(2.5, 1.35, -3.6)
const CAM_AT := Vector3(0.0, 0.45, -0.2)

var _ids: Array[String] = []
var _out := "user://shots"
var _vp: SubViewport
var _cam: Camera3D
var _car: Node3D
var _i := -1
var _frame := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	for a in args.slice(1):
		_ids.append(a)
	DirAccess.make_dir_recursive_absolute(_out)

	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.93, 0.95, 1.0)
	e.ambient_light_energy = 0.8
	env.environment = e
	_vp.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 155, 0)
	sun.light_energy = 1.6
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -35, 0)
	fill.light_energy = 0.6
	fill.light_color = Color(1.0, 0.82, 0.62)   # тёплая подсветка сбоку
	_vp.add_child(fill)

	_cam = Camera3D.new()
	_cam.fov = 30
	_cam.look_at_from_position(CAM_OFF, CAM_AT, Vector3.UP)
	_vp.add_child(_cam)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame % 10 != 0:
		return
	if _car:
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.save_png("%s/car_%s.png" % [_out, _ids[_i]])
		print("SHOT ", _ids[_i])
		_car.queue_free()
		_car = null
	_i += 1
	if _i >= _ids.size():
		get_tree().quit(0)
		return
	_car = CarModelLibrary.build(_ids[_i], 3.2, 0.0)
	if _car == null:
		print("НЕТ ", _ids[_i])
		return
	_vp.add_child(_car)
