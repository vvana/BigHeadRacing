extends Node3D
## ГАРАЖ — главный экран игры. Слева машина стоит в освещённом боксе
## (тянешь мышью или пальцем — поворачивается), справа — эмалевая доска
## «АВТОПАРК» с миниатюрами всех машин. Сверху полка табличек: «ГАРАЖ»,
## уровень с полосой опыта, кошелёк, «+500 ЗА РЕКЛАМУ», имя игрока.
## Снизу слева — имя машины, ряд красок, «РЕЖИМ», «СТАРТ», «ТЮНИНГ».
## Стиль — эмалевые таблички с заклёпками и аварийными лентами по
## референсам в корне проекта (UiKit). Адреса сервера на экране НЕТ:
## «СТАРТ» стучится на адрес из Net (по умолчанию VDS), не ответил —
## тихо едем оффлайн с ботами.
## Управление: ←→ / A D — листать, ↑↓ — по рядам доски, мышь — клик по
## ячейке (повторный клик по выбранной — старт), Enter/Space — в гонку.

## Человеческие названия машин (БАЗОВЫЙ id → имя на экране).
const DISPLAY_NAMES := {
	"vz01": "Копейка", "vz02": "Двойка", "vz21": "Нива",
	"vz03": "Тройка", "vz04": "Четвёрка", "vz05": "Пятёрка",
	"vz06": "Шестёрка", "vz07": "Семёрка", "vz05r": "Пятёрка Спорт",
	"vz08": "Зубило", "vz09": "Девятка", "vz099": "Самара 99",
	"gz21": "Волга 21", "gz24": "Волга 24", "vz31": "Нива Лонг",
	"fastback": "Fastback", "godfather": "Godfather", "lemans": "Le Mans GT",
	"superbird": "Superbird", "chevelle": "Chevelle SS", "diablo": "Diablo",
	"dragster": "Dragster", "safari": "Safari 4x4",
	# Аркадные конструкторы (Customizable Arcade Car Pack).
	"ac1": "Стрела", "ac2": "Сарай", "ac3": "Багги", "ac4": "Малыш",
	"ac5": "Пикап", "ac6": "Монстр", "ac7": "Маслкар", "ac8": "Кирпич",
}

const GRID_COLUMNS := 5
const THUMB_SIZE := Vector2(104, 78)

## Сколько радиан поворота подиума даёт один пиксель протяжки.
const DRAG_SPEED := 0.008

## Раскладка экрана (базовое окно 1280×720, растяжка canvas_items).
const TOP_Y := 18          # верхняя полка табличек (ярлык торчит выше на 8)
const TOP_H := 80
const BOARD_X := 684       # левая кромка доски «АВТОПАРК»
const BOARD_Y := 110
const BOARD_W := 580
const BOARD_H := 594
## Нижний ряд кнопок. Табличка-стайлбокс несёт поля 20 px сверху и снизу,
## и кнопка НЕ может быть ниже «40 + строка шрифта» (у Russo One 26 px —
## около 74): при 56 «СТАРТ» вырастал сам и уезжал за нижний край окна
## (снимок 03.09). Держим ряд 74 px — с запасом под метрики любой машины.
const ROW_H := 74
const ROW_Y := -12 - ROW_H
## Левая колонка (имя машины, краски, нижний ряд кнопок, подсказка) —
## один Control шириной COL_W. Пока подменю закрыты, машина стоит по
## центру экрана и колонка центрирована (COL_X_CENTER); открыли
## «АВТОПАРК» или «ТЮНИНГ» — колонка и камера (h_offset → CAM_H_OPEN)
## съезжают влево, освобождая правую половину под доску.
const COL_W := 656
const COL_X_CENTER := 312.0    # 640 − COL_W/2
const COL_X_OPEN := 12.0
const CAM_H_OPEN := 1.59
const SLIDE_TIME := 0.35
const UI_DIR := "res://assets/ui/garage/"

## Показ ролика на Яндекс Играх. Результат складываем в window.bhrAd и
## опрашиваем из _process (JavaScriptBridge не умеет ждать промис).
const AD_JS_SHOW := """
window.bhrAd = {state: 'showing', rewarded: false};
try {
	window.ysdk.adv.showRewardedVideo({callbacks: {
		onRewarded: function() { window.bhrAd.rewarded = true; },
		onClose: function() { window.bhrAd.state = 'closed'; },
		onError: function(e) { window.bhrAd.state = 'error'; }
	}});
} catch (e) { window.bhrAd.state = 'error'; }
"""

var _index := 0
var _turntable: Node3D
var _dragging := false            # тянут машину на подиуме (мышь/палец)
var _model: Node3D
var _podium_smoke: Array[CPUParticles3D] = []   # цветной дым на подиуме
var _name_label: Label
var _count_label: Label
var _buttons: Array[Button] = []
var _mode_button: Button          # переключатель ГОНКА/ФУТБОЛ
var _canvas: CanvasLayer          # слой HUD (нужен окну ввода имени)
var _name_btn: Button             # «ИМЯ: …» на верхней полке
var _name_dialog: Control         # модальное окно ввода имени (null — нет)
var _name_edit: LineEdit
var _scroll: ScrollContainer
var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _ui_font: FontFile  # Russo One — индустриальный, с кириллицей
var _level_label: Label           # «УРОВЕНЬ 10» на жёлтой табличке
var _xp_sub: Label                # «895 / 1000» рядом
var _xp_bar: ProgressBar          # полоса опыта внутри уровня
var _coins_label: Label           # число монет на белой табличке
var _coin_flash: Label            # «+500» взлетает над кошельком
var _ad_btn: Button               # «+500 ЗА РЕКЛАМУ» / «ЧЕРЕЗ 9:59»
var _ad_showing := false          # ролик идёт (ждём результата платформы)
var _ad_tick := 0.0               # таймер обновления кнопки рекламы
var _connecting := false          # «СТАРТ» уже нажат, ждём сервер
var _start_btn: Button            # «СТАРТ» (у купленной машины)
var _buy_btn: Button              # «КУПИТЬ · цена» (у закрытой машины)
var _grid_locks: Array[Label] = []    # ярлыки «N ур.» на ячейках доски
var _buy_flash := 0               # поколение вспышки «НЕ ХВАТАЕТ МОНЕТ»
var _tuning: TuningPanel          # панель косметики (на месте доски)
var _tuning_btn: Button           # «ТЮНИНГ» (у купленной аркадной машины)
var _board_btn: Button            # «АВТОПАРК» — открыть доску миниатюр
var _grid_panel: Control          # доска «АВТОПАРК» (скрыта, пока не открыли)
var _column: Control              # левая колонка HUD (см. COL_*)
var _arrows: Array[TextureButton] = []   # стрелки листания (прячутся с доской)
var _cam: Camera3D
var _panel_open := false          # открыта доска или тюнинг (машина слева)
var _ui_tween: Tween              # съезд колонки и камеры


## Полный id скина машины из сетки: база + её текущий цвет/комплектация.
func _full_id(i: int) -> String:
	return GameState.full_id(CarModelLibrary.CAR_IDS[i])


func _ready() -> void:
	_index = maxi(0, CarModelLibrary.CAR_IDS.find(
			CarModelLibrary.base_id(GameState.selected_car_id)))
	Music.play_menu()
	_setup_environment()
	_setup_garage()
	_setup_podium()
	_setup_hud()
	_set_index(_index)
	_generate_thumbs()
	# Имя игрока: под ним его увидят соперники. Сначала спрашиваем платформу
	# (Яндекс Игры отдают имя из SDK — см. GameState.platform_name), не
	# дала — при ПЕРВОМ запуске показываем окно ввода.
	if GameState.player_name == "":
		var pn: String = GameState.platform_name()
		if pn != "":
			GameState.set_player_name(pn)
			_refresh_name_btn()
		else:
			_open_name_dialog(true)


