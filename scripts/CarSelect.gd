extends Node3D
## Экран выбора машины: слева тачка крутится на подиуме, справа — сетка
## миниатюр всех машин (рендерятся в текстуры один раз, кэш в GameState).
## Управление: ←→ / A D — листать, ↑↓ — по рядам сетки, мышь — клик по
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
}

## Названия цветов-скинов для подсказок.
const COLOR_NAMES := {
	"black": "чёрный", "blue": "синий", "gray": "серый",
	"green": "зелёный", "lightblue": "голубой", "purple": "фиолетовый",
	"red": "красный", "sand": "песочный", "white": "белый",
	"yellow": "жёлтый",
}
## Цвет квадратика-образца (приблизительный тон краски палитры).
const SWATCH_COLORS := {
	"black": Color(0.12, 0.12, 0.13), "blue": Color(0.13, 0.3, 0.62),
	"gray": Color(0.55, 0.57, 0.6), "green": Color(0.24, 0.5, 0.26),
	"lightblue": Color(0.42, 0.7, 0.85), "purple": Color(0.48, 0.26, 0.62),
	"red": Color(0.73, 0.16, 0.17), "sand": Color(0.8, 0.71, 0.5),
	"white": Color(0.93, 0.93, 0.93), "yellow": Color(0.92, 0.77, 0.13),
}

const GRID_COLUMNS := 5
const THUMB_SIZE := Vector2(104, 78)

var _index := 0
var _turntable: Node3D
var _model: Node3D
var _name_label: Label
var _count_label: Label
var _buttons: Array[Button] = []
var _host_edit: LineEdit          # адрес сетевого сервера
var _net_status: Label
var _size_label: Label            # число участников заезда (4..8)
var _size_panel: Control          # панель «УЧАСТНИКОВ» (в футболе всегда 8)
var _size_buttons: Array[Button] = []
var _mode_button: Button          # переключатель ГОНКА/ФУТБОЛ
var _canvas: CanvasLayer          # слой HUD (нужен окну ввода имени)
var _name_btn: Button             # «ИМЯ: …» под строкой уровня
var _name_dialog: Control         # модальное окно ввода имени (null — нет)
var _name_edit: LineEdit
var _scroll: ScrollContainer
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _ui_font: FontFile  # Russo One — индустриальный, с кириллицей
var _xp_label: Label              # строка «УРОВЕНЬ · ОПЫТ · МОНЕТЫ»
var _start_btn: Button            # «СТАРТ» (у купленной машины)
var _buy_btn: Button              # «КУПИТЬ · цена» (у закрытой машины)
var _color_btns: Array[Button] = []   # ряд квадратиков-скинов
var _color_panel: Control         # подложка ряда скинов
var _grid_locks: Array[Label] = []    # значки «N ур.» на ячейках сетки
var _buy_flash := 0               # поколение вспышки «НЕ ХВАТАЕТ МОНЕТ»


## Полный id скина машины из сетки: база + её текущий цвет.
func _full_id(i: int) -> String:
	var base: String = CarModelLibrary.CAR_IDS[i]
	return CarModelLibrary.skin_id(base, GameState.color_of(base))


func _ready() -> void:
	_index = maxi(0, CarModelLibrary.CAR_IDS.find(
			CarModelLibrary.base_id(GameState.selected_car_id)))
	_setup_environment()
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
	_turntable.rotation.y += delta * 0.9
	# Открыто окно ввода имени — клавиши достаются ему, а не выбору машины
	# (иначе Enter в поле имени тут же запускал бы гонку).
	if _name_dialog != null:
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


