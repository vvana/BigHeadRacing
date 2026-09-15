extends Node3D
## Служебный снимок ЗИМНЕЙ трассы: грузит Main с track_kind = snow и
## снимает несколько ракурсов в PNG (общий вид, старт с ёлкой, шпилька,
## деревня, машина игрока крупно со снегопадом).
## Запуск С ОКНОМ: godot --path . res://tools/ShotSnow.tscn -- <папка>

var _main: Node3D
var _cam: Camera3D
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.track_kind = TrackBuilder.KIND_SNOW
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
	await _shot(Vector3(0, 210, 150), Vector3.ZERO, "snow_overview.png")
	await _shot(start + fwd * 30.0 + Vector3(0, 14, 0),
			start + Vector3(0, 4, 0), "snow_start.png")
	# Ёлка у старта (46 м по ходу, снаружи).
	var tree := track._curve.sample_baked(46.0)
	await _shot(tree + Vector3(0, 12, 26), tree + Vector3(0, 3, 0), "snow_tree.png")
	# Шпилька — самое узкое место (участок 4, ~0.33 круга).
	var hp := track._curve.sample_baked(length * 0.33)
	await _shot(hp + Vector3(0, 30, 30), hp, "snow_hairpin.png")
	# Деревня: ищем первый дом в декоре.
	var decor: Node = track.get_node_or_null("Decor")
	if decor != null:
		for n: Node in decor.get_children():
			if String(n.name).to_lower().begins_with("winter_house"):
				var vp: Vector3 = (n as Node3D).global_position
				await _shot(vp + Vector3(0, 16, 30), vp, "snow_village.png")
				break
	# Гоночная камера: своя машина со снегопадом (ждём, пока разгонятся).
	for _i in 200:
		await get_tree().physics_frame
	var iso: Camera3D = _main.get_node_or_null("IsoCamera")
	if iso != null:
		iso.make_current()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + "/snow_race.png")
		print("SHOT snow_race.png")
	get_tree().quit(0)
