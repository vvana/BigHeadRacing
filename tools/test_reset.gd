extends Node
## Одноразовый стенд полного цикла заезда по сети: клиент подключается и
## СТОИТ (газ не жмёт), боты доезжают 4 круга, сервер закрывает заезд по
## FINISH_TIMEOUT, через 8 с перезапускает трассу и шлёт _rx_reset — клиент
## обязан перезагрузить сцену и вернуться в лобби нового заезда.
##
## После reload_current_scene() эта нода пересоздаётся вместе со сценой:
## факт «мы перезапустились и снова получили слот» и есть критерий PASS
## (флаг переживает перезагрузку в GameState-автолоаде нельзя — не трогаем
## его; используем Net: после _rx_reset слот сброшен в −1 и выдан заново).
##
## Запуск (сервер должен работать):
##   godot --headless --path . res://tools/TestReset.tscn
## Ожидание долгое: ~3-6 минут (боты едут 4 круга + таймаут 40 с + 8 с).

const DEADLINE := 420.0   # с запасом: круг ~727 м, боты ~17 м/с

static var _run := 0      # static переживает reload_current_scene
static var _t0 := 0.0

var _t := 0.0


func _ready() -> void:
	_run += 1
	if _run == 1:
		_t0 = Time.get_ticks_msec() / 1000.0
		print("  [reset-test] первый запуск сцены, подключаемся")
		Net.join_server("127.0.0.1", Net.PORT, false)
	else:
		# Сцену перезагрузил _rx_reset. Net уже CLIENT, соединение живо —
		# Main._ready сам скажет hello. Ждём повторной выдачи слота.
		print("  [reset-test] сцена перезагружена после заезда (запуск %d)" % _run)


func _physics_process(delta: float) -> void:
	_t += delta
	var total := Time.get_ticks_msec() / 1000.0 - _t0
	if total > DEADLINE:
		print("RESET TEST: FAIL (за %.0f с перезапуск так и не случился)" % DEADLINE)
		get_tree().quit(1)
		return
	if _run >= 2 and Net.my_slot >= 0:
		print("  [reset-test] слот выдан заново: %d (на %.0f с)" % [Net.my_slot, total])
		print("RESET TEST: PASS")
		get_tree().quit(0)
