extends Node3D
## Стенд удвоения наград за ролик на плите финиша (22.09). Проверяем:
##   1) финиш начислил опыт и монеты, кнопка «УДВОИТЬ ЗА РЕКЛАМУ» активна,
##      плашки показывают награды заезда;
##   2) недосмотренный ролик — ничего не начислил, кнопка снова активна;
##   3) нажатие: кнопка «ИДЁТ РОЛИК…», флаг _ad_showing (Enter/Esc не
##      действуют), под HUD появился RewardedAd (заглушка 3-2-1 вне web);
##   4) после заглушки: опыт и монеты заезда начислены ещё раз (+ бонус за
##      взятые уровни, как в add_xp), плашки удвоены, кнопка «УДВОЕНО ✓»;
##   5) повторное нажатие ничего не делает.
## Профиль на диске подменяется и в конце ВОССТАНАВЛИВАЕТСЯ. Запуск:
## godot --headless --path . res://tools/TestFinishAd.tscn

var _fails := 0


func _check(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _ready() -> void:
	var had := FileAccess.file_exists(GameState.PROFILE_PATH)
	var orig := FileAccess.get_file_as_bytes(GameState.PROFILE_PATH) \
			if had else PackedByteArray()
	var money0: int = GameState.money
	var xp0: int = GameState.xp

	GameState.money = 1000
	GameState.xp = 0
	var main: Node3D = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._my_kills = 2
	main._show_finish(1)
	var xp1: int = GameState.xp
	var m1: int = GameState.money
	var fxp: int = main._finish_xp
	var fcoins: int = main._finish_coins
	_check(fxp > 0 and fcoins > 0 and xp1 == fxp and m1 >= 1000 + fcoins,
			"финиш: +%d опыта, +%d монет (опыт %d, монеты %d)"
			% [fxp, fcoins, xp1, m1])
	var btn: Button = main._ad_x2_btn
	_check(btn != null and btn.visible and not btn.disabled
			and btn.text == "×2",
			"кнопка «▶ ×2» активна: «%s»" % (btn.text if btn else "—"))
	_check(main._x2_tags.size() == 2 and (main._x2_tags[0] as Control).visible,
			"ярлычки «×2» на опыте и монетах видны")
	var vxp: Label = main._reward_vals.xp
	var vcoins: Label = main._reward_vals.coins
	_check(vxp.text == "+%d" % fxp and vcoins.text == "+%d" % fcoins,
			"плашки: «%s» / «%s»" % [vxp.text, vcoins.text])

	# Недосмотренный ролик — без награды, кнопка активна.
	main._ad_showing = true
	main._on_ad_x2_done(false)
	_check(GameState.xp == xp1 and GameState.money == m1
			and not main._ad_showing and not btn.disabled and not main._ad_x2_done,
			"недосмотренный ролик: без награды, кнопка активна")

	# Нажатие: ролик пошёл (заглушка вне web), кнопка занята.
	main._ad_x2_pressed()
	_check(main._ad_showing and btn.disabled and btn.text == "…",
			"нажатие: ролик идёт, «%s»" % btn.text)
	_check(main._hud_canvas.has_node("RewardedAd"), "под HUD есть RewardedAd")
	var before: Vector3i = GameState.level_info()

	# Заглушка длится 3 с.
	await get_tree().create_timer(3.8).timeout
	var after: Vector3i = GameState.level_info()
	var bonus := 0
	for lv in range(before.x + 1, after.x + 1):
		bonus += GameState.LEVEL_MONEY * lv
	_check(main._ad_x2_done and not main._ad_showing,
			"ролик досмотрен: удвоение получено")
	_check(GameState.xp == xp1 + fxp,
			"опыт начислен ещё раз: %d (ждали %d)" % [GameState.xp, xp1 + fxp])
	_check(GameState.money == m1 + fcoins + bonus,
			"монеты начислены ещё раз: %d (ждали %d, бонус за уровни %d)"
			% [GameState.money, m1 + fcoins + bonus, bonus])
	_check(vxp.text == "+%d" % (fxp * 2) and vcoins.text == "+%d" % (fcoins * 2),
			"плашки удвоены: «%s» / «%s»" % [vxp.text, vcoins.text])
	_check(btn.disabled and btn.text.contains("✓"),
			"кнопка: «%s»" % btn.text)
	_check(not (main._x2_tags[0] as Control).visible, "ярлычки «×2» спрятаны")
	_check(not main._hud_canvas.has_node("RewardedAd"), "RewardedAd убрался")

	# Повторное нажатие — ничего.
	main._ad_x2_pressed()
	await get_tree().process_frame
	_check(not main._ad_showing and not main._hud_canvas.has_node("RewardedAd")
			and GameState.xp == xp1 + fxp,
			"повторное нажатие ничего не делает")

	# Вернуть профиль и память как были.
	GameState.money = money0
	GameState.xp = xp0
	if had:
		var f := FileAccess.open(GameState.PROFILE_PATH, FileAccess.WRITE)
		f.store_buffer(orig)
	else:
		DirAccess.remove_absolute(GameState.PROFILE_PATH)

	print("FINISH AD TEST: %s" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0 if _fails == 0 else 1)