func _process(delta: float) -> void:
	# Кнопка рекламы живёт по часам (обратный отсчёт) и ждёт результат
	# ролика от платформы — обновляем дважды в секунду, всегда.
	_ad_tick -= delta
	if _ad_tick <= 0.0:
		_ad_tick = 0.5
		_refresh_ad_btn()
		if _ad_showing and OS.has_feature("web"):
			_poll_web_ad()
	# Подиум сам не крутится — только рукой (см. _unhandled_input).
	# Открыто окно ввода имени — клавиши достаются ему, а не выбору машины
	# (иначе Enter в поле имени тут же запускал бы гонку).
	if _name_dialog != null or _ad_showing:
		return
	# Открыта панель тюнинга — стрелки ей не мешают; Esc закрывает.
	if _tuning != null and _tuning.visible:
		if Input.is_action_just_pressed("ui_cancel"):
			_tuning.close()
		return
	# Esc закрывает и доску «АВТОПАРК».
	if _grid_panel != null and _grid_panel.visible \
			and Input.is_action_just_pressed("ui_cancel"):
		_close_board()
		return

	var total := CarModelLibrary.CAR_IDS.size()
	if Input.is_action_just_pressed("ui_right") \
			or Input.is_action_just_pressed("steer_right"):
		_set_index((_index + 1) % total)
	elif Input.is_action_just_pressed("ui_left") \
			or Input.is_action_just_pressed("steer_left"):
		_set_index((_index - 1 + total) % total)
	elif Input.is_action_just_pressed("ui_down"):
		_set_index(mini(_index + GRID_COLUMNS, total - 1))
	elif Input.is_action_just_pressed("ui_up"):
		_set_index(maxi(_index - GRID_COLUMNS, 0))
	elif Input.is_action_just_pressed("ui_accept"):
		_start_race()


## Вращение машины на подиуме мышью или пальцем: тянем по горизонтали —
## подиум поворачивается, отпустили — стоит. Сюда события доходят только
## если их не забрал HUD (кнопки, доска миниатюр), то есть крутить можно
## за свободное место вокруг машины. Касания приходят как мышь (штатная
## эмуляция Godot, input_devices/pointing/emulate_mouse_from_touch),
## поэтому отдельной ветки для тачскрина не нужно.
func _unhandled_input(event: InputEvent) -> void:
	if _name_dialog != null or _ad_showing:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_turntable.rotation.y += (event as InputEventMouseMotion).relative.x \
				* DRAG_SPEED


## Куда стучится «СТАРТ»: [адрес, порт]. Адрес — из Net (сохранённый в
## net.cfg, по умолчанию VDS), порт — ДОМАШНИЙ, а не текущий: после
## перенаправления в комнату Net.port равен порту КОМНАТЫ, а комнаты
## смертны (поймано у живого игрока 28.08). Поля адреса на экране больше
## нет (просьба 03.09) — игроку это знать незачем.
func _net_target() -> Array:
	var port: int = Net.home_port if Net.home_port > 0 else Net.PORT
	return [Net.host.strip_edges(), port]


## «СТАРТ» — единственная кнопка запуска: гонка идёт ПО СЕТИ (адрес из
## Net, по умолчанию VDS). Сервер не ответил / нет адреса — тихо стартуем
## оффлайн с ботами: они и так подписаны человеческими никами и от живых
## игроков неотличимы, игрок просто едет. Футбол сетевого протокола пока
## не имеет — сразу оффлайн.
func _start_race() -> void:
	if _name_dialog != null or _connecting or _ad_showing:
		return   # сначала имя — окно модальное; либо уже стучимся
	var base: String = CarModelLibrary.CAR_IDS[_index]
	if not GameState.car_owned(base):
		return   # закрытая машина — сперва купить (кнопка «КУПИТЬ»)
	Net.leave()   # вдруг остались хвосты прошлого сетевого заезда
	GameState.select_car(base)
	if GameState.game_mode == GameState.MODE_SOCCER:
		# Футбол: своя арена, трасса не нужна.
		get_tree().change_scene_to_file("res://scenes/Soccer.tscn")
		return
	var target := _net_target()
	if String(target[0]).is_empty():
		_start_offline()
		return
	# Свою сцену строим сразу под желаемый размер: если мы окажемся первым
	# игроком лобби, сервер примет его и перестройка не понадобится; если
	# заезд уже другого размера — сервер продиктует свой (_rx_track).
	Net.race_size = GameState.race_size
	_connecting = true
	if _start_btn:
		_start_btn.disabled = true
		_start_btn.text = "ПОДКЛЮЧЕНИЕ…"
	if Net.join_server(target[0], target[1]):
		_watch_connect_timeout()
	else:
		_start_offline()


## Оффлайн-заезд: игрок + (race_size−1) ботов, случайная трасса.
func _start_offline() -> void:
	Net.leave()
	GameState.track_kind = TrackBuilder.pick_random_kind()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


## ENet сам по себе может молчать очень долго, поэтому ограничиваем
## ожидание вручную: не ответил за CONNECT_TIMEOUT — рвём и тихо стартуем
## оффлайн с ботами (для игрока разницы нет — ники у ботов человеческие).
func _watch_connect_timeout() -> void:
	await get_tree().create_timer(Net.CONNECT_TIMEOUT).timeout
	if not is_inside_tree() or not Net.is_client():
		return
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() \
			== MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_start_offline()


func _on_joined() -> void:
	# По сети вид трассы диктует сервер (_rx_track): строим классику, а
	# если сервер выбрал другую — Main перезагрузит сцену с нужной.
	GameState.track_kind = ""
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_join_failed(reason: String) -> void:
	# Сервер отказал или оборвался на этапе подключения — не мучаем игрока
	# сообщениями, просто едем оффлайн с ботами (причина — в лог).
	print("Сеть недоступна (", reason, ") — оффлайн-заезд")
	_start_offline()


## Сигналы сети: гонка начнётся, когда сервер подтвердит соединение
## (Net.joined), а не ответит — оффлайн с ботами.
func _build_net_ui() -> void:
	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)


# ---- Раскладка: помощники ----

## Прибить контрол к углу окна абсолютными пикселями (окно 1280×720
## растягивается целиком, так что пиксели базового кадра точны).
## from_bottom — координата y отсчитывается от нижней кромки (отрицательная).
func _place(c: Control, x: float, y: float, w: float, h: float,
		from_bottom := false) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 0.0
	c.anchor_top = 1.0 if from_bottom else 0.0
	c.anchor_bottom = c.anchor_top
	c.offset_left = x
	c.offset_right = x + w
	c.offset_top = y
	c.offset_bottom = y + h


## Переключатель режима игры (ГОНКА / ФУТБОЛ) — стальная табличка слева
## от «СТАРТ». Числа участников больше не выбирают: в заезде всегда 8
## машин (GameState.race_size), в футболе — те же 8, 4 на 4.
func _build_mode_ui(col: Control) -> void:
	var panel := UiKit.plate(col, "steel", Vector2.ZERO, Vector2(140, ROW_H))
	_place(panel, 0, ROW_Y, 140, ROW_H, true)

	var title := UiKit.label(panel, "РЕЖИМ", 12, Color(1, 1, 1, 0.7))
	title.position = Vector2(0, 8)
	title.size = Vector2(140, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Кнопка плоского стиля (UiKit.style_button мелкой кнопке навязывает
	# рост и заклёпки — см. _mini_button).
	_mode_button = _mini_button("ГОНКА")
	_mode_button.add_theme_font_size_override("font_size", 17)
	_mode_button.position = Vector2(12, 28)
	_mode_button.size = Vector2(116, 34)
	_mode_button.pressed.connect(_toggle_mode)
	panel.add_child(_mode_button)


func _toggle_mode() -> void:
	GameState.set_game_mode(
			GameState.MODE_SOCCER
			if GameState.game_mode == GameState.MODE_RACE
			else GameState.MODE_RACE)
	_apply_mode_ui()


## Обновить подпись кнопки под текущий режим.
func _apply_mode_ui() -> void:
	if _mode_button:
		_mode_button.text = "ФУТБОЛ" \
				if GameState.game_mode == GameState.MODE_SOCCER else "ГОНКА"


## Маленькая плоская кнопка. НЕ UiKit.style_button, и это выстрадано:
## 1) стайлбокс-табличка несёт поля 20 px с каждой стороны, и минимальный
##    размер кнопки выходит «поля + метрики шрифта» — она перерастает
##    заданный size, причём НАСКОЛЬКО — зависит от машины (масштаб окна
##    меняет метрики через оверсэмплинг шрифта): у меня на скриншоте цифра
##    рядом стояла ровно, у игрока — дважды криво;
## 2) на 38 px табличка с четырьмя заклёпками превращается в кашу, знака
##    не разглядеть. Плоская заливка с малыми полями решает и то и другое.
func _mini_button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	if _ui_font:
		b.add_theme_font_override("font", _ui_font)
	b.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed"]:
		var k := 1.0
		if state == "hover":
			k = 1.15
		elif state == "pressed":
			k = 0.78
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiKit.TEAL.r * k, UiKit.TEAL.g * k,
				UiKit.TEAL.b * k)
		sb.set_corner_radius_all(9)
		sb.set_content_margin_all(2)
		sb.set_border_width_all(2)
		sb.border_color = Color(0, 0, 0, 0.35)
		b.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, UiKit.INK)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _refresh_name_btn() -> void:
	if _name_btn:
		_name_btn.text = "ИМЯ: %s" % GameState.display_name()