## «СТАРТ» — единственная кнопка запуска: гонка идёт ПО СЕТИ (адрес из
## поля, по умолчанию VDS). Сервер не ответил / нет адреса — тихо стартуем
## оффлайн с ботами: они и так подписаны человеческими никами и от живых
## игроков неотличимы, игрок просто едет. Футбол сетевого протокола пока
## не имеет — сразу оффлайн.
func _start_race() -> void:
	if _name_dialog != null:
		return   # сначала имя — окно модальное
	var base: String = CarModelLibrary.CAR_IDS[_index]
	if not GameState.car_owned(base):
		return   # закрытая машина — сперва купить (кнопка «КУПИТЬ»)
	Net.leave()   # вдруг остались хвосты прошлого сетевого заезда
	GameState.select_car(base)
	if GameState.game_mode == GameState.MODE_SOCCER:
		# Футбол: своя арена, трасса не нужна.
		get_tree().change_scene_to_file("res://scenes/Soccer.tscn")
		return
	var text := _host_edit.text.strip_edges() if _host_edit else ""
	var addr := text
	var port := Net.PORT
	# Порт можно дописать через двоеточие: 1.2.3.4:9977. Режем ПОСЛЕДНЕЕ
	# двоеточие — в IPv6-адресе их много.
	var colon := text.rfind(":")
	if colon > 0:
		addr = text.substr(0, colon)
		port = int(text.substr(colon + 1))
		if port <= 0:
			port = Net.PORT
	if addr.is_empty():
		_start_offline()
		return
	# Свою сцену строим сразу под желаемый размер: если мы окажемся первым
	# игроком лобби, сервер примет его и перестройка не понадобится; если
	# заезд уже другого размера — сервер продиктует свой (_rx_track).
	Net.race_size = GameState.race_size
	if _net_status:
		_net_status.text = "Подключение…"
	if Net.join_server(addr, port):
		_watch_connect_timeout()
	else:
		_start_offline()


## Оффлайн-заезд: игрок + (race_size−1) ботов, случайная трасса.
func _start_offline() -> void:
	Net.leave()
	GameState.track_kind = TrackBuilder.pick_random_kind()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


