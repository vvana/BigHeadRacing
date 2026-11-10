extends Node3D
## Обзор всего круга ракурсом игровой камеры (23.10, для дизайна
## окружения): та же изометрия (TrackDecor._iso_basis), только окно на всю
## трассу — видно, как разложены зоны, кварталы и не стоит ли рядом
## одинаковое. Плюс четыре четверти крупнее. Интерфейс заезда спрятан.
## Запуск С ОКНОМ: godot --path . --resolution 1920x1080
##     res://tools/ShotOverview.tscn -- <папка> --track=grass

var _main: Node3D
var _cam: Camera3D
var _frame := 0
var _out := "user://shots"
var _kind := TrackBuilder.KIND_GRASS


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	for a in args:
		if a.begins_with("--track="):
			_kind = a.trim_prefix("--track=")
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.track_kind = _kind
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(_cam)


func _process(_d: float) -> void:
	_frame += 1
	if _frame == 40:
		for c: Node in _main.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	if _frame < 45:
		return
	var b := TrackDecor._iso_basis()
	var track: TrackBuilder = _main._track
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var curve := track._curve
	var d := 0.0
	while d < curve.get_baked_length():
		var q := curve.sample_baked(d)
		var s := Vector2(q.dot(b.x), q.dot(b.y))
		lo = lo.min(s)
		hi = hi.max(s)
		d += 5.0
	var mid := (lo + hi) * 0.5
	var span := hi - lo + Vector2(60.0, 40.0)
	var aspect := float(get_viewport().size.x) / get_viewport().size.y
	var views := [[mid, maxf(span.y, span.x / aspect), "all"]]
	for k in 4:
		var c := Vector2(lo.x + span.x * (0.25 + 0.5 * (k % 2)) - 30.0,
				lo.y + span.y * (0.25 + 0.5 * (k / 2)) - 20.0)
		views.append([c, maxf(span.y, span.x / aspect) * 0.5, "q%d" % k])
	var i := _frame - 45
	if i % 3 != 0:
		return
	var v: int = i / 3
	if v > 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [_out, _kind, views[v - 1][2]])
	if v >= views.size():
		get_tree().quit()
		return
	var c2: Vector2 = views[v][0]
	_cam.size = views[v][1]
	_cam.global_transform = Transform3D(b, b.x * c2.x + b.y * c2.y + b.z * 300.0)
	_cam.far = 1000.0
	_cam.make_current()
