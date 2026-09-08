extends Node3D
## Автотест 07.09 «моя ракета пролетела сквозь машину противника». На
## сервере машина живого игрока — сглаженная марионетка: в повороте курс
## ТЕЛА отстаёт от курса, который доложил владелец (сырой снимок). Выстрел
## считался по телу — ракета уходила в сторону от того, куда целился игрок.
## Сценарий: тело марионетки развёрнуто на 12° от курса снимка, жертва
## стоит в 20 м ровно по курсу СНИМКА (по телу — промах на ~4 м).
## Ждём попадания: выстрел идёт от true_position/true_forward.

const LAG := 0.2
const DIST := 20.0
const OFF_DEG := 12.0

var _main: Node3D
var _shooter: Car
var _victim: Car
var _frame := 0
var _aim := Vector3.FORWARD
var _snap_pos := Vector3.ZERO
var _snap_rot := Quaternion.IDENTITY


func _ready() -> void:
	Net.port = 29983
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_shooter = _main._cars[0]
		_victim = _main._cars[1]
		for i in _main._cars.size():
			var c: Car = _main._cars[i]
			c.controls_enabled = false
			if i > 1:
				c.alive = false
				c.global_position = Vector3(150, 2, 150 + i * 8)
		_shooter.net_make_puppet()
		_shooter.net_client_lag = LAG
		var body_fwd: Vector3 = -_shooter.global_transform.basis.z
		body_fwd.y = 0.0
		body_fwd = body_fwd.normalized()
		# Курс снимка — на 12° левее курса тела.
		_aim = body_fwd.rotated(Vector3.UP, deg_to_rad(OFF_DEG))
		_snap_pos = _shooter.global_position
		_snap_rot = Quaternion(Basis.looking_at(_aim))
		_victim.global_transform = Transform3D(Basis.looking_at(_aim),
				_snap_pos + _aim * DIST)
		_victim.linear_velocity = Vector3.ZERO
		return
	if _shooter == null:
		return
	if _frame < 90:
		_victim.linear_velocity = Vector3.ZERO
	if _frame == 60:
		# Снимок владельца: то же место, курс на жертву (первый снимок ставит
		# тело ровно по нему).
		_shooter.net_apply_snapshot(_snap_pos, _snap_rot, Vector3.ZERO, 5.0)
		return
	if _frame == 90:
		# Тело марионетки «не успело»: разворачиваем его на 12° от курса
		# снимка (как в настоящем повороте, где подтяжка отстаёт) и стреляем.
		_shooter.global_transform = Transform3D(
				Basis.looking_at(_aim.rotated(Vector3.UP, -deg_to_rad(OFF_DEG))),
				_snap_pos)
		var body_fwd: Vector3 = -_shooter.global_transform.basis.z
		body_fwd.y = 0.0
		var miss := (_victim.global_position - _shooter.global_position) 				.cross(body_fwd.normalized()).length()
		print("[aim] по курсу тела промах %.1f м, снимок смотрит на жертву" % miss)
		_shooter.weapon = Weapons.ROCKET
		_shooter.use_weapon()
		return
	if _frame == 130:
		var hit := not _victim.alive or _victim.is_ghost()
		print("ROCKETAIM TEST: %s" % ("PASS" if hit
				else "FAIL — ракета ушла по курсу тела марионетки, мимо жертвы"))
		get_tree().quit(0 if hit else 1)
