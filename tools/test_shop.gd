# Стенд магазина GameState: покупка машин, ПОШТУЧНЫХ деталей кузова,
# наклеек, полосы и металлика по цветам (03.09 вечер), комплектации
# аркадных машин, перенос старых профилей со ступенями и пакетом
# наклеек; всё переживает перезапуск (профиль перечитывается заново).
# Профиль игрока СНАЧАЛА откладывается в бэкап и в конце
# ВОССТАНАВЛИВАЕТСЯ (даже при провале). Запуск:
# godot --headless --path . --script tools/test_shop.gd
extends SceneTree

var _failed := 0
var _checks := 0
const BAK := "user://profile.cfg.bak_test_shop"
# Автозагрузки при --script не поднимаются — GameState создаём сами.
const GS := preload("res://scripts/GameState.gd")


func _init() -> void:
	var abs := ProjectSettings.globalize_path(GS.PROFILE_PATH)
	var had := FileAccess.file_exists(GS.PROFILE_PATH)
	if had:
		DirAccess.copy_absolute(abs, ProjectSettings.globalize_path(BAK))
	_run()
	# Восстановить профиль игрока.
	if had:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(BAK), abs)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BAK))
	else:
		DirAccess.remove_absolute(abs)
	print("RESULT: %d/%d ok" % [_checks - _failed, _checks])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL ", what)


