extends Node3D
## Автотест ускорителей: ставим машину игрока за 12 м до первой плиты,
## давим газ — проехав по плите, машина обязана получить буст
## (_boost_time > 0), а её скорость — превысить обычный потолок max_speed.

var _main: Node3D
var _t := 0.0
var _placed := false
var _boost_seen := false
var _top_speed := 0.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(delta: float) -> void:
	_t += delta
	var car: Car = _main._cars[0]
	if not _placed:
		if not car.controls_enabled:
			return   # ждём отсчёт 3-2-1-GO
		var track: TrackBuilder = _main._track
		if track.boost_pad_offsets.is_empty():
			print("BOOST PAD TEST: FAIL (на трассе нет ускорителей)")
			get_tree().quit(1)
			return
		var length: float = track._curve.get_baked_length()
		var off: float = fposmod(track.boost_pad_offsets[0] - 12.0, length)
		var pos: Vector3 = track._curve.sample_baked(off)
		var ahead: Vector3 = track._curve.sample_baked(fmod(off + 3.0, length))
		var dir := (ahead - pos).normalized()
		car.global_transform = Transform3D(
				Basis.looking_at(dir), pos + Vector3(0, 0.62, 0))
		# Ходом: с места буст истекает раньше, чем машина доберётся до
		# обычного потолка, и превышение не увидеть.
		car.linear_velocity = dir * 25.0
		car.reset_speed_memory()
		Input.action_press("accelerate")
		_placed = true
		_t = 0.0
		return
	if car._boost_time > 0.0:
		_boost_seen = true
	if _boost_seen:
		_top_speed = maxf(_top_speed, car.linear_velocity.length())
	if _t < 6.0:
		return
	Input.action_release("accelerate")
	var ok := _boost_seen and _top_speed > car.max_speed + 1.0
	print("BOOST PAD TEST: %s (буст %s, максимум %.1f м/с при max_speed %.1f)" % [
			"PASS" if ok else "FAIL",
			"получен" if _boost_seen else "НЕ получен",
			_top_speed, car.max_speed])
	get_tree().quit(0 if ok else 1)