## Переключатель режима игры (ГОНКА / ФУТБОЛ) — над панелью «УЧАСТНИКОВ».
## Футбол: всегда 8 машин 4 на 4, поэтому выбор числа участников гаснет.
func _build_mode_ui(canvas: Node) -> void:
	var panel := UiKit.plate(canvas, "steel", Vector2.ZERO, Vector2(150, 70))
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20
	panel.offset_right = 170
	panel.offset_top = -200
	panel.offset_bottom = -130

	var title := Label.new()
	title.text = "РЕЖИМ"
	if _ui_font:
		title.add_theme_font_override("font", _ui_font)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	title.position = Vector2(0, 6)
	title.size = Vector2(150, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	# Кнопка того же плоского стиля, что −/+ (UiKit.style_button мелкой
	# кнопке навязывает рост и заклёпки — см. _mini_button).
	_mode_button = _mini_button("ГОНКА")
	_mode_button.add_theme_font_size_override("font_size", 18)
	_mode_button.position = Vector2(12, 24)
	_mode_button.size = Vector2(126, 38)
	_mode_button.pressed.connect(_toggle_mode)
	panel.add_child(_mode_button)


func _toggle_mode() -> void:
	GameState.set_game_mode(
			GameState.MODE_SOCCER
			if GameState.game_mode == GameState.MODE_RACE
			else GameState.MODE_RACE)
	_apply_mode_ui()


## Обновить подписи под текущий режим: текст кнопки и доступность выбора
## числа участников (в футболе состав фиксированный — 4 на 4).
func _apply_mode_ui() -> void:
	var soccer := GameState.game_mode == GameState.MODE_SOCCER
	if _mode_button:
		_mode_button.text = "ФУТБОЛ" if soccer else "ГОНКА"
	if _size_panel:
		_size_panel.modulate = Color(1, 1, 1, 0.45) if soccer else Color.WHITE
	for b in _size_buttons:
		b.disabled = soccer
	if _size_label:
		_size_label.text = "8" if soccer else str(GameState.race_size)


## Выбор числа участников заезда (4..8) — стальная табличка в левом нижнем
## углу, рядом со «СТАРТ». Действует и оффлайн (игрок + N−1 ботов), и по
## сети: размер лобби задаёт ПЕРВЫЙ подключившийся игрок (Main._rx_hello),
## остальные приезжают в заезд его размера. Выбор хранится в профиле.
func _build_race_size_ui(canvas: Node) -> void:
	var panel := UiKit.plate(canvas, "steel", Vector2.ZERO, Vector2(150, 70))
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20
	panel.offset_right = 170
	panel.offset_top = -122
	panel.offset_bottom = -52
	_size_panel = panel

	var title := Label.new()
	title.text = "УЧАСТНИКОВ"
	if _ui_font:
		title.add_theme_font_override("font", _ui_font)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	title.position = Vector2(0, 6)
	title.size = Vector2(150, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	_size_label = Label.new()
	_size_label.text = str(GameState.race_size)
	if _ui_font:
		_size_label.add_theme_font_override("font", _ui_font)
	_size_label.add_theme_font_size_override("font_size", 28)
	_size_label.add_theme_color_override("font_color", UiKit.YELLOW)
	_size_label.add_theme_constant_override("outline_size", 5)
	_size_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	# Ровно полоса МЕЖДУ кнопками (50..100) и ОДНА линия с ними (y и
	# высота совпадают с кнопками): дважды подгонялось «на глазок» и
	# дважды оказывалось криво — теперь кнопки держат заданный размер
	# (см. _flatten_button), и все три бокса просто одинаковые.
	_size_label.position = Vector2(50, 24)
	_size_label.size = Vector2(50, 38)
	_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_size_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_size_label)

	var minus := _mini_button("–")
	minus.position = Vector2(12, 24)
	minus.size = Vector2(38, 38)
	minus.pressed.connect(func() -> void: _change_race_size(-1))
	panel.add_child(minus)

	var plus := _mini_button("+")
	plus.position = Vector2(100, 24)
	plus.size = Vector2(38, 38)
	plus.pressed.connect(func() -> void: _change_race_size(1))
	panel.add_child(plus)
	_size_buttons = [minus, plus]


## Маленькая плоская кнопка −/+. НЕ UiKit.style_button, и это выстрадано:
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
	dim.color = Color(0, 0, 0, 0.6)
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

	var title := Label.new()
	title.text = "КАК ТЕБЯ ЗОВУТ?"
	if _ui_font:
		title.add_theme_font_override("font", _ui_font)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", UiKit.INK)
	title.position = Vector2(0, 16)
	title.size = Vector2(460, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(title)

	var hint := Label.new()
	hint.text = "Под этим именем тебя увидят другие игроки"
	if _ui_font:
		hint.add_theme_font_override("font", _ui_font)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	hint.position = Vector2(0, 54)
	hint.size = Vector2(460, 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(hint)

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


func _change_race_size(dir: int) -> void:
	if GameState.game_mode == GameState.MODE_SOCCER:
		return   # в футболе состав фиксированный: 4 на 4
	GameState.set_race_size(GameState.race_size + dir)
	if _size_label:
		_size_label.text = str(GameState.race_size)


## Сетевая строка гаража: статус подключения и поле адреса сервера.
## Отдельной кнопки «ПО СЕТИ» больше нет — по сети везёт сама «СТАРТ»
## (см. _start_race); гонка начнётся, когда сервер подтвердит соединение
## (сигнал Net.joined), а не ответит — оффлайн с ботами.
func _build_net_ui(canvas: Node) -> void:
	_net_status = Label.new()
	_net_status.text = ""
	if _ui_font:
		_net_status.add_theme_font_override("font", _ui_font)
	_net_status.add_theme_font_size_override("font_size", 18)
	_net_status.add_theme_constant_override("outline_size", 5)
	_net_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_net_status.add_theme_color_override("font_color", UiKit.YELLOW)
	canvas.add_child(_net_status)
	# Панель жмётся к левой половине экрана: справа от 685 px начинается
	# сетка машин, и на анкере 0.75 кнопка уезжала ПОД неё — в кадре её
	# было не видно вовсе (поймано скриншот-стендом ScreenshotSelect).
	_net_status.anchor_left = 0.0
	_net_status.anchor_right = 0.0
	_net_status.anchor_top = 1.0
	_net_status.anchor_bottom = 1.0
	_net_status.offset_left = 450
	_net_status.offset_right = 690
	_net_status.offset_top = -196
	_net_status.offset_bottom = -172
	_net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_host_edit = LineEdit.new()
	# В поле — ДОМАШНИЙ порт, а не Net.port: тот после перенаправления в
	# комнату (_rx_redirect) равен порту КОМНАТЫ, и игрок, вернувшись в
	# гараж и нажав «ПО СЕТИ», сохранял его себе в net.cfg как постоянный —
	# комната смертна, и дальше вечное «Сервер не ответил за 5 с» (поймано
	# у живого игрока 28.08: в поле оказалось :9978, на экране обрезано до
	# «:99»). Стандартный порт не показываем вовсе — меньше мусора в поле.
	_host_edit.text = Net.host if Net.home_port == Net.PORT \
			else "%s:%d" % [Net.host, Net.home_port]
	_host_edit.placeholder_text = "адрес[:порт]"
	_host_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _ui_font:
		_host_edit.add_theme_font_override("font", _ui_font)
	_host_edit.add_theme_font_size_override("font_size", 20)
	# Стальная рамка вместо системной серой.
	var edit_sb := UiKit.steel_box(6, 0.95)
	edit_sb.set_content_margin_all(6)
	for state in ["normal", "focus"]:
		_host_edit.add_theme_stylebox_override(state, edit_sb)
	_host_edit.add_theme_color_override("font_color", Color.WHITE)
	_host_edit.add_theme_color_override("caret_color", UiKit.YELLOW)
	_host_edit.anchor_left = 0.0
	_host_edit.anchor_right = 0.0
	_host_edit.anchor_top = 1.0
	_host_edit.anchor_bottom = 1.0
	# Ширина как у кнопки ниже: в 200 px «адрес:порт» не влезал, и хвост
	# порта ОБРЕЗАЛСЯ на экране («:9978» выглядел как «:99») — игрок не мог
	# увидеть, куда на самом деле стучится игра.
	_host_edit.offset_left = 450
	_host_edit.offset_right = 690
	_host_edit.offset_top = -166
	_host_edit.offset_bottom = -130
	canvas.add_child(_host_edit)

	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)


## ENet сам по себе может молчать очень долго, поэтому ограничиваем
## ожидание вручную: не ответил за CONNECT_TIMEOUT — рвём и тихо стартуем
## оффлайн с ботами (для игрока разницы нет — ники у ботов человеческие).
func _watch_connect_timeout() -> void:
	await get_tree().create_timer(Net.CONNECT_TIMEOUT).timeout
	if not is_inside_tree() or not Net.is_client():
		return
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() 			== MultiplayerPeer.CONNECTION_CONNECTED:
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


func _set_index(i: int) -> void:
	var prev := _index
	_index = i
	if _model:
		_model.queue_free()
	var base: String = CarModelLibrary.CAR_IDS[_index]
	_model = CarModelLibrary.build(_full_id(_index), 3.2, 0.02)
	if _model:
		_turntable.add_child(_model)
	var owned: bool = GameState.car_owned(base)
	_name_label.text = DISPLAY_NAMES.get(base, base)
	_name_label.add_theme_color_override("font_color",
			Color.WHITE if owned else Color(1, 1, 1, 0.45))
	_count_label.text = "%d / %d" % [_index + 1, CarModelLibrary.CAR_IDS.size()]
	# Закрытая машина стоит на подиуме «тенью» — видно, но не наша.
	if _model and not owned:
		_dim_model(_model)
	_refresh_lock_ui()
	_refresh_swatches()
	# Подсветка ячейки в сетке.
	if _buttons.size() > prev:
		_apply_style(_buttons[prev], _style_normal)
	if _buttons.size() > _index:
		_apply_style(_buttons[_index], _style_selected)
		_scroll.ensure_control_visible(_buttons[_index])


## Затемнить модель на подиуме (закрытая машина — «силуэт в тени»).
func _dim_model(model: Node) -> void:
	for child in model.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var dim := StandardMaterial3D.new()
			dim.albedo_color = Color(0.1, 0.1, 0.12)
			dim.roughness = 0.9
			mi.material_override = dim
		_dim_model(child)


## Кнопки под подиумом: у купленной машины — «СТАРТ», у закрытой —
## «КУПИТЬ · цена» (уровень мал — серая «С N УРОВНЯ · цена»).
func _refresh_lock_ui() -> void:
	var base: String = CarModelLibrary.CAR_IDS[_index]
	var owned: bool = GameState.car_owned(base)
	if _start_btn:
		_start_btn.visible = owned
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


func _refresh_money_label() -> void:
	if _xp_label == null:
		return
	var info: Vector3i = GameState.level_info()
	_xp_label.text = "УРОВЕНЬ %d  ·  ОПЫТ %d / %d  ·  МОНЕТЫ %d" \
			% [info.x, info.y, info.z, GameState.money]


## Значки «N ур.» и затемнение на закрытых ячейках сетки.
func _refresh_grid_locks() -> void:
	for i in _buttons.size():
		var base: String = CarModelLibrary.CAR_IDS[i]
		var owned: bool = GameState.car_owned(base)
		_buttons[i].modulate = Color.WHITE if owned \
				else Color(0.5, 0.5, 0.55)
		if i < _grid_locks.size():
			_grid_locks[i].visible = not owned
		_buttons[i].tooltip_text = DISPLAY_NAMES.get(base, base) if owned \
				else "%s — с %d уровня, %s монет" % [
						DISPLAY_NAMES.get(base, base),
						GameState.car_unlock_level(base),
						_fmt_money(GameState.car_price(base))]


# ---- Скины: ряд цветов под подиумом ----

## Ряд из 10 квадратиков-красок; для машин без скинов прячется целиком.
func _build_color_ui(canvas: Node) -> void:
	var panel := Control.new()
	panel.anchor_left = 0.25
	panel.anchor_right = 0.25
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -178
	panel.offset_right = 178
	panel.offset_top = -254
	panel.offset_bottom = -222
	canvas.add_child(panel)
	_color_panel = panel
	for k in CarModelLibrary.SOVIET_COLORS.size():
		var color: String = CarModelLibrary.SOVIET_COLORS[k]
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.position = Vector2(k * 36, 0)
		b.size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = String(COLOR_NAMES.get(color, color)).capitalize()
		b.pressed.connect(_on_color_pressed.bind(color))
		panel.add_child(b)
		_color_btns.append(b)


## Подсветить выбранный цвет текущей машины (жёлтая рамка).
func _refresh_swatches() -> void:
	var base: String = CarModelLibrary.CAR_IDS[_index]
	if _color_panel == null:
		return
	_color_panel.visible = CarModelLibrary.has_skins(base)
	if not _color_panel.visible:
		return
	var current: String = GameState.color_of(base)
	for k in _color_btns.size():
		var color: String = CarModelLibrary.SOVIET_COLORS[k]
		var sb := StyleBoxFlat.new()
		sb.bg_color = SWATCH_COLORS.get(color, Color.MAGENTA)
		sb.set_corner_radius_all(6)
		if color == current:
			sb.set_border_width_all(3)
			sb.border_color = UiKit.YELLOW
		else:
			sb.set_border_width_all(1)
			sb.border_color = Color(0, 0, 0, 0.5)
		for state in ["normal", "hover", "pressed", "focus"]:
			_color_btns[k].add_theme_stylebox_override(state, sb)


func _on_color_pressed(color: String) -> void:
	var base: String = CarModelLibrary.CAR_IDS[_index]
	GameState.set_car_color(base, color)
	_set_index(_index)      # перестроить подиум в новом цвете
	_update_thumb(_index)   # и миниатюру в сетке


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


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.06, 0.1)  # тёмный «гараж»
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.6)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 140, 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.0, 4.6)
	cam.rotation_degrees = Vector3(-14, 0, 0)
	cam.fov = 50
	# Сетка занимает правые ~600px из 1280 → видимая зона 0..680,
	# её центр = 0.266 ширины экрана. Сдвиг кадра: (0.5-0.266) от ширины
	# фрустума на дистанции до подиума (~4.8 м) ≈ 1.85 м.
	cam.h_offset = 1.85
	add_child(cam)
	cam.make_current()


