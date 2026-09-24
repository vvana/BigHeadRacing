extends Node
## Реклама платформы: Android (22.09) и Яндекс Игры (23.09) за одним фасадом.
##
## Android — Yandex Mobile Ads через плагин GodotAndroidYandexAds (addons/,
## Java-синглтон «GodotAndroidYandexAds», SDK com.yandex.android:mobileads:
## 7.18.7, подтягивается gradle-сборкой). Ролик подгружается заранее
## (preload_all при старте и после каждого показа); показ по нажатию ждёт
## загрузку до SHOW_TIMEOUT.
## Web (Яндекс Игры) — SDK площадки window.ysdk (tools/yandex/shell.html):
## ролик ysdk.adv.showRewardedVideo. JavaScriptBridge не умеет ждать
## промис — обратные вызовы SDK складывают состояние в window.bhrAd, а
## _process опрашивает его раз в WEB_POLL. Предзагрузки у SDK Яндекс Игр
## нет: rewarded_ready() там всегда true, а не показавшийся ролик — как
## недосмотренный с last_error.
## На столе платформы нет — available() = false, и ролики показывает
## заглушка RewardedAd._simulate.
##
## Единственный формат — ролик с вознаграждением (решение игрока 23.09:
## межстраничной рекламы в игре нет, только ролики по желанию игрока):
##  - «▶ ×2» на плите финиша — опыт и монеты заезда ещё раз
##    (Main._on_ad_x2_done);
##  - «+500 за пару» в гараже раз в 10 минут (GameState.register_ad).
## Оба — через RewardedAd.play → show_rewarded. Блок Android REWARDED_ID —
## из кабинета Яндекс Рекламы 22.09.2026; тестовые Android-сборки
## (Net.is_test_build) крутят демо-блок demo-rewarded-yandex — всегда есть
## заполнение, деньги не считаются.

const REWARDED_ID := "R-M-20093870-2"
const DEMO_REWARDED_ID := "demo-rewarded-yandex"
const SHOW_TIMEOUT := 12.0          # с ждать загрузку ролика по нажатию (Android)
const RETRY_GAP := 30.0             # с до повторной попытки загрузки после отказа
const WEB_POLL := 0.5               # с между опросами window.bhrAd

## Web: ролик с вознаграждением. rewarded ставит onRewarded (досмотрен),
## state уходит из 'showing' по onClose / onError.
const JS_REWARDED := """
window.bhrAd = {state: 'showing', rewarded: false};
try {
	window.ysdk.adv.showRewardedVideo({callbacks: {
		onRewarded: function() { window.bhrAd.rewarded = true; },
		onClose: function() { window.bhrAd.state = 'closed'; },
		onError: function(e) { console.error('[yandex] rewarded:', e); window.bhrAd.state = 'error'; }
	}});
} catch (e) { window.bhrAd.state = 'error'; }
"""
const JS_POLL := "JSON.stringify(window.bhrAd || {state: 'error'})"

## Готовность ролика с вознаграждением изменилась (загрузился / показан /
## не загрузился) — плита финиша по нему показывает или прячет «▶ ×2».
signal rewarded_ready_changed(ready: bool)

var last_error := ""                # почему последний показ не состоялся ("" — всё ок)

var _sdk: Object = null             # Android: Java-синглтон плагина
var _web := false                   # Яндекс Игры: реклама через window.ysdk
var _rewarded_loaded := false
var _rewarded_loading := false
var _rewarded_retry_at := 0.0
var _reward_got := false            # onRewarded пришёл в текущем показе
var _show_cb: Callable              # ждущий показ ролика: cb(rewarded)
var _wait_t := 0.0                  # Android: ожидание загрузки для показа
var _poll_t := 0.0                  # web: до следующего опроса window.bhrAd


func _ready() -> void:
	if OS.has_feature("web"):
		# Яндекс Игры: показ по требованию через ysdk, грузить заранее нечего.
		_web = true
		print("[ads] Yandex Games: rewarded через ysdk.adv")
		return
	if not Engine.has_singleton("GodotAndroidYandexAds"):
		return
	_sdk = Engine.get_singleton("GodotAndroidYandexAds")
	_sdk._on_rewarded_video_ad_loaded.connect(_on_rewarded_loaded)
	_sdk._on_rewarded_video_ad_failed_to_load.connect(_on_rewarded_failed_to_load)
	_sdk._on_rewarded_video_ad_failed_to_show.connect(_on_rewarded_failed_to_show)
	_sdk._on_rewarded.connect(_on_rewarded_with_args)
	_sdk._on_rewarded_video_ad_dismissed.connect(_on_rewarded_dismissed)
	_sdk.init("")   # без AppMetrica — только MobileAds.initialize
	print("[ads] Yandex Mobile Ads: rewarded=%s" % _rewarded_id())
	preload_all()


