extends Node
## Autoload: регистрирует действия управления в InputMap при старте.
## Держим раскладку в коде, а не в project.godot — проще править и нет проблем
## с сериализацией InputEventKey в конфиге.

const ACTIONS := {
	"accelerate": [KEY_UP, KEY_W],
	"brake": [KEY_DOWN, KEY_S],
	"steer_left": [KEY_LEFT, KEY_A],
	"steer_right": [KEY_RIGHT, KEY_D],
	"handbrake": [KEY_SPACE],
	"fire": [KEY_E],             # использовать текущее оружие
	"jump": [KEY_SHIFT, KEY_K],  # прыжок как в RnRR
	"drop": [KEY_L, KEY_C],      # тоже использует оружие (привычный палец)
	"respawn": [KEY_R],          # вернуться на трассу, если застрял
}


func _ready() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	_set_window_icon()
	# Android: системная кнопка «Назад» = Esc (в гараж / закрыть панель).
	# Выход из игры по ней выключен в project.godot (quit_on_go_back=false).
	for phys in [true, false]:
		var back := InputEventKey.new()
		if phys:
			back.physical_keycode = KEY_BACK
		else:
			back.keycode = KEY_BACK
		InputMap.action_add_event("ui_cancel", back)


## Иконка окна и кнопки на панели задач (10.09: игрок прислал ярлык —
## горящее колесо). На Windows Godot берёт иконку окна из РЕСУРСОВ exe, а
## переписать их при экспорте умеет только rcedit, которого в редакторе не
## настроено, — поэтому ставим картинку сами, на старте. Android и
## веб-версии это не касается (там иконку даёт манифест), headless — тем
## более: у него нет окна, и вызов сыпал бы ошибками в стендах.
func _set_window_icon() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex: Texture2D = load("res://assets/ui/icon/icon_192.png")
	if tex == null:
		return
	DisplayServer.set_icon(tex.get_image())