func _run() -> void:
	var gs: Node = GS.new()
	gs._ready()
	# Чистый профиль: нищий новичок.
	gs.xp = 0
	gs.money = 0
	gs.owned_cars = []
	gs.car_colors = {}
	gs.car_upgrades = {}
	gs.car_items = {}
	gs.car_tuning = {}
	gs.car_packs = {}
	gs.selected_car_id = gs.full_id("vz01")
	gs._save_profile()

	# --- Советская машина: деталей нет, цвета бесплатны.
	_ok(not gs.try_buy_item("vz01", "engine:1"), "у советской машины деталей нет")
	gs.add_xp(100)   # 2-й уровень (+400 монет бонуса)
	_ok(gs.level_info().x == 2 and gs.money == 400, "2 уровень, бонус 400")
	gs.set_car_color("vz01", "green")
	_ok(gs.color_of("vz01") == "green" and gs.money == 400,
			"цвет советской машины сменился бесплатно")

	# --- Советская машина: детали из СВОЕГО набора (03.09 вечер), цвет
	# деталей бесплатен, наклеек/полосы/металлика нет.
	_ok(not gs.try_buy_item("vz01", "engine:2"), "мотор №2 не из набора Копейки")
	_ok(gs.item_price("vz01", "engine:1") > 0, "мотор №1 Копейки продаётся")
	var money_sov: int = gs.money
	_ok(gs.try_buy_item("vz01", "engine:1")
			and gs.money == money_sov - gs.item_price("vz01", "engine:1"),
			"мотор №1 куплен, списано")
	_ok(gs.set_tuning("vz01", "engine", 1) and not gs.set_tuning("vz01", "engine", 3),
			"мотор №1 ставится, №3 (не куплен) — нет")
	_ok(gs.set_tuning("vz01", "wheel", 0) and not gs.set_tuning("vz01", "wheel", 4),
			"родные колёса свободны, диски №4 не из набора")
	_ok(gs.set_tuning("vz01", "pcolor", "grey2")
			and not gs.set_tuning("vz01", "pcolor", "zzz"), "цвет деталей: grey2 да, мусор нет")
	_ok(not gs.try_buy_item("vz01", "sticker:1") and not gs.try_buy_item("vz01", "line")
			and not gs.try_buy_item("vz01", "metal:red"),
			"наклейки, полоса и металлик советским не продаются")
	_ok(gs.full_id("vz01") == "vz01_green-e1-pgrey2",
			"полный id Копейки: %s" % gs.full_id("vz01"))
	_ok(gs.set_tuning("vz01", "pcolor", "") and gs.full_id("vz01") == "vz01_green-e1",
			"цвет деталей «как кузов» — токен пропал")
	_ok(gs.set_tuning("vz01", "engine", 0) and gs.full_id("vz01") == "vz01_green",
			"снял мотор — короткий id как раньше")
	gs.set_tuning("vz01", "engine", 1)
	_ok(not gs.set_tuning("fastback", "pcolor", "grey2"), "у Unity-машин слотов нет")

	# --- Аркадная машина: покупка, детали поштучно, наклейки поштучно.
	_ok(not gs.try_buy_item("ac1", "wheel:2"), "чужую машину не тюнить")
	gs.add_xp(4000)   # далеко за 12 уровень
	gs.add_money(50000)
	_ok(gs.try_buy_car("ac1"), "куплен ac1")
	_ok(gs.full_id("ac1") == "ac1-red2-g0-w1-e0-s0-x0-k0-l0", "сток ac1: %s" % gs.full_id("ac1"))
	_ok(gs.item_price("ac1", "wheel:2") == 50 and gs.item_price("ac1", "wheel:5") == 60
			and gs.item_price("ac1", "engine:7") == 80,
			"цены деталей по ярусам 1.5/2/2.5 % от 3000 = 50/60/80")
	_ok(gs.item_price("ac1", "wheel:1") == 0 and gs.item_price("ac1", "bogus:3") == 0,
			"сток и мусорный ключ не продаются")
	_ok(gs.item_unlock_level("ac1", "wheel:2") == 2
			and gs.item_unlock_level("ac1", "wheel:5") == 6
			and gs.item_unlock_level("ac1", "engine:7") == 12, "ярусы со 2/6/12 уровня")
	_ok(not gs.set_tuning("ac1", "wheel", 5), "колёса №5 без покупки — нельзя")
	_ok(gs.set_tuning("ac1", "color", "cyan") and gs.set_tuning("ac1", "shade", 3),
			"краска свободна")
	var money_before_parts: int = gs.money
	_ok(gs.try_buy_item("ac1", "wheel:5"), "куплены колёса №5 (ярус II, без яруса I)")
	_ok(gs.money == money_before_parts - 60, "списано 60")
	_ok(not gs.try_buy_item("ac1", "wheel:5"), "повторно — нет")
	_ok(gs.set_tuning("ac1", "wheel", 5) and not gs.set_tuning("ac1", "wheel", 6),
			"колёса №5 можно, №6 (того же яруса, не куплены) нельзя")
	_ok(gs.items_owned_count("ac1", "wheel:") == 1, "куплен один комплект дисков")
	_ok(not gs.set_tuning("ac1", "sticker", 3), "наклейка без покупки — нельзя")
	_ok(gs.item_price("ac1", "sticker:3") == 60 and gs.item_price("ac1", "line") == 60,
			"наклейка и полоса — 2 % = 60")
	_ok(gs.try_buy_item("ac1", "sticker:3") and gs.set_tuning("ac1", "sticker", 3),
			"наклейка №3 куплена и поставлена")
	_ok(not gs.set_tuning("ac1", "sticker", 4), "наклейка №4 — отдельная покупка")
	_ok(not gs.set_tuning("ac1", "line", 1), "полоса без покупки — нельзя")
	_ok(gs.try_buy_item("ac1", "line") and gs.set_tuning("ac1", "line", 1),
			"полоса куплена и включена")
	_ok(not gs.try_buy_pack("ac1", gs.PACK_STICKERS), "пакета наклеек больше нет")
	_ok(not gs.try_buy_pack("ac1", gs.PACK_METALLIC), "пакета металлика больше нет")
	_ok(gs.item_price("ac1", "metal:cyan") == 110 and gs.item_price("ac1", "metal:bogus") == 0,
			"металлик цвета 3.5 % = 110, чужой цвет не продаётся")
	_ok(not gs.set_tuning("ac1", "glitter", 1), "металлик без покупки — нельзя")
	_ok(gs.try_buy_item("ac1", "metal:cyan") and gs.set_tuning("ac1", "glitter", 1),
			"металлик cyan куплен и включён")
	_ok(gs.set_tuning("ac1", "color", "red") and int(gs.tuning_of("ac1")["glitter"]) == 0,
			"перекрасили в red без металлика — металлик погас")
	_ok(gs.set_tuning("ac1", "color", "cyan") and gs.set_tuning("ac1", "glitter", 1),
			"вернули cyan — металлик снова включается")
	# Уровень мал — ярус закрыт.
	var xp_save: int = gs.xp
	gs.xp = 0
	_ok(not gs.try_buy_item("ac1", "engine:1"), "на 1 уровне ярус I закрыт")
	gs.xp = xp_save
	gs.select_car("ac1")
	var want := "ac1-cyan3-g1-w5-e0-s0-x0-k3-l1"
	_ok(gs.selected_car_id == want, "выбор: %s (надо %s)" % [gs.selected_car_id, want])
	var money_before: int = gs.money

	# --- Перезапуск: всё перечитывается из профиля.
	var fresh: Node = GS.new()
	fresh._ready()
	_ok(fresh.money == money_before, "монеты пережили перезапуск")
	_ok(fresh.full_id("vz01") == "vz01_green-e1",
			"мотор Копейки пережил перезапуск: %s" % fresh.full_id("vz01"))
	_ok(fresh.item_owned("ac1", "wheel:5") and fresh.item_owned("ac1", "sticker:3")
			and fresh.item_owned("ac1", "line") and not fresh.item_owned("ac1", "wheel:6"),
			"поштучные покупки пережили перезапуск")
	_ok(fresh.item_owned("ac1", "metal:cyan") and not fresh.item_owned("ac1", "metal:red"),
			"металлик cyan пережил перезапуск")
	_ok(fresh.selected_car_id == want, "выбор с комплектацией: %s" % fresh.selected_car_id)
	_ok(fresh.car_owned("ac1") and fresh.color_of("ac1") == "cyan", "владение и цвет")
	fresh.free()

	# --- Перенос профиля до 03.09: ступени и пакет наклеек → поштучно.
	gs.car_items = {}
	gs.car_upgrades = {"ac1": {"wheel": 2, "engine": 1}}
	gs.car_packs = {"ac1": {gs.PACK_STICKERS: true, gs.PACK_METALLIC: true}}
	gs._save_profile()
	var old: Node = GS.new()
	old._ready()
	_ok(old.item_owned("ac1", "wheel:2") and old.item_owned("ac1", "wheel:7")
			and not old.item_owned("ac1", "wheel:8"),
			"колёса II ступени → диски №2–7 (не №8)")
	_ok(old.item_owned("ac1", "engine:3") and not old.item_owned("ac1", "engine:4"),
			"мотор I ступени → компрессоры №1–3")
	_ok(old.item_owned("ac1", "sticker:1") and old.item_owned("ac1", "sticker:10")
			and old.item_owned("ac1", "line"), "пакет наклеек → все 10 и полоса")
	_ok(old.item_owned("ac1", "metal:red") and old.item_owned("ac1", "metal:cyan"),
			"пакет металлика → все 12 цветов")
	_ok(old.set_tuning("ac1", "wheel", 7) and old.set_tuning("ac1", "sticker", 9),
			"перенесённое ставится")
	old.free()
	gs.free()
