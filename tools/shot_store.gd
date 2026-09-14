extends Node3D
## Снимок гаража ДЛЯ ВИТРИНЫ МАГАЗИНА (11.09.2026, публикация в RuStore).
## Обычный ScreenshotSelect для карточки не годится: он поднимается на
## тестовом профиле, а тот рисует красную плашку «СТЕНД · ТЕСТОВЫЙ
## ПРОФИЛЬ» и, если имя стенда занято на сервере друзей, ещё и окно «КАК
## ТЕБЯ ЗОВУТ?» поверх машины. Здесь то и другое убирается, связь с
## сервером друзей не поднимается вовсе — в кадре чистый гараж.
##
## Запуск С ОКНОМ (headless не рендерит):
## godot --path . res://tools/ShotStore.tscn -- <папка_вывода>

var _select: Node
var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.player_name = "Гонщик"
	Social.go_offline()
	_select = (load("res://scenes/CarSelect.tscn") as PackedScene).instantiate()
	add_child(_select)


## Красная плашка тестового профиля: ищем её по подписи (путь к
## profile_test.cfg) и прячем вместе с родителем.
func _hide_test_badge(node: Node) -> void:
	if node is Label and (node as Label).text == GameState.PROFILE_TEST_PATH:
		var badge := node.get_parent() as CanvasItem
		if badge:
			badge.visible = false
		return
	for c in node.get_children():
		_hide_test_badge(c)


func _process(_d: float) -> void:
	_frame += 1
	if _frame == 20:
		Social.go_offline()
		Social.connected = false
		Social.name_ok = false
		if _select.has_method("_close_name_dialog"):
			_select.call("_close_name_dialog")
		_hide_test_badge(_select)
	if _frame == 70:
		# Ещё раз: окно имени могло прилететь ответом сервера позже.
		if _select.has_method("_close_name_dialog"):
			_select.call("_close_name_dialog")
		_hide_test_badge(_select)
	if _frame == 90:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out + "/store_garage.png")
		print("SHOT store_garage.png")
		get_tree().quit(0)
