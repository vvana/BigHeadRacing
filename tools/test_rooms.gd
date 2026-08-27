extends Node
## Клиент стенда параллельных заездов (Rooms.gd). Подключается к воротам
## (127.0.0.1:порт по умолчанию) и ждёт, пока КАКОЙ-НИБУДЬ сервер выдаст
## слот — здесь или в комнате после перенаправления (_rx_redirect
## перезагружает сцену, этот узел переживает это вместе с ней). Итог одной
## строкой:  ROOMS CLIENT: port=<порт> slot=<слот> hops=<прыжков>.
## Оркестровка снаружи: несколько таких клиентов запускаются отдельными
## процессами против одних ворот, и по их строкам видно, что лишние
## игроки разъехались по комнатам (см. ПРОГРЕСС.md, раздел про Rooms).
##
## Как и TestNet, корень сцены обязан быть /root/Main с Main.gd — RPC в
## Godot адресуются по пути узла.

const DEADLINE := 40.0   # запас на подъём комнаты (спавн процесса ~2-4 с)

var _t := 0.0
## `--stay` (после `--`): получив слот, НЕ выходить — сидеть в заезде до
## убийства процесса. Нужен сценарию «опоздавший»: кто-то должен держать
## гонку ворот идущей, пока второй клиент опаздывает к ней.
var _stay := false
var _said := false


func _ready() -> void:
	# Headless без капа выедает ядро busy-loop'ом (см. test_net.gd).
	Engine.max_fps = 60
	_stay = OS.get_cmdline_user_args().has("--stay")
	# После перенаправления сцена перезагружается уже подключённой к
	# комнате — второй раз к воротам не идём.
	if not Net.is_online():
		# Чужой адрес — аргументом после `--`, как в test_net.gd.
		var addr := "127.0.0.1"
		for a: String in OS.get_cmdline_user_args():
			if not a.begins_with("--"):
				addr = a
				break
		Net.join_server(addr, Net.PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	if Net.my_slot >= 0:
		if not _said:
			_said = true
			print("ROOMS CLIENT: port=%d slot=%d hops=%d"
					% [Net.port, Net.my_slot, Net.redirect_hops])
		if not _stay:
			get_tree().quit(0)
	elif Net.my_slot == -2:
		print("ROOMS CLIENT: kicked (port=%d)" % Net.port)
		get_tree().quit(1)
	elif _t > DEADLINE:
		print("ROOMS CLIENT: timeout (port=%d)" % Net.port)
		get_tree().quit(1)
