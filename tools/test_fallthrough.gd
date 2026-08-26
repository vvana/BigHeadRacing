extends Node3D
## Автотест «провалился под полотно»: жёсткий удар может продавить машину
## сквозь тонкий тримеш дороги, и раньше она ЕЗДИЛА ПОД АСФАЛЬТОМ — ни одна
## проверка возврата этого не ловила (вылет меряет расстояние в плане, под
## дорогой оно ~0). Теперь Main._check_recovery возвращает такую машину
## сразу. Стенд ставит машину под полотно и ждёт возврата НА дорогу.

var _main: Node3D
var _frame := 0
var _spot := 0.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	var car: Car = _main._car
	if _frame == 30:
		# Под полотно: на оси трассы, на 1.6 м ниже дороги (машина под
		# тримешем, колёсами на земле-обочине с её GROUND_DROP 1.2).
		_spot = curve.get_baked_length() * 0.4
		var road := curve.sample_baked(_spot)
		car.global_position = road + Vector3.DOWN * 1.6
		car.linear_velocity = Vector3.ZERO
		car.reset_track_offset()
		print("посадили под полотно: y=%.2f (дорога %.2f)"
				% [car.global_position.y, road.y])
	# Возврат мгновенный, но даём 1.5 с на кадры физики и падение на колёса.
	if _frame == 120:
		var road := curve.sample_baked(track.closest_offset_near(
				car.global_position, _spot))
		var above := car.global_position.y > road.y - 0.2
		var dist := track.distance_from_axis_at(
				car.global_position, car.track_offset)
		print("через 1.5 с: y=%.2f (дорога %.2f), до оси %.1f м"
				% [car.global_position.y, road.y, dist])
		var ok := above and dist < track.half_width_at_offset(car.track_offset)
		print("FALLTHROUGH TEST: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
