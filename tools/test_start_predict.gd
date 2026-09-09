extends Node3D
## Стенд: ПРЕДСКАЗАНИЕ СТАРТА МАРИОНЕТКИ (Car.net_predict_start, 09.09,
## жалоба «я всегда стартую первым, другие отстают»). На локалхосте
## (TestStartNet) отставание записи 0.05 с и разницы не видно; здесь
## запись соперника задерживаем ИСКУССТВЕННО на LAG с: сначала снимки
## «стоит», потом — разгон с места, отставший на LAG. Проверяем:
##   1) по GO картинка марионетки трогается сама, не дожидаясь записи;
##   2) когда запись доезжает, добавка сходит на нет — картинка не убегает
##      от записи дальше, чем на доверительный запас, и не отстаёт от неё;
##   3) предсказание само гаснет.
## Запуск: godot --headless --path . res://tools/TestStartPredict.tscn

const LAG := 0.3          # с — искусственное отставание записи
const ACC := 9.0          # м/с² — разгон в «записи»
const DT := 1.0 / 60.0

var _main: Node3D
var _frame := 0
var _ok := {}
var _p: Car
var _origin := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _rot := Quaternion.IDENTITY
var _t := 0.0             # с от GO
var _stamp := 10.0
var _ahead_max := 0.0     # худшее «убежал вперёд записи», м
var _behind_max := 0.0    # худшее «отстал от записи», м (после прихода записи)


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


## Где запись показывает машину в момент t после GO (с отставанием LAG).
func _record_dist(t: float) -> float:
	var tr := maxf(0.0, t - LAG)
	return 0.5 * ACC * tr * tr


func _record_vel(t: float) -> float:
	return ACC * maxf(0.0, t - LAG)


func _physics_process(_d: float) -> void:
	_frame += 1
	var cars: Array = _main._cars
	if cars.size() < 3:
		return
	if _frame < 30:
		return
	if _frame == 30:
		for c: Car in cars:
			c.controls_enabled = false
		_p = cars[2]
		_p.net_make_puppet()
		# Буфер воспроизведения (и предсказание в нём) — путь клиента;
		# роль включаем руками, как TestStampSwap: без my_slot к сети
		# никто не обращается.
		Net.mode = Net.Mode.CLIENT
		Car.net_buf_delay = 0.06
		Car.net_view_lead = 0.0
		_origin = _p.global_position
		_rot = _p.global_transform.basis.get_rotation_quaternion()
		_fwd = -_p.global_transform.basis.z
		_fwd.y = 0.0
		_fwd = _fwd.normalized()
		# Пара снимков «стоим» — буферу нужна запись.
		for i in 6:
			_p.net_apply_snapshot(_origin, _rot, Vector3.ZERO, _stamp)
			_stamp += 1.0
		return
	if _frame == 60:
		_p.net_predict_start()   # GO
		_t = 0.0
		return
	if _frame < 60:
		_p.net_apply_snapshot(_origin, _rot, Vector3.ZERO, _stamp)
		_stamp += 1.0
		return
	# После GO: запись с отставанием LAG.
	_t += DT
	var rd := _record_dist(_t)
	_p.net_apply_snapshot(_origin + _fwd * rd, _rot, _fwd * _record_vel(_t),
			_stamp)
	_stamp += 1.0
	var shown := (_p.global_position - _origin).dot(_fwd)
	# Эталон «назад» — запись В ВОСПРОИЗВЕДЕНИИ (буфер net_buf_delay):
	# картинка марионетки и без предсказания идёт за записью на буфер.
	var rd_play := _record_dist(_t - Car.net_buf_delay)
	if _t > LAG + 0.2:
		_ahead_max = maxf(_ahead_max, shown - rd)
		_behind_max = maxf(_behind_max, rd_play - shown)
	if absf(_t - 0.3) < DT * 0.5:
		_ok["на 0.3 с по GO картинка тронулась сама (запись ещё стоит)"] = \
				shown > 0.2
		print("  0.3 с: картинка %.2f м, запись %.2f м" % [shown, rd])
	if absf(_t - 0.6) < DT * 0.5:
		print("  0.6 с: картинка %.2f м, запись %.2f м" % [shown, rd])
	if absf(_t - 1.0) < DT * 0.5:
		print("  1.0 с: картинка %.2f м, запись %.2f м" % [shown, rd])
	if _t >= 1.6:
		print("  худший отрыв от записи вперёд %.2f м, назад %.2f м"
				% [_ahead_max, _behind_max])
		# Вперёд — не дальше предсказанного пути (0.9 м) с запасом.
		_ok["картинка не убегает от записи дальше 1.2 м"] = _ahead_max < 1.2
		# Назад — запись догоняет, подтяжка тела к цели даёт до ~0.3 м.
		_ok["картинка не отстаёт от записи больше 0.6 м"] = _behind_max < 0.6
		_ok["предсказание погасло"] = _p._pred_t < 0.0
		var all_ok := true
		for k in _ok:
			print("  %s  %s" % ["ok  " if _ok[k] else "FAIL", k])
			all_ok = all_ok and bool(_ok[k])
		print("START PREDICT TEST: %s" % ("PASS" if all_ok else "FAIL"))
		get_tree().quit(0 if all_ok else 1)
