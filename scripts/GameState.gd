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
## База → Vector2i(уровень открытия, цена в монетах). 28 платных машин:
## почти по одной на уровень со 2-го по 30-й (ЭКОНОМИКА.md, раздел 4);
## аркадные конструкторы (ac1..ac8) рассыпаны по всей лестнице — тюнинг
## виден с 5-го уровня.
const CAR_UNLOCKS := {
	"vz03": Vector2i(2, 600),
	"vz04": Vector2i(3, 1200),
	"vz05": Vector2i(4, 2000),
	"ac1": Vector2i(5, 3000),
	"vz06": Vector2i(6, 4000),
	"vz07": Vector2i(7, 5500),
	"ac2": Vector2i(8, 7000),
	"vz05r": Vector2i(9, 9000),
	"vz08": Vector2i(10, 11000),
	"ac3": Vector2i(11, 13500),
	"vz09": Vector2i(12, 16000),
	"vz099": Vector2i(13, 19000),
	"ac4": Vector2i(14, 22000),
	"gz21": Vector2i(15, 25000),
	"gz24": Vector2i(16, 29000),
	"ac5": Vector2i(17, 33000),
	"vz31": Vector2i(18, 37000),
	"fastback": Vector2i(19, 41000),
	"ac6": Vector2i(20, 46000),
	"safari": Vector2i(21, 50000),
	"chevelle": Vector2i(22, 55000),
	"ac7": Vector2i(23, 60000),
	"godfather": Vector2i(24, 65000),
	"lemans": Vector2i(25, 70000),
	"ac8": Vector2i(26, 76000),
	"superbird": Vector2i(27, 82000),
	"dragster": Vector2i(28, 88000),
	"diablo": Vector2i(30, 95000),
}

var owned_cars: Array = []   # купленные базы (стартовые тут не хранятся)
var car_colors := {}         # база → выбранный цвет скина

# ---- Улучшения машин: 4 слота × 3 ступени (ЭКОНОМИКА.md, раздел 5) ----
# Каждая машина — четыре слота: мотор (разгон), колёса (сцепление и руль),
# спойлер (потолок скорости), выхлоп (длительность ускорения). В каждом
# слоте три ступени; ступень открывается уровнем игрока и покупается за
# процент от цены машины (у стартовых — от условной FREE_CAR_BASE_PRICE).
# У аркадных конструкторов ступень ещё и ОТКРЫВАЕТ детали на кузов: по
# три варианта на ступень (CarModelLibrary.part_tier); у остальных машин
# ступени — только характеристики.
const UPGRADE_SLOTS: Array[String] = ["engine", "wheel", "spoiler", "exhaust"]
const UPGRADE_STEPS := 3
const UPGRADE_PRICE_PCT: Array[float] = [0.04, 0.06, 0.08]   # ступени I, II, III
const UPGRADE_LEVELS: Array[int] = [2, 6, 12]                # с какого уровня
const FREE_CAR_BASE_PRICE := 1000
## Прибавка одной ступени к характеристике слота (множитель 1 + k·ступень).
const UPGRADE_EFFECT := {
	"engine": 0.04, "wheel": 0.04, "spoiler": 0.02, "exhaust": 0.10,
}

# ---- Косметика аркадных машин (раздел 7а): пакеты на машину ----
# «Наклейки» открывают все 10 наклеек и двойную полосу, «Металлик» —
# металлик-версию всех 36 красок. Сами краски (12 цветов × 3 оттенка)
# бесплатны, как цвета советских машин.
const PACK_STICKERS := "stickers"
const PACK_METALLIC := "metallic"
const PACK_PCT := {PACK_STICKERS: 0.20, PACK_METALLIC: 0.40}
const PACK_MIN := {PACK_STICKERS: 300, PACK_METALLIC: 600}

var car_upgrades := {}   # база → {слот: ступень 0..3}
var car_tuning := {}     # аркадная база → комплектация (ключи ARCADE_DEFAULT)
var car_packs := {}      # база → {пакет: true}

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

