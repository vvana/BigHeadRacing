extends Node3D
## Служебные снимки ИСКР (08.09: «искр при ударе о машины и ограждения
## нет»): грузит Main, после отсчёта пускает машину игрока в борт под
## 55° (как TestWallSlide) — снопы о стену, потом ставит соперника перед
## носом навстречу — сноп тарана. Ничего не форсит напрямую: искры
## должны родиться из ИГРОВОГО кода (Car._wall_slide / столкновение).
## Запуск С ОКНОМ (headless не рендерит):
## godot --path . res://tools/ShotSparks.tscn -- <папка_вывода>

var _main: Node3D
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.track_kind = "grass"
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


## Сколько снопов искр сейчас живёт в сцене (и где первый) — в консоль,
## чтобы по логу было видно, что искры родились НА МАШИНЕ, а не в (0,0,0).
func _count_sparks(tag: String) -> void:
	var n := 0
	var first := Vector3.ZERO
	for node in _main.get_children():
		if node is SparksFx:
			if n == 0:
				first = (node as Node3D).global_position
			n += 1
	var me: Car = _main._cars[0]
	print("%s: снопов %d, первый в %s, машина в %s" % [
			tag, n, first, me.global_position])


func _physics_process(_d: float) -> void:
	_frame += 1
	var cars: Array = _main._cars
	if cars.is_empty():
		return
	var me: Car = cars[0]
	var track: TrackBuilder = _main._track
	# Боты без оружия и без мин на полотне: в первом прогоне бот заминировал
	# стартовую прямую, и пущенная в борт машина взорвалась вместо искр.
	for c: Car in cars:
		c.weapon = -1
	for node in _main.get_children():
		if node is Mine:
			node.queue_free()
	match _frame:
		250:   # отсчёт прошёл: пуск в стену со стартовой прямой, 55°, 20 м/с
			var curve: Curve3D = track._curve
			var off := curve.get_baked_length() * 0.05
			var pos := curve.sample_baked(off)
			var tangent := (curve.sample_baked(off + 1.0) - pos)
			tangent.y = 0.0
			tangent = tangent.normalized()
			# По умолчанию — ДАЛЬНИЙ от камеры борт: ближний (2.6 м) закрывает
			# собой своё же основание с той стороны, где искры (и корму
			# машины у него тоже). Ключ `--near` — ближний борт.
			var side := tangent.cross(Vector3.UP).normalized()
			if not OS.get_cmdline_user_args().has("--near"):
				side = -side
			var dir := (tangent * cos(deg_to_rad(55.0))
					+ side * sin(deg_to_rad(55.0))).normalized()
			# В 3 м от грани борта (не от оси: без газа машина тормозит и
			# за 25 кадров до стены с оси не доезжает — первый прогон).
			var face := track.half_width_at_offset(off) \
					- TrackBuilder.WALL_THICKNESS * 0.5
			me.global_transform = Transform3D(
				Basis.looking_at(dir), pos + side * (face - 3.0) + Vector3.UP * 0.62)
			me.linear_velocity = dir * 20.0
			me.angular_velocity = Vector3.ZERO
			me.reset_track_offset()
		262:
			_count_sparks("стена")
			_shot("sparks_wall.png")
		275:
			_count_sparks("стена, позже")
			_shot("sparks_wall_late.png")
		320:   # таран: соперник перед носом, летит навстречу
			var fwd := -me.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var other: Car = cars[1]
			other.global_transform = Transform3D(
				Basis.looking_at(-fwd),
				me.global_position + fwd * 3.6 + Vector3.UP * 0.05)
			other.linear_velocity = -fwd * 8.0
			other.angular_velocity = Vector3.ZERO
			other.reset_track_offset()
			me.linear_velocity = fwd * 10.0
		326:
			_count_sparks("таран")
			_shot("sparks_car.png")
		334:
			_shot("sparks_car_late.png")
		350:
			print("DONE")
			get_tree().quit()
