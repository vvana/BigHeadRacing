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
	"fire": [KEY_CTRL, KEY_J],   # снаряд вперёд
	"jump": [KEY_SHIFT, KEY_K],  # прыжок как в RnRR
	"drop": [KEY_L, KEY_C],      # мина назад
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
