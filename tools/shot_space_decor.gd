extends Node3D
## Снимки 23.09: декор космоса (планеты, шаттл, комета) глазами игрока —
## изометрия как у IsoCamera (наклон -32°, поворот 45°, орто-окно 26 м).
## Для каждой планеты ищет точку оси, с которой виден наибольший кусок
## диска (та же оценка, что TrackDecor._iso_visible), и печатает долю;
## шаттл снимает, когда он виден на ≥ 40 %, и печатает, какую часть
## времени он на виду; комету — когда видна наполовину. Просьба игрока
## «поместить объекты за трассу, чтобы хотя бы были видны».
## Запуск С ОКНОМ: godot --path . res://tools/ShotSpaceDecor.tscn -- <папка>
## Снимки planetN.png, rockN.png, shuttle.png, comet.png; с --static
## (вторым аргументом) — только планеты и астероиды.

var _main: Node3D
var _cam: Camera3D
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameState.track_kind = TrackBuilder.KIND_SPACE
	DirAccess.make_dir_recursive_absolute(_out)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_cam = Camera3D.new()
	add_child(_cam)


func _iso(center: Vector3, file: String) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(-32.0), deg_to_rad(45.0), 0.0))
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 26.0
	_cam.global_position = center + b.z * 60.0
	_cam.global_basis = b
	_cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/" + file)
	print("SHOT ", file)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 40:
		_run()


func _nearest_axis(p: Vector3) -> Vector3:
	var track: TrackBuilder = _main._track
	return track._curve.sample_baked(track._curve.get_closest_offset(p))


## Лучшая точка оси для шара (p, r): [точка, доля видимого диска].
func _best_view(p: Vector3, r: float) -> Array:
	var b := Basis.from_euler(Vector3(deg_to_rad(-32.0), deg_to_rad(45.0), 0.0))
	var track: TrackBuilder = _main._track
	var samples: Array[Vector3] = [p]
	for k in 12:
		var a := TAU * k / 12.0
		samples.append(p + (b.x * cos(a) + b.y * sin(a)) * r)
	var open: Array[Vector3] = []
	for sp in samples:
		if sp.y < 0.0:
			var g := sp + b.z * (-sp.y / b.z.y)
			if track.distance_from_axis(g) < track.half_width_at_pos(g) + 1.0:
				continue
		open.append(sp)
	var curve := track._curve
	var length := curve.get_baked_length()
	var near := curve.get_closest_offset(p)
	var best := 0
	var best_q := Vector3.INF
	var off := -70.0
	while off <= 70.0:
		var q := curve.sample_baked(fposmod(near + off, length))
		var n := 0
		for sp in open:
			var d := sp - q
			if absf(d.dot(b.x)) < 20.8 and absf(d.dot(b.y)) < 13.0:
				n += 1
		if n > best:
			best = n
			best_q = q
		off += 2.0
	return [best_q, float(best) / 13.0]


func _run() -> void:
	var decor: Node3D = _main._track.get_node("Decor")
	var k := 0
	for mi: MeshInstance3D in decor.find_children("*", "MeshInstance3D", false, false):
		if mi.mesh is SphereMesh and (mi.mesh as SphereMesh).radius >= 3.0:
			k += 1
			var r: float = (mi.mesh as SphereMesh).radius
			var ringed := mi.get_child_count() > 0
			var bv := _best_view(mi.global_position, r * (2.3 if ringed else 1.0))
			print("planet %d at %s r=%.1f rings=%s visible=%.2f" % [k, mi.global_position, r, ringed, bv[1]])
			if bv[1] > 0.0:
				await _iso(bv[0] + Vector3(0, 0.5, 0), "planet%d.png" % k)
	# Астероиды (24.09: неровные глыбы у полотна) — первые три.
	var n_rock := 0
	for rock: MeshInstance3D in decor.find_children("Asteroid*", "MeshInstance3D", false, false):
		n_rock += 1
		if n_rock <= 3:
			var bv := _best_view(rock.global_position, 2.0)
			await _iso(bv[0] + Vector3(0, 0.5, 0), "rock%d.png" % n_rock)
	print("rocks: %d" % n_rock)
	if OS.get_cmdline_user_args().has("--static"):
		get_tree().quit()
		return
	var shuttles := decor.find_children("space_shuttle*", "", false, false)
	if not shuttles.is_empty():
		var sh: Node3D = shuttles[0]
		var seen := 0
		var total := 0
		var bv: Array = [Vector3.INF, 0.0]
		for _i in 1800:
			total += 1
			bv = _best_view(sh.global_position + Vector3(0, 2.0, 0), 4.0)
			if bv[1] >= 0.4:
				seen += 1
				if seen == 1:
					await _iso(bv[0] + Vector3(0, 0.5, 0), "shuttle.png")
			await get_tree().process_frame
		print("shuttle visible (>=40%%) on %d%% of frames" % (seen * 100 / total))
	for _i in 6000:
		var found := decor.find_children("Comet*", "", false, false)
		var done := false
		for c: Node3D in found:
			var bv := _best_view(c.global_position, 2.0)
			if bv[1] >= 0.5:
				await _iso(bv[0] + Vector3(0, 0.5, 0), "comet.png")
				done = true
				break
		if done:
			break
		await get_tree().process_frame
	get_tree().quit()
