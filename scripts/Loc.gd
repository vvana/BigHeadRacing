class_name Loc
## Язык игры (18.09.2026, требование 2.14 Яндекс Игр + английский).
## Тексты в коде остаются русскими и служат КЛЮЧАМИ перевода: Loc.t("СТАРТ")
## в русской игре вернёт ту же строку, в английской — перевод из LocEn.EN.
## Простые подписи (Label/Button с готовым текстом) движок переводит и сам
## (auto_translate), но составные («КРУГ %d/%d» % …) обязаны идти через
## Loc.t ДО подстановки чисел. Класс статический, без автозагрузки — чтобы
## работал и в стендах-скриптах (`--script`), и в static-функциях.
##
## Язык приходит от площадки: GameState._apply_platform_lang() зовёт
## Loc.setup(ysdk.environment.i18n.lang). Вне web — русский; стенды и
## проверка английского: ключ командной строки `--lang=en`.

## Языки, на которых есть игра; первый — язык по умолчанию вне площадки.
const LOCALES: Array[String] = ["ru", "en"]
## Языки площадки, которым показываем русский (остальным — английский):
## резервный набор из требований Яндекс Игр для русскоязычных стран.
const RU_FAMILY: Array[String] = ["ru", "be", "kk", "uk", "uz"]

static var _registered := false
static var _patterns: Array = []   # [[RegEx, en_fmt], …] — см. server()


## Какой язык игры показать игроку с языком площадки lang («» — площадки нет).
static func pick_locale(lang: String) -> String:
	lang = lang.to_lower().substr(0, 2)
	if lang == "":
		return LOCALES[0]
	if lang in RU_FAMILY:
		return "ru"
	return "en"


## Включить язык игры. Зовётся один раз на старте (GameState._ready).
static func setup(locale: String) -> void:
	if not _registered:
		_registered = true
		var tr_en := Translation.new()
		tr_en.locale = "en"
		# Русский — тождественный перевод «ключ → ключ». Без него движок,
		# не найдя перевода для ru, берёт ЗАПАСНУЮ локаль (по умолчанию en)
		# — и русская игра становилась английской (поймано снимком 18.09).
		var tr_ru := Translation.new()
		tr_ru.locale = "ru"
		for k: String in LocEn.EN:
			tr_en.add_message(k, LocEn.EN[k])
			tr_ru.add_message(k, k)
		TranslationServer.add_translation(tr_en)
		TranslationServer.add_translation(tr_ru)
	TranslationServer.set_locale(locale if locale in LOCALES else LOCALES[0])


## Ключ `--lang=xx` командной строки (стенды, проверка перевода) или «».
static func cmdline_lang() -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--lang="):
			return a.substr(7)
	return ""


static func is_en() -> bool:
	return TranslationServer.get_locale().begins_with("en")


## Перевод строки-ключа на язык игры (нет перевода — вернётся сам ключ).
static func t(s: String) -> String:
	return String(TranslationServer.translate(s))


## Перевод текста, пришедшего С СЕРВЕРА уже собранным («Вася сейчас не в
## игре»): сервер один на всех и пишет по-русски. Сначала точное
## совпадение, затем шаблоны LocEn.SERVER_PATTERNS (%s / %d → группы).
static func server(text: String) -> String:
	if not is_en() or text == "":
		return text
	var exact := t(text)
	if exact != text:
		return exact
	if _patterns.is_empty():
		for ru: String in LocEn.SERVER_PATTERNS:
			var src := ""
			for ch in ru:
				src += ("\\" + ch) if ch in "\\.^$|?*+()[]{}" else ch
			src = src.replace("%s", "(.+?)").replace("%d", "(\\d+)")
			var re := RegEx.new()
			re.compile("^" + src + "$")
			_patterns.append([re, LocEn.SERVER_PATTERNS[ru]])
	for p: Array in _patterns:
		var m: RegExMatch = p[0].search(text)
		if m:
			var out: String = p[1]
			for i in range(1, m.get_group_count() + 1):
				out = out.replace("{%d}" % i, m.get_string(i))
			return out
	return text
