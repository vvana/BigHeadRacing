# Стенд магазина GameState: покупка машин, ступеней улучшений, пакетов
# косметики и комплектации аркадных машин; всё переживает перезапуск
# (профиль перечитывается заново). Профиль игрока СНАЧАЛА откладывается в
# бэкап и в конце ВОССТАНАВЛИВАЕТСЯ (даже при провале). Запуск:
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
	gs.car_tuning = {}
	gs.car_packs = {}
	gs.selected_car_id = gs.full_id("vz01")
	gs._save_profile()

	# --- Улучшения стартовой машины: цена от условной 1000, уровень 2.
	_ok(gs.upgrade_price("vz01", "engine") == 40, "ступень I Копейки 40")
	_ok(not gs.try_buy_upgrade("vz01", "engine"), "1 уровень — ступень закрыта")
	gs.add_xp(100)   # 2-й уровень (+400 монет бонуса)
	_ok(gs.level_info().x == 2 and gs.money == 400, "2 уровень, бонус 400")
	_ok(gs.try_buy_upgrade("vz01", "engine"), "куплена ступень I мотора")
	_ok(gs.money == 360 and gs.upgrade_level("vz01", "engine") == 1, "списано 40")
	_ok(gs.upgrade_price("vz01", "engine") == 60, "ступень II — 60")
	_ok(not gs.try_buy_upgrade("vz01", "engine"), "ступень II с 6 уровня")
	var m: Dictionary = gs.upgrade_multipliers("vz01")
	_ok(is_equal_approx(m["accel"], 1.04) and is_equal_approx(m["speed"], 1.0),
			"множители: разгон 1.04")

	# --- Аркадная машина: покупка, детали по ступеням, пакеты.
	_ok(not gs.try_buy_upgrade("ac1", "wheel"), "чужую машину не прокачать")
	gs.add_xp(4000)   # далеко за 12 уровень
	gs.add_money(50000)
	_ok(gs.try_buy_car("ac1"), "куплен ac1")
	_ok(gs.full_id("ac1") == "ac1-red2-g0-w1-e0-s0-x0-k0-l0", "сток ac1: %s" % gs.full_id("ac1"))
	_ok(not gs.set_tuning("ac1", "wheel", 5), "колёса II ступени без ступени — нельзя")
	_ok(gs.set_tuning("ac1", "color", "cyan") and gs.set_tuning("ac1", "shade", 3),
			"краска свободна")
	_ok(gs.upgrade_price("ac1", "wheel") == 120, "ступень I колёс 4% от 3000 = 120")
	_ok(gs.try_buy_upgrade("ac1", "wheel") and gs.try_buy_upgrade("ac1", "wheel"),
			"колёса I и II")
	_ok(gs.set_tuning("ac1", "wheel", 5) and not gs.set_tuning("ac1", "wheel", 9),
			"колёса №5 можно, №9 (III) нельзя")
	_ok(not gs.set_tuning("ac1", "sticker", 3), "наклейка без пакета — нельзя")
	_ok(gs.pack_price("ac1", gs.PACK_STICKERS) == 600
			and gs.pack_price("ac1", gs.PACK_METALLIC) == 1200, "пакеты 600/1200")
	_ok(gs.pack_price("vz01", gs.PACK_STICKERS) == 300, "минимум пакета 300")
	_ok(gs.try_buy_pack("ac1", gs.PACK_STICKERS), "куплены наклейки")
	_ok(not gs.try_buy_pack("ac1", gs.PACK_STICKERS), "повторно — нет")
	_ok(gs.set_tuning("ac1", "sticker", 3) and gs.set_tuning("ac1", "line", 1),
			"наклейка и полоса")
	_ok(not gs.set_tuning("ac1", "glitter", 1), "металлик без пакета — нельзя")
	_ok(gs.try_buy_pack("ac1", gs.PACK_METALLIC) and gs.set_tuning("ac1", "glitter", 1),
			"металлик куплен и включён")
	gs.select_car("ac1")
	var want := "ac1-cyan3-g1-w5-e0-s0-x0-k3-l1"
	_ok(gs.selected_car_id == want, "выбор: %s (надо %s)" % [gs.selected_car_id, want])
	var money_before: int = gs.money

	# --- Перезапуск: всё перечитывается из профиля.
	var fresh: Node = GS.new()
	fresh._ready()
	_ok(fresh.money == money_before, "монеты пережили перезапуск")
	_ok(fresh.upgrade_level("vz01", "engine") == 1
			and fresh.upgrade_level("ac1", "wheel") == 2, "ступени пережили перезапуск")
	_ok(fresh.pack_owned("ac1", gs.PACK_STICKERS)
			and fresh.pack_owned("ac1", gs.PACK_METALLIC), "пакеты пережили перезапуск")
	_ok(fresh.selected_car_id == want, "выбор с комплектацией: %s" % fresh.selected_car_id)
	_ok(fresh.car_owned("ac1") and fresh.color_of("ac1") == "cyan", "владение и цвет")
	fresh.free()
	gs.free()
