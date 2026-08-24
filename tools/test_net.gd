extends Node
## Сквозной тест сетевой игры. Подключается к УЖЕ ЗАПУЩЕННОМУ серверу
## (`godot --headless --path . res://scenes/Main.tscn -- --server`) на
## 127.0.0.1, просит начать заезд, даёт газ и проверяет, что:
##   1) сервер выдал слот и ростер машин;
##   2) СВОЯ машина поехала (она клиент-авторитетна: физика локальная,
##      состояние уходит серверу через Main._client_tick);
##   3) марионетки (боты) тоже поехали — снимки состояния приходят;
##   4) над второй машиной игрока висит маркер (её должно быть видно);
##   5) заезд стартовал САМ, без второго игрока: сервер ждёт его
##      LOBBY_WAIT секунд и дальше едет с ботом в пустом слоте.
##
## ГРАБЛИ, из-за которых стенд устроен именно так: адресация RPC в Godot
## идёт ПО ПУТИ УЗЛА. На сервере гонка живёт в /root/Main, значит и у
## клиента она обязана быть /root/Main — поэтому корень этой сцены зовётся
## Main и несёт тот же Main.gd, а проверяльщик висит ДОЧЕРНИМ узлом.
## Дочерний _ready вызывается раньше родительского — там и подключаемся,
## чтобы Main._ready увидел уже выставленный режим клиента.
##
## ВАЖНО: тест ОДИНОЧНЫЙ. Проверка «метка соперника скрыта» верна ровно
## потому, что второй слот ведёт бот. Если запустить два таких клиента
## одновременно, эта проверка ЗАКОНОМЕРНО упадёт у обоих — метка обязана
## загореться. Так и проверялось, что уведомление о занятии слота доходит.
##
## Запуск (сервер должен работать в фоне):
##   godot --headless --path . res://tools/TestNet.tscn
## По умолчанию бьёт в 127.0.0.1; чужой адрес — аргументом после `--`:
##   godot --headless --path . res://tools/TestNet.tscn -- 139.100.234.166

const RUN_TIME := 16.0
const MOVE_MIN := 15.0     # сколько метров должна проехать машина

var _t := 0.0
var _main: Node3D
var _start_pos := []
var _asked_start := false
var _ok := {}
# Замер плавности марионетки (машины, которую считает сервер, а клиент
# только рисует). Дёрганость видна двумя признаками: шаг назад против
# собственного хода и разнобой в длине кадрового шага.
var _sm_prev := Vector3.ZERO
var _sm_steps: Array[float] = []
var _sm_back := 0
var _sm_frames := 0
# Тот же замер отдельно для машины СОПЕРНИКА-ИГРОКА (слот 1-мой): она идёт
# двойным прыжком клиент→сервер→клиент, и жалоба «противник дёргается»
# была именно на неё. Осмыслен только при двух клиентах — без второго
# игрока слот ведёт бот и попадает в общий замер.
var _rv_prev := Vector3.ZERO
var _rv_steps: Array[float] = []
var _rv_back := 0
var _rv_frames := 0


