extends Node
## Автотест музыки (03.09). Проверяет, что все четыре файла на месте и
## грузятся, что трек меню зациклен и реально играет, а гоночные идут
## по кругу без повтора подряд и НЕ зациклены (иначе следующий не встанет).
##
## ЗАПУСК С ОКНОМ (в headless Music молчит намеренно — там нет звука):
##   godot --path . res://tools/TestMusic.tscn

var _pass := 0
var _fail := 0
var _frame := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _ready() -> void:
	# Файлы на диске и импортированы.
	var paths: Array[String] = [Music.MENU]
	paths.append_array(Music.RACE)
	for p in paths:
		var s: AudioStream = ResourceLoader.load(p) as AudioStream
		_ok(s != null and s.get_length() > 30.0, "трек %s (длина)" % p)

	_ok(not Music._silent, "звук доступен (стенд надо гонять С ОКНОМ)")
	Music.play_menu()
	_ok(Music._current == Music.MENU, "в меню играет menu.mp3")
	_ok((ResourceLoader.load(Music.MENU) as AudioStreamMP3).loop,
			"трек меню зациклен")

	# Заезд: шесть переключений подряд — ни один трек не повторился
	# вплотную и все три успели побывать.
	var seen := {}
	var prev := Music._current
	for i in 6:
		Music.next_race()
		_ok(Music._current != prev, "трек заезда сменился (шаг %d)" % i)
		_ok(Music.RACE.has(Music._current), "трек заезда из списка (шаг %d)" % i)
		seen[Music._current] = true
		prev = Music._current
	_ok(seen.size() == Music.RACE.size(), "за шесть заездов слышны все три")
	_ok(not (ResourceLoader.load(Music.RACE[0]) as AudioStreamMP3).loop,
			"гоночный трек не зациклен — за ним встаёт следующий")
	# Перезагрузка сцены заезда (смена трассы по сети, рестарт) музыку
	# не сбивает: play_race при играющем гоночном треке ничего не делает.
	var during := Music._current
	Music.play_race()
	_ok(Music._current == during, "перезаход в гонку не сбивает трек")


func _process(_d: float) -> void:
	# Даём склейке доиграть: проигрыватель обязан звучать.
	_frame += 1
	if _frame < 60:
		return
	_ok(Music._player.playing, "музыка играет")
	print("MUSIC TEST: %s (%d/%d)" % ["PASS" if _fail == 0 else "FAIL",
			_pass, _pass + _fail])
	get_tree().quit(0 if _fail == 0 else 1)
