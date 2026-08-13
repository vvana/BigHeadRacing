extends Node3D
## Автотест подрыва: машине наносят смертельный урон и следят, чтобы она
## НЕ исчезала (visible всё время true) и вернулась в гонку.

var _main: Node3D
var _frame := 0
var _went_invisible := false
var _was_dead := false
var _hp_on_revive := -1.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame > 200:
		if not car.visible:
			_went_invisible = true
		if not car.alive:
			_was_dead = true
		elif _was_dead and _hp_on_revive < 0.0:
			# Первый кадр после возрождения: ИИ ещё не успел снова подстрелить.
			_hp_on_revive = car.hp
	match _frame:
		200:
			car.take_damage(999.0, Vector3.UP)
			print("blown up: hp=%.0f alive=%s" % [car.hp, car.alive])
		230:
			print("после взрыва: visible=%s alive=%s y=%.2f" % [
				car.visible, car.alive, car.global_position.y])
		360:  # ~2.6 c спустя — должна снова ехать
			var ok := car.visible and car.alive and not _went_invisible \
					and _was_dead and _hp_on_revive > 90.0
			print("EXPLOSION TEST: %s (visible=%s alive=%s hp_на_возрождении=%.0f, исчезала=%s)" % [
				"PASS" if ok else "FAIL", car.visible, car.alive,
				_hp_on_revive, _went_invisible])
			get_tree().quit(0 if ok else 1)
