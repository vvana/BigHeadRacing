extends Node3D
## Упреждение картинки соперника (жалоба 08.09 «оба видим себя первыми»).
##
## Синтетический канал: «настоящий» соперник едет по кругу R=45 м на
## 26 м/с, его состояния приходят с задержкой WIRE и буфером
## воспроизведения BUF. Марионетка ведётся штатным кодом
## (Car._follow_buffered). Меряем:
##   * отставание картинки — расстояние от нарисованной машины до того
##     места, где соперник НА САМОМ ДЕЛЕ сейчас;
##   * дрожание — разброс длины шага за кадр (у ровного хода 0).
## Прогон А — без упреждения (как было), прогон Б — с упреждением.
## PASS: отставание упало хотя бы вдвое, а дрожание не выросло больше
## чем в полтора раза.

const R := 45.0
const SPEED := 26.0
const WIRE := 0.05          # дорога владелец → сервер → я, с
const BUF := 0.20           # буфер воспроизведения
const FRAMES := 400

var _car: Car
var _phase := 0
var _frame := 0
var _t := 0.0
var _sum := 0.0
var _n := 0
var _steps: Array[float] = []
var _prev := Vector3.ZERO
var _res: Array = []


func _ready() -> void:
	Net.mode = Net.Mode.CLIENT      # в сцене только машина — влиять не на что
	_car = Car.new()
	add_child(_car)
	_car.net_make_puppet()
	Car.net_buf_delay = BUF


func _true_pos(t: float) -> Vector3:
	var w := SPEED / R
	return Vector3(R * cos(w * t), 0.6, R * sin(w * t))


func _true_rot(t: float) -> Quaternion:
	var w := SPEED / R
	var dir := Vector3(-sin(w * t), 0.0, cos(w * t))
	return Basis.looking_at(dir).get_rotation_quaternion()


func _true_vel(t: float) -> Vector3:
	var w := SPEED / R
	return Vector3(-sin(w * t), 0.0, cos(w * t)) * SPEED


func _physics_process(delta: float) -> void:
	# Упреждение держим руками: в бою его считает net_note_gap по каналу.
	Car.net_view_lead = 0.0 if _phase == 0 else BUF * Car.VIEW_LEAD_SHARE
	_t += delta
	# Приходит состояние ПРОШЛОГО (дорога WIRE), метка — тик автора.
	var at := _t - WIRE
	if at > 0.0:
		_car.net_apply_snapshot(_true_pos(at), _true_rot(at), _true_vel(at),
				roundf(at * 60.0))
	_frame += 1
	if _frame > 60:      # даём буферу набраться
		var drawn := _car.global_position
		_sum += Vector2(drawn.x - _true_pos(_t).x,
				drawn.z - _true_pos(_t).z).length()
		_n += 1
		if _prev != Vector3.ZERO:
			_steps.append((drawn - _prev).length())
		_prev = drawn
	if _frame >= FRAMES:
		var avg := _sum / maxf(1.0, float(_n))
		var mean := 0.0
		for s in _steps:
			mean += s
		mean /= maxf(1.0, float(_steps.size()))
		var dev := 0.0
		for s in _steps:
			dev += (s - mean) * (s - mean)
		dev = sqrt(dev / maxf(1.0, float(_steps.size())))
		_res.append([avg, dev])
		print("[lead] прогон %s: отставание картинки %.2f м, дрожание шага %.3f м"
				% ["А (без упреждения)" if _phase == 0 else "Б (с упреждением)",
				avg, dev])
		_phase += 1
		if _phase >= 2:
			var ok: bool = _res[1][0] <= _res[0][0] * 0.5 \
					and _res[1][1] <= _res[0][1] * 1.5 + 0.005
			print("[lead] %s" % ("PASS" if ok else "FAIL"))
			get_tree().quit(0 if ok else 1)
		# Сброс на второй прогон.
		_frame = 0
		_t = 0.0
		_sum = 0.0
		_n = 0
		_steps.clear()
		_prev = Vector3.ZERO
		_car.queue_free()
		_car = Car.new()
		add_child(_car)
		_car.net_make_puppet()
