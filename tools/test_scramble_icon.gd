extends Node3D
## Стенд значка глушилки (31.08): «при получении эффекта оглушения игрок
## должен видеть над машинкой, что действует эффект, как при магните».
## Проверяем: после apply_scramble над машиной ПОЯВЛЯЕТСЯ значок глушилки
## (Sprite3D с текстурой) и ДЕРЖИТСЯ всё время эффекта, а не пару кадров.

var _main: Node3D
var _frame := 0
var _car: Car
var _ok := {}


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	match _frame:
		20:
			_car = _main._cars[0]
			_car.apply_scramble(ScrambleWave.SCRAMBLE_TIME)
		30:
			_ok["вид значка = глушилка"] = \
					_car.status_icon_kind() == Weapons.SCRAMBLE
			var icon := _car.get_node_or_null("StatusIcon") as Sprite3D
			_ok["значок виден"] = icon != null and icon.visible \
					and icon.texture != null
		260:
			# 4 c после попадания: эффект (5 c) ещё идёт — значок обязан
			# висеть до конца эффекта, как у магнита на время его действия.
			var icon := _car.get_node_or_null("StatusIcon") as Sprite3D
			_ok["значок держится весь эффект"] = \
					_car.status_icon_kind() == Weapons.SCRAMBLE \
					and icon != null and icon.visible
			var all_ok := true
			for k: String in _ok:
				if not _ok[k]:
					all_ok = false
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
			print("SCRAMBLE ICON TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
