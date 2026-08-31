extends Node3D
## Стенд «сквозь оружие» (31.08): «машины иногда проезжают сквозь мины и
## лазер не уничтожаясь». Две дыры, обе закрыты:
## 1) МИНА: задержка взведения 0.7 c была ОБЩЕЙ — соперник, ехавший
##    впритык за сбросившим, проскакивал свежую мину безнаказанно.
##    Теперь окно защищает только хозяина: чужого свежая мина рвёт сразу.
## 2) ЛАЗЕР: урон считался ОДИН кадр выстрела, а луч виден ~полсекунды и
##    едет с носом стрелявшего — машина, ВЪЕХАВШАЯ в видимый луч, была
##    цела. Теперь коридор перепроверяется каждый тик жизни луча.
## На старом коде обе проверки — честный FAIL.

var _main: Node3D
var _frame := 0
var _mine_victim: Car
var _laser_victim: Car
var _shooter: Car
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
			var all_ok := true
			for k: String in _ok:
				if not _ok[k]:
					all_ok = false
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
			print("WEAPON PIERCE TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