## Модальное окно ввода имени. first — первый запуск: имени ещё нет,
## закрыть окно можно только введя его (кнопки «ОТМЕНА» нет). Дальше имя
## меняется той же формой по клику на «ИМЯ: …» в гараже.
func _open_name_dialog(first: bool) -> void:
	if _name_dialog != null:
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # клики вниз не пропускаем
	_canvas.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_dialog = dim

	var plate := UiKit.plate(dim, "steel", Vector2.ZERO, Vector2(460, 220))
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.anchor_top = 0.5
	plate.anchor_bottom = 0.5
	plate.offset_left = -230
	plate.offset_right = 230
	plate.offset_top = -110
	plate.offset_bottom = 110

	var title := UiKit.label(plate, "КАК ТЕБЯ ЗОВУТ?", 26, Color.WHITE, 6)
	title.position = Vector2(0, 16)
	title.size = Vector2(460, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var hint := UiKit.label(plate, "Под этим именем тебя увидят другие игроки",
			14, Color(1, 1, 1, 0.7))
	hint.position = Vector2(0, 54)
	hint.size = Vector2(460, 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_name_edit = LineEdit.new()
	_name_edit.text = GameState.player_name
	_name_edit.placeholder_text = "твоё имя"
	_name_edit.max_length = GameState.NAME_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _ui_font:
		_name_edit.add_theme_font_override("font", _ui_font)
	_name_edit.add_theme_font_size_override("font_size", 22)
	var edit_sb := UiKit.steel_box(6, 0.95)
	edit_sb.set_content_margin_all(6)
	for state in ["normal", "focus"]:
		_name_edit.add_theme_stylebox_override(state, edit_sb)
	_name_edit.add_theme_color_override("font_color", Color.WHITE)
	_name_edit.add_theme_color_override("caret_color", UiKit.YELLOW)
	_name_edit.position = Vector2(90, 88)
	_name_edit.size = Vector2(280, 42)
	_name_edit.text_submitted.connect(func(_t: String) -> void:
		_name_accept())
	plate.add_child(_name_edit)
	_name_edit.call_deferred("grab_focus")

	var ok := Button.new()
	ok.text = "ГОТОВО"
	UiKit.style_button(ok, "orange", 22)
	ok.position = Vector2(90 if first else 40, 146)
	ok.size = Vector2(280 if first else 180, 54)
	ok.pressed.connect(_name_accept)
	plate.add_child(ok)
	if not first:
		var cancel := _mini_button("ОТМЕНА")
		cancel.add_theme_font_size_override("font_size", 18)
		cancel.position = Vector2(250, 152)
		cancel.size = Vector2(170, 42)
		cancel.pressed.connect(_close_name_dialog)
		plate.add_child(cancel)


func _name_accept() -> void:
	var n: String = GameState.sanitize_name(_name_edit.text)
	if n == "":
		_name_edit.placeholder_text = "введи хоть что-нибудь"
		return
	GameState.set_player_name(n)
	_close_name_dialog()


func _close_name_dialog() -> void:
	if _name_dialog:
		_name_dialog.queue_free()
		_name_dialog = null
	_refresh_name_btn()


# ---- Реклама с вознаграждением ----
# Учёт — в GameState (ЭКОНОМИКА.md, раздел 1): пара роликов → +500 монет,
# после пары 10 минут отдыха. Ролики показывает платформа (Яндекс Игры,
# ysdk.adv.showRewardedVideo); вне web-сборки — заглушка с отсчётом, чтобы
# сценарий можно было прогнать руками и стендом TestAdButton.

func _build_ad_ui(canvas: Node, x: float, w: float) -> void:
	_ad_btn = Button.new()
	UiKit.style_button(_ad_btn, "teal", 15)
	_ad_btn.icon = load(UI_DIR + "play.png")
	_ad_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ad_btn.add_theme_constant_override("icon_max_width", 26)
	_ad_btn.add_theme_constant_override("h_separation", 8)
	_ad_btn.tooltip_text = "Досмотри два ролика подряд — +%d монет.\n" \
			% GameState.AD_PAIR_REWARD + "Потом 10 минут отдыха."
	_ad_btn.pressed.connect(_ad_pressed)
	_place(_ad_btn, x, TOP_Y, w, TOP_H)
	canvas.add_child(_ad_btn)
	_refresh_ad_btn()


## Подпись и доступность кнопки по состоянию учёта.
func _refresh_ad_btn() -> void:
	if _ad_btn == null:
		return
	if _ad_showing:
		_ad_btn.disabled = true
		_ad_btn.text = "ИДЁТ РОЛИК…"
		return
	if GameState.ad_available():
		_ad_btn.disabled = false
		if GameState.ad_pair_progress() == 0:
			_ad_btn.text = "+%d ЗА РЕКЛАМУ" % GameState.AD_PAIR_REWARD
		else:
			_ad_btn.text = "ЕЩЁ РОЛИК · +%d" % GameState.AD_PAIR_REWARD
		return
	var left := int(ceil(GameState.ad_cooldown_left()))
	_ad_btn.disabled = true
	_ad_btn.text = "ЧЕРЕЗ %d:%02d" % [left / 60, left % 60]


func _ad_pressed() -> void:
	if _ad_showing or not GameState.ad_available():
		return
	_ad_showing = true
	_dragging = false
	_set_sound_muted(true)   # платформа требует тишины на время ролика
	_refresh_ad_btn()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(AD_JS_SHOW)
	else:
		_simulate_ad()


## Результат ролика от платформы (window.bhrAd, см. AD_JS_SHOW).
func _poll_web_ad() -> void:
	var v: Variant = JavaScriptBridge.eval(
			"JSON.stringify(window.bhrAd || {state: 'error'})", true)
	if v == null:
		return
	var d: Variant = JSON.parse_string(str(v))
	if d is Dictionary and String(d.get("state", "showing")) != "showing":
		_ad_finished(bool(d.get("rewarded", false)))


## Заглушка ролика вне web-сборки: стальная табличка с отсчётом 3-2-1,
## после — как досмотренный. Чтобы механику можно было пощупать в
## настольной сборке; на Яндекс Играх сюда не заходим.
func _simulate_ad() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.add_child(dim)
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
	var title := UiKit.label(plate, "РЕКЛАМА", 26, Color.WHITE, 6)
	title.position = Vector2(0, 16)
	title.size = Vector2(460, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := UiKit.label(plate, "Ролик %d из %d · на Яндекс Играх здесь идёт видео"
			% [GameState.ad_pair_progress() + 1, GameState.AD_PAIR_SIZE],
			14, Color(1, 1, 1, 0.7))
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
	dim.queue_free()
	_ad_finished(true)


## Ролик закрыт. rewarded — досмотрен до конца (награда — только за
## второй ролик пары, GameState.register_ad).
func _ad_finished(rewarded: bool) -> void:
	_ad_showing = false
	_set_sound_muted(false)
	if rewarded:
		var got: int = GameState.register_ad()
		_refresh_money_label()
		if got > 0:
			_flash_coins("+%s" % _fmt_money(got))
	_refresh_ad_btn()


func _set_sound_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)


## «+500» взлетает над кошельком и тает.
func _flash_coins(txt: String) -> void:
	if _coin_flash == null:
		return
	_coin_flash.text = txt
	_coin_flash.visible = true
	_coin_flash.modulate = Color.WHITE
	_coin_flash.position.y = 22
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_coin_flash, "position:y", -26.0, 1.3) \
			.set_ease(Tween.EASE_OUT)
	tw.tween_property(_coin_flash, "modulate:a", 0.0, 1.3) \
			.set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: _coin_flash.visible = false)


