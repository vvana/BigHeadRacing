# Стенд МАГАЗИНА ОРУЖИЯ (08.09): ступени I/II/III покупаются по порядку,
# каждая со своего уровня и за свою цену (Weapons.STEP_LEVELS/PRICES по
# группе), набор для машины (weapon_steps) и вес выпадения III ступени,
# всё переживает перезапуск (профиль перечитывается). Профиль игрока
# СНАЧАЛА откладывается в бэкап и в конце ВОССТАНАВЛИВАЕТСЯ. Запуск:
# godot --headless --path . --script tools/test_weapon_shop.gd
extends SceneTree

var _failed := 0
var _checks := 0
const BAK := "user://profile.cfg.bak_test_wshop"
const GS := preload("res://scripts/GameState.gd")


func _init() -> void:
	var abs := ProjectSettings.globalize_path(GS.PROFILE_PATH)
	var had := FileAccess.file_exists(GS.PROFILE_PATH)
	if had:
		DirAccess.copy_absolute(abs, ProjectSettings.globalize_path(BAK))
	_run()
	if had:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(BAK), abs)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BAK))
	else:
		DirAccess.remove_absolute(abs)
	print("RESULT: %d/%d ok" % [_checks - _failed, _checks])
	print("WEAPON SHOP TEST: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL ", what)


## Опыт, с которого профиль на уровне lv (GameState.level_info).
func _xp_for_level(lv: int) -> int:
	var xp := 0
	for l in range(1, lv):
		xp += l * 40 + 60
	return xp


func _run() -> void:
	var gs: Node = GS.new()
	gs._ready()
	gs.xp = 0
	gs.money = 0
	gs.weapon_upgrades = {}
	gs._save_profile()

	# --- Таблица: группы, уровни, цены.
	_ok(Weapons.group_of(Weapons.MINE) == "A" and Weapons.group_of(Weapons.MAGNET) == "B"
			and Weapons.group_of(Weapons.LASER) == "C", "группы A/B/C по видам")
	_ok(Weapons.step_level(Weapons.MINE, 1) == 3 and Weapons.step_price(Weapons.MINE, 1) == 500,
			"мина I: 3 ур., 500")
	_ok(Weapons.step_level(Weapons.LASER, 3) == 22 and Weapons.step_price(Weapons.LASER, 3) == 10000,
			"лазер III: 22 ур., 10 000")
	for kind in Weapons.COUNT:
		for s in range(1, Weapons.STEPS + 1):
			_ok(Weapons.step_desc(kind, s) != "", "описание ступени %d вида %d" % [s, kind])

	# --- Новичок (1 уровень, 0 монет): ничего не купить.
	_ok(gs.weapon_step(Weapons.MINE) == 0 and gs.weapon_next_step(Weapons.MINE) == 1,
			"старт: ступень 0, следующая I")
	_ok(not gs.try_buy_weapon_step(Weapons.MINE), "1 уровень: мина I не продаётся")
	gs.money = 100000
	_ok(not gs.try_buy_weapon_step(Weapons.MINE), "с деньгами, но без уровня — нет")

	# --- 3 уровень: мина I за 500; II ещё рано (7).
	gs.xp = _xp_for_level(3)
	_ok(gs.level_info().x == 3, "уровень 3")
	var m0: int = gs.money
	_ok(gs.try_buy_weapon_step(Weapons.MINE) and gs.money == m0 - 500, "мина I куплена, -500")
	_ok(gs.weapon_step(Weapons.MINE) == 1, "ступень мины — I")
	_ok(not gs.try_buy_weapon_step(Weapons.MINE), "мина II на 3 уровне — рано")
	_ok(not gs.try_buy_weapon_step(Weapons.MAGNET), "магнит I с 4 уровня — рано")
	_ok(gs.weapon_next_level(Weapons.MINE) == 7 and gs.weapon_next_price(Weapons.MINE) == 1500,
			"следующая мина: 7 ур., 1 500")

	# --- Порядок: II без I нельзя (у масла ступень 0 → покупается именно I).
	gs.xp = _xp_for_level(7)
	_ok(gs.try_buy_weapon_step(Weapons.OIL) and gs.weapon_step(Weapons.OIL) == 1,
			"масло: первая покупка — I, не II")
	_ok(gs.try_buy_weapon_step(Weapons.OIL) and gs.weapon_step(Weapons.OIL) == 2,
			"масло II куплено на 7 уровне")
	_ok(not gs.try_buy_weapon_step(Weapons.OIL), "масло III с 14 уровня — рано")

	# --- Нехватка монет.
	gs.money = 100
	_ok(not gs.try_buy_weapon_step(Weapons.MINE) and gs.weapon_step(Weapons.MINE) == 1,
			"мина II: не хватает монет — ступень не выросла")

	# --- До максимума и «МАКС».
	gs.xp = _xp_for_level(22)
	gs.money = 1000000
	_ok(gs.try_buy_weapon_step(Weapons.MINE) and gs.try_buy_weapon_step(Weapons.MINE),
			"мина II и III куплены")
	_ok(gs.weapon_step(Weapons.MINE) == 3 and gs.weapon_next_step(Weapons.MINE) == 0,
			"мина на максимуме, следующей нет")
	_ok(not gs.try_buy_weapon_step(Weapons.MINE), "четвёртой ступени нет")
	var spent: int = 1000000 - gs.money
	_ok(spent == 1500 + 4000, "за мину II+III списано 5 500")
	_ok(not gs.try_buy_weapon_step(-1) and not gs.try_buy_weapon_step(Weapons.COUNT),
			"чужой вид не покупается")

	# --- Набор для машины и вес выпадения.
	var steps: PackedByteArray = gs.weapon_steps()
	_ok(steps.size() == Weapons.COUNT and steps[Weapons.MINE] == 3
			and steps[Weapons.OIL] == 2 and steps[Weapons.LASER] == 0,
			"weapon_steps: байт на вид")
	_ok(Weapons.step_of(steps, Weapons.MINE) == 3 and Weapons.step_of(PackedByteArray(), Weapons.MINE) == 0
			and Weapons.step_of(steps, 99) == 0, "step_of: пустой набор и чужой вид — 0")
	_ok(gs.weapon_steps_total() == 5, "куплено ступеней всего: 5")
	# Мина на III — из бокса в 1.5 раза чаще: на 9000 бросках доля ~1.5/9.5.
	seed(3)
	var mines := 0
	const N := 9000
	for i in N:
		if Weapons.random_weapon(false, 0.0, -1, steps) == Weapons.MINE:
			mines += 1
	var share := float(mines) / N
	_ok(share > 0.135 and share < 0.185, "мина III выпадает чаще (доля %.3f, ждём ~0.158)" % share)
	_ok(Weapons.display_name_step(Weapons.MINE, 3) == "Мина III"
			and Weapons.display_name_step(Weapons.MINE, 1) == "Мина",
			"имя со ступенью: «Мина III», I — без приписки")

	# --- Перезапуск: профиль перечитывается.
	var gs2: Node = GS.new()
	gs2._ready()
	_ok(gs2.weapon_step(Weapons.MINE) == 3 and gs2.weapon_step(Weapons.OIL) == 2
			and gs2.weapon_step(Weapons.ROCKET) == 0, "ступени пережили перезапуск")
	_ok(gs2.money == gs.money, "деньги совпали после перезапуска")
