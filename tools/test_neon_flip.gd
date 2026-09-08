extends Node3D
## Автотест 07.09: «после переворота и возврата на колёса пятно неона
## остаётся позади и сбоку от машины» + «скорлупа заморозки едет отдельно
## от машины». Машину с неоном крутим кувырком 60 кадров, ставим обратно
## на колёса и смотрим, где пятно (Underglow/Glow): его локальное
## смещение в модели должно остаться штатным, а само пятно — под машиной
## на дороге. Заодно проверяем, что скорлупа льда стоит там же, где
## нарисован кузов (картинка машины, а не тело).
## Запуск: godot --headless --path . res://tools/TestNeonFlip.tscn

var _main: Node3D
var _car: Car
var _frame := 0
var _spin := 0.0
var _home := Transform3D.IDENTITY


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(delta: float) -> void:
	_frame += 1
	if _frame == 30:
		_car = _main._cars[0]
		for c in _main._cars:
			c.controls_enabled = false
		_main._set_car_model(_car, "vz05r_blue-nred")
		_car.apply_freeze(5.0)
		_home = _car.global_transform
		return
	if _car == null:
		return
	if _frame > 40 and _frame <= 100:
		# Кувырок: крен и тангаж растут, машина висит над дорогой.
		_spin += delta * 6.0
		var b := Basis(Vector3.FORWARD, _spin) * Basis(Vector3.RIGHT, _spin * 0.7)
		_car.global_transform = Transform3D(_home.basis * b,
				_home.origin + Vector3.UP * 1.2)
		_car.linear_velocity = Vector3.ZERO
		_car.angular_velocity = Vector3.ZERO
	elif _frame > 100 and _frame <= 110:
		_car.global_transform = _home
		_car.linear_velocity = Vector3.ZERO
		_car.angular_velocity = Vector3.ZERO
	if _frame == 160:
		var glow: Node3D = _car.get_node_or_null("CarModel/Underglow/Glow")
		var ok := glow != null
		var msg := ""
		if ok:
			var local_xz := Vector2(glow.position.x, glow.position.z).length()
			var d := glow.global_position - _car.global_position
			var off := Vector2(d.x, d.z).length()
			msg = "лок. сдвиг %.2f м, от центра машины %.2f м, высота %.2f" % [
					local_xz, off, d.y]
			ok = local_xz < 0.05 and off < 0.15 and d.y > -1.0 and d.y < 0.2
		else:
			msg = "нет узла Underglow/Glow"
		# Скорлупа льда — на картинке машины (модель едет по xf), а не на теле.
		var ice: Node3D = _car.get_node_or_null("IceShell")
		var model: Node3D = _car.get_node_or_null("CarModel")
		var ice_ok := ice != null and model != null and ice.visible
		if ice_ok:
			var want := model.global_transform * _car._vis_base.affine_inverse()
			var gap := ice.global_position.distance_to(
					want.origin + want.basis.y * 0.45)
			msg += "; лёд от кузова %.3f м" % gap
			ice_ok = gap < 0.02
		else:
			msg += "; скорлупы льда нет или не видна"
		print("NEONFLIP TEST: %s (%s)" % ["PASS" if ok and ice_ok else "FAIL", msg])
		get_tree().quit(0 if ok and ice_ok else 1)
