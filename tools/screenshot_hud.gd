extends Node3D
## Служебные снимки HUD: грузит Main и снимает кадры интерфейса —
## отсчёт «3», момент «GO!», обычная езда (панели, слот оружия),
## предупреждение и финишный баннер (включаются принудительно).
## Запуск С ОКНОМ (headless не рендерит):
## godot --path . res://tools/ScreenshotHud.tscn -- <папка_вывода>

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
	# Позже Main._process: тот каждый кадр гасит плашку предупреждения,
	# а стенду надо её принудительно показать.
	process_priority = 100


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + file)
	print("SHOT ", file)


func _process(_d: float) -> void:
	# После Main._process (process_priority) — иначе тот гасит плашку.
	if _frame >= 295 and _frame <= 315:
		_main._warn_label.text = "Вне трассы! Возврат через 2…"
		_main._warn_panel.visible = true


func _physics_process(_d: float) -> void:
	_frame += 1
	match _frame:
		20:
			_shot("hud_count3.png")
		165:
			_shot("hud_go.png")
		280:
			_shot("hud_race.png")
		305:
			_shot("hud_warn.png")
		320:
			_main._warn_panel.visible = false
			_main._finish_label.text = "ФИНИШ!  Место: 1 из 4"
			_main._finish_root.visible = true
		325:
			_shot("hud_finish.png")
		330:
			_main._finish_root.visible = false
			# Авиаудар прямо по игроку (не по лидеру — тот может быть вне
			# кадра): через ~0.6 с тени с кольцами и ракеты в полёте.
			var strike := Airstrike.new()
			strike.track = _main._track
			strike.target = _main._car
			_main.add_child(strike)
		365:
			_shot("hud_airstrike.png")
		430:
			# Значки действующих эффектов над крышей — двумя кадрами и ОБА
			# на своей машине: соперника сюда не притащить, ИИ тут же уводит
			# его на свою траекторию и в кадр он не попадает (проверено).
			# Кадр поздний: раньше оранжевые тени авиаудара перекрывали значок.
			# ГРАБЛИ (см. ПРОГРЕСС): тип _main — Node3D, поэтому у _main._car
			# тип НЕ выводится, и `var x := _main._car.что-то` роняет парсинг
			# всего стенда — окно висит без единого кадра. Пишем тип явно.
			var player: Car = _main._car
			player.show_effect_icon(Weapons.MAGNET, 5.0)
		445:
			_shot("hud_status_magnet.png")
		450:
			var player2: Car = _main._car
			player2._status_time = 0.0
			player2._boost_time = 5.0
		465:
			_shot("hud_status_boost.png")
		470:
			# Всплывающие анонсы: большой «штамп» + малый ярус.
			_main._announcer.big("ДВОЙНОЕ УБИЙСТВО!", "Player 1", "red")
			_main._announcer.small("Player 3 уничтожен!", "teal")
		492:
			_shot("hud_announce.png")
		500:
			get_tree().quit(0)
