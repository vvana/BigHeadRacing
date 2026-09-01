extends Node3D
## Стенд «сквозь оружие» (31.08): «машины иногда проезжают сквозь мины и
## лазер не уничтожаясь». Дыры, все закрыты:
## 1) МИНА: задержка взведения 0.7 c была ОБЩЕЙ — соперник, ехавший
##    впритык за сбросившим, проскакивал свежую мину безнаказанно.
##    Теперь окно защищает только хозяина: чужого свежая мина рвёт сразу.
## 2) ЛАЗЕР: урон считался ОДИН кадр выстрела, а луч виден ~полсекунды и
##    едет с носом стрелявшего — машина, ВЪЕХАВШАЯ в видимый луч, была
##    цела. Теперь коридор перепроверяется каждый тик жизни луча.
## 3) ГЛУШИЛКА: мерялся только ЦЕНТР машины — кольцо, чиркнувшее по
##    борту, не оглушало («цепляешь краем — не всегда оглушает»).
##    Теперь три пробы по кузову с полушириной (ScrambleWave.BODY_R).
## 4) СТЕНА: куча машин продавливала кузов сквозь тонкое ограждение —
##    Car._clamp_inside_walls возвращает центр за грань; честно
##    приземлившихся СНАРУЖИ (далеко за стеной) кламп не трогает.
## На старом коде проверки 1-4 — честный FAIL.

var _main: Node3D
var _frame := 0
var _mine_victim: Car
var _laser_victim: Car
var _wave_victim: Car
var _shooter: Car
var _half := 0.0
var _ok := {}


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	match _frame:
		20:
			# 1) Свежая мина (0 c от сброса) под ЧУЖОЙ машиной.
			_mine_victim = _main._cars[1]
			var mine := Mine.new()
			mine.dropper = _main._cars[2]
			_main.add_child(mine)
			mine.global_position = _mine_victim.global_position \
					+ Vector3.UP * 0.2
		30:
			# 10 тиков (~0.17 c) — куда меньше прежних 0.7 c взведения.
			_ok["свежая мина рвёт чужого сразу"] = _mine_victim.is_ghost()
		40:
			# 2) Лазер: жертва в момент выстрела СБОКУ от коридора (8 м).
			_shooter = _main._cars[0]
			_laser_victim = _main._cars[3] if _main._cars.size() > 3 \
					else _main._cars[2]
			var fwd := -_shooter.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var right := fwd.cross(Vector3.UP)
			_laser_victim.global_position = _shooter.global_position \
					+ fwd * 20.0 + right * 8.0
			_laser_victim.linear_velocity = Vector3.ZERO
			_shooter.weapon = Weapons.LASER
			_shooter.use_weapon()
		42:
			_ok["сбоку от луча цела"] = not _laser_victim.is_ghost()
		46:
			# ~0.1 c от выстрела — луч (0.55 c) ещё жив; жертва «въезжает»
			# в его коридор.
			var fwd := -_shooter.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			_laser_victim.global_position = _shooter.global_position \
					+ fwd * 20.0
			_laser_victim.linear_velocity = Vector3.ZERO
		52:
			_ok["въехала в живой луч — гибнет"] = _laser_victim.is_ghost()
		60:
			# 3) Глушилка ЧИРКАЕТ КРАЕМ: жертва в 15 м впереди и в 3.2 м
			# сбоку от пути волны — центр дальше HIT_R (2.6), но кольцо
			# задевает кузов (2.6 + BODY_R = 3.5). Ставим ОТ ОСИ трассы:
			# волна доворачивает вдоль полотна.
			var curve: Curve3D = _main._track._curve
			var off: float = curve.get_baked_length() * 0.06
			var base: Vector3 = curve.sample_baked(off)
			var tan_v: Vector3 = curve.sample_baked(off + 1.0) - base
			tan_v.y = 0.0
			tan_v = tan_v.normalized()
			var right := tan_v.cross(Vector3.UP)
			_shooter.global_transform = Transform3D(
					Basis.looking_at(tan_v), base + Vector3.UP * 0.62)
			_shooter.linear_velocity = Vector3.ZERO
			_wave_victim = _main._cars[2]
			_wave_victim.global_transform = Transform3D(
					Basis.looking_at(tan_v),
					base + tan_v * 15.0 + right * 3.2 + Vector3.UP * 0.62)
			_wave_victim.linear_velocity = Vector3.ZERO
			_shooter.weapon = Weapons.SCRAMBLE
			_shooter.use_weapon()
		95:
			# Волна прошла 15 м (50 м/с) с запасом.
			_ok["волна цепляет краем кузов"] = _wave_victim.scramble_left() > 4.0
			# 4) СТЕНА, продавливание: центр за внутренней гранью (на 1 м) —
			# так выглядит кадр, когда куча машин продавила кузов в стену.
			_half = _main._track.half_width_at_offset(_shooter.track_offset)
			var out := _outward_of(_shooter)
			_shooter.global_position += out \
					* (_half - TrackBuilder.WALL_THICKNESS * 0.5 + 1.0
					- _main._track.distance_from_axis_at(
							_shooter.global_position, _shooter.track_offset))
			_shooter.linear_velocity = out * 5.0   # и давят дальше наружу
		110:
			var dist: float = _main._track.distance_from_axis_at(
					_shooter.global_position, _shooter.track_offset)
			_ok["продавленного вернуло за стену"] = dist < _half
			if dist >= _half:
				print("  [стена] dist=%.2f half=%.2f" % [dist, _half])
			# Приземлился ДАЛЕКО снаружи — кламп не трогает (вернёт
			# автовозврат по таймеру, тянуть сквозь стену нельзя).
			var out := _outward_of(_mine_victim)
			_mine_victim._end_ghost()
			_mine_victim.global_position = \
					_main._track._curve.sample_baked(_mine_victim.track_offset) \
					+ out * (_half + 5.0) + Vector3.UP * 0.62
			_mine_victim.linear_velocity = Vector3.ZERO
		125:
			var dist: float = _main._track.distance_from_axis_at(
					_mine_victim.global_position, _mine_victim.track_offset)
			_ok["упавшего снаружи не тянет сквозь стену"] = dist > _half + 3.0
			var all_ok := true
			for k: String in _ok:
				if not _ok[k]:
					all_ok = false
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
			print("WEAPON PIERCE TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)


## Горизонтальный «вбок от оси» в точке машины: от её смещения, а для
## машины на самой оси — перпендикуляр к касательной (не глобальный RIGHT:
## тот может смотреть ВДОЛЬ дороги, и точка «снаружи» ляжет на полотно).
func _outward_of(car: Car) -> Vector3:
	var curve: Curve3D = _main._track._curve
	var here: Vector3 = curve.sample_baked(car.track_offset)
	var lat := car.global_position - here
	lat.y = 0.0
	if lat.length() > 0.5:
		return lat.normalized()
	var tan_v: Vector3 = curve.sample_baked(fposmod(
			car.track_offset + 1.0, curve.get_baked_length())) - here
	tan_v.y = 0.0
	return tan_v.normalized().cross(Vector3.UP)
