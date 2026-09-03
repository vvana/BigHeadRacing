extends Node3D
## Стенд подбора бокса ОФФЛАЙН (Area3D, жалоба 03.09 «часто проезжаешь
## сквозь бонус, не собирая его»). Машина игрока разгоняется по прямой и
## проезжает бокс: 1) насквозь на 40 м/с; 2) по касательной — куб на 1.3 м
## сбоку от линии хода (задевает углом); 3) «призраком» сразу после
## взрыва (раньше призрак боксы НЕ подбирал — 2 с после возврата на
## трассу кубы проезжались насквозь); 4) с оружием в руках — бокс обязан
## выдать ДРУГОЕ (без смены значка подбор выглядел как промах).

var _main: Node3D
var _car: Car
var _box: WeaponBox
var _frame := 0
var _phase := -1
var _phase_frame := 0
var _ok := {}
var _dir := Vector3.FORWARD
var _off := 0.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


## Поставить машину в начало самой длинной прямой (кроме стартовой) и
## разогнать вдоль оси; бокс — на 18 м впереди со сдвигом lateral.
func _start_phase(n: int, speed: float, lateral: float) -> void:
	_phase = n
	_phase_frame = 0
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var pool: Array = track._straights.slice(1)
	pool.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return (a.y - a.x) > (b.y - b.x))
	var seg: Vector2 = pool[0]
	_off = length * (seg.x + (seg.y - seg.x) * 0.25)
	var pos := curve.sample_baked(_off)
	var ahead := curve.sample_baked(fposmod(_off + 3.0, length))
	_dir = (ahead - pos).normalized()
	_car.global_transform = Transform3D(Basis.looking_at(_dir),
			pos + Vector3.UP * 0.62)
	_car.linear_velocity = _dir * speed
	_car.angular_velocity = Vector3.ZERO
	_car.reset_track_offset()
	if _box != null:
		_box.queue_free()
	_box = WeaponBox.new()
	_main.add_child(_box)
	_box.global_position = curve.sample_baked(fposmod(_off + 18.0, length)) \
			+ track.right_at_offset(_off) * lateral + Vector3.UP * 0.85


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_car = _main._cars[0]
		for i in _main._cars.size():
			var c: Car = _main._cars[i]
			c.controls_enabled = false
			if i > 0:
				c.alive = false
				c.global_position = Vector3(150, 2, 150 + i * 8)
		_car.weapon = Weapons.MINE
		_start_phase(0, 40.0, 0.0)
		return
	if _phase < 0:
		return
	_phase_frame += 1
	# Держим скорость: без газа машина тормозит, а нам нужен полный ход.
	if _phase_frame < 40:
		var v := _car.linear_velocity
		var want := 40.0 if _phase != 2 else 30.0
		var h := Vector3(v.x, 0, v.z)
		if h.length() < want - 1.0:
			_car.linear_velocity = _dir * want + Vector3.UP * v.y
	if _phase_frame == 60:
		var got: bool = _box._next_pickup.has(_car.get_instance_id())
		match _phase:
			0:
				_ok["насквозь 40 м/с"] = got
				_ok["другое оружие, не мина"] = got and _car.weapon != Weapons.MINE \
						and _car.weapon >= 0
				print("фаза 0: выдан=%s, оружие=%d" % [str(got), _car.weapon])
				_start_phase(1, 40.0, 1.3)
			1:
				_ok["по касательной 1.3 м"] = got
				print("фаза 1: выдан=%s" % str(got))
				_start_phase(2, 30.0, 0.0)
				_car._start_ghost()
				_ok["призрак включён"] = _car.is_ghost()
			2:
				_ok["призраком"] = got
				print("фаза 2: выдан=%s (призрак=%s)" % [str(got), str(_car.is_ghost())])
				var all_ok := true
				for k: String in _ok:
					if not _ok[k]:
						all_ok = false
					print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
				print("BOXOFFLINE TEST: %s" % ("PASS" if all_ok else "FAIL"))
				get_tree().quit(0 if all_ok else 1)
