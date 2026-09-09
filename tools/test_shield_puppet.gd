extends Node3D
## Стенд: ЩИТ II/III У МАРИОНЕТКИ (машины живого игрока на сервере) БЬЁТ
## ТАРАНЯЩЕГО БОТА. Жалоба 09.09: «красная сфера щита не убивает
## противников при касании, а жёлтая не тормозит» — по сети, где держатель
## щита на сервере марионетка. Причина: бот, наехав на марионетку, сам
## позиционно выдавливал себя из неё в _bounce_off_cars, и проверка
## держателя (_shield_sweep) капсулы уже не пересекающимися не ловила.
## Теперь касание судится по СФЕРЕ (SHIELD_TOUCH_GAP), из _tick_effects
## любого держателя. Держатель тут — марионетка в оффлайн-сцене (Net не
## клиент, sweep идёт), бот едет в неё с ускорением.
## Запуск: godot --headless --path . res://tools/TestShieldPuppet.tscn

var _main: Node3D
var _frame := 0
var _ok := {}
var _holder: Car
var _ram: Car
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD


func _ready() -> void:
	seed(5)
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


func _check(name: String, cond: bool, note := "") -> void:
	_ok[name] = cond
	if not cond and note != "":
		print("  [%s] %s" % [name, note])


func _physics_process(_d: float) -> void:
	_frame += 1
	var cars: Array = _main._cars
	if cars.size() < 4:
		return
	match _frame:
		30:
			for c: Car in cars:
				c.controls_enabled = false
				c.alive = false
				c.global_position = Vector3(120.0, 2.0, 120.0 + 10.0 * cars.find(c))
			_holder = cars[1]
			_ram = cars[2]
			var track: TrackBuilder = _main._track
			_base = track._curve.sample_baked(40.0)
			_tan = (track._curve.sample_baked(41.0) - _base).normalized()
			# Держатель — марионетка со щитом III, стоит на трассе.
			_place(_holder, _base, _tan)
			_holder.net_make_puppet()
			var rot: Quaternion = _holder.global_transform.basis.get_rotation_quaternion()
			_holder.net_apply_snapshot(_holder.global_position, rot, Vector3.ZERO, 10.0)
			_holder._shield_level = 3
			_holder._shield_time = 8.0
			# Бот таранит сзади с ускорением (как настоящий контакт в гонке).
			_place(_ram, _base - _tan * 9.0, _tan)
			_ram.linear_velocity = _tan * 10.0
		60:
			_check("держатель — марионетка под красным щитом",
					_holder.net_role == Car.NetRole.PUPPET
					and _holder.shield_level() == 3)
		130:
			_check("щит III у марионетки: таранивший бот уничтожен", _ram.is_ghost(),
					"gap %.2f alive=%s pos %s" % [_holder._capsule_gap(_ram),
					_ram.alive, _ram.global_position])
			_check("щит III: держатель цел", _holder.alive)
			# ЖЁЛТЫЙ (II): бот замедляется, но жив.
			_ram = cars[3]
			_holder._shield_level = 2
			_holder._shield_time = 8.0
			_place(_ram, _base - _tan * 9.0, _tan)
			_ram.linear_velocity = _tan * 10.0
		200:
			_check("щит II у марионетки: таранивший бот замедлен",
					_ram.oil_slow_left() > 0.0
					or _ram.status_icon_kind() == Weapons.SHIELD,
					"slow %.2f gap %.2f" % [_ram.oil_slow_left(),
					_holder._capsule_gap(_ram)])
			_check("щит II: бот жив", _ram.alive and not _ram.is_ghost())
			var all_ok := true
			for k in _ok:
				print("  %s  %s" % ["ok  " if _ok[k] else "FAIL", k])
				all_ok = all_ok and bool(_ok[k])
			print("SHIELD PUPPET TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