func _setup_podium() -> void:
	var podium := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.2
	mesh.bottom_radius = 2.5
	mesh.height = 0.35
	podium.mesh = mesh
	podium.position.y = -0.175
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.2)
	mat.metallic = 0.6
	mat.roughness = 0.35
	podium.material_override = mat
	add_child(podium)

	_turntable = Node3D.new()
	_turntable.name = "TurnTable"
	add_child(_turntable)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_canvas = canvas
	_ui_font = UiKit.font()

	# Заголовок — белая эмалевая табличка с чернильным текстом и
	# аварийной лентой по нижней кромке («гаражный» стиль).
	var banner := UiKit.plate(canvas, "white", Vector2.ZERO,
			Vector2(420, 92), false)
	banner.anchor_left = 0.25
	banner.anchor_right = 0.25
	banner.offset_left = -210
	banner.offset_right = 210
	banner.offset_top = 14
	banner.offset_bottom = 106
	UiKit.hazard(banner, Vector2(14, 92 - 22), Vector2(420 - 28, 12), 0.95)
	var title := Label.new()
	title.text = "ВЫБОР МАШИНЫ"
	if _ui_font:
		title.add_theme_font_override("font", _ui_font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiKit.INK)
	banner.add_child(title)
	# and_offsets: обычный set_anchors_preset сохранил бы крошечный размер.
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.offset_bottom = -10
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Уровень, опыт и кошелёк профиля — жёлтая строка под заголовком.
	# Опыт и монеты даются на финише (GameState); уровни открывают машины
	# и оружие для покупки за монеты — сетка и цены в ЭКОНОМИКА.md.
	var xp_label := Label.new()
	_xp_label = xp_label
	_refresh_money_label()
	if _ui_font:
		xp_label.add_theme_font_override("font", _ui_font)
	xp_label.add_theme_font_size_override("font_size", 15)
	xp_label.add_theme_color_override("font_color", UiKit.YELLOW)
	xp_label.add_theme_constant_override("outline_size", 5)
	xp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	xp_label.anchor_left = 0.25
	xp_label.anchor_right = 0.25
	xp_label.offset_left = -210
	xp_label.offset_right = 210
	xp_label.offset_top = 112
	xp_label.offset_bottom = 138
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(xp_label)

	# Имя игрока — строкой под уровнем; клик открывает окно смены имени.
	_name_btn = _mini_button("")
	_name_btn.add_theme_font_size_override("font_size", 16)
	_name_btn.anchor_left = 0.25
	_name_btn.anchor_right = 0.25
	_name_btn.offset_left = -110
	_name_btn.offset_right = 110
	_name_btn.offset_top = 144
	_name_btn.offset_bottom = 174
	_name_btn.pressed.connect(func() -> void: _open_name_dialog(false))
	canvas.add_child(_name_btn)
	_refresh_name_btn()

	# Имя машины — на стальной табличке.
	var name_panel := UiKit.plate(canvas, "steel", Vector2.ZERO,
			Vector2(380, 70))
	name_panel.anchor_left = 0.25
	name_panel.anchor_right = 0.25
	name_panel.anchor_top = 1.0
	name_panel.anchor_bottom = 1.0
	name_panel.offset_left = -190
	name_panel.offset_right = 190
	name_panel.offset_top = -216
	name_panel.offset_bottom = -146
	_name_label = Label.new()
	if _ui_font:
		_name_label.add_theme_font_override("font", _ui_font)
	_name_label.add_theme_font_size_override("font_size", 30)
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.add_theme_color_override("font_outline_color", UiKit.INK)
	name_panel.add_child(_name_label)
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_count_label = Label.new()
	if _ui_font:
		_count_label.add_theme_font_override("font", _ui_font)
	_count_label.add_theme_font_size_override("font_size", 16)
	_count_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_count_label.anchor_right = 0.5
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.position.y = -144
	_count_label.modulate = Color(1, 1, 1, 0.7)
	canvas.add_child(_count_label)

	# Стрелки листания по бокам подиума — оранжевые таблички.
	_make_arrow(canvas, "res://assets/ui/garage/arrow_l.png", 0.06,
			func() -> void: _set_index(
					(_index - 1 + CarModelLibrary.CAR_IDS.size())
					% CarModelLibrary.CAR_IDS.size()))
	_make_arrow(canvas, "res://assets/ui/garage/arrow_r.png", 0.44,
			func() -> void: _set_index(
					(_index + 1) % CarModelLibrary.CAR_IDS.size()))

	# Кнопка «СТАРТ» — оранжевая эмалевая табличка (как START референса).
	var start_btn := Button.new()
	start_btn.text = "СТАРТ"
	UiKit.style_button(start_btn, "orange", 30)
	start_btn.anchor_left = 0.25
	start_btn.anchor_right = 0.25
	start_btn.anchor_top = 1.0
	start_btn.anchor_bottom = 1.0
	start_btn.offset_left = -130
	start_btn.offset_right = 130
	start_btn.offset_top = -122
	start_btn.offset_bottom = -52
	start_btn.pressed.connect(_start_race)
	canvas.add_child(start_btn)
	_start_btn = start_btn

	# «КУПИТЬ · цена» — на месте «СТАРТ», видна только у закрытой машины.
	var buy_btn := Button.new()
	UiKit.style_button(buy_btn, "orange", 22)
	buy_btn.anchor_left = 0.25
	buy_btn.anchor_right = 0.25
	buy_btn.anchor_top = 1.0
	buy_btn.anchor_bottom = 1.0
	buy_btn.offset_left = -130
	buy_btn.offset_right = 130
	buy_btn.offset_top = -122
	buy_btn.offset_bottom = -52
	buy_btn.visible = false
	buy_btn.pressed.connect(_buy_pressed)
	canvas.add_child(buy_btn)
	_buy_btn = buy_btn

	_build_color_ui(canvas)
	_build_race_size_ui(canvas)
	_build_mode_ui(canvas)
	_build_net_ui(canvas)
	_apply_mode_ui()

	var help := Label.new()
	help.text = "←→↑↓ / AD — выбор  |  клик — выбрать, ещё раз — старт  |  Enter — в гонку"
	if _ui_font:
		help.add_theme_font_override("font", _ui_font)
	help.add_theme_font_size_override("font_size", 15)
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.anchor_right = 0.5
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.position.y = -36
	help.modulate = Color(1, 1, 1, 0.7)
	canvas.add_child(help)

	_setup_grid(canvas)


