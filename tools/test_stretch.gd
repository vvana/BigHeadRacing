extends Node3D
## Автотест РАСТЯЖЕНИЯ ВРЕМЕНИ вместо замирания (28.08).
## Соперник рисуется по записи с отставанием (см. Car._follow_buffered).
## Когда канал молчит дольше отставания, запись кончается. Раньше плеер в
## этот момент упирался и машина ВСТАВАЛА КОЛОМ, а потом рывком догоняла —
## именно это глаз читает как дрожание, и именно поэтому отставание
## приходилось держать большим. Теперь при иссякающем запасе время
## РАСТЯГИВАЕТСЯ (приём из джиттер-буферов телефонии): машина едет
## медленнее, но едет.
## Проверяем: во время молчания канала 0.3 с
##   1) темп воспроизведения просел ниже единицы (растяжение включилось);
##   2) машина всё это время ЕХАЛА, а не стояла;
##   3) и не улетела вперёд гаданием (экстраполяция под капом).

const SPEED := 12.0     # м/с в присланных состояниях
const SILENCE := 18     # кадров молчания канала (0.3 с)

var _main: Node3D
var _car: Car
var _frame := 0
var _base := Vector3.ZERO
var _rot := Quaternion.IDENTITY
var _n := 0             # сколько состояний отправлено
var _at_silence := Vector3.ZERO
var _at_tail := Vector3.ZERO
var _min_rate := 9.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_car = _main._cars[1]
		for i in _main._cars.size():
			var c: Car = _main._cars[i]
			c.controls_enabled = false
			if i != 1:
				c.alive = false
				c.global_position = Vector3(150, 2, 150 + i * 8)
		_base = _car.global_position
		_rot = _car.global_transform.basis.get_rotation_quaternion()
		_car.net_make_puppet()
		Net.mode = Net.Mode.CLIENT
		Car.net_reset_buf_delay()
		return
	if _car == null:
		return
	# Полторы секунды ровного потока 60/с — буфер набран, канал «чистый».
	if _frame > 30 and _frame <= 120:
		_send()
		return
	if _frame == 121:
		_at_silence = _car.global_position
		print("канал замолчал; отставание %.0f мс"
				% [Car.net_buf_delay * 1000.0])
		return
	# Молчание канала: ни одного снимка.
	if _frame > 121 and _frame <= 121 + SILENCE:
		_min_rate = minf(_min_rate, _car._play_rate)
		# Отметка за 6 кадров до конца молчания: к этому мигу запас БУФЕРА
		# исчерпан заведомо, и именно здесь старый код вставал колом.
		if _frame == 121 + SILENCE - 6:
			_at_tail = _car.global_position
		return
	if _frame == 122 + SILENCE:
		var moved := _car.global_position.distance_to(_at_silence)
		var tail := _car.global_position.distance_to(_at_tail)
		# За 0.3 с на 12 м/с «по записи» вышло бы 3.6 м; растянутое время
		# даёт меньше, но НЕ ноль. Верхняя граница ловит гадание.
		var alive_move := moved > 0.3 and moved < 3.6
		# РАЗЛИЧАЮЩАЯ проверка: на пустом буфере машина всё ещё ЕДЕТ.
		# Без растяжения тут ноль — плеер упирается в конец записи.
		var tail_move := tail > 0.05
		var stretched := _min_rate < 0.5
		print("за 0.3 с молчания прошла %.2f м (в последние 0.1 с — %.2f м), "
				% [moved, tail] + "минимальный темп %.2f" % _min_rate)
		var ok := alive_move and tail_move and stretched
		print("STRETCH TEST: %s" % ("PASS" if ok
				else "FAIL — ехала=%s хвост=%s растянуто=%s"
				% [alive_move, tail_move, stretched]))
		get_tree().quit(0 if ok else 1)


func _send() -> void:
	_n += 1
	var pos := _base + Vector3(1, 0, 0) * SPEED * (float(_n) / 60.0)
	_car.net_apply_snapshot(pos, _rot, Vector3(SPEED, 0, 0), 1000.0 + float(_n))
