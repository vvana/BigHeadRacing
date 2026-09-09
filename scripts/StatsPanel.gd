class_name StatsPanel
extends PanelContainer
## СТАТИСТИКА ИГРОКА в гараже (09.09): на месте доски «АВТОПАРК». Всё —
## из GameState.stats (копится на финише: record_race / record_soccer):
## рейтинг, заезды, победы, подиумы, среднее и лучшее место, уничтоженные
## соперники, любимая машина, футбол.

signal closed

const CAR_NAMES: Dictionary = preload("res://scripts/CarSelect.gd").DISPLAY_NAMES

var _font: FontFile
var _box: VBoxContainer
var _head: HBoxContainer          # шапка с «ЗАКРЫТЬ» — вне прокрутки


func _ready() -> void:
	_font = UiKit.font()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.19, 0.21, 0.24, 0.96)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(UiKit.RIM.r, UiKit.RIM.g, UiKit.RIM.b, 0.45)
	add_theme_stylebox_override("panel", style)
	# Корень — колонка: НЕподвижная шапка и прокручиваемый список (09.09 —
	# «ЗАКРЫТЬ» уезжало вверх вместе с содержимым).
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 10)
	root.add_child(_head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	visible = false


func open() -> void:
	visible = true
	rebuild()


func close() -> void:
	visible = false
	closed.emit()


func rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	for c in _head.get_children():
		_head.remove_child(c)
		c.queue_free()
	# Шапка с «ЗАКРЫТЬ» — вне прокрутки, всегда на виду.
	var head := _head
	var title := _label("СТАТИСТИКА · %s" % GameState.display_name(), 20,
			UiKit.YELLOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "ЗАКРЫТЬ"
	UiKit.style_button(close_btn, "steel", 14)
	close_btn.custom_minimum_size = Vector2(110, 34)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var st: Dictionary = GameState.stats if not GameState.stats.is_empty() \
			else GameState.empty_stats()
	var info: Vector3i = GameState.level_info()
	var races := int(st.races)

	# Рейтинг — крупно, отдельной плашкой.
	var big := HBoxContainer.new()
	big.add_theme_constant_override("separation", 14)
	_box.add_child(big)
	_tile(big, "РЕЙТИНГ", str(GameState.rating()), UiKit.YELLOW)
	_tile(big, "УРОВЕНЬ", "%d" % info.x, Color.WHITE)
	_tile(big, "ЗАЕЗДОВ", str(races), Color.WHITE)
	var about := _label(
			"Рейтинг: старт %d, за победу +%d, за последнее место −%d, "
			% [GameState.RATING_START, GameState.RATING_SWING,
					GameState.RATING_SWING]
			+ "середина 0, плюс %d за каждого уничтоженного соперника."
			% GameState.RATING_KILL, 11, Color(1, 1, 1, 0.5))
	# Без переноса длинная строка растянула бы колонку шире панели — и все
	# значения строк уехали бы за правый край (поймано снимком 09.09).
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(about)
	_box.add_child(HSeparator.new())

	_section("ГОНКИ")
	_row("Заездов", "%d (по сети %d)" % [races, int(st.net_races)])
	_row("Побед", "%d" % int(st.wins) + _pct(int(st.wins), races))
	_row("Подиумов (1–3 место)", "%d" % int(st.podiums)
			+ _pct(int(st.podiums), races))
	_row("Среднее место", "%.1f" % GameState.avg_place() if races > 0 else "—")
	_row("Уничтожено соперников", "%d" % int(st.kills))
	_row("Уничтожали тебя", "%d" % int(st.get("deaths", 0)))
	_row("Опыт", "%d (до уровня %d: %d / %d)" % [GameState.xp, info.x + 1,
			info.y, info.z])

	_section("ЛЮБИМАЯ МАШИНА")
	var fav: Array = GameState.favourite_car()
	if str(fav[0]) == "":
		_box.add_child(_label("Проедь первый заезд — узнаем", 13,
				Color(1, 1, 1, 0.6)))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		var full: String = GameState.full_id(str(fav[0]))
		var tex: Variant = GameState.car_thumbs.get(full)
		if tex is Texture2D:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.custom_minimum_size = Vector2(104, 78)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(pic)
		var col := VBoxContainer.new()
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		# Без переноса: в колонке рядом с картинкой перенос по словам рвал
		# название на буквы (снимок 09.09).
		var fav_l := _label(str(CAR_NAMES.get(str(fav[0]), str(fav[0]))), 18,
				Color.WHITE)
		fav_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(fav_l)
		var cnt_l := _label("заездов на ней: %d" % int(fav[1]), 13,
				Color(1, 1, 1, 0.6))
		cnt_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(cnt_l)
		# Остальные машины — по убыванию заездов, до пяти.
		var others: Array = []
		for base: String in st.cars:
			if base != str(fav[0]):
				others.append([base, int(st.cars[base])])
		others.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		var parts := PackedStringArray()
		for i in mini(others.size(), 5):
			parts.append("%s — %d" % [CAR_NAMES.get(others[i][0], others[i][0]),
					others[i][1]])
		if not parts.is_empty():
			var more := _label("ещё: " + ", ".join(parts), 11, Color(1, 1, 1, 0.5))
			more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_box.add_child(more)

	_section("ФУТБОЛ")
	var games := int(st.soccer_games)
	_row("Матчей", str(games))
	_row("Побед", "%d" % int(st.soccer_wins) + _pct(int(st.soccer_wins), games))
	_row("Голов", str(int(st.soccer_goals)))


func _pct(n: int, total: int) -> String:
	if total <= 0:
		return ""
	return "  (%d %%)" % roundi(100.0 * n / total)


func _section(txt: String) -> void:
	var l := _label(txt, 14, UiKit.TEAL)
	l.add_theme_constant_override("outline_size", 0)
	_box.add_child(l)


func _row(k: String, v: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	var kl := _label(k, 14, Color(1, 1, 1, 0.75))
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kl)
	var vl := _label(v, 15, Color.WHITE)
	vl.size_flags_horizontal = Control.SIZE_SHRINK_END
	vl.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(vl)


## Крупная плашка «подпись / число».
func _tile(parent: Node, cap: String, val: String, color: Color) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.steel_box(8, 0.9))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	p.add_child(col)
	var c := _label(cap, 11, Color(1, 1, 1, 0.55))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(c)
	var v := _label(val, 30, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(v)


func _label(txt: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Колонка не шире панели: длинный текст переносится, а не растягивает.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