# ---- Подиум и доска ----

func _set_index(i: int) -> void:
	var prev := _index
	_index = i
	if _model:
		_model.queue_free()
	var base: String = CarModelLibrary.CAR_IDS[_index]
	var id := _podium_id()
	_model = CarModelLibrary.build(id, 3.2, 0.02)
	if _model:
		_turntable.add_child(_model)
	var owned: bool = GameState.car_owned(base)
	_name_label.text = DISPLAY_NAMES.get(base, base)
	_name_label.add_theme_color_override("font_color",
			Color.WHITE if owned else Color(1, 1, 1, 0.5))
	_count_label.text = "%d / %d" % [_index + 1, CarModelLibrary.CAR_IDS.size()]
	# Закрытая машина стоит на подиуме «тенью» — видно, но не наша.
	if _model and not owned:
		_dim_model(_model)
	_refresh_lock_ui()
	# Панель тюнинга открыта — перевести на новую машину (чужая — закрыть).
	if _tuning != null and _tuning.visible:
		if owned:
			_tuning.open(base)
		else:
			_tuning.close()
	# Дым — ПОСЛЕ open(): у другой машины панель переходит на первую
	# вкладку, и решать «дымить ли» надо по ней.
	_refresh_podium_smoke()
	# Подсветка ячейки на доске.
	if _buttons.size() > prev:
		_apply_style(_buttons[prev], _style_normal, _style_hover)
	if _buttons.size() > _index:
		_apply_style(_buttons[_index], _style_selected)
		_scroll.ensure_control_visible(_buttons[_index])


## id машины на подиуме: С ПРИМЕРКОЙ из панели тюнинга (некупленные
## детали надеты только здесь; профиль и миниатюра — без них).
func _podium_id() -> String:
	var base: String = CarModelLibrary.CAR_IDS[_index]
	if _tuning != null and _tuning.visible and _tuning.base() == base \
			and _tuning.has_preview():
		return _tuning.preview_id()
	return _full_id(_index)


## Цветной дым на подиуме (04.09): ленивые клубы из-под задних колёс,
## когда у машины куплен или примерен цвет дыма — иначе покупку в
## гараже не видно (в заезде дым идёт только в заносе). Показывается
## ТОЛЬКО пока открыта вкладка ЭФФЕКТЫ панели тюнинга, т.е. когда дым
## выбирают (просьба 04.09: «не всегда в гараже, только когда
## выбираешь»); в остальное время подиум чистый. Обычный серый не
## показываем. Эмиттеры — дети поворотного стола, как модель.
func _refresh_podium_smoke() -> void:
	var color := ""
	if _tuning != null and _tuning.visible and _tuning.tab() == "fx":
		color = str(CarModelLibrary.parse_cfg(_podium_id()).get("smoke", ""))
	_set_podium_smoke(color)


func _set_podium_smoke(color: String) -> void:
	for p in _podium_smoke:
		p.queue_free()
	_podium_smoke.clear()
	if not CarModelLibrary.ARCADE_COLORS.has(color):
		return
	for sx: float in [-0.55, 0.55]:
		var p := Car.make_smoke()
		Car.tint_smoke(p, color, false)
		p.amount = 10
		p.lifetime = 1.1
		p.initial_velocity_min = 0.3
		p.initial_velocity_max = 0.7
		p.position = Vector3(sx, 0.15, 1.4)   # за задними колёсами (нос −Z)
		_turntable.add_child(p)
		p.emitting = true   # ПОСЛЕ add_child: вне дерева эмиттер ругается на transform
		_podium_smoke.append(p)


## Затемнить модель на подиуме (закрытая машина — «силуэт в тени»).
func _dim_model(model: Node) -> void:
	for child in model.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var dim := StandardMaterial3D.new()
			dim.albedo_color = Color(0.17, 0.17, 0.2)
			dim.roughness = 0.85
			mi.material_override = dim
		_dim_model(child)


## Кнопки под подиумом: у купленной машины — «СТАРТ», у закрытой —
## «КУПИТЬ · цена» (уровень мал — серая «С N УРОВНЯ · цена»).
func _refresh_lock_ui() -> void:
	var base: String = CarModelLibrary.CAR_IDS[_index]
	var owned: bool = GameState.car_owned(base)
	if _start_btn:
		_start_btn.visible = owned
	# Тюнинг — у любой купленной машины: краски теперь только там (03.09),
	# у аркадных конструкторов ещё детали и наклейки.
	if _tuning_btn:
		_tuning_btn.visible = owned
	if _buy_btn == null:
		return
	_buy_btn.visible = not owned
	if owned:
		return
	_buy_flash += 1   # сбросить возможную вспышку «НЕ ХВАТАЕТ МОНЕТ»
	var lvl: int = GameState.car_unlock_level(base)
	var price: int = GameState.car_price(base)
	if GameState.level_info().x < lvl:
		_buy_btn.disabled = true
		_buy_btn.text = "С %d УРОВНЯ · %s" % [lvl, _fmt_money(price)]
	else:
		_buy_btn.disabled = false
		_buy_btn.text = "КУПИТЬ · %s" % _fmt_money(price)


