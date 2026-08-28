extends Node
## Сквозной сетевой тест: ЗАМОРОЖЕННОГО ИГРОКА ВИДЯТ ДРУГИЕ.
##
## Жалоба 28.08: «я был замороженный, а мой друг по сети ехал впритык ко
## мне и не заморозился тоже». Заразность дебафа (Car._bounce_off_cars)
## смотрит на `_freeze_time` СОПЕРНИКА, а он до протокола 12 по сети не
## ездил вовсе: на чужом экране моя машина всегда была «тёплой».
##
## Проверяется вся цепочка целиком, которую офлайновый стенд
## (TestFreezeSpread) закрыть не может: клиент-владелец докладывает свою
## заморозку серверу 12-м числом состояния (_rx_pstate), сервер кладёт её
## 4-м байтом в снимок (_pack_state), другой клиент разбирает (_rx_state).
##
## Стенд ПАРНЫЙ: два клиента к одному серверу, роль — аргументом.
##   godot --headless --path . res://scenes/Main.tscn -- --server
##   godot --headless --path . res://tools/TestNetFreeze.tscn -- freezer
##   godot --headless --path . res://tools/TestNetFreeze.tscn -- watcher
## Оба клиента запускать одновременно (иначе второй опоздает к заезду и
## будет ждать следующего). Адрес сервера — вторым аргументом.
##
## ГРАБЛИ те же, что у TestNet: RPC адресуются ПО ПУТИ УЗЛА, поэтому корень
## сцены зовётся Main и несёт Main.gd, а проверяльщик висит дочерним узлом.

const FREEZE := 3.0        # длительность дебафа, с
const REFREEZE := 0.5      # как часто «морозильщик» подновляет дебаф
const MEASURE := 6.0       # сколько секунд смотрим на соперника
const START_DEADLINE := 40.0
const MIN_SEEN := 0.6      # доля кадров, где соперник обязан быть синим

var _t := 0.0
var _main: Node3D
var _watcher := false
var _started_at := -1.0
var _next_freeze := 0.0
var _seen := 0
var _frames := 0
var _rival := -1
var _ok := {}


func _ready() -> void:
	# Кап частоты — как в TestNet: headless без него выедает ядро, и на
	# одной машине с сервером и вторым клиентом стенд ловит паузы ОС.
	Engine.max_fps = 120
	_main = get_parent() as Node3D
	var addr := "127.0.0.1"
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if a == "watcher":
			_watcher = true
		elif a == "freezer":
			_watcher = false
		elif not a.begins_with("--"):
			addr = a
	print("  роль: %s, сервер %s:%d"
			% ["наблюдатель" if _watcher else "морозильщик", addr, Net.PORT])
	# remember=false: не затирать игроку сохранённый адрес VDS.
	Net.join_server(addr, Net.PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	if Net.my_slot < 0:
		if _t > 10.0:
			_fail("сервер не выдал слот за 10 с (он запущен?)")
		return
	if _started_at < 0.0:
		if _main._car != null and _main._car.controls_enabled:
			_started_at = _t
			print("  заезд начался на %.1f с, мой слот %d" % [_t, Net.my_slot])
		elif _t > START_DEADLINE:
			_fail("заезд не начался за %.0f с" % START_DEADLINE)
		return
	if _watcher:
		_watch()
	else:
		_freeze()
	if _t < _started_at + MEASURE:
		return
	if _watcher:
		_ok["соперник-игрок найден"] = _rival >= 0
		_ok["замер набрался"] = _frames >= 60
		var share := float(_seen) / maxf(1.0, float(_frames))
		print("  соперник был заморожен в %.0f%% кадров (%d из %d)"
				% [share * 100.0, _seen, _frames])
		_ok["заморозку соперника видно"] = share >= MIN_SEEN
	_report()


## «Морозильщик»: держит СВОЮ машину замороженной весь замер. Дебаф
## накладывается локально — машина клиент-авторитетна, ровно так же он
## подхватывается и от касания (Car._bounce_off_cars).
func _freeze() -> void:
	if _main._car == null or _t < _next_freeze:
		return
	_next_freeze = _t + REFREEZE
	_main._car.apply_freeze(FREEZE)
	_ok["своя машина заморожена"] = _main._car.freeze_left() > 0.0


## «Наблюдатель»: смотрит на слот ДРУГОГО ЖИВОГО ИГРОКА (боты сюда не
## годятся — их морозит сам сервер, и такой замер ничего не доказывал бы).
func _watch() -> void:
	if _rival < 0:
		for s in _main._slot_taken.size():
			if s != Net.my_slot and _main._slot_taken[s] \
					and s < _main._cars.size():
				_rival = s
				print("  соперник-игрок в слоте %d" % s)
				break
		return
	_frames += 1
	if _main._cars[_rival].freeze_left() > 0.0:
		_seen += 1


func _fail(reason: String) -> void:
	print("NETFREEZE TEST: FAIL (%s)" % reason)
	get_tree().quit(1)


func _report() -> void:
	var all_ok := true
	for k: String in _ok:
		if not _ok[k]:
			all_ok = false
		print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
	print("NETFREEZE TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
