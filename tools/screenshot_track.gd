extends Node3D
## Служебный снимок трассы: грузит Main, снимает несколько ракурсов в PNG.
## Запуск: godot --path . res://tools/ScreenshotTrack.tscn -- <папка_вывода>

var _main: Node3D
var _cam: Camera3D
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_cam = Camera3D.new()
	add_child(_cam)


func _shot(pos: Vector3, look: Vector3, file: String, ortho := 0.0) -> void:
	if ortho > 0.0:
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = ortho
	else:
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.global_position = pos
	_cam.look_at(look)
	_cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 40:
		_run()


func _run() -> void:
	var track: TrackBuilder = _main._track
	var start := track._curve.sample_baked(0.0)
	# Общий вид сверху.
	await _shot(Vector3(0, 190, 130), Vector3.ZERO, "overview.png")
	# Стартовая зона: арка, огни, башня.
	var fwd := (track._curve.sample_baked(3.0) - start).normalized()
	await _shot(start + fwd * 30.0 + Vector3(0, 14, 0), start + Vector3(0, 4, 0),
			"start_gate.png")
	await _shot(start - fwd * 25.0 + Vector3(0, 12, 0), start + Vector3(0, 4, 0),
			"start_back.png")
	# Середина трассы: трибуна на t=0.55 и обочины.
	var mid := track._curve.sample_baked(track._curve.get_baked_length() * 0.55)
	await _shot(mid + Vector3(0, 30, 40), mid, "mid_track.png")
	# Мультяшная трибуна на t=0.75 — камера снаружи, смотрит на трассу.
	var t75 := track._curve.sample_baked(track._curve.get_baked_length() * 0.75)
	var out75 := Vector3(t75.x, 0, t75.z).normalized()
	await _shot(t75 + out75 * 42.0 + Vector3(0, 22, 0), t75, "tribune75.png")
	# ШПИЛЬКА и узкое место: самая крутая дуга конфигурации (см.
	# TrackBuilder.SEGMENTS) — тут полотно сужается до 6 м полуширины.
	var length := track._curve.get_baked_length()
	var hairpin := track._curve.sample_baked(length * 0.345)
	await _shot(hairpin + Vector3(0, 46, 46), hairpin, "hairpin.png")
	# Переход «широкая прямая → узкий крутой поворот» (сужение видно).
	var narrow := track._curve.sample_baked(length * 0.70)
	await _shot(narrow + Vector3(0, 40, 40), narrow, "narrowing.png")
	# ГОРКА (единственный перепад высот, см. TrackBuilder.HEIGHT_KEYS):
	# сбоку — виден силуэт подъёма и спуска; с подножия — как её видит
	# гонщик. Доли берём из профиля, а не «на глаз».
	var foot := track._curve.sample_baked(length * 0.122)
	var top := track._curve.sample_baked(length * 0.184)
	var side := (top - foot)
	side.y = 0.0
	side = side.normalized().cross(Vector3.UP) * 48.0
	await _shot(top + side + Vector3(0, 7, 0), top, "hill_side.png")
	# Вид «как у гонщика» — камеру ставим ПО КРИВОЙ на 26 м до подножия.
	# Прямая экстраполяция по касательной тут не годится: подъём начинается
	# на выходе из дуги, и камера уезжала ЗА ограждение (в кадре был только
	# красный борт).
	var behind := track._curve.sample_baked(
			fposmod(length * 0.122 - 26.0, length))
	await _shot(behind + Vector3(0, 3.2, 0), top + Vector3(0, 1.0, 0),
			"hill_drive.png")
	# Игровой ракурс — как видит игрок (изометрия).
	var cam := IsoCamera.new()
	var p := start + fwd * 6.0
	await _shot(p + Vector3(30, 38, 30), p, "gameplay.png", 30.0)
	get_tree().quit(0)
