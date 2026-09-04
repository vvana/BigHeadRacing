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

# ---- Тюнинг машин: 4 слота × 3 ступени (ЭКОНОМИКА.md, раздел 5) ----
# ВАЖНО (03.09): тюнинг — ЧИСТАЯ КОСМЕТИКА, на характеристики машины он
# НЕ влияет. Улучшать характеристики можно будет только оружию и бонусам
# (ЭКОНОМИКА.md, раздел 7) — иначе прокачанный игрок в сетевом заезде
# заведомо быстрее новичка. Детали на кузов (мотор, колёса, спойлер,
# выхлоп) есть только у аркадных конструкторов и с 03.09 (вечер)
# покупаются ПОШТУЧНО (try_buy_item): цена по ярусу детали
# (CarModelLibrary.part_tier: I — №1–3, II — №4–6, III — №7–10), ярус
# открывается уровнем. У остальных машин — только бесплатные цвета.
const UPGRADE_SLOTS: Array[String] = ["engine", "wheel", "spoiler", "exhaust"]
const UPGRADE_STEPS := 3        # ступени старых профилей (перенос, _migrate_items)
const PART_PRICE_PCT: Array[float] = [0.015, 0.02, 0.025]   # ярус I, II, III
const PART_LEVELS: Array[int] = [2, 6, 12]                  # с какого уровня
const STICKER_PRICE_PCT := 0.02   # наклейка или полоса, за штуку
const STICKER_MIN := 30
const METAL_PRICE_PCT := 0.035    # металлик одного цвета (все 3 оттенка)
const METAL_MIN := 50
# Эффекты (04.09, ЛЮБОЙ машине): цветной дым из-под колёс и неон под
# днищем — каждый цвет отдельно («smoke:<цвет>», «neon:<цвет>»).
const SMOKE_PRICE_PCT := 0.03
const SMOKE_MIN := 40
const NEON_PRICE_PCT := 0.04
const NEON_MIN := 60
const FREE_CAR_BASE_PRICE := 1000

# ---- Косметика аркадных машин (раздел 7а) ----
# С 03.09 (вечер) всё поштучно (car_items): детали, наклейки, полоса и
# металлик — каждый ЦВЕТ металлика отдельно («metal:<цвет>», покрывает
# три его оттенка). Пакеты «Наклейки» и «Металлик» больше не продаются
# (PACK_PCT пуст), купленные раньше переносятся в поштучное владение
# (_migrate_items). Обычные краски (12 цветов × 3 оттенка) бесплатны.
const PACK_STICKERS := "stickers"   # только для переноса старых профилей
const PACK_METALLIC := "metallic"   # только для переноса старых профилей
const PACK_PCT := {}
const PACK_MIN := {}

var car_upgrades := {}   # база → {слот: ступень 0..3} — старые профили, перенос
var car_items := {}      # база → {«слот:номер» | «sticker:N» | «line»: true}
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

## Сколько машин в заезде. С 03.09 выбора в гараже нет — ВСЕГДА 8
## (полное поле, как в оригинале); значение и в профиле не хранится,
## чтобы старые профили с четвёркой не остались без возможности сменить
## его. Оффлайн — это игрок + (race_size−1) ботов; по сети желание
## уезжает в hello, и размер заезда решает сервер (Net.race_size): его
## задаёт ПЕРВЫЙ игрок пустого лобби, остальные приезжают в заезд такого
## размера. Диапазон и set_race_size оставлены: ими пользуются стенды
## (tools/test_race_size.gd) и сетевой код.
const RACE_SIZE_MIN := 4
const RACE_SIZE_MAX := 8
var race_size := RACE_SIZE_MAX:
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
## Файл профиля. Стенды и тесты (tools/*, --script, --headless) живут в
## ОТДЕЛЬНОМ user://profile_test.cfg: 04.09 игрок дважды «терял прогресс» —
## запускал игру, пока test_gift/test_shop на секунды подменяли боевой
## profile.cfg тестовым, и игра жила с ним в памяти (см. PROGRESS.md).
static var PROFILE_PATH: String = _pick_profile_path()
const PROFILE_TEST_PATH := "user://profile_test.cfg"
const PLACE_XP := [100, 60, 40, 25]   # опыт за 1..4 место


