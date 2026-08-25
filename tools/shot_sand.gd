extends Node3D
## Служебный снимок ПЕСЧАНОЙ трассы: грузит Main с track_kind = sand и
## снимает несколько ракурсов в PNG (общий вид, старт, кромка полотна,
## ускоритель). Запуск: godot --path . res://tools/ShotSand.tscn -- <папка>

var _main: Node3D
var _cam: Camera3D
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.track_kind = TrackBuilder.KIND_SAND
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
	await _shot(Vector3(0, 190, 130), Vector3.ZERO, "sand_overview.png")
	await _shot(start + fwd * 30.0 + Vector3(0, 14, 0),
			start + Vector3(0, 4, 0), "sand_start.png")
	# Кромка полотна без ограждений — виден съезд на песок.
	var mid := track._curve.sample_baked(length * 0.45)
	await _shot(mid + Vector3(0, 26, 34), mid, "sand_edge.png")
	# Первый ускоритель крупным планом.
	if not track.boost_pad_offsets.is_empty():
		var pad := track._curve.sample_baked(track.boost_pad_offsets[0])
		await _shot(pad + Vector3(10, 9, 10), pad, "sand_boost_pad.png")
	# Игровой ракурс (изометрия).
	var p := start + fwd * 6.0
	await _shot(p + Vector3(30, 38, 30), p, "sand_gameplay.png", 30.0)
	get_tree().quit(0)