## Цена с тонкой шпацией между тысячами: 24000 → «24 000».
func _fmt_money(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _buy_pressed() -> void:
	var base: String = CarModelLibrary.CAR_IDS[_index]
	if GameState.try_buy_car(base):
		_refresh_money_label()
		_refresh_grid_locks()
		_set_index(_index)   # перестроить подиум уже без «тени»
		return
	# Уровень проверен кнопкой — значит, не хватило монет: мигнуть ценой.
	_buy_flash += 1
	var gen := _buy_flash
	var old := _buy_btn.text
	_buy_btn.text = "НЕ ХВАТАЕТ МОНЕТ"
	await get_tree().create_timer(1.2).timeout
	if is_inside_tree() and _buy_flash == gen and _buy_btn.visible:
		_buy_btn.text = old


## Уровень, полоса опыта и кошелёк на верхней полке.
func _refresh_money_label() -> void:
	var info: Vector3i = GameState.level_info()
	if _level_label:
		_level_label.text = "УРОВЕНЬ %d" % info.x
	if _xp_sub:
		_xp_sub.text = "%d / %d" % [info.y, info.z]
	if _xp_bar:
		_xp_bar.max_value = info.z
		_xp_bar.value = info.y
	if _coins_label:
		_coins_label.text = _fmt_money(GameState.money)


## Ярлыки «N ур.» и серые силуэты на закрытых ячейках доски.
func _refresh_grid_locks() -> void:
	for i in _buttons.size():
		var base: String = CarModelLibrary.CAR_IDS[i]
		var owned: bool = GameState.car_owned(base)
		# Не modulate (он красил бы и ярлык): серый только силуэт машины.
		var icon_col := Color.WHITE if owned else Color(0.42, 0.42, 0.47, 0.8)
		for st in ["icon_normal_color", "icon_hover_color",
				"icon_pressed_color", "icon_focus_color"]:
			_buttons[i].add_theme_color_override(st, icon_col)
		if i < _grid_locks.size():
			_grid_locks[i].visible = not owned
		_buttons[i].tooltip_text = DISPLAY_NAMES.get(base, base) if owned \
				else "%s — с %d уровня, %s монет" % [
						DISPLAY_NAMES.get(base, base),
						GameState.car_unlock_level(base),
						_fmt_money(GameState.car_price(base))]


# ---- Тюнинг: косметика ----

func _open_tuning() -> void:
	var base: String = CarModelLibrary.CAR_IDS[_index]
	if not GameState.car_owned(base) or _tuning == null:
		return
	_grid_panel.visible = false
	_tuning.open(base)
	_set_panel_open(true)


## Панель что-то купила/переставила: кошелёк, подиум, миниатюра.
func _on_tuning_changed() -> void:
	_refresh_money_label()
	_set_index(_index)
	_update_thumb(_index)


## Закрыли тюнинг — машина возвращается в центр (доска не показывается:
## её открывают отдельной кнопкой).
func _on_tuning_closed() -> void:
	_set_panel_open(false)
	_set_index(_index)   # примерка сброшена — подиум без неё


# ---- Подменю: доска «АВТОПАРК» и съезд машины влево ----

func _open_board() -> void:
	if _tuning != null and _tuning.visible:
		_tuning.visible = false   # без closed — иначе машина метнётся в центр
	_grid_panel.visible = true
	if _buttons.size() > _index:
		_scroll.ensure_control_visible(_buttons[_index])
	_set_panel_open(true)


func _close_board() -> void:
	_grid_panel.visible = false
	_set_panel_open(false)


## Подменю открыто — машина и левая колонка уезжают влево, стрелки
## листания прячутся (просьба 03.09); закрыто — всё обратно, машина по
## центру. Съезд плавный: камера через h_offset (сдвигает её вбок),
## колонка — через offset_left/right.
func _set_panel_open(open: bool) -> void:
	_panel_open = open
	for a in _arrows:
		a.visible = not open
	if _ui_tween:
		_ui_tween.kill()
	_ui_tween = create_tween().set_parallel(true) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var col_x := COL_X_OPEN if open else COL_X_CENTER
	_ui_tween.tween_property(_column, "offset_left", col_x, SLIDE_TIME)
	_ui_tween.tween_property(_column, "offset_right", col_x + COL_W, SLIDE_TIME)
	_ui_tween.tween_property(_cam, "h_offset",
			CAM_H_OPEN if open else 0.0, SLIDE_TIME)


## Перерисовать миниатюру одной машины (после смены цвета): из кэша /
## с диска / рендером одного вьюпорта.
func _update_thumb(i: int) -> void:
	var full: String = _full_id(i)
	if GameState.car_thumbs.has(full):
		_buttons[i].icon = GameState.car_thumbs[full]
		return
	var png_path := "%s/%s.png" % [THUMB_CACHE_DIR, full]
	if FileAccess.file_exists(png_path):
		var img := Image.new()
		if img.load(png_path) == OK:
			var tex := ImageTexture.create_from_image(img)
			GameState.car_thumbs[full] = tex
			_buttons[i].icon = tex
			return
	var vp_info := _make_thumb_viewport()
	var m := CarModelLibrary.build(full, 3.2, 0.0)
	if m:
		(vp_info["holder"] as Node3D).add_child(m)
	(vp_info["vp"] as SubViewport).render_target_update_mode = \
			SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var shot := (vp_info["vp"] as SubViewport).get_texture().get_image()
	shot.save_png(png_path)
	var tex2 := ImageTexture.create_from_image(shot)
	GameState.car_thumbs[full] = tex2
	_buttons[i].icon = tex2
	(vp_info["vp"] as SubViewport).queue_free()


func _on_cell_pressed(i: int) -> void:
	if i == _index:
		_start_race()  # повторный клик по выбранной — старт
	else:
		_set_index(i)


const THUMB_CACHE_DIR := "user://thumbs"
const THUMB_BATCH := 8  # сколько машин рендерим за один кадр

## Раздаёт миниатюры кнопкам: из памяти → с диска → рендер недостающих
## пачками по THUMB_BATCH вьюпортов за кадр (и сохранение в user://thumbs).
func _generate_thumbs() -> void:
	DirAccess.make_dir_recursive_absolute(THUMB_CACHE_DIR)
	var missing: Array[int] = []
	for i in CarModelLibrary.CAR_IDS.size():
		var id: String = _full_id(i)   # миниатюра — в ТЕКУЩЕМ цвете машины
		if GameState.car_thumbs.has(id):
			_buttons[i].icon = GameState.car_thumbs[id]
			continue
		var png_path := "%s/%s.png" % [THUMB_CACHE_DIR, id]
		if FileAccess.file_exists(png_path):
			var img := Image.new()
			if img.load(png_path) == OK:
				var tex := ImageTexture.create_from_image(img)
				GameState.car_thumbs[id] = tex
				_buttons[i].icon = tex
				continue
		missing.append(i)
	if missing.is_empty():
		return

	# Пул вьюпортов — по одному на машину в пачке.
	var pool: Array[Dictionary] = []
	for k in mini(THUMB_BATCH, missing.size()):
		pool.append(_make_thumb_viewport())

	for start in range(0, missing.size(), THUMB_BATCH):
		var batch: Array[int] = missing.slice(start, start + THUMB_BATCH)
		for k in batch.size():
			var vp_info := pool[k]
			var holder: Node3D = vp_info["holder"]
			for old in holder.get_children():
				old.free()
			var m := CarModelLibrary.build(_full_id(batch[k]), 3.2, 0.0)
			if m:
				holder.add_child(m)
			(vp_info["vp"] as SubViewport).render_target_update_mode = \
					SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return  # сцену сменили во время генерации
		for k in batch.size():
			var i: int = batch[k]
			var id: String = _full_id(i)
			var img := (pool[k]["vp"] as SubViewport).get_texture().get_image()
			img.save_png("%s/%s.png" % [THUMB_CACHE_DIR, id])
			var tex := ImageTexture.create_from_image(img)
			GameState.car_thumbs[id] = tex
			_buttons[i].icon = tex
	for vp_info in pool:
		(vp_info["vp"] as SubViewport).queue_free()


## Вьюпорт с камерой/светом/столиком для рендера одной миниатюры.
func _make_thumb_viewport() -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(208, 156)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.9, 4.4)
	cam.rotation_degrees = Vector3(-16, 0, 0)
	cam.fov = 45
	vp.add_child(cam)
	cam.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.3
	vp.add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)

	var holder := Node3D.new()
	holder.rotation.y = deg_to_rad(150)  # 3/4-ракурс
	vp.add_child(holder)
	return {"vp": vp, "holder": holder}


# ---- Бокс: свет, стены, пол ----

func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.64, 0.60, 0.55)   # тёплый бетон за стеной
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.80, 0.76, 0.70)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	# Свет приглушён (просьба 03.09 «поменьше света»): бокс освещён, но
	# не залит — тени и объём читаются, стены не выбелены.
	# Ключевой свет — тёплая лампа бокса, с тенями.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.light_energy = 0.9
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	add_child(key)

	# Заполняющий — холодный, с окна напротив.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 145, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.82, 0.88, 1.0)
	add_child(fill)

	# Лампа над подиумом — пятно света на машине и пол вокруг.
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 5.5, 1.0)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	lamp.spot_angle = 42
	lamp.spot_range = 9
	lamp.light_energy = 1.4
	lamp.light_color = Color(1.0, 0.94, 0.82)
	add_child(lamp)

	var cam := Camera3D.new()
	# ДЛИННЫЙ ОБЪЕКТИВ. Раньше было 50° с 4.6 м, и машина стояла у самого
	# края кадра (h_offset физически сдвигает камеру вбок, см. ниже) —
	# широкоугольная кромка «заваливала» кузов: машина выглядела стоящей
	# косо, хотя на подиуме она ровно. 24° с 9 м дают тот же размер в
	# кадре почти без перспективных искажений.
	cam.position = Vector3(0, 2.5, 9.0)
	# −12.5°, а не −11.5: под подиумом теперь три ряда табличек, машину
	# поднимаем в кадре на ~30 px, чтобы колёса не прятались за именем.
	cam.rotation_degrees = Vector3(-12.5, 0, 0)
	cam.fov = 24
	# Пока подменю закрыты, машина стоит по центру (h_offset 0). Открыли
	# доску — она занимает правые ~600px из 1280 → видимая зона 0..680,
	# её центр = 0.266 ширины экрана. h_offset двигает камеру вправо, и
	# машина уходит влево ровно настолько: h = 0.468·tan(fov_h/2)·дистанция,
	# при 16:9 tan(fov_h/2) = tan(12°)·16/9 = 0.378 → CAM_H_OPEN = 1.59
	# (см. _set_panel_open).
	cam.h_offset = 0.0
	add_child(cam)
	cam.make_current()
	_cam = cam


