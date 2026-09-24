class_name RewardedAd
extends Node
## Ролик с вознаграждением — один показ (22.09, вынесено из CarSelect,
## когда реклама понадобилась и на плите финиша). Создаётся play(), сам
## глушит звук на время ролика, показывает ролик платформы через Ads
## (Яндекс Игры — ysdk.adv.showRewardedVideo, Android — Yandex Mobile Ads)
## или, на столе, заглушку с отсчётом 3-2-1, и по закрытию зовёт
## on_done(rewarded) — rewarded = досмотрен до конца (награда только
## тогда). После этого узел удаляет себя.
## Учёт наград — у вызывающего (гараж: GameState.register_ad, пары и
## кулдаун; финиш: удвоение опыта и монет заезда, Main._on_ad_x2_done).

signal finished(rewarded: bool)

var _subtitle := ""
var _done := false


## Запустить ролик. canvas — слой интерфейса (под ним рисуется заглушка),
## subtitle — подпись на заглушке («Ролик 1 из 2 · …»), on_done(rewarded).
static func play(canvas: Node, subtitle: String, on_done: Callable) -> RewardedAd:
	var ad := RewardedAd.new()
	ad.name = "RewardedAd"
	ad._subtitle = subtitle
	ad.finished.connect(on_done)
	canvas.add_child(ad)
	return ad


func _ready() -> void:
	_mute(true)   # платформа требует тишины на время ролика
	if Ads.available():
		# Яндекс Игры / Android: настоящий ролик (scripts/Ads.gd); занят
		# другим показом — как недосмотренный.
		if not Ads.show_rewarded(_finish):
			_finish(false)
	else:
		_simulate()


## Заглушка ролика на столе: стальная табличка с отсчётом 3-2-1, после —
## как досмотренный. Чтобы механику можно было пощупать в настольной
## сборке; на Яндекс Играх и Android сюда не заходим.
func _simulate() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var plate := UiKit.plate(dim, "steel", Vector2.ZERO, Vector2(460, 200))
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.anchor_top = 0.5
	plate.anchor_bottom = 0.5
	plate.offset_left = -230
	plate.offset_right = 230
	plate.offset_top = -100
	plate.offset_bottom = 100
	var title := UiKit.label(plate, Loc.t("РЕКЛАМА"), 26, Color.WHITE, 6)
	title.position = Vector2(0, 16)
	title.size = Vector2(460, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := UiKit.label(plate, _subtitle, 14, Color(1, 1, 1, 0.7))
	sub.position = Vector2(0, 54)
	sub.size = Vector2(460, 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var count := UiKit.label(plate, "3", 56, UiKit.YELLOW, 8)
	count.position = Vector2(0, 88)
	count.size = Vector2(460, 80)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for s in [3, 2, 1]:
		count.text = str(s)
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
	_finish(true)


func _finish(rewarded: bool) -> void:
	if _done:
		return
	_done = true
	_mute(false)
	finished.emit(rewarded)
	queue_free()


func _mute(muted: bool) -> void:
	set_muted(muted)


## Тишина на время ролика (платформы этого требуют).
static func set_muted(muted: bool) -> void:
	Music.ad_muted = muted   # чтобы возврат фокуса не включил звук в ролике
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),
			muted or Music.is_focus_muted())
