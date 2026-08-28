extends Node
## Стенд «комната не ответила — клиент возвращается к воротам» (27.08:
## игрока выслали в комнату, та не ответила, и он застревал на тупиковом
## экране «Сервер не ответил», хотя ворота живы).
## Имитируем состояние клиента СРАЗУ ПОСЛЕ _rx_redirect: home_port смотрит
## на живые ворота (локальный сервер), а подключаемся к мёртвому порту.
## Ожидание: Main сам замечает молчание (_watch_join_timeout или отказ
## ENet), возвращается к воротам и получает там слот.
##
## Запуск (ворота должны работать в фоне):
##   godot --headless --path . res://tools/TestHomeFallback.tscn
##
## ГРАБЛИ те же, что у TestNet: корень сцены обязан зваться Main и нести
## Main.gd (RPC адресуются по пути узла), проверяльщик — дочерний узел, его
## _ready выполняется раньше родительского. Возврат домой перезагружает
## сцену — при повторном _ready мы уже подключены и не вмешиваемся.

const DEADLINE := 25.0   # 5 c таймаут мёртвого порта + подключение + hello
const DEAD_PORT := 39999

var _t := 0.0


func _ready() -> void:
	Engine.max_fps = 120
	if Net.is_online():
		return   # сцена перезагружена после возврата домой — уже подключены
	Net.host = "127.0.0.1"
	Net.home_port = Net.PORT
	print("  подключаемся к мёртвому порту %d (дом: %d)"
			% [DEAD_PORT, Net.PORT])
	Net.join_server("127.0.0.1", DEAD_PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	if Net.my_slot >= 0 and Net.port == Net.PORT:
		print("  вернулись домой: порт %d, слот %d" % [Net.port, Net.my_slot])
		print("HOMEFALLBACK TEST: PASS")
		get_tree().quit(0)
		return
	if _t > DEADLINE:
		print("HOMEFALLBACK TEST: FAIL — слот у ворот не получен за %.0f c "
				% DEADLINE
				+ "(порт %d, слот %d)" % [Net.port, Net.my_slot])
		get_tree().quit(1)
