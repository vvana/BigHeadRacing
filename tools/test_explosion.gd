extends Node3D
## Автотест уничтожения (ракета/лазер/авиаудар): destroy() тут же ставит
## машину на трассу с нулевой скоростью и делает «призраком» — она мигает,
## НЕ сталкивается с другими машинами, но может ехать; после ghost_time
## коллизии и видимость полностью возвращаются.

var _main: Node3D
var _frame := 0
var _blinked := false          # видимость хоть раз гасла (моргание)
var _speed_after := -1.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame > 200 and not car.visible:
		_blinked = true
	match _frame:
		200:
			car.linear_velocity = -car.global_transform.basis.z * 20.0
			car.destroy()
			_speed_after = car.linear_velocity.length()
			var ghost_ok := car.is_ghost() and car.collision_layer == 0 \
					and (car.collision_mask & 0b100) == 0
			print("destroy: v=%.2f ghost=%s слои_сняты=%s dist=%.2f" % [
				_speed_after, car.is_ghost(), ghost_ok,
				_main._track.distance_from_axis(car.global_position)])
			if not ghost_ok or _speed_after > 0.01:
				print("EXPLOSION TEST: FAIL (призрак не включился или скорость не обнулилась)")
				get_tree().quit(1)
		260:
			# Середина призрака: машина может разгоняться (ИИ уже газует).
			print("призрак: ghost=%s v=%.1f мигала=%s" % [
				car.is_ghost(), car.linear_velocity.length(), _blinked])
		380:  # 3 c спустя (ghost_time 2.0) — всё как раньше
			var back_ok: bool = not car.is_ghost() and car.visible \
					and car.collision_layer == 0b100 \
					and car.collision_mask == 0b111
			var on_track: bool = _main._track.distance_from_axis(
					car.global_position) < TrackBuilder.TRACK_HALF_WIDTH
			var ok: bool = back_ok and on_track and _blinked and car.alive
			print("EXPLOSION TEST: %s (вернулась=%s на_трассе=%s мигала=%s)" % [
				"PASS" if ok else "FAIL", back_ok, on_track, _blinked])
			get_tree().quit(0 if ok else 1)
