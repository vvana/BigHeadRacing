extends Node
## Глобальное состояние игры (autoload GameState):
## всё, что должно пережить смену сцены.

## Машина, выбранная на экране выбора: ПОЛНЫЙ id скина («база_цвет» для
## советского пака, просто база для машин без скинов) — он же уезжает в
## сетевой hello и определяет визуал у соперников. Выбор и цвета хранятся
## в профиле (select_car/set_car_color).
var selected_car_id := "vz01_red"

# ---- Парк машин: стартовые, открытие за уровни, покупка за монеты ----
# Стартовые три доступны сразу со всеми цветами; остальные открываются
# уровнем (виден замок с ценой) и покупаются за монеты — сетка уровней и
# цен из ЭКОНОМИКА.md (разделы 3–4). Скины-цвета бесплатны у купленной
# машины. Куплённое — в профиле (owned_cars), цвета — там же (car_colors).
const FREE_CARS: Array[String] = ["vz01", "vz02", "vz21"]
## База → Vector2i(уровень открытия, цена в монетах).
const CAR_UNLOCKS := {
	"vz03": Vector2i(2, 600),
	"vz04": Vector2i(3, 1200),
	"vz05": Vector2i(4, 2000),
	"vz06": Vector2i(5, 3000),
	"vz07": Vector2i(6, 4500),
	"vz05r": Vector2i(7, 6500),
	"vz08": Vector2i(8, 9000),
	"vz09": Vector2i(9, 12000),
	"vz099": Vector2i(10, 15000),
	"gz21": Vector2i(12, 19000),
	"gz24": Vector2i(14, 24000),
	"vz31": Vector2i(16, 29000),
	"fastback": Vector2i(18, 35000),
	"safari": Vector2i(20, 42000),
	"chevelle": Vector2i(21, 46000),
	"godfather": Vector2i(22, 50000),
	"lemans": Vector2i(24, 59000),
	"superbird": Vector2i(26, 69000),
	"dragster": Vector2i(28, 80000),
	"diablo": Vector2i(30, 92000),
}

var owned_cars: Array = []   # купленные базы (стартовые тут не хранятся)
var car_colors := {}         # база → выбранный цвет скина

## Вид трассы ближайшего заезда (TrackBuilder.KINDS). Оффлайн выбирается
## случайно при старте из гаража; по сети сюда пишет _rx_track (вид диктует
## сервер). Пусто — классика: тесты, грузящие Main напрямую, ничего не
## выбирают, и регрессия остаётся детерминированной.
var track_kind := ""

## Кэш миниатюр машин для сетки выбора (ID → Texture2D).
## Генерируются один раз за запуск игры.
var car_thumbs := {}

## Сколько машин в заезде хочет игрок (выбор в гараже, 4..8). Оффлайн —
## это игрок + (race_size−1) ботов; по сети желание уезжает в hello, и
## размер заезда решает сервер (Net.race_size): его задаёт ПЕРВЫЙ игрок
## пустого лобби, остальные приезжают в заезд такого размера.
const RACE_SIZE_MIN := 4
const RACE_SIZE_MAX := 8
var race_size := 4:
	set(v):
		race_size = clampi(v, RACE_SIZE_MIN, RACE_SIZE_MAX)

## Режим игры, выбирается в гараже: гонка или футбол (4 на 4, мяч в ворота).
## Футбол пока ТОЛЬКО оффлайн (игрок + 7 ботов) — сетевой потребует нового
## протокола. Хранится в профиле.
const MODE_RACE := "race"
const MODE_SOCCER := "soccer"
var game_mode := MODE_RACE:
	set(v):
		game_mode = v if v in [MODE_RACE, MODE_SOCCER] else MODE_RACE

# ---- Имя игрока ----
# Под ним игрока видят соперники (лобби, лента событий, анонсы). Пустое —
# имя ещё не спрашивали: гараж (CarSelect) при первом запуске показывает
# окно ввода и сохраняет ответ в профиль. В сборке для Яндекс Игр имя
# берётся из их SDK (см. platform_name) и окно не показывается вовсе.
const NAME_MAX := 16
var player_name := ""

# ---- Профиль игрока: опыт (переживает перезапуск игры) ----
# Опыт даётся на финише заезда: за место + за уничтоженных соперников
# (Main._show_finish). Уровни открывают машины, оружие и ступени улучшений
# для ПОКУПКИ за монеты — вся сетка разблокировок и цен в ЭКОНОМИКА.md.
const PROFILE_PATH := "user://profile.cfg"
const PLACE_XP := [100, 60, 40, 25]   # опыт за 1..4 место
const KILL_XP := 10                    # + за каждого уничтоженного соперника

var xp := 0

# ---- Кошелёк: монеты (внутриигровая валюта) ----
# Зарабатываются на финише (место + уничтоженные), бонусом за новый уровень
# и за просмотр рекламы (парами роликов). Тратятся в будущем магазине:
# машины, улучшения машин и оружия — цены посчитаны в ЭКОНОМИКА.md.
const PLACE_MONEY := [600, 450, 350, 250]   # монеты за 1..4 место (хуже — как 4-е)
const KILL_MONEY := 25                      # + за каждого уничтоженного
const LEVEL_MONEY := 200        # бонус за взятый уровень: 200 × номер уровня

