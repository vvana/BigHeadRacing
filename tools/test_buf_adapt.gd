extends Node
## Автотест АДАПТИВНОГО отставания воспроизведения (28.08). До этого дня
## отставание было константой 0.35 c — цена худшего случая канала,
## которую платили ВСЕГДА, даже когда канал чист (жалоба «друг у меня чуть
## позади, я у него чуть впереди»). Замеры показали, что VDS отправляет
## снимки ровно 60/с (tcpdump на eth0), а рвёт последняя миля, причём
## по-разному в разные минуты. Значит отставание должно ходить за каналом.
## Проверяем три свойства:
##   1) чистый канал (ровно 60/с) сводит отставание к полу BUF_MIN;
##   2) дыра 0.3 c поднимает его сразу (иначе марионетка замрёт);
##   3) после дыры оно СПАДАЕТ обратно, но не мгновенно (иначе на рваном
##      канале начнётся качель «выросли-упали-замерли»).

func _ready() -> void:
	var ok := {}
	# 1. Три секунды ровного потока 60/с.
	Car.net_reset_buf_delay()
	for i in 180:
		Car.net_note_gap(1.0 / 60.0)
	var clean: float = Car.net_buf_delay
	ok["чистый канал -> пол"] = is_equal_approx(clean, Car.BUF_MIN)
	print("ровный поток 60/с: отставание %.0f мс (пол %.0f)"
			% [clean * 1000.0, Car.BUF_MIN * 1000.0])

	# 2. Дыра 0.3 c — закладываемся немедленно.
	Car.net_note_gap(0.3)
	var after_hole: float = Car.net_buf_delay
	ok["дыра -> рост сразу"] = after_hole > 0.3
	print("после дыры 300 мс: отставание %.0f мс" % [after_hole * 1000.0])

	# 3. Спад: за 2 с ровного потока опускается, но пола ещё не достигает;
	#    за 10 с — достигает.
	for i in 120:
		Car.net_note_gap(1.0 / 60.0)
	var after2: float = Car.net_buf_delay
	ok["спад не мгновенный"] = after2 < after_hole and after2 > Car.BUF_MIN
	print("через 2 с ровного потока: %.0f мс" % [after2 * 1000.0])
	for i in 480:
		Car.net_note_gap(1.0 / 60.0)
	var after10: float = Car.net_buf_delay
	ok["спад доходит до пола"] = is_equal_approx(after10, Car.BUF_MIN)
	print("через 10 с ровного потока: %.0f мс" % [after10 * 1000.0])

	var all_ok := true
	for k: String in ok:
		if not ok[k]:
			all_ok = false
			print("  ПРОВАЛ: %s" % k)
	print("BUFADAPT TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
