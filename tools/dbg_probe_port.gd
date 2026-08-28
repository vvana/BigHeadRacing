extends SceneTree
## Проба игрового UDP-порта: доходит ли ENet-рукопожатие до сервера.
## Печатает PROBE OK (соединение установлено) или PROBE FAIL (таймаут).
## Появился 27.08: игрока перенаправило в комнату 9978, и у него
## «Сервер не ответил за 5 сек» — пробник отделяет «порт закрыт снаружи»
## от бед самого клиента.
##
## Запуск:
##   godot --headless --path . --script res://tools/dbg_probe_port.gd \
##       -- <адрес> <порт>

const TIMEOUT := 6.0

var _peer := ENetMultiplayerPeer.new()
var _t := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("PROBE FAIL: нужно два аргумента — адрес и порт")
		quit(2)
		return
	var addr := args[0]
	var port := int(args[1])
	print("пробуем %s:%d ..." % [addr, port])
	if _peer.create_client(addr, port, 8) != OK:
		print("PROBE FAIL: create_client не запустился")
		quit(1)


func _process(delta: float) -> bool:
	_t += delta
	_peer.poll()
	match _peer.get_connection_status():
		MultiplayerPeer.CONNECTION_CONNECTED:
			print("PROBE OK: соединение за %.1f с" % _t)
			quit(0)
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			print("PROBE FAIL: соединение отвергнуто за %.1f с" % _t)
			quit(1)
	if _t > TIMEOUT:
		print("PROBE FAIL: нет ответа за %.0f с" % TIMEOUT)
		quit(1)
	return false
