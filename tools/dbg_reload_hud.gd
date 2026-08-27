extends Node
## Диагностика «после перезагрузки пропадает uikit»: клиент едет заезд,
## сервер после финиша перезапускает трассу (_rx_reset), сцена
## перезагружается — и в НОВОМ заезде снимаем экран и печатаем, что с HUD.
## Запуск С РЕНДЕРОМ: godot --path . res://tools/DbgReloadHud.tscn

static var _run := 0
var _main: Node3D
var _shot_frames := 0
var _raced := false


func _ready() -> void:
	_run += 1
	_main = get_parent() as Node3D
	print("  [dbg] запуск сцены %d" % _run)
	if _run == 1:
		Net.join_server("127.0.0.1", Net.PORT, false)


func _physics_process(_d: float) -> void:
	Input.action_press("accelerate")
	if _main._net_started:
		_raced = true


var _lobby_shot := false


func _process(_d: float) -> void:
	# Снимок ЛОББИ после перезагрузки — до старта нового заезда: жалоба
	# могла быть и на него, а не на HUD гонки.
	if _run >= 2 and not _lobby_shot and not _raced 			and _main._lobby != null and _main._lobby.visible:
		_lobby_shot = true
		_shot("bhr_reload_lobby.png")
	# Во втором запуске (после перезагрузки) ждём старта нового заезда
	# и снимаем экран через пару секунд после него.
	if _run < 2 or not _raced:
		return
	_shot_frames += 1
	if _shot_frames == 120:
		_report()


func _report() -> void:
	var canvas := _main.get_node_or_null("CanvasLayer")
	print("  [dbg] после перезагрузки: canvas=%s" % str(canvas != null))
	print("  [dbg] speed_label=%s lap=%s pos=%s minimap=%s lobby=%s"
			% [_lbl(_main._speed_label), _lbl(_main._lap_label),
			_lbl(_main._pos_label), str(_main._minimap != null),
			str(_main._lobby != null and _main._lobby.visible)])
	await _shot("bhr_reload_hud.png")
	get_tree().quit(0)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("USERPROFILE") + "/" + file
	img.save_png(out)
	print("  [dbg] снимок: %s" % out)


func _lbl(l: Label) -> String:
	if l == null:
		return "null"
	return "есть, видим=%s, в дереве=%s" % [
			str(l.visible and l.is_visible_in_tree()), str(l.is_inside_tree())]
