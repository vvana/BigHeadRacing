extends Node
## Стенд поля адреса в гараже (28.08). После перенаправления в комнату
## Net.port равен порту КОМНАТЫ, а поле «адрес:порт» подставляло именно
## его: игрок жал «ПО СЕТИ» и сохранял себе смертный порт комнаты как
## постоянный — дальше вечное «Сервер не ответил за 5 с» (в поле у живого
## игрока оказалось :9978, на экране обрезанное до «:99»). Проверяем:
##   1) поле подставляет ДОМАШНИЙ порт (стандартный не пишется вовсе);
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
	var text: String = sel._host_edit.text
	var ok1: bool = not text.contains(":")
	print("поле после редиректа: «%s» %s" % [text, "ok" if ok1 else "FAIL"])

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

	print("SELECTPREFILL TEST: %s" % ("PASS" if ok1 and ok2 else "FAIL"))
	get_tree().quit(0 if ok1 and ok2 else 1)
