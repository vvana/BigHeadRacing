extends Node3D
## Замер: сколько реально живут запись ленты событий и анонс (защита от
## регресса «сообщения пропадают раньше времени», см. FEED_MIN_SHOW).
## Печатает посекундно число записей в ленте и детей анонсера.

var _main: Node3D
var _frame := 0
var _fired := false
var _feed_born := -1.0
var _feed_died := -1.0
var _ann_born := -1.0
var _ann_died := -1.0


func _ready() -> void:
	seed(42)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame < 160:
		return
	var now := _frame / 60.0
	if not _fired:
		_fired = true
		_main._show_weapon_event(0, 1, Weapons.ROCKET)
		_main._announcer.big("ТЕСТ АНОНСА", "подпись", "red")
		_feed_born = now
		_ann_born = now
		print("t=%.1f: событие и анонс запущены" % now)
		return
	var feed_n: int = _main._feed_box.get_child_count()
	var ann_n: int = _main._announcer.get_child_count()
	if feed_n == 0 and _feed_died < 0.0:
		_feed_died = now
		print("t=%.1f: запись ленты ИСЧЕЗЛА (жила %.1f с)"
				% [now, now - _feed_born])
	if ann_n == 0 and _ann_died < 0.0 and now - _ann_born > 0.5:
		_ann_died = now
		print("t=%.1f: анонс ИСЧЕЗ (жил %.1f с)" % [now, now - _ann_born])
	if _frame % 60 == 0:
		print("t=%.1f: лента=%d анонсер=%d" % [now, feed_n, ann_n])
	if _frame >= 160 + 14 * 60:
		var feed_life := _feed_died - _feed_born if _feed_died > 0 else 99.0
		var ann_life := _ann_died - _ann_born if _ann_died > 0 else 99.0
		var ok := feed_life >= 7.0 and ann_life >= 9.0
		print("FEED TIMING TEST: %s (лента %.1f с, анонс %.1f с)"
				% ["PASS" if ok else "FAIL", feed_life, ann_life])
		get_tree().quit(0 if ok else 1)
