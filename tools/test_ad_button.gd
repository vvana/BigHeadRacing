extends Node
## Стенд кнопки «+500 ЗА РЕКЛАМУ» в гараже (03.09). Учёт пар и кулдауна —
## в GameState (ЭКОНОМИКА.md, раздел 1): пара роликов → +500, потом
## 10 минут отдыха. Проверяем сценарий целиком через кнопку гаража:
##   1) пара целая — кнопка активна, зовёт смотреть;
##   2) первый ролик досмотрен — монет не прибавилось, кнопка просит второй;
##   3) второй досмотрен — +500 и кнопка выключена с обратным отсчётом;
##   4) кулдаун вышел — кнопка снова активна.
## Профиль на диске подменяется и в конце ВОССТАНАВЛИВАЕТСЯ (register_ad
## сохраняет профиль). Запуск:
## godot --headless --path . res://tools/TestAdButton.tscn

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
	var pair0: int = GameState._ads_in_pair
	var done0: float = GameState._ad_pair_done_at

	GameState.money = 1000
	GameState._ads_in_pair = 0
	GameState._ad_pair_done_at = 0.0
	var sel: Node = (load("res://scenes/CarSelect.tscn")
			as PackedScene).instantiate()
	add_child(sel)
	await get_tree().process_frame
	var btn: Button = sel._ad_btn
	_check(btn != null and btn.visible, "кнопка рекламы есть на экране")
	_check(not btn.disabled and btn.text.contains("+500"),
			"пара целая: активна, «%s»" % btn.text)

	sel._ad_finished(true)
	_check(GameState.money == 1000,
			"первый ролик: монет не прибавилось (%d)" % GameState.money)
	_check(not btn.disabled and btn.text.contains("ЕЩЁ"),
			"первый ролик: просит второй, «%s»" % btn.text)

	sel._ad_finished(true)
	_check(GameState.money == 1500,
			"второй ролик: +500 (%d)" % GameState.money)
	_check(btn.disabled and btn.text.contains(":"),
			"после пары: выключена с отсчётом, «%s»" % btn.text)
	_check(sel._coins_label.text == "1 500",
			"кошелёк на табличке обновился: «%s»" % sel._coins_label.text)

	# Кулдаун «вышел»: отматываем время пары назад.
	GameState._ad_pair_done_at -= GameState.AD_COOLDOWN + 1.0
	sel._refresh_ad_btn()
	_check(not btn.disabled and btn.text.contains("+500"),
			"кулдаун вышел: снова активна, «%s»" % btn.text)

	# Прерванный ролик (закрыли, не досмотрев) — ничего не даёт.
	sel._ad_finished(false)
	_check(GameState.money == 1500 and not btn.disabled,
			"недосмотренный ролик: без награды, кнопка активна")

	# Вернуть профиль и память как были.
	GameState.money = money0
	GameState._ads_in_pair = pair0
	GameState._ad_pair_done_at = done0
	if had:
		var f := FileAccess.open(GameState.PROFILE_PATH, FileAccess.WRITE)
		f.store_buffer(orig)
	else:
		DirAccess.remove_absolute(GameState.PROFILE_PATH)

	print("ADBUTTON TEST: %s" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0 if _fails == 0 else 1)
