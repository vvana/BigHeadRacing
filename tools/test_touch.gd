extends Node
## Стенд экранного управления (TouchControls, 09.09.2026): синтетические
## касания через Input.parse_input_event — два пальца разом (газ + руль),
## переезд пальца с ◀ на ▶, палец уполз с кнопки (держится), отпускание,
## бонус = fire «только что нажат», тап ✕ = ui_cancel на один кадр,
## кнопка СТАРТ прячет езду и даёт ui_accept, мышь как палец, освобождение
## действий при уходе слоя. Headless:
## godot --headless --path . res://tools/TestTouch.tscn

var _tc: TouchControls
var _frame := 0
var _fails := 0
var _w := 1280.0
var _h := 720.0


func _ready() -> void:
	_tc = TouchControls.new(244.0)
	add_child(_tc)
	var s := get_viewport().get_visible_rect().size
	_w = s.x
	_h = s.y
	print("[touch] полотно %s" % s)


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = _win(pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = _win(pos)
	Input.parse_input_event(ev)


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _win(pos)
	ev.global_position = _win(pos)
	Input.parse_input_event(ev)


## Полотно -> окно: parse_input_event ждёт ОКОННЫЕ координаты (в headless
## окно 64x64, полотно 1280x720 ужато в него), Window сам вернёт их в полотно.
func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _check(name: String, ok: bool) -> void:
	print("[touch] %s: %s" % [name, "ok" if ok else "FAIL"])
	if not ok:
		_fails += 1


func _process(_d: float) -> void:
	_frame += 1
	var gas := Vector2(252, _h - 112)
	var brake := Vector2(104, _h - 96)
	var left := Vector2(_w - 272, _h - 96)
	var right := Vector2(_w - 96, _h - 96)
	var bonus := Vector2(_w - 96, _h - 256)
	var exit_c := Vector2(_w - 16 - 244 - 24, 36)
	var tap_c := Vector2(_w * 0.5, _h - 60)
	match _frame:
		2:
			_touch(0, gas, true)
		3:
			_check("газ нажат", Input.is_action_pressed("accelerate"))
			_check("ось газа +1",
					is_equal_approx(Input.get_axis("brake", "accelerate"), 1.0))
			_touch(1, right, true)
		4:
			_check("второй палец: руль вправо",
					Input.is_action_pressed("steer_right"))
			_check("газ при этом держится", Input.is_action_pressed("accelerate"))
			_check("ось руля −1",
					is_equal_approx(Input.get_axis("steer_right", "steer_left"), -1.0))
			_drag(1, left)
		5:
			_check("переезд на ◀: влево", Input.is_action_pressed("steer_left"))
			_check("переезд на ◀: вправо отпущено",
					not Input.is_action_pressed("steer_right"))
			_drag(1, Vector2(_w - 292, _h - 400))
		6:
			_check("палец уполз — руль держится",
					Input.is_action_pressed("steer_left"))
			_touch(0, gas, false)
		7:
			_check("газ отпущен", not Input.is_action_pressed("accelerate"))
			_check("руль всё ещё влево", Input.is_action_pressed("steer_left"))
			_touch(1, left, false)
		8:
			_check("всё отпущено", not Input.is_action_pressed("steer_left")
					and not Input.is_action_pressed("accelerate"))
			_touch(2, bonus, true)
		9:
			_check("бонус: fire только что нажат",
					Input.is_action_just_pressed("fire"))
			_touch(2, bonus, false)
		10:
			_check("бонус отпущен", not Input.is_action_pressed("fire"))
			_touch(0, exit_c, true)
		11:
			_check("✕ по нажатию ещё ничего",
					not Input.is_action_pressed("ui_cancel"))
			_touch(0, exit_c, false)
		12:
			_check("✕ по отпусканию: ui_cancel только что нажат",
					Input.is_action_just_pressed("ui_cancel"))
		15:
			_check("✕ отпущен сам", not Input.is_action_pressed("ui_cancel"))
			_tc.show_tap("СТАРТ")
			_touch(0, gas, true)
		16:
			_check("под СТАРТ кнопки езды спрятаны — газ не жмётся",
					not Input.is_action_pressed("accelerate"))
			_touch(0, gas, false)
			_touch(3, tap_c, true)
		17:
			_touch(3, tap_c, false)
		18:
			_check("СТАРТ: ui_accept только что нажат",
					Input.is_action_just_pressed("ui_accept"))
			_tc.show_tap("")
		21:
			_check("СТАРТ отпущен сам", not Input.is_action_pressed("ui_accept"))
			_mouse(brake, true)
		22:
			_check("мышь: тормоз нажат", Input.is_action_pressed("brake"))
			_check("ось газа −1",
					is_equal_approx(Input.get_axis("brake", "accelerate"), -1.0))
			_mouse(brake, false)
		23:
			_check("мышь: тормоз отпущен", not Input.is_action_pressed("brake"))
			_touch(0, Vector2(_w * 0.5, _h * 0.5), true)
		24:
			_check("касание мимо кнопок ничего не жмёт",
					not Input.is_action_pressed("accelerate")
					and not Input.is_action_pressed("fire"))
			_touch(0, Vector2(_w * 0.5, _h * 0.5), false)
			_touch(1, gas, true)
		25:
			_check("газ перед уходом слоя нажат",
					Input.is_action_pressed("accelerate"))
			_tc.queue_free()
		27:
			_check("слой ушёл — газ отпущен",
					not Input.is_action_pressed("accelerate"))
			print("TEST_TOUCH TEST: %s (ошибок %d)"
					% ["PASS" if _fails == 0 else "FAIL", _fails])
			get_tree().quit(0 if _fails == 0 else 1)
