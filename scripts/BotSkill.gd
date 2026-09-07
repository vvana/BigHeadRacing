class_name BotSkill
## Адаптивная сложность ботов (просьба 07.09: «если игрок играет всё время
## с ботами и постоянно побеждает — сделать ботов посильнее, чтобы
## сложность подстраивалась для удержания»).
##
## У каждого имени игрока — УРОВЕНЬ 0..1. Считается только по заездам, где
## человек ехал ОДИН против ботов (оффлайн или сетевой заезд с одним живым
## игроком): выиграл — уровень растёт, серия побед подряд разгоняет рост,
## проиграл — падает. Уровень переводится в «класс» ботов (Car.ai_skill —
## постоянный множитель темпа) и в нижний предел «резинки» (Main: убежавший
## вперёд бот сбрасывает темп; чем выше уровень, тем меньше сбрасывает).
## На уровне 0 всё ровно как было (ai_skill 0.86..0.94, резинка от 0.8),
## на уровне 1 боты едут на 97..105 % темпа игрока и почти не ждут его.
##
## Хранится в user://bot_skill.cfg: у сервера — в его user:// (ключ — имя,
## каким игрок представился в hello), у оффлайн-игры — у игрока. Стенды
## (tools/, --script) пишут в отдельный файл, чтобы не портить счёт игрока.

const PATH_LIVE := "user://bot_skill.cfg"
const PATH_TEST := "user://bot_skill_test.cfg"
static var path: String = _pick_path()

## Диапазон ai_skill при уровне 0 и при уровне 1.
const SKILL_LO_0 := 0.86
const SKILL_HI_0 := 0.94
const SKILL_LO_1 := 0.97
const SKILL_HI_1 := 1.05
## Нижний кламп «резинки» (Main): 0.8 — убежавшего бота легко догнать.
const RUBBER_MIN_0 := 0.8
const RUBBER_MIN_1 := 0.93
## Шаг уровня за заезд: первое место +WIN, последнее −LOSE, между ними
## линейно; серия побед от STREAK_FROM подряд добавляет STREAK_STEP за
## каждую лишнюю победу (не больше STREAK_MAX).
const WIN := 0.15
const LOSE := 0.2
const STREAK_FROM := 3
const STREAK_STEP := 0.05
const STREAK_MAX := 0.15


static func _pick_path() -> String:
	for a in OS.get_cmdline_args():
		var s := str(a).replace("\\", "/")
		if s.contains("tools/") or s == "--script" or s.begins_with("--script="):
			return PATH_TEST
	return PATH_LIVE


static func _load() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(path)
	return cf


static func _key(pname: String) -> String:
	var n := pname.strip_edges()
	return n if n != "" else "Игрок"


## Запись игрока: {level, streak, races, wins}.
static func entry_of(pname: String) -> Dictionary:
	var cf := _load()
	var v: Variant = cf.get_value("players", _key(pname), {})
	if v is Dictionary:
		return v
	return {}


static func level_of(pname: String) -> float:
	return clampf(float(entry_of(pname).get("level", 0.0)), 0.0, 1.0)


## Уровень для заезда с несколькими живыми игроками — среднее по ним.
static func mean_level(names: PackedStringArray) -> float:
	if names.is_empty():
		return 0.0
	var sum := 0.0
	for n in names:
		sum += level_of(n)
	return sum / names.size()


## Заезд окончен: игрок pname занял place из count машин. Возвращает новый
## уровень. Звать ТОЛЬКО за заезды «один против ботов».
static func record(pname: String, place: int, count: int) -> float:
	var e := entry_of(pname)
	var level := clampf(float(e.get("level", 0.0)), 0.0, 1.0)
	var streak := int(e.get("streak", 0))
	var rel := 0.0
	if count > 1:
		rel = clampf(float(place - 1) / float(count - 1), 0.0, 1.0)
	var delta := WIN - (WIN + LOSE) * rel
	if place == 1:
		streak += 1
		if streak >= STREAK_FROM:
			delta += minf(STREAK_STEP * (streak - STREAK_FROM + 1), STREAK_MAX)
	else:
		streak = 0
	level = clampf(level + delta, 0.0, 1.0)
	e["level"] = level
	e["streak"] = streak
	e["races"] = int(e.get("races", 0)) + 1
	e["wins"] = int(e.get("wins", 0)) + (1 if place == 1 else 0)
	var cf := _load()
	cf.set_value("players", _key(pname), e)
	cf.save(path)
	print("[боты] %s: место %d из %d → уровень сложности %.2f (серия побед %d)"
			% [_key(pname), place, count, level, streak])
	return level


## Диапазон ai_skill бота для уровня (x — нижняя граница, y — верхняя).
static func skill_range(level: float) -> Vector2:
	var t := clampf(level, 0.0, 1.0)
	return Vector2(lerpf(SKILL_LO_0, SKILL_LO_1, t),
			lerpf(SKILL_HI_0, SKILL_HI_1, t))


## Нижний кламп «резинки» для уровня.
static func rubber_min(level: float) -> float:
	return lerpf(RUBBER_MIN_0, RUBBER_MIN_1, clampf(level, 0.0, 1.0))


## Стереть запись (стенды).
static func reset(pname: String) -> void:
	var cf := _load()
	if cf.has_section_key("players", _key(pname)):
		cf.erase_section_key("players", _key(pname))
		cf.save(path)