## Мультяшная кнопка-стрелка листания (позиция — доля ширины экрана).
func _make_arrow(canvas: CanvasLayer, tex_path: String, anchor_x: float,
		on_press: Callable) -> void:
	var btn := TextureButton.new()
	btn.texture_normal = load(tex_path)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left = anchor_x
	btn.anchor_right = anchor_x
	btn.anchor_top = 0.5
	btn.anchor_bottom = 0.5
	btn.offset_left = 0
	btn.offset_right = 76
	btn.offset_top = -38
	btn.offset_bottom = 38
	btn.modulate = Color(1, 1, 1, 0.92)
	btn.pressed.connect(on_press)
	btn.button_down.connect(func() -> void: btn.modulate = Color(0.75, 0.75, 0.75))
	btn.button_up.connect(func() -> void: btn.modulate = Color(1, 1, 1, 0.92))
	canvas.add_child(btn)


## Правая половина: прокручиваемая сетка миниатюр всех машин.
func _setup_grid(canvas: CanvasLayer) -> void:
	_style_normal = UiKit.steel_box()
	_style_selected = UiKit.steel_box()
	_style_selected.bg_color = Color(0.30, 0.27, 0.14, 0.95)
	_style_selected.set_border_width_all(3)
	_style_selected.border_color = UiKit.YELLOW

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(UiKit.INK.r, UiKit.INK.g, UiKit.INK.b, 0.88)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(10)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(UiKit.RIM.r, UiKit.RIM.g,
			UiKit.RIM.b, 0.45)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -600
	panel.offset_top = 20
	panel.offset_bottom = -20
	panel.offset_right = -16
	canvas.add_child(panel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(grid)

	for i in CarModelLibrary.CAR_IDS.size():
		var btn := Button.new()
		btn.custom_minimum_size = THUMB_SIZE
		btn.expand_icon = true
		btn.focus_mode = Control.FOCUS_NONE
		_apply_style(btn, _style_normal)
		btn.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(btn)
		_buttons.append(btn)
		# Значок «с N уровня» на закрытой ячейке (текст ставит
		# _refresh_grid_locks — он же красит и тултипы).
		var lock := Label.new()
		lock.text = "%d ур." % GameState.car_unlock_level(
				CarModelLibrary.CAR_IDS[i])
		if _ui_font:
			lock.add_theme_font_override("font", _ui_font)
		lock.add_theme_font_size_override("font_size", 13)
		lock.add_theme_color_override("font_color", UiKit.YELLOW)
		lock.add_theme_constant_override("outline_size", 4)
		lock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lock.offset_left = -52
		lock.offset_top = -22
		lock.offset_right = -6
		lock.offset_bottom = -4
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lock.visible = false
		btn.add_child(lock)
		_grid_locks.append(lock)
	_refresh_grid_locks()


func _apply_style(btn: Button, style: StyleBoxFlat) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, style)