# ---- Разовый подарок 1 000 000 монет (2026-09-02, себе и второму игроку) ----
const GIFT_1M_AMOUNT := 1_000_000
var _gift_1m_claimed := false


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
		var ups: Variant = cf.get_value("profile", "car_upgrades", {})
		if ups is Dictionary:
			car_upgrades = ups
		var tun: Variant = cf.get_value("profile", "car_tuning", {})
		if tun is Dictionary:
			car_tuning = tun
		var packs: Variant = cf.get_value("profile", "car_packs", {})
		if packs is Dictionary:
			car_packs = packs
		sel = str(cf.get_value("profile", "selected_car", ""))
		_gift_1m_claimed = bool(cf.get_value("profile", "gift_1m_claimed", false))
	# Восстановить выбор машины; пропавшая/некупленная база → стартовая.
	if not CarModelLibrary.CAR_IDS.has(sel) or not car_owned(sel):
		sel = FREE_CARS[0]
	selected_car_id = full_id(sel)
	if not _gift_1m_claimed:
		_gift_1m_claimed = true
		money += GIFT_1M_AMOUNT
		_save_profile()


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
	_save_profile()


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
	_save_profile()


## Запомнить выбранный режим игры (гонка/футбол).
func set_game_mode(m: String) -> void:
	game_mode = m
	_save_profile()


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
	_save_profile()
	return true


## Выбранный цвет скина машины (не выбирался — цвет по умолчанию).
## У аркадных цвет живёт в комплектации (car_tuning).
func color_of(base: String) -> String:
	if CarModelLibrary.is_arcade(base):
		return str(tuning_of(base)["color"])
	return str(car_colors.get(base, CarModelLibrary.default_color(base)))


## Запомнить цвет скина; если эта машина сейчас выбрана — перекрасить
## и выбор. Переживает перезапуск игры.
func set_car_color(base: String, color: String) -> void:
	if CarModelLibrary.is_arcade(base):
		set_tuning(base, "color", color)
		return
	car_colors[base] = color
	_refresh_selected(base)
	_save_profile()


## Полный id скина машины с её текущим цветом / комплектацией.
func full_id(base: String) -> String:
	if CarModelLibrary.is_arcade(base):
		return CarModelLibrary.arcade_id(base, tuning_of(base))
	return CarModelLibrary.skin_id(base, color_of(base))


## Выбрать машину (база): selected_car_id собирается с её текущим цветом
## и комплектацией. Переживает перезапуск игры.
func select_car(base: String) -> void:
	selected_car_id = full_id(base)
	_save_profile()


## Если base сейчас выбрана — пересобрать selected_car_id (цвет/детали).
func _refresh_selected(base: String) -> void:
	if CarModelLibrary.base_id(selected_car_id) == base:
		selected_car_id = full_id(base)


# ---- Улучшения: ступени слотов ----

## Цена, от которой считаются улучшения и пакеты: цена машины, у
## стартовых — условная FREE_CAR_BASE_PRICE.
func price_base(base: String) -> int:
	return car_price(base) if CAR_UNLOCKS.has(base) else FREE_CAR_BASE_PRICE


## Купленная ступень слота (0..UPGRADE_STEPS).
func upgrade_level(base: String, slot: String) -> int:
	var ups: Dictionary = car_upgrades.get(base, {})
	return clampi(int(ups.get(slot, 0)), 0, UPGRADE_STEPS)


## Цена СЛЕДУЮЩЕЙ ступени слота (0 — всё куплено). Округлена до десятков.
func upgrade_price(base: String, slot: String) -> int:
	var lv := upgrade_level(base, slot)
	if lv >= UPGRADE_STEPS:
		return 0
	return maxi(10, int(round(price_base(base) * UPGRADE_PRICE_PCT[lv] / 10.0)) * 10)


## Уровень игрока, нужный для следующей ступени слота.
func upgrade_unlock_level(base: String, slot: String) -> int:
	var lv := upgrade_level(base, slot)
	return UPGRADE_LEVELS[mini(lv, UPGRADE_STEPS - 1)]


## Купить следующую ступень слота: нужна своя машина, уровень и монеты.
func try_buy_upgrade(base: String, slot: String) -> bool:
	if not car_owned(base) or not UPGRADE_SLOTS.has(slot):
		return false
	var lv := upgrade_level(base, slot)
	if lv >= UPGRADE_STEPS or level_info().x < upgrade_unlock_level(base, slot):
		return false
	if not try_spend(upgrade_price(base, slot)):
		return false
	if not car_upgrades.has(base):
		car_upgrades[base] = {}
	car_upgrades[base][slot] = lv + 1
	_save_profile()
	return true