var money := 0

# ---- Реклама с вознаграждением ----
# Пара роликов раз в 10 минут: досмотрел 2 подряд — получил AD_PAIR_REWARD
# монет, дальше кулдаун AD_COOLDOWN, и пара доступна снова. Сами ролики
# показывает платформа (Яндекс Игры: ysdk.adv.showRewardedVideo), здесь
# только учёт и награда: UI спрашивает ad_available()/ad_cooldown_left()
# и после onRewarded зовёт register_ad().
const AD_PAIR_SIZE := 2
const AD_PAIR_REWARD := 500     # монет за досмотренную пару роликов
const AD_COOLDOWN := 600.0      # секунд отдыха после пары (10 минут)

var _ads_in_pair := 0           # роликов текущей пары уже досмотрено
var _ad_pair_done_at := 0.0     # unix-время завершения последней пары


func _ready() -> void:
	var sel := ""
	var cf := ConfigFile.new()
	if cf.load(PROFILE_PATH) == OK:
		xp = int(cf.get_value("profile", "xp", 0))
		money = int(cf.get_value("profile", "money", 0))
		_ads_in_pair = int(cf.get_value("profile", "ads_in_pair", 0))
		_ad_pair_done_at = float(cf.get_value("profile",
				"ad_pair_done_at", 0.0))
		race_size = int(cf.get_value("profile", "race_size", 4))
		game_mode = str(cf.get_value("profile", "game_mode", MODE_RACE))
		player_name = sanitize_name(str(cf.get_value("profile",
				"player_name", "")))
		owned_cars = Array(cf.get_value("profile", "owned_cars", []))
		var colors: Variant = cf.get_value("profile", "car_colors", {})
		if colors is Dictionary:
			car_colors = colors
		sel = str(cf.get_value("profile", "selected_car", ""))
	# Восстановить выбор машины; пропавшая/некупленная база → стартовая.
	if not CarModelLibrary.CAR_IDS.has(sel) or not car_owned(sel):
		sel = FREE_CARS[0]
	selected_car_id = CarModelLibrary.skin_id(sel, color_of(sel))


## Общая чистка имени: пробелы по краям и повторные внутри, длина NAME_MAX.
## Ей же сервер чистит имена, присланные клиентами (Main._set_slot_name).
static func sanitize_name(n: String) -> String:
	n = n.strip_edges()
	while n.contains("  "):
		n = n.replace("  ", " ")
	return n.left(NAME_MAX)


## Запомнить имя игрока (переживает перезапуск игры).
func set_player_name(n: String) -> void:
	player_name = sanitize_name(n)
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)   # не затирать другие поля профиля
	cf.set_value("profile", "player_name", player_name)
	cf.save(PROFILE_PATH)


## Имя для показа: пока не введено — просто «Игрок».
func display_name() -> String:
	return player_name if player_name != "" else "Игрок"


## Имя с платформы (Яндекс Игры). Работает только в web-сборке: страница
## после инициализации Yandex SDK должна положить имя авторизованного
## игрока в window.bhrPlayerName:
##   ysdk.getPlayer().then(p => { window.bhrPlayerName = p.getName(); });
## Пустая строка — платформа имени не дала (не web-сборка, игрок-аноним,
## SDK ещё грузится) — тогда гараж спросит имя сам.
func platform_name() -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("window.bhrPlayerName || ''", true)
	return sanitize_name(str(v)) if v != null else ""


## Запомнить выбранное число участников (переживает перезапуск игры).
func set_race_size(n: int) -> void:
	race_size = n
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)   # не затирать другие поля профиля
	cf.set_value("profile", "race_size", race_size)
	cf.save(PROFILE_PATH)


## Запомнить выбранный режим игры (гонка/футбол).
func set_game_mode(m: String) -> void:
	game_mode = m
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)   # не затирать другие поля профиля
	cf.set_value("profile", "game_mode", game_mode)
	cf.save(PROFILE_PATH)


## Начислить опыт и сразу сохранить профиль на диск. Каждый взятый уровень
## приносит бонус монет LEVEL_MONEY × номер нового уровня (2-й — 400,
## 10-й — 2000…): уровень должен ОЩУЩАТЬСЯ наградой, а не только цифрой.
func add_xp(amount: int) -> void:
	var before: int = level_info().x
	xp += maxi(0, amount)
	var after: int = level_info().x
	for lv in range(before + 1, after + 1):
		money += LEVEL_MONEY * lv
	_save_profile()


## Начислить монеты и сразу сохранить профиль.
func add_money(amount: int) -> void:
	money += maxi(0, amount)
	_save_profile()


## Списать монеты (покупка). Не хватает — false и ничего не меняется.
func try_spend(amount: int) -> bool:
	if amount < 0 or money < amount:
		return false
	money -= amount
	_save_profile()
	return true


# ---- Парк машин: владение, покупка, скины ----