func _ready() -> void:
	_main = get_parent() as Node3D
	var addr := "127.0.0.1"
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			addr = a
			break
	print("  сервер: %s:%d" % [addr, Net.PORT])
	# remember=false: иначе каждый прогон стенда затирал бы игроку
	# сохранённый адрес VDS в user://net.cfg своим 127.0.0.1.
	Net.join_server(addr, Net.PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	if Net.my_slot < 0:
		if _t > 8.0:
			_fail("сервер не выдал слот за 8 с (он запущен?)")
		return
	if _start_pos.is_empty():
		_ok["слот выдан"] = true
		_ok["ростер получен"] = _main._roster.size() == _main._cars.size()
		for c: Car in _main._cars:
			_start_pos.append(c.global_position)
	# Стартовать НЕ просим: проверяем как раз то, что сервер сам подождёт
	# второго игрока LOBBY_WAIT секунд и начнёт с ботом.
	if not _asked_start and _main._car != null and _main._car.controls_enabled:
		_asked_start = true
		_ok["старт без второго игрока"] = _t < 12.0
		print("  заезд начался на %.1f с" % _t)
	if _t > 9.0 and _t <= RUN_TIME:
		_sample_smoothness(delta)
	# Газ в пол ЧЕРЕЗ Input: своя машина клиент-авторитетна — её физику
	# целиком считает клиент и сам шлёт серверу состояние (_client_tick).
	if _main._car != null and _main._car.controls_enabled:
		Input.action_press("accelerate")
	if _t < RUN_TIME:
		return

	var me: Car = _main._cars[Net.my_slot]
	var moved_me := me.global_position.distance_to(_start_pos[Net.my_slot])
	var moved_bot := 0.0
	for i in _main._cars.size():
		if i == Net.my_slot:
			continue
		moved_bot = maxf(moved_bot,
				_main._cars[i].global_position.distance_to(_start_pos[i]))
	_ok["своя машина поехала"] = moved_me > MOVE_MIN
	_ok["снимки ботов идут"] = moved_bot > MOVE_MIN
	# Метка соперника СОЗДАНА, но пока он не подключился — СКРЫТА: слот
	# ведёт бот, а оранжевая стрелка означает живого игрока. Тест одиночный,
	# поэтому ждём именно скрытую.
	_ok["метка соперника есть"] = _main._rival_marker != null
	_ok["метка соперника скрыта без него"] = 			_main._rival_marker != null and not _main._rival_marker.visible
	_ok["своя машина не марионетка"] = me.net_role == Car.NetRole.OWNED
	var jitter := _jitter()
	print("  марионетка: шаг расходится со скоростью на %.1f%%, рывков назад %d из %d"
			% [jitter, _sm_back, _sm_frames])
	# Машина соперника-игрока (только при двух клиентах): двойной прыжок
	# клиент→сервер→клиент. Критерий как у бота + рывки назад = 0.
	if _rv_frames >= 30:
		var rvj := _jitter(_rv_steps)
		print("  соперник-игрок: шаг расходится на %.1f%%, рывков назад %d из %d"
				% [rvj, _rv_back, _rv_frames])
		_ok["соперник-игрок идёт ровно"] = rvj < 35.0
		_ok["соперника не дёргает назад"] = _rv_back == 0
	# Марионетка: пройденное за кадр сходится с присланной скоростью.
	# Порог 35%. Он ДОЛЖЕН учитывать реальный канал, а не локалхост:
	#   локалхост      2-5%   (пакеты идут ровно)
	#   живой VDS      21-31% (дрожание прихода пакетов)
	#   одиночная игра 0.3%   (сети нет вовсе)
	# Порог всё равно ловит все неудачные переделки интерполяции: буфер с
	# отставанием давал 60% на интернете, «еду от текущего места» — 50%.
	_ok["марионетка идёт ровно"] = jitter < 35.0
	_ok["марионетку не дёргает назад"] = _sm_back == 0
	print("  проехали: своя %.1f м, лучший из остальных %.1f м"
			% [moved_me, moved_bot])
	_report()


## Плавность марионетки. Меряем НЕ разброс длины шага (он гуляет от того, КАК
## едет бот: разгон, поворот, удар о стену — метрика скакала вдвое между
## прогонами и ничего не доказывала), а насколько пройденный за кадр путь
## сходится с ЗАЯВЛЕННОЙ В СНИМКЕ скоростью. Интерполяция ровно за это и
## отвечает, а от манеры езды бота это не зависит.
##
## Замер в _physics_process: там работает Car._follow_snapshot, там позиция и
## меняется. В _process мерить бессмысленно — headless крутит его в разы чаще
## физики, и почти все шаги нулевые (тоже проверено на себе).
func _sample_smoothness(delta: float) -> void:
	var idx := 2 if Net.my_slot != 2 else 3     # заведомо бот-марионетка
	_sample_one(_main._cars[idx], delta, _sm_steps, false)
	# Соперник-игрок (если второй клиент подключён — иначе это бот и он
	# уже покрыт общим замером, второй раз не считаем).
	var rv := 1 - Net.my_slot
	if rv >= 0 and rv < _main._cars.size() and _main._rival_marker != null \
			and _main._rival_marker.visible:
		_sample_one(_main._cars[rv], delta, _rv_steps, true)


func _sample_one(car: Car, delta: float, steps: Array[float],
		rival: bool) -> void:
	var pos := car.global_position
	# Скорость берём ИЗ СНИМКА, а не из car.linear_velocity: у замороженного
	# кинематического тела Godot пересчитывает linear_velocity сам, по сдвигу
	# трансформа, и выдаёт вдвое больше реального (замерено: 62 м/с при
	# максимуме машины 34). На эти грабли я наступил и полчаса чинил
	# интерполяцию, которая была не виновата.
	var vel := car._snap_vel
	vel.y = 0.0
	var prev := _rv_prev if rival else _sm_prev
	if prev != Vector3.ZERO and vel.length() > 5.0:
		var step := pos - prev
		step.y = 0.0
		# Шаг ПРОТИВ хода — тот самый рывок назад от экстраполяции.
		if step.length() > 0.001 \
				and step.normalized().dot(vel.normalized()) < -0.2:
			if rival:
				_rv_back += 1
			else:
				_sm_back += 1
		var expected := vel.length() * delta
		if expected > 0.001:
			steps.append(absf(step.length() - expected) / expected)
		if rival:
			_rv_frames += 1
		else:
			_sm_frames += 1
	if rival:
		_rv_prev = pos
	else:
		_sm_prev = pos


## Средняя относительная невязка «шаг против скорости», в процентах.
func _jitter(steps: Array[float] = []) -> float:
	if steps.is_empty():
		steps = _sm_steps
	if steps.size() < 30:
		return 999.0
	var sum := 0.0
	for v: float in steps:
		sum += v
	return sum / steps.size() * 100.0


func _fail(reason: String) -> void:
	print("NET TEST: FAIL (%s)" % reason)
	get_tree().quit(1)


func _report() -> void:
	var all_ok := true
	for k: String in _ok:
		if not _ok[k]:
			all_ok = false
		print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
	print("NET TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
