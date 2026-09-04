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


## Прокрутка меню панели: ScrollContainer лежит в колонке-корне (под ним
## неподвижный подвал с «КУПИТЬ»), потому ищем рекурсивно.
func _find_scroll(root: Node) -> ScrollContainer:
	if root is ScrollContainer:
		return root
	for c in root.get_children():
		var s := _find_scroll(c)
		if s != null:
			return s
	return null


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 60:
		_select.call("_open_tuning")
	# Ключ `--tab <вкладка>` (engine/wheel/spoiler/exhaust/paint/line/sticker):
	# открыть эту вкладку панели. ПЕРВЫМ делом: смена вкладки снимает
	# примерку (03.09, ночь), иначе --preview с ней не сложить.
	var ta := OS.get_cmdline_user_args()
	var ti := ta.find("--tab")
	if _frame == 66 and ti >= 0 and ti + 1 < ta.size():
		(_select.get("_tuning") as TuningPanel)._select_tab(ta[ti + 1])
	# Ключ `--preview`: примерить некупленную деталь ОТКРЫТОЙ вкладки (по
	# умолчанию мотор) — оранжевая рамка и строка «ПРИМЕРКА … КУПИТЬ» внизу.
	if _frame == 70 and OS.get_cmdline_user_args().has("--preview"):
		var panel: TuningPanel = _select.get("_tuning")
		var b: String = panel.base()
		var slot: String = panel._tab
		if slot == "fx":
			# Вкладка ЭФФЕКТЫ: примерить голубой дым и розовый неон — на
			# подиуме появляются клубы дыма и пятно неона.
			panel._try_on("smoke", "cyan")
			panel._try_on("neon", "pink")
			return
		if not GameState.UPGRADE_SLOTS.has(slot):
			slot = "engine"
		panel._try_on(slot, CarModelLibrary.slot_options(b, slot)[-1])
	# Ключ `--bottom`: прокрутить панель вниз (краски и наклейки).
	if _frame == 80 and OS.get_cmdline_user_args().has("--bottom"):
		var panel: Control = _select.get("_tuning")
		var scroll := _find_scroll(panel)
		if scroll != null:
			scroll.scroll_vertical = 9999
	if _frame == 100:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var args := OS.get_cmdline_user_args()
		var name := "tuning_soviet.png" if args.has("--soviet") \
				else ("tuning_bottom.png" if args.has("--bottom") else "tuning.png")
		if args.has("--preview"):
			name = name.replace(".png", "_preview.png")
		var tab := args.find("--tab")
		if tab >= 0 and tab + 1 < args.size():
			name = name.replace(".png", "_%s.png" % args[tab + 1])
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)