## Игра, запущенная человеком (play.bat, dist, Яндекс), — без «tools/»,
## «--script» и «--headless» в командной строке; всё остальное — стенд.
static func _pick_profile_path() -> String:
	for a in OS.get_cmdline_args():
		var s := str(a).replace("\\", "/")
		if s.contains("tools/") or s == "--script" or s == "--headless" \
				or s.begins_with("--script="):
			return PROFILE_TEST_PATH
	return "user://profile.cfg"
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
		var items: Variant = cf.get_value("profile", "car_items", {})
		if items is Dictionary:
			car_items = items
		_migrate_items()
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


## Задать число участников заезда (в профиле не хранится — см. race_size).
func set_race_size(n: int) -> void:
	race_size = n


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


## Полный id скина машины с её текущим цветом / комплектацией
## (аркадные и советские — с деталями, прочие — база).
func full_id(base: String) -> String:
	var cfg := tuning_of(base)
	cfg["color"] = color_of(base)
	return CarModelLibrary.tuned_id(base, cfg)


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


# ---- Косметика поштучно: детали кузова, наклейки, полоса (03.09) ----
# Каждый элемент покупается ОТДЕЛЬНО (просьба 03.09: «не несколько за
# раз»). Ключ элемента: «слот:номер» для детали (engine:4, wheel:5),
# «sticker:N» для наклейки, «line» для двойной полосы. Купленное лежит в
# car_items[база][ключ] = true. Металлик остаётся одним элементом-пакетом
# (car_packs), краски бесплатны.

## Разобрать ключ элемента: [вид, слот, номер]; вид — "part" | "sticker"
## | "line" | "metal" (слот — цвет) | "" (ключ не про эту игру).
static func item_parts(key: String) -> Array:
	if key == "line":
		return ["line", "", 0]
	var slot := key.get_slice(":", 0)
	if key.count(":") != 1:
		return ["", "", 0]
	if slot == "metal" or CarModelLibrary.FX_KEYS.has(slot):
		var color := key.get_slice(":", 1)
		return [slot, color, 0] if CarModelLibrary.ARCADE_COLORS.has(color) \
				else ["", "", 0]
	var idx := int(key.get_slice(":", 1))
	if idx <= 0 or idx > CarModelLibrary.PART_COUNT:
		return ["", "", 0]
	if slot == "sticker":
		return ["sticker", "", idx]
	if UPGRADE_SLOTS.has(slot) and CarModelLibrary.part_tier(slot, idx) > 0:
		return ["part", slot, idx]
	return ["", "", 0]


func item_owned(base: String, key: String) -> bool:
	var items: Dictionary = car_items.get(base, {})
	return bool(items.get(key, false))


## Цена элемента: деталь — процент от цены машины по ярусу (I/II/III —
## PART_PRICE_PCT), наклейка и полоса — STICKER_PRICE_PCT. Округление до
## десятков; 0 — ключ не продаётся (сток).
func item_price(base: String, key: String) -> int:
	var p := item_parts(key)
	match String(p[0]):
		"part":
			var tier: int = CarModelLibrary.part_tier(p[1], p[2])
			return maxi(10, int(round(price_base(base)
					* PART_PRICE_PCT[tier - 1] / 10.0)) * 10)
		"sticker", "line":
			return maxi(STICKER_MIN, int(round(price_base(base)
					* STICKER_PRICE_PCT / 10.0)) * 10)
		"metal":
			return maxi(METAL_MIN, int(round(price_base(base)
					* METAL_PRICE_PCT / 10.0)) * 10)
		"smoke":
			return maxi(SMOKE_MIN, int(round(price_base(base)
					* SMOKE_PRICE_PCT / 10.0)) * 10)
		"neon":
			return maxi(NEON_MIN, int(round(price_base(base)
					* NEON_PRICE_PCT / 10.0)) * 10)
	return 0


