extends Node3D
## Служебный снимок НОЧНОЙ ГОРОДСКОЙ трассы: грузит Main с track_kind =
## neon и снимает несколько ракурсов в PNG (общий вид, старт, неоновая
## кромка, здания, игровая изометрия).
## Запуск: godot --path . res://tools/ShotNeon.tscn -- <папка>

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
	var length := track._curve.get_baked_length()
	var start := track._curve.sample_baked(0.0)
	var fwd := (track._curve.sample_baked(3.0) - start).normalized()
	await _shot(Vector3(0, 200, 140), Vector3.ZERO, "neon_overview.png")
	await _shot(start + fwd * 30.0 + Vector3(0, 14, 0),
			start + Vector3(0, 4, 0), "neon_start.png")
	# Кромка с неоновыми трубками на дальней прямой.
	var mid := track._curve.sample_baked(length * 0.45)
	await _shot(mid + Vector3(0, 18, 26), mid, "neon_edge.png")
	# Взгляд низко вдоль полотна — видны здания и вывески за ограждением.
	var low := track._curve.sample_baked(length * 0.6)
	var low_fwd := (track._curve.sample_baked(
			fmod(length * 0.6 + 4.0, length)) - low).normalized()
	await _shot(low + Vector3(0, 4, 0) - low_fwd * 14.0,
			low + low_fwd * 20.0 + Vector3(0, 2, 0), "neon_city.png")
	# Игровой ракурс (изометрия, как IsoCamera).
	var p := start + fwd * 6.0
	await _shot(p + Vector3(30, 38, 30), p, "neon_gameplay.png", 30.0)
	get_tree().quit(0)
