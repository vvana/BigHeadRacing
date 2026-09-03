extends Node3D
## Стенд «машина едет ПОД дорогой» и «за бортом в космосе не падает»
## (жалобы 03.09). Ключ `--kind=<grass|sand|neon|space>` (по умолчанию space).
##
## 1) Машину ставим на землю-обочину ПОД полотном (GROUND_DROP 1.2 м: центр
##    кузова оказывается всего на ~0.6 м ниже оси). Прежняя проверка
##    Main._check_recovery ловила только y < дорога − 1.0 — стоящая на
##    подвеске машина под неё не попадала и ездила под асфальтом.
##    Ожидание: через 1.5 с машина снова НА дороге.
## 2) (только космос) машину ставим ЗА ограждением на уровне полотна:
##    она обязана ПАДАТЬ в пустоту (просесть глубже 6 м) и вернуться на
##    трассу автовозвратом.

var _main: Node3D
var _frame := 0
var _spot := 0.0
var _min_y := 1.0e9
var _kind := TrackBuilder.KIND_SPACE
var _ok1 := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kind="):
			_kind = a.trim_prefix("--kind=")
	GameState.track_kind = _kind
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _road_y(car: Car) -> float:
	var track: TrackBuilder = _main._track
	return track._curve.sample_baked(track.closest_offset_near(
			car.global_position, car.track_offset)).y


func _physics_process(_d: float) -> void:
	_frame += 1
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	var car: Car = _main._car
	if _frame == 40:
		print("на дороге (%s): центр на %+.2f м от оси"
				% [_kind, car.global_position.y - _road_y(car)])
		# Под полотно: на ось, центром на 0.8 м ниже дороги — колёса
		# встанут на землю-обочину (−1.2), кузов усядется на ~−0.6.
		_spot = curve.get_baked_length() * 0.4
		var road := curve.sample_baked(_spot)
		car.global_position = road + Vector3.DOWN * 0.8
		car.linear_velocity = Vector3.ZERO
		car.reset_track_offset()
		_min_y = 1.0e9
	if _frame > 40 and _frame <= 130:
		_min_y = minf(_min_y, car.global_position.y - _road_y(car))
	if _frame == 130:
		var rel := car.global_position.y - _road_y(car)
		var dist := track.distance_from_axis_at(
				car.global_position, car.track_offset)
		_ok1 = rel > -0.2 and dist < track.half_width_at_offset(car.track_offset)
		print("под полотном: минимум %+.2f м, через 1.5 с %+.2f м, до оси %.1f — %s"
				% [_min_y, rel, dist, "ok" if _ok1 else "FAIL (ездит под дорогой)"])
		if _kind != TrackBuilder.KIND_SPACE:
			print("UNDERROAD TEST: %s" % ("PASS" if _ok1 else "FAIL"))
			get_tree().quit(0 if _ok1 else 1)
			return
		# 2) За борт: 8 м за кромкой полотна, на уровне дороги.
		var off := curve.get_baked_length() * 0.55
		var road := curve.sample_baked(off)
		car.global_position = road + track.right_at_offset(off) \
				* (track.half_width_at_offset(off) + 8.0) + Vector3.UP * 0.6
		car.linear_velocity = Vector3.ZERO
		car.reset_track_offset()
		_min_y = 1.0e9
	if _frame > 130 and _frame <= 260:
		_min_y = minf(_min_y, car.global_position.y - _road_y(car))
	if _frame == 260:
		var rel := car.global_position.y - _road_y(car)
		var dist := track.distance_from_axis_at(
				car.global_position, car.track_offset)
		var fell := _min_y < -6.0
		var back := rel > -0.2 \
				and dist < track.half_width_at_offset(car.track_offset)
		print("за бортом: минимум %+.2f м (%s), через 2 с %+.2f м, до оси %.1f (%s)"
				% [_min_y, "упала" if fell else "НЕ ПАДАЕТ", rel, dist,
				"на трассе" if back else "НЕ ВЕРНУЛАСЬ"])
		var ok := _ok1 and fell and back
		print("UNDERROAD TEST: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