## Уровень игрока, с которого элемент продаётся: детали — по ярусу
## (PART_LEVELS), наклейки и полоса — с первого.
func item_unlock_level(base: String, key: String) -> int:
	var p := item_parts(key)
	if String(p[0]) == "part":
		return PART_LEVELS[CarModelLibrary.part_tier(p[1], p[2]) - 1]
	return 1


## Купить элемент: своя машина; дым и неон («smoke:<цвет>»,
## «neon:<цвет>») — любой машине; детали — только со слотами (аркадная
## или советская — CarModelLibrary.has_parts; у советских деталь должна
## быть из её набора slot_options), наклейки/полоса/металлик — только у
## аркадных; уровень, монеты, ещё не куплен. Порядок свободный — ярус II
## можно брать без яруса I.
func try_buy_item(base: String, key: String) -> bool:
	if not car_owned(base):
		return false
	var p := item_parts(key)
	var kind := String(p[0])
	if kind == "" or item_owned(base, key):
		return false
	if CarModelLibrary.FX_KEYS.has(kind):
		pass   # эффекты продаются всем машинам
	elif not CarModelLibrary.has_parts(base):
		return false
	elif kind == "part":
		if not CarModelLibrary.slot_options(base, p[1]).has(int(p[2])):
			return false
	elif not CarModelLibrary.is_arcade(base):
		return false
	if level_info().x < item_unlock_level(base, key):
		return false
	if not try_spend(item_price(base, key)):
		return false
	if not car_items.has(base):
		car_items[base] = {}
	car_items[base][key] = true
	_save_profile()
	return true


## Сколько элементов слота/наклеек куплено (для подписей панели).
func items_owned_count(base: String, prefix: String) -> int:
	var n := 0
	for key in car_items.get(base, {}):
		if String(key).begins_with(prefix):
			n += 1
	return n


## Перенос профилей до 03.09: ступень слота N открывала детали ярусов
## 1..N, пакет «Наклейки» — все наклейки и полосу. Переводим в поштучное
## владение, чтобы купленное не пропало; старые ключи в профиле остаются
## (перенос повторяется при каждом запуске — он идемпотентен).
func _migrate_items() -> void:
	for base in car_upgrades:
		var ups: Variant = car_upgrades[base]
		if not ups is Dictionary:
			continue
		for slot in ups:
			var lv := clampi(int(ups[slot]), 0, UPGRADE_STEPS)
			for idx in range(1, CarModelLibrary.PART_COUNT + 1):
				var tier := CarModelLibrary.part_tier(str(slot), idx)
				if tier >= 1 and tier <= lv:
					_grant_item(base, "%s:%d" % [slot, idx])
	for base in car_packs:
		if pack_owned(base, PACK_STICKERS):
			for idx in range(1, CarModelLibrary.PART_COUNT + 1):
				_grant_item(base, "sticker:%d" % idx)
			_grant_item(base, "line")
		if pack_owned(base, PACK_METALLIC):
			for color in CarModelLibrary.ARCADE_COLORS:
				_grant_item(base, "metal:%s" % color)


func _grant_item(base: String, key: String) -> void:
	if not car_items.has(base):
		car_items[base] = {}
	car_items[base][key] = true


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


