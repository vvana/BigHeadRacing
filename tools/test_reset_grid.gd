extends Node
## Стенд жалобы 31.08: «после завершения гонки началась следующая, и мы с
## другим игроком появились не у старта, а дальше». Механика бага: после
## _rx_reset сервер строит новую решётку, а в неё прилетает ХВОСТ потока
## _rx_pstate из ПРОШЛОЙ сцены клиента (пакет уже был в полёте) — серверная
## марионетка телепортируется туда, где игрок закончил прошлый заезд,
## снимки разносят это всем, клиентская машина-марионетка уезжает со
## старта, и welcome вручает игроку слот УЖЕ УВЕЗЁННОЙ машины.
##
## Воспроизводим напрямую: блокируем авто-hello (Net.my_slot = -3 —
## _say_hello выходит), после подключения шлём «устаревший» _rx_pstate с
## точкой в чистом поле (300, 0.6, 300), ждём, разблокируем hello. После
## welcome своя машина ОБЯЗАНА стоять у стартовой решётки, а не в поле.
## Лечения два (любое закрывает симптом, живут оба):
##   1) сервер выбрасывает _rx_pstate от слота, не сказавшего hello В ЭТОЙ
##      сцене (_hello_done);
##   2) welcome возвращает свою машину на клетку решётки (_grid_xf).
## На коде до правок стенд падает: машина остаётся в (300, 300).
##
## Запуск (сервер поднять отдельно, СВЕЖИЙ, с фиксированной трассой):
##   godot --headless --path . res://scenes/Main.tscn -- --server --track=grass
##   godot --headless --path . res://tools/TestResetGrid.tscn
## ГРАБЛИ те же, что у TestNet: корень сцены обязан зваться Main и нести
## Main.gd (RPC адресуются по пути узла), проверяльщик — дочерний узел.

const POISON := Vector3(300.0, 0.6, 300.0)
const DEADLINE := 30.0

var _t := 0.0
var _main: Node3D
var _phase := 0          # 0 ждём связь, 1 яд отправлен, 2 hello, 3 замер
var _phase_t := 0.0


func _ready() -> void:
	Engine.max_fps = 120
	_main = get_parent() as Node3D
	if Net.is_online():
		return   # сцену перестроили (чужая трасса) — мы уже в деле
	# Сервер стенда поднят с --track=grass; клиент строит то же — без
	# перестройки сцены (она бы не сломала стенд, но шумит в логе).
	GameState.track_kind = TrackBuilder.KIND_GRASS
	# Блокируем авто-hello сцены: -1 означает «ещё не выдан», любое другое
	# отрицательное значение останавливает цикл _say_hello. Поздороваемся
	# сами — ПОСЛЕ отправки яда.
	Net.my_slot = -3
	var addr := "127.0.0.1"
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			addr = a
			break
	print("  сервер: %s:%d" % [addr, Net.PORT])
	Net.join_server(addr, Net.PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	_phase_t += delta
	if _t > DEADLINE:
		_finish(false, "не дождались слота/связи")
		return
	match _phase:
		0:
			var peer := multiplayer.multiplayer_peer
			if peer != null and peer.get_connection_status() \
					== MultiplayerPeer.CONNECTION_CONNECTED:
				# «Пакет из прошлой сцены»: состояние машины в чистом поле.
				var q := Quaternion.IDENTITY
				_main._rx_pstate.rpc_id(1, PackedFloat32Array([
						POISON.x, POISON.y, POISON.z,
						q.x, q.y, q.z, q.w, 0.0, 0.0, 0.0, 1.0]))
				print("  яд отправлен: %.0f, %.0f (hello ещё не было)"
						% [POISON.x, POISON.z])
				_phase = 1
				_phase_t = 0.0
		1:
			# Даём яду и снимкам сервера секунду разойтись, потом здороваемся.
			if _phase_t > 1.0:
				Net.my_slot = -1
				_main._say_hello()
				_phase = 2
		2:
			if Net.my_slot >= 0:
				print("  слот выдан: %d" % Net.my_slot)
				_phase = 3
				_phase_t = 0.0
		3:
			# Пара секунд на «устаканиться» (снимки, возможный отсчёт).
			if _phase_t > 2.0:
				var car: Car = _main._cars[Net.my_slot]
				var start: Vector3 = _main._track.start_transform().origin
				var to_start := car.global_position.distance_to(start)
				var to_poison := car.global_position.distance_to(POISON)
				print("  до старта %.1f м, до точки яда %.1f м"
						% [to_start, to_poison])
				_finish(to_start < 25.0 and to_poison > 100.0,
						"машина у решётки" if to_start < 25.0
						else "машину увезло со старта")


func _finish(ok: bool, note: String) -> void:
	print("RESET GRID TEST: %s (%s)" % ["PASS" if ok else "FAIL", note])
	get_tree().quit(0 if ok else 1)
