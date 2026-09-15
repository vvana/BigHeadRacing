extends Node3D
## Снимки машины игрока В МОМЕНТ сильного подъёма переднего колеса в арку
## (гипотеза 15.09 «передние диски иногда пропадают»): машину ведёт ИИ по
## классике, стенд ждёт кадр, где lift переднего пивота > порога, и
## сохраняет вырезку вокруг машины с гоночной камеры (×3) + такую же
## вырезку через 0.5 с (для сравнения «после»). До 4 пар.
## Запуск С ОКНОМ: godot --path . res://tools/ShotWheelLift.tscn -- <папка> [id]

var _main: Node3D
var _out := "user://shots"
var _t := 0.0
var _shots := 0
var _cool := 0.0
var _car: Car


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	if args.size() > 1:
		GameState.selected_car_id = args[1]
	GameState.track_kind = TrackBuilder.KIND_GRASS
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


func _process(delta: float) -> void:
	_t += delta
	_cool -= delta
	if _t < 6.0:
		return
	if _car == null:
		_car = _main._cars[_main._my_index()]
		_car.is_player = false   # без ввода машина стояла бы на старте
		_car.ai_skill = 1.0
	if _shots >= 4 or _cool > 0.0:
		if _t > 120.0:
			get_tree().quit(0)
		return
	var lift_f := 0.0
	var lift_r := 0.0
	for pivot: Node3D in _car._wheel_pivots:
		var l: float = pivot.get_meta("lift")
		if pivot.get_meta("is_front"):
			lift_f = maxf(lift_f, l)
		else:
			lift_r = maxf(lift_r, l)
	if lift_f > 0.09:
		_shots += 1
		_cool = 3.0
		print("[lift] t=%.1f перед %.3f зад %.3f кузов %.3f" % [
			_t, lift_f, lift_r, _car._body_lift])
		await _cut("lift_%d_a.png" % _shots)
		await get_tree().create_timer(0.5).timeout
		await _cut("lift_%d_b.png" % _shots)
