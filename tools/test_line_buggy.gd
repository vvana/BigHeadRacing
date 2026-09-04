extends Node3D
## Стенд полосы на Багги (ac3) — жалоба 04.09 «на багги полосу можно
## выбрать, но она не появляется». Гоняем реальный поток гаража: панель
## тюнинга → вкладка ПОЛОСА → примерка → покупка; на каждом шаге смотрим
## id подиума и материал поверхности "sticker line" кузова на подиуме.
## Профиль восстанавливается. Запуск (headless):
##   godot --headless --path . res://tools/TestLineBuggy.tscn

var _frame := 0
var _select: Node
var _failed := 0
var _saved := {}


func _ready() -> void:
	for k in ["money", "xp", "owned_cars", "car_items", "car_tuning",
			"car_colors", "selected_car_id"]:
		var v: Variant = GameState.get(k)
		_saved[k] = v.duplicate(true) if v is Dictionary or v is Array else v
	GameState.money = 50000
	GameState.xp = 2400
	if not GameState.owned_cars.has("ac3"):
		GameState.owned_cars.append("ac3")
	GameState.car_items["ac3"] = {}
	GameState.car_tuning["ac3"] = {}
	GameState.selected_car_id = GameState.full_id("ac3")
	_select = (load("res://scenes/CarSelect.tscn") as PackedScene).instantiate()
	add_child(_select)


func _ok(cond: bool, what: String) -> void:
	if not cond:
		_failed += 1
	print(("ok   " if cond else "FAIL ") + what)


## Материал поверхности "sticker line" у кузова на подиуме: "hidden",
## "line", "line:<цвет>" или "нет кузова".
func _podium_line_state() -> String:
	var model: Node = _select.get("_model")
	if model == null:
		return "нет модели"
	var body := model.get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return "нет Body"
	for i in body.mesh.get_surface_count():
		var m := body.mesh.surface_get_material(i)
		if m and m.resource_name == "sticker line":
			var ov := body.get_surface_override_material(i) as StandardMaterial3D
			if ov == null:
				return "без override"
			return "hidden" if ov.albedo_color.a == 0.0 else "line rgb=%s" % ov.albedo_color
	return "нет поверхности"


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		print("выбранная: ", GameState.selected_car_id, " индекс подиума: ", _select.get("_index"))
		_select.call("_open_tuning")
	if _frame != 40:
		return
	var panel: TuningPanel = _select.get("_tuning")
	_ok(panel.visible and panel.base() == "ac3", "панель открыта на Багги (base=%s)" % panel.base())
	_ok(panel._tabs().has("line"), "вкладка ПОЛОСА есть: %s" % [panel._tabs()])
	print("подиум до: ", _podium_line_state(), " id=", _select.call("_podium_id"))
	panel._select_tab("line")
	panel._try_on("line", 1)
	var pid: String = panel.preview_id()
	_ok(pid.contains("-l1"), "preview_id с полосой: " + pid)
	_ok(_podium_line_state().begins_with("line"), "подиум ПРИМЕРКА: " + _podium_line_state())
	var buy := Button.new()
	panel._buy_preview(buy)
	_ok(GameState.item_owned("ac3", "line"), "полоса куплена (кнопка: %s)" % buy.text)
	_ok(int(GameState.tuning_of("ac3")["line"]) == 1, "line=1 в профиле")
	var fid: String = GameState.full_id("ac3")
	_ok(fid.contains("-l1"), "полный id с полосой: " + fid)
	_ok(_podium_line_state().begins_with("line"), "подиум ПОСЛЕ ПОКУПКИ: " + _podium_line_state())
	# Переключение ВКЛ/ВЫКЛ купленной полосы.
	GameState.set_tuning("ac3", "line", 0)
	_select.call("_on_tuning_changed")
	_ok(_podium_line_state() == "hidden", "ВЫКЛ прячет: " + _podium_line_state())
	GameState.set_tuning("ac3", "line", 1)
	_select.call("_on_tuning_changed")
	_ok(_podium_line_state().begins_with("line"), "ВКЛ показывает: " + _podium_line_state())
	for k in _saved:
		GameState.set(k, _saved[k])
	GameState._save_profile()
	print("TestLineBuggy TEST: %s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)
