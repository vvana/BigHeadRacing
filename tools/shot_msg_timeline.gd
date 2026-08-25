extends Node3D
## Служебный стенд: таймлайн жизни сообщений В РЕАЛЬНОМ РЕНДЕРЕ.
## На кадре 200 — запись в ленту + большой анонс, дальше скриншоты
## через 0.5/2/4/6/8/10 с. Запуск С ОКНОМ:
## godot --path . res://tools/ShotMsgTimeline.tscn -- <папка_вывода>

var _main: Node3D
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


func _physics_process(_d: float) -> void:
	_frame += 1
	match _frame:
		200:
			_main._show_weapon_event(0, 1, Weapons.ROCKET)
			_main._announcer.big("ТЕСТ ТАЙМЛАЙНА", "Player 1", "red")
			# Мину в слот — заодно виден значок мины на HUD.
			var player: Car = _main._car
			player.weapon = Weapons.MINE
			print("t=0: событие + анонс")
		230:
			_shot("msg_0_5s.png")
		320:
			_shot("msg_2s.png")
		440:
			_shot("msg_4s.png")
		560:
			_shot("msg_6s.png")
		680:
			_shot("msg_8s.png")
		800:
			_shot("msg_10s.png")
		820:
			get_tree().quit(0)
