extends Node3D
## Автотест правок магнита (жалобы 31.08):
##   1) «несколько машин применили — выкидывает с трассы с огромной силой»:
##      повторные рывки по одной и той же машине СЛАБЕЮТ (Car.magnet_wear);
##   2) «магнитит куда-то за пределы трассы, где никого нет»: магнит
##      по-прежнему достаёт ВСЮ ТРАССУ (так хочет игрок), но дальнего
##      волочёт ВДОЛЬ ПОЛОТНА, а не по прямой через местность
##      (Car._magnet_pull_dir);
##   3) и не выдёргивает с полотна: у края рывок разворачивается ВДОЛЬ
##      трассы (Car._magnet_guard), а не в сторону от неё.
## На старом коде падают все три: рывок был одинаково полным сколько угодно
## раз и тянул строго по прямой к магниту.

var _main: Node3D
var _frame := 0
var _ok := {}
var _attacker: Car
var _victim: Car
var _far: Car
var _edge: Car
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD
var _out := Vector3.RIGHT   # наружная нормаль трассы в точке _base
var _far_tan := Vector3.FORWARD  # касательная трассы у дальней машины
var _pull := [0.0, 0.0, 0.0]


func _ready() -> void:
	seed(11)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _place(car: Car, pos: Vector3, look: Vector3) -> void:
	car.alive = true
	car.global_transform = Transform3D(
			Basis.looking_at(look), pos + Vector3.UP * 0.62)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	car.reset_track_offset()


func _park(car: Car) -> void:
	car.alive = false
	car.global_transform = Transform3D(Basis.IDENTITY,
			Vector3(130.0, 2.0, 130.0) + Vector3.RIGHT * randf_range(0, 20))
	car.linear_velocity = Vector3.ZERO


## Один залп магнита от _attacker.
func _zap() -> void:
	_attacker.weapon = Weapons.MAGNET
	_attacker.use_weapon()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame < 160:
		return
	match _frame:
		160:
			var curve: Curve3D = _main._track._curve
			var off: float = curve.get_baked_length() * 0.06
			_base = curve.sample_baked(off)
			_tan = curve.sample_baked(off + 1.0) - _base
			_tan.y = 0.0
			_tan = _tan.normalized()
			# Наружу — от оси кольца к внешнему борту.
			_out = _tan.cross(Vector3.UP).normalized()
			if (_base + _out).length() < _base.length():
				_out = -_out
			for c: Car in _main._cars:
				c.controls_enabled = false
				c.weapon = -1
			_attacker = _main._cars[0]
			_victim = _main._cars[1]
			_far = _main._cars[2]
			_edge = _main._cars[3]
			for i in range(4, _main._cars.size()):
				_park(_main._cars[i])
			_place(_attacker, _base, _tan)
			# Жертва ПОЗАДИ (магнит тянет её вперёд): впередиедущим он ещё и
			# режет скорость, а это замер бы путало.
			_place(_victim, _base - _tan * 10.0, _tan)
			# Дальняя — в 70 м ПОЗАДИ ПО КРИВОЙ (на другом участке кольца):
			# прямая к магниту там уже уходит с полотна, и тянуть жертву
			# обязано вдоль трассы — вперёд по разметке.
			var flen := curve.get_baked_length()
			var fp := curve.sample_baked(fposmod(off - 70.0, flen))
			_far_tan = curve.sample_baked(fposmod(off - 69.0, flen)) - fp
			_far_tan.y = 0.0
			_far_tan = _far_tan.normalized()
			_place(_far, fp, _far_tan)
			_park(_edge)
		161:
			_zap()
		162:
			_pull[0] = _victim.linear_velocity.dot(_tan)
			# Дальняя: магнит достаёт (рывок есть), но тянет ВДОЛЬ трассы —
			# вперёд по разметке, к магниту, а не по прямой через местность.
			var fv := _far.linear_velocity
			fv.y = 0.0
			var f_along := fv.dot(_far_tan)
			var f_side := (fv - _far_tan * f_along).length()
			_ok["дальнюю магнит достаёт"] = f_along > 1.0
			_ok["дальнюю тянет вдоль трассы"] = f_along > f_side * 2.0
			_ok["дальнюю тянет слабее ближней"] = f_along < _pull[0] * 0.7
			print("  [дальняя] вдоль %.2f, поперёк %.2f м/с (по прямой %.0f м)"
					% [f_along, f_side,
					_base.distance_to(_far.global_position)])
			_place(_victim, _base - _tan * 10.0, _tan)
			_zap()
		163:
			_pull[1] = _victim.linear_velocity.dot(_tan)
			_place(_victim, _base - _tan * 10.0, _tan)
			_zap()
		164:
			_pull[2] = _victim.linear_velocity.dot(_tan)
			_ok["первый рывок сильный"] = _pull[0] > 8.0
			_ok["второй слабее первого"] = _pull[1] < _pull[0] * 0.75
			_ok["третий слабее второго"] = _pull[2] < _pull[1] * 0.9
			print("  [сила рывков] %.1f -> %.1f -> %.1f м/с"
					% [_pull[0], _pull[1], _pull[2]])
			# Фаза КРАЙ ПОЛОТНА: жертва у внешнего борта, магнит — снаружи
			# трассы и наискось вперёд. Рывок «к магниту» уводил бы её за
			# ограждение; после правки наружу тянуть не должно.
			var hw: float = _main._track.half_width_at_pos(_base)
			_place(_edge, _base + _out * (hw - 1.2), _tan)
			_place(_attacker, _base + _out * (hw + 7.0) + _tan * 7.0, _tan)
		166:
			_zap()
		167:
			var v := _edge.linear_velocity
			var outward := v.dot(_out)
			var along := v.dot(_tan)
			_ok["у края наружу не тянет"] = outward < 1.5
			_ok["у края тянет вдоль трассы"] = along > 2.0
			print("  [край] наружу %.2f, вдоль %.2f м/с" % [outward, along])
			var all_ok := true
			for k: String in _ok:
				if not _ok[k]:
					all_ok = false
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
			print("MAGNET TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
