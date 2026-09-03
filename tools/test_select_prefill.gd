extends Node
## Стенд адреса сервера в гараже (28.08, переписан 03.09: поля адреса на
## экране больше нет — «СТАРТ» берёт адрес и ДОМАШНИЙ порт из Net сам).
## После перенаправления в комнату Net.port равен порту КОМНАТЫ; раньше
## поле подставляло именно его, игрок жал «ПО СЕТИ» и сохранял смертный
## порт комнаты как постоянный — дальше вечное «Сервер не ответил за 5 с».
## Проверяем:
##   1) цель «СТАРТ» (_net_target) — домашний порт, а не порт комнаты;
##   2) амнистию cfg: сохранённый порт из диапазона комнат при загрузке
##      откатывается к воротам (net.cfg бережно восстанавливается).

func _ready() -> void:
	# Состояние «нас только что перенаправили»: дом — ворота, порт — комната.
	Net.host = "139.100.234.166"
	Net.home_port = Net.PORT
	Net.port = Net.PORT + 1
	var sel: Node = (load("res://scenes/CarSelect.tscn")
			as PackedScene).instantiate()
	add_child(sel)
	var target: Array = sel._net_target()
	var ok1: bool = target[0] == "139.100.234.166" and target[1] == Net.PORT
	print("цель СТАРТ после редиректа: %s:%d %s"
			% [target[0], target[1], "ok" if ok1 else "FAIL"])
	# Адреса на экране быть не должно вовсе (просьба 03.09).
	var ok3: bool = not _has_text(sel, "139.100.234.166")
	print("адрес на экране: %s" % ("нет, ok" if ok3 else "ЕСТЬ — FAIL"))

	var had_cfg := FileAccess.file_exists(Net.CONFIG_PATH)
	var orig := FileAccess.get_file_as_string(Net.CONFIG_PATH) \
			if had_cfg else ""
	var cfg := ConfigFile.new()
	cfg.set_value("net", "host", "139.100.234.166")
	cfg.set_value("net", "port", Net.PORT + 1)
	cfg.save(Net.CONFIG_PATH)
	Net._load_config()
	var ok2: bool = Net.port == Net.PORT and Net.home_port == Net.PORT
	print("амнистия cfg: порт %d, дом %d %s"
			% [Net.port, Net.home_port, "ok" if ok2 else "FAIL"])
	if had_cfg:
		var f := FileAccess.open(Net.CONFIG_PATH, FileAccess.WRITE)
		f.store_string(orig)
	else:
		DirAccess.remove_absolute(Net.CONFIG_PATH)

	var ok := ok1 and ok2 and ok3
	print("SELECTPREFILL TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


## Есть ли строка в тексте какого-нибудь Label/Button/LineEdit сцены.
func _has_text(node: Node, needle: String) -> bool:
	for c in node.get_children():
		if (c is Label or c is Button or c is LineEdit) \
				and String(c.get("text")).contains(needle):
			return true
		if _has_text(c, needle):
			return true
	return false