## Материал с тайлом текстуры.
func _tex_mat(file: String, uv: Vector3, tint := Color.WHITE,
		rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(UI_DIR + file)
	m.albedo_color = tint
	m.uv1_scale = uv
	m.roughness = rough
	return m


func _plain_mat(color: Color, metallic := 0.0, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m


func _plane(size: Vector2, pos: Vector3, mat: Material,
		orient := PlaneMesh.FACE_Y, yaw := 0.0) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.orientation = orient
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


## Бокс гаража вокруг подиума: бетонный пол, оранжевый рифлёный лист
## с аварийной лентой под машиной, светлая рифлёная стена с воротами и
## немного реквизита у стены. Камера смотрит чуть вниз (горизонт у
## верхней кромки кадра), поэтому стена закрывает весь верх, пол — низ;
## видимая полоса по x при z≈−6 — от −4 до +2 м (h_offset сдвигает камеру
## вправо), реквизит стоит в ней.
func _setup_garage() -> void:
	const FLOOR_Y := -0.36   # низ подиума −0.35
	_plane(Vector2(48, 48), Vector3(0, FLOOR_Y, 0),
			_tex_mat("concrete.png", Vector3(12, 12, 1), Color(0.70, 0.69, 0.67)))
	# Оранжевый лист под подиумом (референс A_seamless_tileable_texture_1);
	# чуть приглушён, чтобы не спорил с машиной.
	_plane(Vector2(7.6, 9.6), Vector3(0, FLOOR_Y + 0.006, -0.4),
			_tex_mat("diamond_orange.jpg", Vector3(2.5, 3.2, 1),
					Color(0.80, 0.80, 0.80), 0.6))
	# Аварийная лента по периметру листа: полосы 45° → тайл 4:1 растянут
	# на ленту шириной 0.3, то есть 1.2 м на повтор.
	var hz := _tex_mat("hazard.png", Vector3(1, 1, 1), Color(0.95, 0.95, 0.95))
	for side in [[Vector2(7.6, 0.3), Vector3(0, 0, 4.4), 0.0],
			[Vector2(7.6, 0.3), Vector3(0, 0, -5.2), 0.0],
			[Vector2(9.6, 0.3), Vector3(3.8, 0, -0.4), PI / 2],
			[Vector2(9.6, 0.3), Vector3(-3.8, 0, -0.4), PI / 2]]:
		var sz: Vector2 = side[0]
		var m := hz.duplicate() as StandardMaterial3D
		m.uv1_scale = Vector3(sz.x / 1.2, 1, 1)
		var p: Vector3 = side[1]
		_plane(sz, Vector3(p.x, FLOOR_Y + 0.012, p.z), m,
				PlaneMesh.FACE_Y, side[2])

	# Задняя стена — светлые рифлёные панели, у пола аварийная лента.
	const WALL_Z := -7.6
	_plane(Vector2(40, 6.0), Vector3(0, FLOOR_Y + 3.0, WALL_Z),
			_tex_mat("wall_panels.png", Vector3(10, 1, 1), Color(1, 1, 1)),
			PlaneMesh.FACE_Z)
	var base_hz := hz.duplicate() as StandardMaterial3D
	base_hz.uv1_scale = Vector3(40 / 1.4, 1, 1)
	_plane(Vector2(40, 0.35), Vector3(0, FLOOR_Y + 0.175, WALL_Z + 0.02),
			base_hz, PlaneMesh.FACE_Z)
	# Ворота: стальная рама и бирюзовое полотно из тех же панелей. Узкие —
	# 3.6 м: широкие (5.5) закрывали всю видимую стену, панелей не было
	# видно вовсе.
	_plane(Vector2(4.0, 4.4), Vector3(-0.6, FLOOR_Y + 2.2, WALL_Z + 0.03),
			_plain_mat(Color(0.30, 0.32, 0.36), 0.5, 0.5), PlaneMesh.FACE_Z)
	_plane(Vector2(3.6, 4.1), Vector3(-0.6, FLOOR_Y + 2.05, WALL_Z + 0.05),
			_tex_mat("wall_panels.png", Vector3(1, 1.4, 1),
					Color(0.22, 0.90, 0.82), 0.55), PlaneMesh.FACE_Z)

	# Реквизит у стены. Из готовых лоуполи-паков (пайплайн TrackDecor: FBX
	# + текстуры по имени материала; модели взяты из Unity-проекта cars,
	# просьба 03.09): стопки шин и красный блок — Cartoon Tracks, бак-
	# мусорка и прожектор — ithappy, вентилятор — Palmov (сундук с замком
	# убран по просьбе 03.09). Правая
	# половина (x > 2) видна только пока машина в центре — доска её
	# закрывает. Бочки и шкафы — свои примитивы (чистые яркие цвета).
	var decor := TrackDecor.new()
	add_child(decor)
	decor._spawn(TrackDecor.CDIR + "prop_tyre_4x8.FBX",
			Vector3(-2.9, FLOOR_Y, -5.6), Vector3.BACK, 0.85, true)
	decor._spawn(TrackDecor.CDIR + "prop_tyre_1x1_B.FBX",
			Vector3(-1.5, FLOOR_Y, -4.8), Vector3.BACK, 1.0, true)
	decor._spawn(TrackDecor.CDIR + "prop_plastic_block.FBX",
			Vector3(-4.6, FLOOR_Y, -2.6), Vector3(1, 0, 0.3), 1.0, true)
	decor._spawn(TrackDecor.CITY_DIR + "trash_can_a.fbx",
			Vector3(4.7, FLOOR_Y, -6.4), Vector3.BACK, 1.0, true)
	decor._spawn(TrackDecor.CITY_DIR + "spotlight_a.fbx",
			Vector3(3.3, FLOOR_Y, -5.0), Vector3(-1, 0, 1), 0.36, true)
	var fan := decor._spawn(TrackDecor.PDIR + "exhaust_fan.fbx",
			Vector3(4.0, FLOOR_Y + 3.9, WALL_Z + 0.3), Vector3.BACK, 1.1, true)
	if fan:
		fan.rotation.x = PI / 2   # лежал плашмя — вешаем на стену
	for barrel in [[Vector3(-1.8, 0, -6.6), UiKit.ORANGE],
			[Vector3(-1.0, 0, -6.9), UiKit.YELLOW]]:
		var c := CylinderMesh.new()
		c.top_radius = 0.34
		c.bottom_radius = 0.34
		c.height = 0.95
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = _plain_mat(barrel[1], 0.25, 0.45)
		var p: Vector3 = barrel[0]
		mi.position = Vector3(p.x, FLOOR_Y + 0.475, p.z)
		add_child(mi)
	# Шкаф целиком в кадре (при x=−3.9 и ширине 1.5 его резала левая кромка —
	# торчал красный кусок).
	_box(Vector3(1.2, 1.8, 0.6), Vector3(-3.3, FLOOR_Y + 0.9, -7.1),
			_plain_mat(Color(0.80, 0.22, 0.17), 0.3, 0.45))
	_box(Vector3(1.24, 0.06, 0.64), Vector3(-3.3, FLOOR_Y + 1.2, -7.1),
			_plain_mat(Color(0.25, 0.27, 0.3), 0.5, 0.5))
	_box(Vector3(1.24, 0.06, 0.64), Vector3(-3.3, FLOOR_Y + 0.6, -7.1),
			_plain_mat(Color(0.25, 0.27, 0.3), 0.5, 0.5))
	_box(Vector3(1.0, 2.2, 0.6), Vector3(1.6, FLOOR_Y + 1.1, -7.2),
			_plain_mat(Color(0.20, 0.72, 0.66), 0.3, 0.5))


func _setup_podium() -> void:
	var podium := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.2
	mesh.bottom_radius = 2.5
	mesh.height = 0.35
	podium.mesh = mesh
	podium.position.y = -0.175
	# Стальной рифлёный лист (tools/gen_podium_tex.py): тайл по UV
	# цилиндра, лёгкий металлик — читается как поворотный круг, а не
	# крашеный диск (03.09, просьба «подходящая текстура»).
	var pm := _tex_mat("podium_plate.png", Vector3(6, 6, 1),
			Color(0.9, 0.9, 0.93), 0.45)
	pm.metallic = 0.55
	pm.metallic_specular = 0.6
	podium.material_override = pm
	add_child(podium)

	_turntable = Node3D.new()
	_turntable.name = "TurnTable"
	# Стартовая поза — три четверти спереди-слева: подиум больше сам не
	# крутится, и «как машина встала, такой её и увидят». В нуле камера
	# смотрела бы ровно в корму (перёд модели — по -Z).
	_turntable.rotation.y = PI - 0.55
	add_child(_turntable)


# ---- HUD ----

func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_canvas = canvas
	_ui_font = UiKit.font()
	# Левая колонка — во всю высоту окна, чтобы _place(..., from_bottom)
	# внутри неё считал от нижней кромки; сама событий мыши не ест —
	# за свободное место вокруг машины её крутят.
	_column = Control.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.anchor_top = 0.0
	_column.anchor_bottom = 1.0
	_column.offset_top = 0
	_column.offset_bottom = 0
	_column.offset_left = COL_X_CENTER
	_column.offset_right = COL_X_CENTER + COL_W
	canvas.add_child(_column)
	_build_top_shelf(canvas)
	_build_test_badge(canvas)
	_build_podium_ui(canvas, _column)
	_build_mode_ui(_column)
	_apply_mode_ui()
	_build_net_ui()
	_setup_grid(canvas)


## Красная плашка поверх гаража, когда игра поднята на ТЕСТОВОМ профиле
## (стенд, снимок, автотест — см. GameState._pick_profile_path). Такой
## гараж всегда пуст: 1 уровень, миллион монет, ни одной купленной
## машины. 04.09 игрок трижды принимал окно стенда за пропавший
## прогресс — теперь на нём написано, что это стенд и где лежит его файл.
func _build_test_badge(canvas: Node) -> void:
	if not GameState.is_test_profile():
		return
	var badge := UiKit.plate(canvas, "red", Vector2.ZERO, Vector2(560, 44))
	_place(badge, 16, TOP_Y + TOP_H + 8, 560, 44)
	# Плашка ничего не ловит мышью: под ней крутят подиум протяжкой
	# (TestSpin ловил именно это — табличка съедала перетаскивание).
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var txt := UiKit.plate_label(badge,
			"СТЕНД · ТЕСТОВЫЙ ПРОФИЛЬ · ВАШ ПРОГРЕСС ЦЕЛ", 17,
			UiKit.text_on("red"))
	txt.offset_top = 2
	txt.offset_bottom = -20
	var sub := UiKit.label(badge, GameState.PROFILE_TEST_PATH, 11,
			Color(1, 1, 1, 0.85))
	sub.position = Vector2(0, 24)
	sub.size = Vector2(560, 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	DisplayServer.window_set_title("Big Head Racing — СТЕНД (тестовый профиль)")


## Верхняя полка табличек: «ГАРАЖ», уровень с полосой опыта, кошелёк,
## «+500 ЗА РЕКЛАМУ», имя игрока. Все — мелкие эмалевые таблички одной
## высоты (крупная девятислайс-табличка с полями 40 в 80 px не влезает).
func _build_top_shelf(canvas: Node) -> void:
	# Заголовок — белая эмаль, аварийная лента по низу, сверху наискось
	# приклеен жёлтый ярлык с названием игры.
	var title_plate := UiKit.plate(canvas, "white", Vector2.ZERO,
			Vector2(320, TOP_H))
	_place(title_plate, 16, TOP_Y, 320, TOP_H)
	UiKit.hazard(title_plate, Vector2(12, TOP_H - 18), Vector2(320 - 24, 9), 0.95)
	var title := UiKit.plate_label(title_plate, "ГАРАЖ", 34, UiKit.INK)
	title.offset_top = 4
	title.offset_bottom = -12
	var tag := Panel.new()
	var tag_sb := StyleBoxFlat.new()
	tag_sb.bg_color = UiKit.YELLOW
	tag_sb.set_corner_radius_all(4)
	tag_sb.set_border_width_all(2)
	tag_sb.border_color = UiKit.INK
	tag.add_theme_stylebox_override("panel", tag_sb)
	# Ярлык приподнят на 7 px и повёрнут на −0.045 рад: правый край
	# поднимается ещё на 8 — итого до кромки окна остаётся 3 px.
	tag.position = Vector2(12, -7)
	tag.size = Vector2(176, 26)
	tag.rotation = -0.045
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_plate.add_child(tag)
	UiKit.plate_label(tag, "BIG HEAD RACING", 13, UiKit.INK)

	# Уровень — жёлтая табличка с полосой опыта. Опыт и монеты даются на
	# финише (GameState); уровни открывают машины и оружие — ЭКОНОМИКА.md.
	var lvl := UiKit.plate(canvas, "yellow", Vector2.ZERO, Vector2(240, TOP_H))
	_place(lvl, 352, TOP_Y, 240, TOP_H)
	_level_label = UiKit.label(lvl, "", 18, UiKit.INK)
	_level_label.position = Vector2(20, 14)
	_level_label.size = Vector2(200, 24)
	_xp_sub = UiKit.label(lvl, "", 12, Color(UiKit.INK.r, UiKit.INK.g, UiKit.INK.b, 0.75))
	_xp_sub.position = Vector2(20, 18)
	_xp_sub.size = Vector2(200, 20)
	_xp_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.position = Vector2(20, 46)
	_xp_bar.size = Vector2(200, 14)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(UiKit.INK.r, UiKit.INK.g, UiKit.INK.b, 0.22)
	track.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiKit.INK
	fill.set_corner_radius_all(5)
	_xp_bar.add_theme_stylebox_override("background", track)
	_xp_bar.add_theme_stylebox_override("fill", fill)
	lvl.add_child(_xp_bar)

	# Кошелёк — белая табличка, гайка-монета и число.
	var wallet := UiKit.plate(canvas, "white", Vector2.ZERO, Vector2(200, TOP_H))
	_place(wallet, 608, TOP_Y, 200, TOP_H)
	var coin := TextureRect.new()
	coin.texture = load(UI_DIR + "coin.png")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.position = Vector2(18, (TOP_H - 40) * 0.5)
	coin.size = Vector2(40, 40)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_child(coin)
	_coins_label = UiKit.label(wallet, "", 24, UiKit.INK)
	_coins_label.position = Vector2(66, 0)
	_coins_label.size = Vector2(118, TOP_H)
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin_flash = UiKit.label(wallet, "", 20, UiKit.TEAL, 4)
	_coin_flash.position = Vector2(66, 22)
	_coin_flash.size = Vector2(118, 30)
	_coin_flash.visible = false
	_refresh_money_label()

	_build_ad_ui(canvas, 824, 210)

	# Имя игрока — стальная табличка; клик открывает окно смены имени.
	_name_btn = Button.new()
	UiKit.style_button(_name_btn, "steel", 16)
	_name_btn.clip_text = true
	_name_btn.pressed.connect(func() -> void: _open_name_dialog(false))
	_place(_name_btn, 1050, TOP_Y, 214, TOP_H)
	canvas.add_child(_name_btn)
	_refresh_name_btn()

	var help := UiKit.label(_column, "←→ / AD — листать  ·  Enter — в гонку"
			+ "  ·  Esc — закрыть подменю", 13, Color(1, 1, 1, 0.9), 4)
	_place(help, 0, TOP_Y + TOP_H + 6, COL_W, 20)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Низ левой колонки (координаты — внутри колонки, см. COL_*): имя
## машины, ряд «РЕЖИМ» / «СТАРТ» / «АВТОПАРК» / «ТЮНИНГ». Стрелки
## листания — на самом холсте по бокам машины, стоящей в центре: они
## живут только пока подменю закрыты.
func _build_podium_ui(canvas: Node, col: Control) -> void:
	var name_panel := UiKit.plate(col, "steel", Vector2.ZERO, Vector2(420, 54))
	_place(name_panel, (COL_W - 420) * 0.5, ROW_Y - 66, 420, 54, true)
	_name_label = UiKit.plate_label(name_panel, "", 26, Color.WHITE, 6)

	# Стрелки листания по бокам машины — оранжевые таблички.
	_make_arrow(canvas, UI_DIR + "arrow_l.png", 226,
			func() -> void: _set_index(
					(_index - 1 + CarModelLibrary.CAR_IDS.size())
					% CarModelLibrary.CAR_IDS.size()))
	_make_arrow(canvas, UI_DIR + "arrow_r.png", 978,
			func() -> void: _set_index(
					(_index + 1) % CarModelLibrary.CAR_IDS.size()))

	# «СТАРТ» — красная эмаль, единственная главная кнопка экрана.
	_start_btn = Button.new()
	_start_btn.text = "СТАРТ"
	UiKit.style_button(_start_btn, "red", 24)
	_place(_start_btn, 152, ROW_Y, 240, ROW_H, true)
	_start_btn.pressed.connect(_start_race)
	col.add_child(_start_btn)

	# «КУПИТЬ · цена» — на месте «СТАРТ», видна только у закрытой машины.
	_buy_btn = Button.new()
	UiKit.style_button(_buy_btn, "orange", 18)
	_place(_buy_btn, 152, ROW_Y, 240, ROW_H, true)
	_buy_btn.visible = false
	_buy_btn.pressed.connect(_buy_pressed)
	col.add_child(_buy_btn)

	# «АВТОПАРК» — жёлтая эмаль: открыть доску миниатюр всех машин.
	_board_btn = Button.new()
	_board_btn.text = "АВТОПАРК"
	UiKit.style_button(_board_btn, "yellow", 15)
	_place(_board_btn, 404, ROW_Y, 120, ROW_H, true)
	_board_btn.pressed.connect(_open_board)
	col.add_child(_board_btn)

	# «ТЮНИНГ» — у своей машины: краски (у всех), у аркадных
	# конструкторов ещё детали кузова и наклейки. Ничего, кроме внешнего
	# вида, тюнинг не меняет.
	_tuning_btn = Button.new()
	_tuning_btn.text = "ТЮНИНГ"
	UiKit.style_button(_tuning_btn, "teal", 15)
	_place(_tuning_btn, 536, ROW_Y, 120, ROW_H, true)
	_tuning_btn.pressed.connect(_open_tuning)
	col.add_child(_tuning_btn)


## Мультяшная кнопка-стрелка листания (x — левая кромка в px, по
## вертикали — середина окна).
func _make_arrow(canvas: CanvasLayer, tex_path: String, x: float,
		on_press: Callable) -> void:
	var btn := TextureButton.new()
	btn.texture_normal = load(tex_path)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_top = 0.5
	btn.anchor_bottom = 0.5
	btn.offset_left = x
	btn.offset_right = x + 76
	btn.offset_top = -38
	btn.offset_bottom = 38
	btn.modulate = Color(1, 1, 1, 0.94)
	btn.pressed.connect(on_press)
	btn.button_down.connect(func() -> void: btn.modulate = Color(0.75, 0.75, 0.75))
	btn.button_up.connect(func() -> void: btn.modulate = Color(1, 1, 1, 0.94))
	canvas.add_child(btn)
	_arrows.append(btn)


## Правая половина: доска «АВТОПАРК» — белая эмаль с аварийной лентой,
## внутри прокручиваемая сетка миниатюр всех машин.
func _setup_grid(canvas: CanvasLayer) -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.84, 0.80, 0.72)
	_style_normal.set_corner_radius_all(6)
	_style_normal.set_border_width_all(1)
	_style_normal.border_color = Color(UiKit.INK.r, UiKit.INK.g, UiKit.INK.b, 0.35)
	_style_hover = _style_normal.duplicate() as StyleBoxFlat
	_style_hover.bg_color = Color(0.92, 0.89, 0.82)
	_style_selected = _style_normal.duplicate() as StyleBoxFlat
	_style_selected.bg_color = UiKit.YELLOW
	_style_selected.set_border_width_all(3)
	_style_selected.border_color = UiKit.INK

	var board := UiKit.plate(canvas, "white", Vector2.ZERO,
			Vector2(BOARD_W, BOARD_H), false)
	_place(board, BOARD_X, BOARD_Y, BOARD_W, BOARD_H)
	board.visible = false   # открывается кнопкой «АВТОПАРК»
	_grid_panel = board
	# Заголовок отступает от заклёпок (у крупной таблички они в 24 px от угла).
	var head := UiKit.label(board, "АВТОПАРК", 20, UiKit.INK)
	head.position = Vector2(44, 12)
	head.size = Vector2(300, 26)
	_count_label = UiKit.label(board, "", 15,
			Color(UiKit.INK.r, UiKit.INK.g, UiKit.INK.b, 0.7))
	_count_label.position = Vector2(260, 15)
	_count_label.size = Vector2(BOARD_W - 260 - 176, 22)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var close_btn := _mini_button("ЗАКРЫТЬ")
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.position = Vector2(BOARD_W - 44 - 120, 9)
	close_btn.size = Vector2(120, 32)
	close_btn.pressed.connect(_close_board)
	board.add_child(close_btn)
	UiKit.hazard(board, Vector2(14, BOARD_H - 22), Vector2(BOARD_W - 28, 10), 0.95)

	# Панель тюнинга — на месте доски, пока открыта.
	_tuning = TuningPanel.new()
	_place(_tuning, BOARD_X, BOARD_Y, BOARD_W, BOARD_H)
	_tuning.changed.connect(_on_tuning_changed)
	_tuning.closed.connect(_on_tuning_closed)
	_tuning.tab_changed.connect(_refresh_podium_smoke)
	canvas.add_child(_tuning)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.position = Vector2(18, 46)
	_scroll.size = Vector2(BOARD_W - 36, BOARD_H - 46 - 30)
	board.add_child(_scroll)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(grid)

	var tag_sb := StyleBoxFlat.new()
	tag_sb.bg_color = UiKit.YELLOW
	tag_sb.set_corner_radius_all(4)
	tag_sb.content_margin_left = 5
	tag_sb.content_margin_right = 5
	for i in CarModelLibrary.CAR_IDS.size():
		var btn := Button.new()
		btn.custom_minimum_size = THUMB_SIZE
		btn.expand_icon = true
		btn.focus_mode = Control.FOCUS_NONE
		_apply_style(btn, _style_normal, _style_hover)
		btn.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(btn)
		_buttons.append(btn)
		# Жёлтый ярлык «с N уровня» на закрытой ячейке (видимость ставит
		# _refresh_grid_locks — он же красит силуэты и тултипы).
		var lock := UiKit.label(btn, "%d ур." % GameState.car_unlock_level(
				CarModelLibrary.CAR_IDS[i]), 11, UiKit.INK)
		lock.add_theme_stylebox_override("normal", tag_sb)
		lock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lock.offset_left = -56
		lock.offset_top = -24
		lock.offset_right = -5
		lock.offset_bottom = -5
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock.visible = false
		_grid_locks.append(lock)
	_refresh_grid_locks()


func _apply_style(btn: Button, style: StyleBoxFlat,
		hover: StyleBoxFlat = null) -> void:
	for state in ["normal", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, style)
	btn.add_theme_stylebox_override("hover", hover if hover else style)
