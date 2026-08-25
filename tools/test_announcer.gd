extends Node
## Изолированный замер Announcer: один big() — сколько живёт и какой
## у него modulate.a по времени. Ловит регресс «анонс исчезает сразу».

var _ann: Announcer
var _frame := 0
var _died := -1.0


func _ready() -> void:
	_ann = Announcer.new()
	add_child(_ann)
	_ann.big("ТЕСТ", "подпись", "red")


func _physics_process(_d: float) -> void:
	_frame += 1
	var t := _frame / 60.0
	if _frame % 15 == 0 and t <= 3.0:
		var a := -1.0
		if _ann.get_child_count() > 0:
			a = (_ann.get_child(0) as Control).modulate.a
		print("t=%.2f: детей=%d alpha=%.2f" % [t, _ann.get_child_count(), a])
	# Смерть по ВИДИМОСТИ, не по узлу: сломанный твин когда-то оставлял
	# узел жить 9 с с alpha=0 — «жив», но игрок ничего не видел.
	var visible_now := false
	if _ann.get_child_count() > 0:
		visible_now = (_ann.get_child(0) as Control).modulate.a > 0.5
	if not visible_now and _died < 0.0 and t > 0.5:
		_died = t
		print("t=%.2f: анонс ПОГАС" % t)
	if _frame >= 12 * 60:
		# Виден не меньше своей паузы (плюс влёт до неё).
		var ok := _died < 0.0 or _died >= Announcer.BIG_HOLD
		print("ANNOUNCER TEST: %s (виден %.1f с при паузе %.1f)"
				% ["PASS" if ok else "FAIL",
				_died if _died > 0 else 12.0, Announcer.BIG_HOLD])
		get_tree().quit(0 if ok else 1)