## Есть ли настоящая реклама (Android с плагином или Яндекс Игры).
func available() -> bool:
	return _sdk != null or _web


## Можно ли прямо сейчас предложить ролик с вознаграждением: на столе и
## в Яндекс Играх всегда (заглушка / показ по требованию), на Android —
## только когда ролик уже загружен (просьба 22.09: «если ролик не
## загрузился, то ×2 не будет»).
func rewarded_ready() -> bool:
	return _sdk == null or _rewarded_loaded


func _set_rewarded_loaded(v: bool) -> void:
	if _rewarded_loaded == v:
		return
	_rewarded_loaded = v
	rewarded_ready_changed.emit(v)


func _rewarded_id() -> String:
	return DEMO_REWARDED_ID if Net.is_test_build() else REWARDED_ID


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Android: подгрузить ролик заранее (если ещё не загружен и не грузится).
## Web и стол — ничего. Имя историческое: раньше грузила и межстраничную.
func preload_all() -> void:
	if _sdk == null:
		return
	if not _rewarded_loaded and not _rewarded_loading and _now() >= _rewarded_retry_at:
		_rewarded_loading = true
		_sdk.loadRewardedVideo(_rewarded_id())


func _process(delta: float) -> void:
	if _web:
		_web_poll(delta)
		return
	if _wait_t <= 0.0:
		return
	_wait_t -= delta
	if _rewarded_loaded:
		_wait_t = 0.0
		_show_now()
	elif _wait_t <= 0.0:
		last_error = "timeout"
		_finish_show(false)


## Web: результат идущего показа от SDK площадки (window.bhrAd).
func _web_poll(delta: float) -> void:
	if not _show_cb.is_valid():
		return
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = WEB_POLL
	var v: Variant = JavaScriptBridge.eval(JS_POLL, true)
	if v == null:
		return
	var d: Variant = JSON.parse_string(str(v))
	if not (d is Dictionary):
		return
	var state := String(d.get("state", "showing"))
	if state == "showing":
		return
	if state == "error":
		last_error = "show"
	_finish_show(bool(d.get("rewarded", false)))


## Показать ролик; cb(rewarded) — по закрытию. false — рекламы нет
## (стол) или уже идёт другой показ. Android: не загружен — ждём загрузку
## до SHOW_TIMEOUT; web — показ по требованию.
func show_rewarded(cb: Callable) -> bool:
	if not available():
		return false
	if _show_cb.is_valid():
		return false   # уже показываем
	last_error = ""
	_show_cb = cb
	_reward_got = false
	if _web:
		_poll_t = WEB_POLL
		JavaScriptBridge.eval(JS_REWARDED)
	elif _rewarded_loaded:
		_show_now()
	else:
		_wait_t = SHOW_TIMEOUT
		_rewarded_retry_at = 0.0
		preload_all()
	return true


func _show_now() -> void:
	_set_rewarded_loaded(false)
	_sdk.showRewardedVideo()


func _finish_show(rewarded: bool) -> void:
	var cb := _show_cb
	_show_cb = Callable()
	_wait_t = 0.0
	if cb.is_valid():
		cb.call(rewarded)
	preload_all()


func _on_rewarded_loaded() -> void:
	_rewarded_loading = false
	_set_rewarded_loaded(true)


func _on_rewarded_failed_to_load(code: int) -> void:
	_rewarded_loading = false
	_set_rewarded_loaded(false)
	_rewarded_retry_at = _now() + RETRY_GAP
	print("[ads] rewarded failed to load: %d" % code)
	if _show_cb.is_valid():
		last_error = "load %d" % code
		_finish_show(false)


func _on_rewarded_failed_to_show(msg: String) -> void:
	print("[ads] rewarded failed to show: %s" % msg)
	if _show_cb.is_valid():
		last_error = "show"
		_finish_show(false)


func _on_rewarded() -> void:
	# Плагин шлёт (currency, amount) — сумма из кабинета нам не нужна:
	# размер награды считает сама игра.
	_reward_got = true


func _on_rewarded_dismissed() -> void:
	if _show_cb.is_valid():
		_finish_show(_reward_got)
	else:
		preload_all()


## Плагин объявляет сигнал с двумя аргументами; Godot зовёт обработчик
## с ними — принимаем и отбрасываем.
func _on_rewarded_with_args(_currency: String, _amount: int) -> void:
	_on_rewarded()