## Множители характеристик по купленным ступеням (Car.apply_upgrades):
## accel — мотор, grip — колёса, speed — спойлер, boost — выхлоп.
func upgrade_multipliers(base: String) -> Dictionary:
	return {
		"accel": 1.0 + UPGRADE_EFFECT["engine"] * upgrade_level(base, "engine"),
		"grip": 1.0 + UPGRADE_EFFECT["wheel"] * upgrade_level(base, "wheel"),
		"speed": 1.0 + UPGRADE_EFFECT["spoiler"] * upgrade_level(base, "spoiler"),
		"boost": 1.0 + UPGRADE_EFFECT["exhaust"] * upgrade_level(base, "exhaust"),
	}


# ---- Косметика: пакеты и комплектация аркадных машин ----

func pack_owned(base: String, pack: String) -> bool:
	var packs: Dictionary = car_packs.get(base, {})
	return bool(packs.get(pack, false))


func pack_price(base: String, pack: String) -> int:
	var raw := price_base(base) * float(PACK_PCT.get(pack, 0.0))
	return maxi(int(PACK_MIN.get(pack, 0)), int(round(raw / 10.0)) * 10)


## Купить пакет косметики (наклейки / металлик) на свою машину.
func try_buy_pack(base: String, pack: String) -> bool:
	if not car_owned(base) or not PACK_PCT.has(pack) or pack_owned(base, pack):
		return false
	if not try_spend(pack_price(base, pack)):
		return false
	if not car_packs.has(base):
		car_packs[base] = {}
	car_packs[base][pack] = true
	_save_profile()
	return true


## Комплектация аркадной машины (копия; пропущенное — сток, цвет — по
## умолчанию для этой базы).
func tuning_of(base: String) -> Dictionary:
	var cfg: Dictionary = CarModelLibrary.ARCADE_DEFAULT.duplicate()
	cfg["color"] = CarModelLibrary.default_color(base)
	var saved: Dictionary = car_tuning.get(base, {})
	for k in saved:
		cfg[k] = saved[k]
	return cfg


## Можно ли поставить value в ключ key комплектации: деталь — куплена ли
## её ступень, наклейки/полоса — пакет наклеек, металлик — пакет металлика;
## цвет и оттенок свободны.
func tuning_allowed(base: String, key: String, value: Variant) -> bool:
	match key:
		"color": return CarModelLibrary.ARCADE_COLORS.has(str(value))
		"shade": return int(value) >= 1 and int(value) <= 3
		"glitter": return int(value) == 0 or pack_owned(base, PACK_METALLIC)
		"sticker", "line":
			return int(value) == 0 or pack_owned(base, PACK_STICKERS)
		"wheel", "engine", "spoiler", "exhaust":
			return CarModelLibrary.part_tier(key, int(value)) \
					<= upgrade_level(base, key)
	return false


## Поставить деталь/краску/наклейку (проверяет права, см. tuning_allowed);
## если машина выбрана — обновляет и выбор. Переживает перезапуск.
func set_tuning(base: String, key: String, value: Variant) -> bool:
	if not CarModelLibrary.is_arcade(base) or not tuning_allowed(base, key, value):
		return false
	if not car_tuning.has(base):
		car_tuning[base] = {}
	car_tuning[base][key] = value
	_refresh_selected(base)
	_save_profile()
	return true


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


## Сохранить профиль ЦЕЛИКОМ. Раньше каждый сеттер делал «load → одно поле
## → save», и битый profile.cfg (load не OK) перезаписывался одним этим
## полем — опыт, монеты и купленные машины пропадали. Теперь нечитаемый
## файл откладывается в сторону (.broken), а на диск идёт полный набор.
func _save_profile() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(PROFILE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		var abs := ProjectSettings.globalize_path(PROFILE_PATH)
		DirAccess.copy_absolute(abs, abs + ".broken")
		cf = ConfigFile.new()
	cf.set_value("profile", "xp", xp)
	cf.set_value("profile", "money", money)
	cf.set_value("profile", "ads_in_pair", _ads_in_pair)
	cf.set_value("profile", "ad_pair_done_at", _ad_pair_done_at)
	cf.set_value("profile", "player_name", player_name)
	cf.set_value("profile", "race_size", race_size)
	cf.set_value("profile", "game_mode", game_mode)
	cf.set_value("profile", "owned_cars", owned_cars)
	cf.set_value("profile", "car_colors", car_colors)
	cf.set_value("profile", "car_upgrades", car_upgrades)
	cf.set_value("profile", "car_tuning", car_tuning)
	cf.set_value("profile", "car_packs", car_packs)
	cf.set_value("profile", "selected_car",
			CarModelLibrary.base_id(selected_car_id))
	cf.set_value("profile", "gift_1m_claimed", _gift_1m_claimed)
	cf.save(PROFILE_PATH)
