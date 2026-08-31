extends Node
## Глобальное состояние игры (autoload GameState):
## всё, что должно пережить смену сцены.

## Машина, выбранная на экране выбора (ID из CarModelLibrary.CAR_IDS).
var selected_car_id := "sharky"

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

# ---- Профиль игрока: опыт (переживает перезапуск игры) ----
# Опыт даётся на финише заезда: за место + за уничтоженных соперников
# (Main._show_finish). За уровни дальше будем открывать «разные штуки»:
# машины, трассы, оружие — см. план в PROGRESS.md.
const PROFILE_PATH := "user://profile.cfg"
const PLACE_XP := [100, 60, 40, 25]   # опыт за 1..4 место
const KILL_XP := 10                    # + за каждого уничтоженного соперника

var xp := 0


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PROFILE_PATH) == OK:
		xp = int(cf.get_value("profile", "xp", 0))
		race_size = int(cf.get_value("profile", "race_size", 4))


## Запомнить выбранное число участников (переживает перезапуск игры).
func set_race_size(n: int) -> void:
	race_size = n
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)   # не затирать другие поля профиля
	cf.set_value("profile", "race_size", race_size)
	cf.save(PROFILE_PATH)


## Начислить опыт и сразу сохранить профиль на диск.
func add_xp(amount: int) -> void:
	xp += maxi(0, amount)
	var cf := ConfigFile.new()
	cf.load(PROFILE_PATH)   # не затирать будущие поля профиля
	cf.set_value("profile", "xp", xp)
	cf.save(PROFILE_PATH)


## Опыт за место в заезде (place с единицы; хуже 4-го — как за 4-е).
func place_xp(place: int) -> int:
	return PLACE_XP[clampi(place, 1, PLACE_XP.size()) - 1]


## Уровень из опыта: на следующий уровень нужно 100·N (N — текущий).
## 1→2: 100, 2→3: 200, 3→4: 300… (до 5-го уровня — 1000 суммарно).
## Возвращает [уровень, опыт внутри уровня, цена следующего уровня].
func level_info() -> Vector3i:
	var lv := 1
	var left := xp
	while left >= lv * 100:
		left -= lv * 100
		lv += 1
	return Vector3i(lv, left, lv * 100)
