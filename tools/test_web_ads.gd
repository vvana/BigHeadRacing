extends Node
## Стенд рекламы Яндекс Игр в autoload Ads (23.09): веб-ветка включается
## руками (Ads._web = true); JavaScriptBridge.eval вне web-сборки — пустышка
## (возвращает null), так что показ «висит» и проверяются правила и
## поведение фасада, а не сам ysdk. Межстраничной в игре нет (решение
## игрока 23.09) — стенд заодно следит, чтобы она не вернулась. Проверяем:
##   1) на столе (без платформы) рекламы нет — show_rewarded отказывает,
##      RewardedAd крутит заглушку;
##   2) web: реклама есть, ролик предлагается всегда; второй show_rewarded
##      во время идущего — отказ;
##   3) ролик web через RewardedAd: показ принят, заглушки нет, площадка
##      молчит — ролик всё ещё идёт (таймаута у ролика нет);
##      «closed» без награды → cb(false), last_error пуст; «error» →
##      cb(false) с last_error; после ролика Ads свободен, звук есть;
##   4) в Ads нет ни метода, ни состояния межстраничной.
## Запуск: godot --headless --path . res://tools/TestWebAds.tscn

var _fails := 0
var _cb_calls: Array = []


func _check(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _muted() -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))


func _on_rewarded(rewarded: bool) -> void:
	_cb_calls.append(rewarded)


func _ready() -> void:
	# 1) стол.
	_check(not Ads.available() and not Ads.show_rewarded(_on_rewarded),
			"стол: платформы нет, show_rewarded отказывает")
	_check(Ads.rewarded_ready(), "стол: ролик предлагается всегда (заглушка)")

	# 2) web.
	Ads._web = true
	_check(Ads.available() and Ads.rewarded_ready(), "web: реклама есть, ролик всегда предлагается")
	_check(Ads.show_rewarded(_on_rewarded), "web: показ принят")
	_check(not Ads.show_rewarded(_on_rewarded), "второй ролик во время идущего — отказ")
	await get_tree().create_timer(1.5).timeout
	_check(_cb_calls.is_empty() and Ads._show_cb.is_valid(),
			"площадка молчит (eval → null) — показ висит, cb не звался")
	Ads._finish_show(false)
	_check(_cb_calls == [false] and not Ads._show_cb.is_valid(), "closed: cb(false), Ads свободен")
	_cb_calls.clear()

	# 3) ролик через RewardedAd: web → площадка, заглушки нет.
	var canvas := CanvasLayer.new()
	add_child(canvas)
	RewardedAd.play(canvas, "стенд", _on_rewarded)
	await get_tree().process_frame
	_check(Ads._show_cb.is_valid() and canvas.has_node("RewardedAd"),
			"ролик web: показ принят Ads, RewardedAd ждёт площадку")
	_check(_muted(), "звук заглушён на время ролика")
	var ad: RewardedAd = canvas.get_node("RewardedAd")
	_check(ad.get_child_count() == 0, "заглушки 3-2-1 нет")
	await get_tree().create_timer(3.5).timeout
	_check(_cb_calls.is_empty() and canvas.has_node("RewardedAd"),
			"площадка молчит — ролик всё ещё идёт (нет таймаута у ролика)")
	# Закрытие без награды.
	Ads._finish_show(false)
	await get_tree().process_frame
	await get_tree().process_frame   # queue_free срабатывает в конце кадра
	_check(_cb_calls == [false] and not canvas.has_node("RewardedAd"),
			"closed без награды: cb(false), RewardedAd убрался")
	# Ошибка площадки помечается в last_error (как на Android).
	_cb_calls.clear()
	_check(Ads.show_rewarded(_on_rewarded), "новый показ принят")
	Ads.last_error = "show"
	Ads._finish_show(false)
	_check(_cb_calls == [false] and Ads.last_error == "show",
			"error площадки: cb(false), last_error = «%s»" % Ads.last_error)
	_check(not Ads._show_cb.is_valid() and not _muted(), "после ролика Ads свободен, звук есть")

	# 4) межстраничной нет и не должно появиться.
	_check(not Ads.has_method("maybe_interstitial") and not Ads.has_method("note_race_finished"),
			"межстраничной в Ads нет (методов maybe_interstitial / note_race_finished)")
	var inter_vars := 0
	for p in Ads.get_property_list():
		if String(p.name).begins_with("_inter"):
			inter_vars += 1
	_check(inter_vars == 0, "состояния межстраничной в Ads нет")

	Ads._web = false
	print("WEB ADS TEST: %s" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0 if _fails == 0 else 1)
