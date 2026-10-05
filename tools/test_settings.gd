extends Node
## Стенд настроек (05.10.2026): сторона руля на экране телефона и смена
## языка из панели настроек.
##   A — раскладка TouchControls: по умолчанию руль слева, педали справа;
##       steer_right — зеркально; ◀ всегда левее ▶; автогаз прячет «ГАЗ».
##   B — выбор ENGLISH в панели перезагружает гараж на английском и снова
##       открывает настройки; РУССКИЙ возвращает русский.
## Стенд живёт в get_tree().root: гараж перезагружается (reload_current_scene).
## Headless: godot --headless --path . res://tools/TestSettings.tscn


class Watcher:
	extends Node

	var step := 0
	var wait := 0
	var fails := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_layout_checks()
		get_tree().change_scene_to_file.call_deferred("res://scenes/CarSelect.tscn")

	func _check(ok: bool, what: String) -> void:
		print("  %s: %s" % [what, "PASS" if ok else "FAIL"])
		if not ok:
			fails += 1

	func _layout_checks() -> void:
		var half := get_viewport().get_visible_rect().size.x * 0.5
		for sr: bool in [false, true]:
			GameState.steer_right = sr
			GameState.auto_gas = false
			var tc := TouchControls.new()
			add_child(tc)
			var l: Vector2 = tc._by_kind["left"].center
			var r: Vector2 = tc._by_kind["right"].center
			var gas: Vector2 = tc._by_kind["gas"].center
			var brake: Vector2 = tc._by_kind["brake"].center
			var bonus: Vector2 = tc._by_kind["bonus"].center
			var tag := "руль справа" if sr else "руль слева (умолчание)"
			_check(l.x < r.x, tag + ": ◀ левее ▶")
			_check((r.x > half) == sr and (l.x > half) == sr, tag + ": руль на своей стороне")
			_check((gas.x < half) == sr and (brake.x < half) == sr, tag + ": педали напротив")
			_check((bonus.x > half) == sr, tag + ": бонус со стороны руля")
			tc.free()
			GameState.auto_gas = true
			tc = TouchControls.new()
			add_child(tc)
			_check(not tc._by_kind["gas"].visible, tag + ": автогаз прячет «ГАЗ»")
			_check((tc._by_kind["brake"].center.x < half) == sr, tag + ": тормоз при автогазе")
			tc.free()
		GameState.steer_right = false
		GameState.auto_gas = false

	func _garage() -> Node:
		var s := get_tree().current_scene
		return s if s != null and s.get("_settings") != null else null

	func _process(_d: float) -> void:
		wait += 1
		var g := _garage()
		if g == null:
			if wait > 600:
				_check(false, "гараж не поднялся")
				_finish()
			return
		var panel: SettingsPanel = g.get("_settings")
		match step:
			0:
				if wait < 30:
					return
				g.call("_close_name_dialog")
				g.call("_open_settings")
				panel._pick_lang("en")
				step = 1
				wait = 0
			1:
				if wait < 30:
					return
				_check(Loc.is_en(), "после ENGLISH игра английская")
				_check(panel.visible, "настройки открыты после перезагрузки гаража")
				_check((g.get("_settings_btn") as Button).text == "SETTINGS",
						"гараж пересобран на английском")
				panel._pick_lang("ru")
				step = 2
				wait = 0
			2:
				if wait < 30:
					return
				_check(not Loc.is_en(), "после РУССКИЙ игра русская")
				_check((g.get("_settings_btn") as Button).text == "НАСТРОЙКИ",
						"гараж пересобран на русском")
				panel._pick_lang("")
				_finish()

	func _finish() -> void:
		print("SETTINGS TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
		get_tree().quit(0 if fails == 0 else 1)
		set_process(false)


func _ready() -> void:
	var w := Watcher.new()
	w.name = "SettingsWatcher"
	get_tree().root.add_child.call_deferred(w)
