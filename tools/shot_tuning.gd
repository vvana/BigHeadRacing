extends Node3D
## Снимок гаража с открытой панелью «ТЮНИНГ» на аркадной машине. Профиль
## НЕ трогается: владение и монеты подменяются только в памяти (панель
## ничего не покупает, лишь рисует). Ключ `--soviet` — панель на Копейке
## (без деталей, только ступени). Запуск С ОКНОМ:
## godot --path . res://tools/ShotTuning.tscn -- <папка_вывода> [--soviet]

var _frame := 0
var _out := "user://shots"
var _select: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var base := "vz01" if args.has("--soviet") else "ac1"
	if not GameState.owned_cars.has(base):
		GameState.owned_cars.append(base)
	GameState.money = 12345
	GameState.xp = 2400   # ~10 уровень: ступени I и II доступны
	if base == "ac1":
		# Поштучно (03.09): пара компрессоров и три комплекта дисков.
		GameState.car_items[base] = {"engine:1": true, "engine:2": true,
				"wheel:2": true, "wheel:4": true, "wheel:5": true,
				"sticker:2": true}
		GameState.car_tuning[base] = {"color": "orange", "shade": 2,
				"engine": 2, "wheel": 5, "sticker": 0}
	GameState.selected_car_id = GameState.full_id(base)
	_select = (load("res://scenes/CarSelect.tscn") as PackedScene).instantiate()
	add_child(_select)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 60:
		_select.call("_open_tuning")
	# Ключ `--preview`: примерить некупленное (мотор №7 и диски, у Копейки
	# — из её набора) — оранжевые рамки, строка «ПРИМЕРКА … КУПИТЬ».
	if _frame == 70 and OS.get_cmdline_user_args().has("--preview"):
		var panel: TuningPanel = _select.get("_tuning")
		var b: String = panel.base()
		panel._try_on("engine", CarModelLibrary.slot_options(b, "engine")[-1])
		panel._try_on("wheel", CarModelLibrary.slot_options(b, "wheel")[-1])
	# Ключ `--bottom`: прокрутить панель вниз (краски и наклейки).
	if _frame == 80 and OS.get_cmdline_user_args().has("--bottom"):
		var panel: Control = _select.get("_tuning")
		for c in panel.get_children():
			if c is ScrollContainer:
				(c as ScrollContainer).scroll_vertical = 9999
	if _frame == 100:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var args := OS.get_cmdline_user_args()
		var name := "tuning_soviet.png" if args.has("--soviet") \
				else ("tuning_bottom.png" if args.has("--bottom") else "tuning.png")
		if args.has("--preview"):
			name = name.replace(".png", "_preview.png")
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)
