extends Node3D
## Автотест «уничтоженный соперник виден как уничтоженный» (жалоба 31.08:
## «не вижу, что он взрывается, а потом мигает, пока неуязвим — он будто
## продолжает ехать»).
##
## Марионетке признак «призрака» приезжает в КАЖДОМ снимке и подливает
## остаток по 0.3 c (Main._rx_state). Фаза мигания раньше считалась по
## ОСТАТКУ («прошло = ghost_time − остаток»), то есть вечно равнялась
## 1.7 из 2.0 — последней фазе, которая всегда «видна». Поэтому чужая
## машина не мигала ВООБЩЕ. Теперь фазу ведёт прожитое время (_ghost_age).
##
## Проверяем:
##   1) net_show_destroy (событие взрыва с сервера) переводит марионетку
##      в «призрака»;
##   2) при непрерывно приезжающем признаке она МИГАЕТ — видимость
##      переключается хотя бы дважды;
##   3) признак кончился — машина снова видна и снова твёрдая.
## На старом коде переключений 0 — стенд FAIL.

var _main: Node3D
var _puppet: Car
var _frame := 0
var _flips := 0
var _was_visible := true
var _ghosted := false


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == 20:
		_puppet = _main._cars[1]
		_puppet.net_make_puppet()
		# Событие взрыва с сервера — тем же путём, каким оно приезжает
		# по сети (Main._rx_destroy_fx → Car.net_show_destroy).
		_main._rx_destroy_fx(1)
		_ghosted = _puppet.is_ghost()
		_was_visible = _puppet.visible
		return
	if _frame < 20:
		return
	if _frame <= 110:
		# Каждый снимок сервера подливает признак «призрака».
		_puppet.net_set_ghost(true)
		if _puppet.visible != _was_visible:
			_flips += 1
			_was_visible = _puppet.visible
		return
	if _frame == 130:
		# Признак больше не приходит — призрак снят.
		_puppet.net_set_ghost(false)
	if _frame == 140:
		var back := _puppet.visible and not _puppet.is_ghost() \
				and _puppet.collision_layer == 0b100
		var ok := _ghosted and _flips >= 2 and back
		print("GHOST BLINK TEST: %s (взрыв дал призрака=%s, миганий %d, "
				% ["PASS" if ok else "FAIL", str(_ghosted), _flips]
				+ "вернулся видимым и твёрдым=%s)" % str(back))
		get_tree().quit(0 if ok else 1)
