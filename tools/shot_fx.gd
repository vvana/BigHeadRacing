extends Node3D
## Служебные снимки СПЕЦЭФФЕКТОВ (Epic Toon FX): грузит Main и по кадрам
## принудительно включает эффекты возле машины игрока — огонь буста,
## выстрел ракетой (вспышка+шлейф), масляная клякса, заморозка соперника,
## взрыв машины (вспышка+кольцо+дым+искры).
## Запуск С ОКНОМ (headless не рендерит):
## godot --path . res://tools/ShotFx.tscn -- <папка_вывода>

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
	var cars: Array = _main._cars
	if cars.is_empty():
		return
	var me: Car = cars[0]
	match _frame:
		250:   # отсчёт прошёл, машины едут; буст — огонь из выхлопа
			me.apply_boost()
		262:
			_shot("fx_boost_flame.png")
		278:   # ракета: вспышка у дула + огненный шлейф
			me.weapon = Weapons.ROCKET
			me.use_weapon()
		280:
			_shot("fx_rocket.png")
		300:   # масло: клякса ложится за корму
			me.weapon = Weapons.OIL
			me.use_weapon()
		318:
			_shot("fx_oil.png")
		335:   # заморозка ближнего соперника: снежный разлёт
			(cars[1] as Car).global_position = \
					me.global_position + Vector3(2.5, 0.5, -3.0)
			(cars[1] as Car).apply_freeze(3.0)
		338:
			_shot("fx_freeze.png")
		365:   # взрыв: вспышка + кольцо + дым + искры + огонь + выжженное пятно
			(cars[2] as Car).global_position = \
					me.global_position + Vector3(-2.5, 0.5, -4.0)
			(cars[2] as Car).destroy()
		368:
			_shot("fx_explosion.png")
		378:
			_shot("fx_explosion_late.png")
		395:   # магнит: кольцо + фиолетовые разряды (и на жертвах)
			me.weapon = Weapons.MAGNET
			me.use_weapon()
		398:
			_shot("fx_magnet.png")
		420:   # звёзды тарана — форсим напрямую
			FxKit.stars_burst(_main, me.global_position + Vector3.UP * 0.9, 8)
		424:
			_shot("fx_stars.png")
		440:   # конфетти финиша
			FxKit.confetti_burst(_main, me.global_position + Vector3.UP * 1.2)
		452:
			_shot("fx_confetti.png")
		470:
			print("DONE")
			get_tree().quit()