## Машина куплена или стартовая.
func car_owned(base: String) -> bool:
	return FREE_CARS.has(base) or owned_cars.has(base)


## Уровень открытия базы (стартовые — 1).
func car_unlock_level(base: String) -> int:
	return (CAR_UNLOCKS[base] as Vector2i).x if CAR_UNLOCKS.has(base) else 1


## Цена базы в монетах (стартовые — 0).
func car_price(base: String) -> int:
	return (CAR_UNLOCKS[base] as Vector2i).y if CAR_UNLOCKS.has(base) else 0


## Купить машину: нужен уровень открытия и монеты. false — не вышло
## (уже куплена / уровень мал / монет не хватает).
func try_buy_car(base: String) -> bool:
	if car_owned(base) or not CAR_UNLOCKS.has(base):
		return false
	if level_info().x < car_unlock_level(base):
		return false
	if not try_spend(car_price(base)):
		return false
	owned_cars.append(base)
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)   # не затирать другие поля профиля
	cf.set_value("profile", "owned_cars", owned_cars)
	cf.save(PROFILE_PATH)
	return true


## Выбранный цвет скина машины (не выбирался — цвет по умолчанию).
func color_of(base: String) -> String:
	return str(car_colors.get(base, CarModelLibrary.default_color(base)))


## Запомнить цвет скина; если эта машина сейчас выбрана — перекрасить
## и выбор. Переживает перезапуск игры.
func set_car_color(base: String, color: String) -> void:
	car_colors[base] = color
	if CarModelLibrary.base_id(selected_car_id) == base:
		selected_car_id = CarModelLibrary.skin_id(base, color)
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)   # не затирать другие поля профиля
	cf.set_value("profile", "car_colors", car_colors)
	cf.set_value("profile", "selected_car",
			CarModelLibrary.base_id(selected_car_id))
	cf.save(PROFILE_PATH)


## Выбрать машину (база): selected_car_id собирается с её текущим цветом.
## Переживает перезапуск игры.
func select_car(base: String) -> void:
	selected_car_id = CarModelLibrary.skin_id(base, color_of(base))
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)   # не затирать другие поля профиля
	cf.set_value("profile", "selected_car", base)
	cf.save(PROFILE_PATH)


## Опыт за место в заезде (place с единицы; хуже 4-го — как за 4-е).
func place_xp(place: int) -> int:
	return PLACE_XP[clampi(place, 1, PLACE_XP.size()) - 1]


## Монеты за место в заезде (place с единицы; хуже 4-го — как за 4-е).
func place_money(place: int) -> int:
	return PLACE_MONEY[clampi(place, 1, PLACE_MONEY.size()) - 1]


## Уровень из опыта: на следующий уровень нужно 40·N + 60 (N — текущий).
## 1→2: 100 (один хороший заезд), 5→6: 260, 10→11: 460, 29→30: 1220;
## суммарно до 30-го ~19 000 опыта — ~320 заездов, ~27 часов. Кривая,
## разблокировки по уровням и цены — в ЭКОНОМИКА.md.
## Возвращает [уровень, опыт внутри уровня, цена следующего уровня].
func level_info() -> Vector3i:
	var lv := 1
	var left := xp
	while left >= lv * 40 + 60:
		left -= lv * 40 + 60
		lv += 1
	return Vector3i(lv, left, lv * 40 + 60)


# ---- Реклама с вознаграждением (учёт пар и кулдауна) ----

## Доступен ли сейчас ролик (пара не исчерпана или кулдаун вышел).
func ad_available() -> bool:
	return ad_cooldown_left() <= 0.0


## Сколько секунд ждать до следующей пары роликов (0 — можно смотреть).
func ad_cooldown_left() -> float:
	if _ads_in_pair < AD_PAIR_SIZE:
		return 0.0
	var passed := Time.get_unix_time_from_system() - _ad_pair_done_at
	if passed >= AD_COOLDOWN:
		_ads_in_pair = 0   # кулдаун вышел — пара снова целая
		return 0.0
	return AD_COOLDOWN - passed


## Ролик ДОСМОТРЕН (звать после onRewarded платформы). Возвращает
## начисленные монеты: 0 за первый ролик пары, AD_PAIR_REWARD за второй
## (награда даётся именно за пару). Вне окна доступности — 0 и без учёта.
func register_ad() -> int:
	if not ad_available():
		return 0
	_ads_in_pair += 1
	if _ads_in_pair < AD_PAIR_SIZE:
		_save_profile()
		return 0
	_ad_pair_done_at = Time.get_unix_time_from_system()
	money += AD_PAIR_REWARD
	_save_profile()
	return AD_PAIR_REWARD


## Сохранить копящиеся поля профиля (опыт, кошелёк, реклама), не затирая
## остальные (имя, размер заезда, режим — у них свои сеттеры).
func _save_profile() -> void:
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)
	cf.set_value("profile", "xp", xp)
	cf.set_value("profile", "money", money)
	cf.set_value("profile", "ads_in_pair", _ads_in_pair)
	cf.set_value("profile", "ad_pair_done_at", _ad_pair_done_at)
	cf.save(PROFILE_PATH)
