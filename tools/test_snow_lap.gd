extends Node3D
## Автотест ЗИМНЕЙ трассы (TrackBuilder.KIND_SNOW, 15.09).
## ИИ 60 с накатывают круги по снегу — худший должен проехать больше
## полукруга (как TestLap/TestSandLap/TestNeonLap): сцепление на снегу
## ниже (SNOW_GRIP), и боты обязаны с этим справляться. Заодно: трасса
## действительно зимняя (kind, стены есть, множитель сцепления < 1,
## снегопад построен), а у машин НЕТ фар (день).

var _main: Node3D
var _t := 0.0
var _next_log := 0.0


func _ready() -> void:
	GameState.track_kind = TrackBuilder.KIND_SNOW
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= _next_log:
		_next_log += 10.0
		var progs: Array[String] = []
		for i in _main._progress.size():
			progs.append("%.0f" % _main._progress[i])
		print("t=%.0f progress: %s" % [_t, ", ".join(progs)])
	if _t < 60.0:
		return
	var track: TrackBuilder = _main._track
	if track.kind != TrackBuilder.KIND_SNOW or not track.has_walls \
			or track.get_node_or_null("Walls") == null \
			or track.road_grip() >= 1.0:
		print("SNOW LAP TEST: FAIL (трасса не зимняя, нет стен или сцепление обычное)")
		get_tree().quit(1)
		return
	var length: float = track._curve.get_baked_length()
	var worst := 1e9
	for i in range(1, _main._progress.size()):
		worst = minf(worst, _main._progress[i])
	var lap_ok := worst > length * 0.5
	var snow_ok: bool = _main._snowfall != null and _main._snowfall.emitting
	var lights := 0
	for car: Car in _main._cars:
		lights += _count_spots(car)
	var decor: Node = track.get_node_or_null("Decor")
	var firs := 0
	var houses := 0
	if decor != null:
		for n: Node in decor.get_children():
			# По имени узла не посчитать: дубли имён Godot переименовывает в
			# «Node3D». Узнаём пропс по пути ресурса его первого меша
			# («…/fir_winter_large.fbx::…»).
			var mi: MeshInstance3D = n if n is MeshInstance3D else null
			if mi == null:
				var found := n.find_children("*", "MeshInstance3D", true, false)
				if not found.is_empty():
					mi = found[0]
			if mi == null or mi.mesh == null:
				continue
			var src := mi.mesh.resource_path.to_lower()
			if src.contains("fir_winter"):
				firs += 1
			elif src.contains("winter_house"):
				houses += 1
	var decor_ok := firs >= 60 and houses == 3
	print("  худший ИИ проехал %.0f м (круг %.0f м) — %s; снегопад %s; фар %d; елей %d, домов %d — %s" % [
		worst, length, "ok" if lap_ok else "FAIL", str(snow_ok), lights,
		firs, houses, "ok" if decor_ok else "FAIL"])
	var ok: bool = lap_ok and snow_ok and lights == 0 and decor_ok
	print("SNOW LAP TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _count_spots(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is SpotLight3D:
			n += 1
		n += _count_spots(child)
	return n