## Комплектация машины (копия; пропущенное — сток: у аркадных колёса №1,
## у советских родные; цвет — по умолчанию для этой базы).
func tuning_of(base: String) -> Dictionary:
	var cfg: Dictionary = CarModelLibrary.default_cfg(base)
	var saved: Dictionary = car_tuning.get(base, {})
	for k in saved:
		cfg[k] = saved[k]
	# Профили дня 03.09: один цвет на все детали (pcolor) и цвет полосы
	# (lcolor) → цвета по деталям (color_<слот>), если те не заданы.
	if saved.has("pcolor"):
		for slot in CarModelLibrary.PART_SLOTS:
			var key: String = CarModelLibrary.COLOR_KEYS[slot]
			if not saved.has(key):
				cfg[key] = saved["pcolor"]
		cfg.erase("pcolor")
	if saved.has("lcolor"):
		if not saved.has("color_line"):
			cfg["color_line"] = saved["lcolor"]
		cfg.erase("lcolor")
	return cfg


## Можно ли поставить value в ключ key комплектации: деталь, наклейка и
## полоса — куплен ли именно этот элемент (сток и «ничего» свободны;
## у советских деталь ещё и из набора машины), металлик — куплен ли
## металлик ТЕКУЩЕГО цвета; цвет, оттенок, цвет деталей (pcolor) и
## полосы (lcolor) свободны.
func tuning_allowed(base: String, key: String, value: Variant) -> bool:
	match key:
		"color": return CarModelLibrary.ARCADE_COLORS.has(str(value))
		"color_wheel", "color_engine", "color_spoiler", "color_exhaust", "color_line":
			return str(value).is_empty() or CarModelLibrary.is_paint_spec(str(value))
		"shade": return int(value) >= 1 and int(value) <= 3
		"glitter":
			return int(value) == 0 \
					or item_owned(base, "metal:%s" % str(tuning_of(base)["color"]))
		"sticker":
			return int(value) == 0 or item_owned(base, "sticker:%d" % int(value))
		"line":
			return int(value) == 0 or item_owned(base, "line")
		"smoke", "neon":
			return str(value).is_empty() or item_owned(base, "%s:%s" % [key, str(value)])
		"wheel", "engine", "spoiler", "exhaust":
			if not CarModelLibrary.slot_options(base, key).has(int(value)):
				return false
			return CarModelLibrary.part_tier(key, int(value)) == 0 \
					or item_owned(base, "%s:%d" % [key, int(value)])
	return false


## Поставить деталь/краску/наклейку/эффект (проверяет права, см.
## tuning_allowed; дым и неон — любой машине, остальное — со слотами);
## если машина выбрана — обновляет и выбор. Переживает перезапуск.
func set_tuning(base: String, key: String, value: Variant) -> bool:
	if not CarModelLibrary.has_parts(base) and not CarModelLibrary.FX_KEYS.has(key):
		return false
	if not tuning_allowed(base, key, value):
		return false
	if not car_tuning.has(base):
		car_tuning[base] = {}
	car_tuning[base][key] = value
	# Перекрасили в цвет, чей металлик не куплен, — металлик гаснет.
	if key == "color" and int(tuning_of(base)["glitter"]) == 1 \
			and not item_owned(base, "metal:%s" % str(value)):
		car_tuning[base]["glitter"] = 0
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


## Сколько роликов текущей пары уже досмотрено (0 — пара целая). Кнопке
## в гараже: «+500 за рекламу» против «ещё ролик · +500».
func ad_pair_progress() -> int:
	ad_cooldown_left()   # вышел кулдаун — сам обнуляет счётчик пары
	return _ads_in_pair


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
	cf.set_value("profile", "game_mode", game_mode)
	cf.set_value("profile", "owned_cars", owned_cars)
	cf.set_value("profile", "car_colors", car_colors)
	cf.set_value("profile", "car_upgrades", car_upgrades)
	cf.set_value("profile", "car_items", car_items)
	cf.set_value("profile", "car_tuning", car_tuning)
	cf.set_value("profile", "car_packs", car_packs)
	cf.set_value("profile", "selected_car",
			CarModelLibrary.base_id(selected_car_id))
	cf.set_value("profile", "gift_1m_claimed", _gift_1m_claimed)
	cf.save(PROFILE_PATH)
