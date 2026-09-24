extends SceneTree
## Стенд 22.09: реестр «вышедших из заезда» (Rooms.mark_left / left_until /
## clear_left). Запуск: godot --headless --path . --script tools/test_left_registry.gd
## Вердикт — «LEFT REGISTRY TEST: PASS|FAIL».

func _init() -> void:
	var ok := {}
	var now := Time.get_unix_time_from_system()
	Rooms.clear_left(9000)
	Rooms.clear_left(9001)
	ok["пусто вначале"] = Rooms.left_until("stand_a") == 0.0
	Rooms.mark_left("stand_a", 9000, now + 60.0)
	var u := Rooms.left_until("stand_a")
	ok["запись есть, срок в будущем"] = u > now + 50.0 and u < now + 70.0
	Rooms.mark_left("stand_b", 9000, now - 1.0)
	ok["просроченная = 0 и прибрана"] = Rooms.left_until("stand_b") == 0.0 \
			and not FileAccess.file_exists("user://rooms/left/stand_b.json")
	Rooms.mark_left("stand_c", 9001, now + 60.0)
	Rooms.clear_left(9000)
	ok["clear_left снял только свой порт"] = Rooms.left_until("stand_a") == 0.0 \
			and Rooms.left_until("stand_c") > 0.0
	ok["пустой uid не пишется"] = true
	Rooms.mark_left("", 9001, now + 60.0)
	ok["пустой uid не пишется"] = Rooms.left_until("") == 0.0
	Rooms.clear_left(9001)
	var all_ok := true
	for k in ok:
		print("  %s  %s" % ["ok  " if ok[k] else "FAIL", k])
		all_ok = all_ok and bool(ok[k])
	print("LEFT REGISTRY TEST: %s" % ("PASS" if all_ok else "FAIL"))
	quit(0 if all_ok else 1)
