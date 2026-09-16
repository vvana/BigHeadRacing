# Проверка стартового кошелька: новый игрок начинает с 0 монет.
# 02.09 здесь проверяли разовый подарок 1 000 000 монет (флаг
# gift_1m_claimed); 16.09 подарок убран — его получал КАЖДЫЙ новый
# профиль, а не только два задуманных. Стенд сторожит, чтобы в
# _ready() снова не появилось начисление «из воздуха».
# Запуск: godot --headless --path . --script tools/test_gift.gd
extends SceneTree

var _failed := 0
var _checks := 0
const GS := preload("res://scripts/GameState.gd")


func _init() -> void:
	# Профиль стенда (--script → user://profile_test.cfg), боевой не трогаем.
	var abs := ProjectSettings.globalize_path(GS.PROFILE_PATH)
	_run()
	DirAccess.remove_absolute(abs)
	print("RESULT: %d/%d ok" % [_checks - _failed, _checks])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL ", what)


func _run() -> void:
	# Чистый профиль: файла нет вовсе.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GS.PROFILE_PATH))
	var g1: Node = GS.new()
	g1._ready()
	_ok(g1.money == 0, "новый профиль: 0 монет (money=%d)" % g1.money)
	_ok(g1.xp == 0, "новый профиль: 0 опыта (xp=%d)" % g1.xp)
	g1._save_profile()

	# Второй запуск на сохранённом профиле: по-прежнему 0, ничего не капает.
	var g2: Node = GS.new()
	g2._ready()
	_ok(g2.money == 0, "повторный запуск: по-прежнему 0 (money=%d)" % g2.money)

	# Заработанное сохраняется и не подменяется подарком.
	g2.money = 750
	g2._save_profile()
	var g3: Node = GS.new()
	g3._ready()
	_ok(g3.money == 750, "заработанное переживает перезапуск (money=%d)" % g3.money)
