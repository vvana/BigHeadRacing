# Разовая проверка подарка 1 000 000 монет (GameState.gift_1m_claimed):
# начисляется один раз при первом _ready(), повторный _ready() уже не
# начисляет. Профиль откладывается в бэкап и восстанавливается в конце.
# Запуск: godot --headless --path . --script tools/test_gift.gd
extends SceneTree

var _failed := 0
var _checks := 0
const BAK := "user://profile.cfg.bak_test_gift"
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
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL ", what)


func _run() -> void:
	# Чистый профиль (без подарка).
	var g1: Node = GS.new()
	g1._ready()
	g1.xp = 0
	g1.money = 0
	g1._gift_1m_claimed = false
	g1._save_profile()

	# Первый запуск после патча: подарок начислен, флаг сохранён.
	var g2: Node = GS.new()
	g2._ready()
	_ok(g2.money == GS.GIFT_1M_AMOUNT, "первый запуск: +1 000 000 (money=%d)" % g2.money)
	_ok(g2._gift_1m_claimed, "флаг gift_1m_claimed выставлен")

	# Повторный запуск: подарок не начисляется снова.
	var g3: Node = GS.new()
	g3._ready()
	_ok(g3.money == GS.GIFT_1M_AMOUNT, "повторный запуск: без повтора (money=%d)" % g3.money)
