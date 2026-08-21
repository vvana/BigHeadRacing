extends Node3D
## Телеметрия «фантомных» отбросов от ограждения: машина 60 с едет с
## газом и лёгким рулём В СТЕНУ (прижата к внешнему борту), считаем
## всплески скорости ОТ стены (отбросы к оси) и подскоки vy у стены.

var _main: Node3D
var _frame := 0
var _throws := 0        # отбросов внутрь > 2.5 м/с
var _hops := 0          # подскоков vy > 1.5 у стены
var _max_inward := 0.0
var _prev_inward := 0.0
var _wall_frames := 0
var _reversals := 0     # скорость вдоль трассы сменила знак у стены (|v|>4)
var _prev_along := 0.0
var _far_frames := 0    # кадры, когда при руле в стену машину ОТНЕСЛО > 2 м
var _dist_sum := 0.0


func _ready() -> void:
	seed(42)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame == 5:
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false  # и от автовозврата на трассу
			extra.weapon = -1
			extra.global_transform = Transform3D(Basis.IDENTITY,
					Vector3(110.0 + i * 6.0, 2.0, 110.0))
			extra.linear_velocity = Vector3.ZERO
		Input.action_press("accelerate")
	if _frame < 60 or not car.alive:
		return
	# Руль слегка к внешней стене (наружу от центра карты).
	var out := car.global_position
	out.y = 0.0
	out = out.normalized()
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	var into_sign := signf(fwd.normalized().signed_angle_to(out, Vector3.UP))
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	# Положительное рысканье = влево (steer_left).
	if into_sign > 0.0:
		Input.action_press("steer_left")
	else:
		Input.action_press("steer_right")

	# Полотно переменной ширины — грань стены берём в точке машины.
	var wall_face: float = _main._track.half_width_at_pos(car.global_position) 			- TrackBuilder.WALL_THICKNESS * 0.5
	var dist: float = _main._track.distance_from_axis(car.global_position)
	_dist_sum += dist
	if dist < wall_face - 2.0:
		_far_frames += 1
	var curve: Curve3D = _main._track._curve
	var coff := curve.get_closest_offset(car.global_position)
	var tangent: Vector3 = curve.sample_baked(
			fposmod(coff + 0.5, curve.get_baked_length())) 			- curve.sample_baked(coff)
	tangent.y = 0.0
	tangent = tangent.normalized()
	var along := car.linear_velocity.dot(tangent)
	var near_wall: bool = car._touching_wall() or car._wall_align_time > 0.0
	if near_wall:
		_wall_frames += 1
		var inward := -car.linear_velocity.dot(out)
		_max_inward = maxf(_max_inward, inward)
		if inward > 2.5 and _prev_inward <= 2.5:
			_throws += 1
			print("THROW f=%d inward=%.2f pos=%s" % [
					_frame, inward, car.global_position])
		if car.linear_velocity.y > 1.5:
			_hops += 1
		if absf(along) > 4.0 and absf(_prev_along) > 4.0 				and signf(along) != signf(_prev_along):
			_reversals += 1
			print("REVERSAL f=%d along=%.1f prev=%.1f pos=%s" % [
					_frame, along, _prev_along, car.global_position])
		_prev_inward = inward
	_prev_along = along
	if _frame >= 60 * 60:
		print("WALLGHOST: throws=%d hops=%d rev=%d max_inward=%.2f wall_frames=%d far_frames=%d avg_dist=%.2f" % [
				_throws, _hops, _reversals, _max_inward, _wall_frames, _far_frames,
				_dist_sum / (_frame - 60)])
		get_tree().quit(0)
