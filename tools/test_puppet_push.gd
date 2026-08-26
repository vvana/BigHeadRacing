extends Node3D
## Автотест толчка от МАРИОНЕТКИ. Марионетка для решателя не твёрдая
## (net_make_puppet ставит исключения): телепортируясь к снимку в чужой
## кузов, раньше она заставляла решатель ВЫДАВЛИВАТЬ машину диким разовым
## импульсом — «врезаются в меня на рывке, вылетаю за трассу». Теперь
## толчок даёт только своя логика (_bounce_off_cars, сближение капсул).
## Проверяем обе стороны медали:
##   1) толчок ЕСТЬ — прижатую марионетку машина не игнорирует, их
##      расталкивает в стороны;
##   2) толчок ОГРАНИЧЕН — скорость жертвы никогда не превышает разумного
##      аркадного рикошета, каким бы диким ни был телепорт марионетки.

const PUSH_SPEED_CAP := 12.0   # м/с: выше — это уже «дикий импульс»

var _main: Node3D
var _frame := 0
var _victim: Car
var _puppet: Car
var _start_gap := 0.0
var _max_speed := 0.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_victim = _main._cars[0]
		_puppet = _main._cars[1]
		# Жертва стоит; остальных глушим и увозим, чтобы не мешали.
		for i in range(2, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false
			extra.global_position = Vector3(150, 2, 150 + i * 8)
		_victim.controls_enabled = false
		_victim.linear_velocity = Vector3.ZERO
		_puppet.controls_enabled = false
		_puppet.net_make_puppet()
		return
	if _frame == 40:
		# Марионетка ТЕЛЕПОРТИРУЕТСЯ вплотную к жертве (снимок с диким
		# сближением — как на рывке канала) и «едет» прямо в неё.
		var at: Vector3 = _victim.global_position \
				+ _victim.global_transform.basis.x * 1.0 + Vector3.UP * 0.1
		_puppet.net_apply_snapshot(at,
				_puppet.global_transform.basis.get_rotation_quaternion(),
				(_victim.global_position - at).normalized() * 18.0)
		_start_gap = _victim.global_position.distance_to(at)
		print("телепорт марионетки вплотную: зазор %.2f м" % _start_gap)
		return
	if _frame > 40 and _frame <= 160:
		_max_speed = maxf(_max_speed, _victim.linear_velocity.length())
		return
	if _frame == 161:
		var gap := _victim.global_position.distance_to(
				_puppet.global_position)
		print("через 2 с: зазор %.2f м (был %.2f), пик скорости жертвы %.1f м/с"
				% [gap, _start_gap, _max_speed])
		var pushed := gap > _start_gap + 0.4      # растолкало
		var sane := _max_speed < PUSH_SPEED_CAP   # но без дикости
		print("PUPPETPUSH TEST: %s" % ("PASS" if pushed and sane
				else "FAIL — pushed=%s sane=%s" % [pushed, sane]))
		get_tree().quit(0 if pushed and sane else 1)
