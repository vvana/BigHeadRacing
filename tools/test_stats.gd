# Стенд СТАТИСТИКИ ИГРОКА (09.09): record_race/record_soccer, рейтинг
# (±20 по месту, +2 за уничтоженного, не ниже нуля), среднее и лучшее
# место, любимая машина, футбол, uid один на профиль; всё переживает
# перезапуск (профиль перечитывается). Профиль игрока СНАЧАЛА откладывается
# в бэкап и в конце ВОССТАНАВЛИВАЕТСЯ. Запуск:
# godot --headless --path . --script tools/test_stats.gd
extends SceneTree

var _failed := 0
var _checks := 0
const BAK := "user://profile.cfg.bak_test_stats"
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
	print("STATS TEST: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL ", what)


func _run() -> void:
	var gs: Node = GS.new()
	gs._ready()
	gs.stats = {}
	gs._save_profile()
	var uid: String = gs.uid
	_ok(uid.length() == 16, "uid сгенерирован (16 hex)")
	_ok(gs.rating() == GS.RATING_START and gs.avg_place() == 0.0
			and gs.favourite_car()[0] == "", "пустая статистика: 1000, «—»")

	var d: int = gs.record_race(1, 8, 2, 1, "vz01", false)
	_ok(d == 24 and gs.rating() == 1024, "победа из 8 + 2 убийства: +24 → 1024 (было %d)" % d)
	d = gs.record_race(8, 8, 0, 2, "vz01", true)
	_ok(d == -20 and gs.rating() == 1004, "последнее из 8: −20 → 1004")
	d = gs.record_race(4, 7, 1, 0, "ac1", true)
	_ok(d == 2 and gs.rating() == 1006, "4-е из 7 (середина) + убийство: +2")
	d = gs.record_race(2, 4, 0, 1, "ac1", false)
	_ok(d == 7 and gs.rating() == 1013, "2-е из 4: round(20·1/3) = +7")
	_ok(int(gs.stats.races) == 4 and int(gs.stats.net_races) == 2,
			"заездов 4, сетевых 2")
	_ok(int(gs.stats.wins) == 1 and int(gs.stats.podiums) == 2,
			"побед 1, подиумов 2")
	_ok(int(gs.stats.kills) == 3 and int(gs.stats.deaths) == 4,
			"уничтожено 3, уничтожали 4 (1+2+0+1)")
	_ok(is_equal_approx(gs.avg_place(), 15.0 / 4.0), "среднее место 3.75")
	var fav: Array = gs.favourite_car()
	_ok(fav[0] == "ac1" and int(fav[1]) == 2 or (fav[0] == "vz01" and int(fav[1]) == 2),
			"любимая — одна из двух с 2 заездами")
	gs.record_race(3, 8, 0, 0, "ac1", false)
	fav = gs.favourite_car()
	_ok(fav[0] == "ac1" and int(fav[1]) == 3, "любимая — ac1 (3 заезда)")
	# Рейтинг не ниже нуля.
	gs.stats.rating = 5
	d = gs.record_race(8, 8, 0, 2, "ac1", false)
	_ok(gs.rating() == 0 and d == -20, "рейтинг упёрся в 0")
	# Кламп места.
	gs.stats.rating = 1000
	d = gs.record_race(99, 8, 0, 0, "ac1", false)
	_ok(d == -20, "место за пределами — как последнее")
	gs.record_soccer(1, 2)
	gs.record_soccer(0, 0)
	gs.record_soccer(-1, 1)
	_ok(int(gs.stats.soccer_games) == 3 and int(gs.stats.soccer_wins) == 1
			and int(gs.stats.soccer_goals) == 3, "футбол: 3 матча, 1 победа, 3 гола")

	# Перезапуск: всё перечитывается, uid тот же.
	var gs2: Node = GS.new()
	gs2._ready()
	_ok(gs2.uid == uid, "uid переживает перезапуск")
	_ok(int(gs2.stats.races) == 7 and gs2.rating() == 980
			and int(gs2.stats.kills) == 3 and int(gs2.stats.soccer_goals) == 3,
			"статистика перечитана: 7 заездов, рейтинг 980, 3 убийства, 3 гола")
	_ok(gs2.favourite_car()[0] == "ac1" and int(gs2.favourite_car()[1]) == 5,
			"любимая машина после перезапуска")
	# Старый профиль без статистики: пусто, а не падение.
	gs2.stats = {}
	gs2._save_profile()
	var gs3: Node = GS.new()
	gs3._ready()
	_ok(gs3.stats.is_empty() and gs3.rating() == GS.RATING_START,
			"профиль без статистики читается")
