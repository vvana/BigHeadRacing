extends Node3D
## Кадры заезда ДЛЯ ВИТРИНЫ МАГАЗИНА (14.09.2026, RuStore): гонка на
## выбранной трассе, серия снимков по ходу заезда — из них выбираются
## лучшие. Отличия от ScreenshotHud: трасса задаётся ключом, у соперников
## человеческие ники вместо «Бот N» и «Стенд» (витрина показывает сетевой
## заезд), без форсированных плашек и финиша.
##
## Машину игрока ведёт ИИ (is_player = false): иначе без ввода она стоит
## на старте, а камера смотрит на пустую трассу. Строка клавиш «WASD…»
## прячется; --touch покажет экранные кнопки телефона (закрывают полкадра).
##
## Запуск С ОКНОМ (headless не рендерит), для витрины — 1920×1080:
## godot --path . --resolution 1920x1080 res://tools/ShotStoreRace.tscn -- <папка> --track=sand

const SHOT_FRAMES: Array[int] = [240, 300, 360, 420, 480, 560, 640, 720, 800]

var _main: Node3D
var _frame := 0
var _out := "user://shots"
var _kind := TrackBuilder.KIND_GRASS


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	for a in args:
		if a.begins_with("--track="):
			_kind = a.trim_prefix("--track=")
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.player_name = "Гонщик"
	Social.go_offline()
	Net.offline_reason = ""
	GameState.track_kind = _kind
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""
	# Ники как в сетевом заезде; нулевой слот — сам игрок.
	var nicks := PlayerNames.pick(_main._names.size())
	for i in _main._names.size():
		_main._names[i] = nicks[i]
	_main._names[0] = "Гонщик"
	var me: Car = _main._car
	me.is_player = false
	me.ai_skill = 0.92   # чуть слабее, чтобы камера держалась в гуще заезда
	_hide_help(_main)


## Строка клавиш внизу экрана — телефону не нужна, в витрине лишняя.
func _hide_help(node: Node) -> void:
	if node is Label and (node as Label).text.begins_with("WASD"):
		(node as Label).visible = false
		return
	for c in node.get_children():
		_hide_help(c)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame in SHOT_FRAMES:
		await RenderingServer.frame_post_draw
		var file := "%s_%03d.png" % [_kind, _frame]
		get_viewport().get_texture().get_image().save_png(_out + "/" + file)
		print("SHOT ", file)
	if _frame > SHOT_FRAMES[-1] + 5:
		get_tree().quit(0)
