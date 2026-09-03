extends Node
## Фоновая музыка (autoload «Music»). В гараже играет свой трек, в заезде
## и в футболе — случайный из трёх; трек меняется короткой склейкой
## (затухание FADE секунд), autoload переживает смену сцены и не начинает
## музыку заново на каждом экране.
##
## Файлы — assets/audio (mp3, лицензия Pixabay: menu — «The Mountain,
## action rock»; гоночные — два heavy metal от strawberry_candy и
## energetic indie rock от alexgrohl).
##
## На выделенном сервере и в headless-стендах молчим: звукового устройства
## там нет, а mp3 всё равно пришлось бы декодировать каждый кадр.

const MENU := "res://assets/audio/menu.mp3"
const RACE: Array[String] = [
	"res://assets/audio/race_adrenaline.mp3",
	"res://assets/audio/race_force.mp3",
	"res://assets/audio/race_jump.mp3",
]
## Музыка — фон: поверх неё ещё поедут анонсы и взрывы.
const VOLUME_DB := -11.0
const QUIET_DB := -40.0     # «тишина» на время склейки
const FADE := 0.35          # затухание/нарастание, с

var _player: AudioStreamPlayer
var _silent := false
var _current := ""                 # путь того, что играет сейчас
var _queue: Array[String] = []     # перемешанная очередь гоночных треков
var _tween: Tween


func _ready() -> void:
	# Пауза в гонке музыку не глушит (и сама пауза ставится через
	# get_tree().paused — обычный узел бы замолчал).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		return
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.volume_db = VOLUME_DB
	_player.finished.connect(_on_finished)
	add_child(_player)


## Трек гаража (тот, что помечен «menu»). Зациклен — меню долгое.
func play_menu() -> void:
	_play(MENU, true)


## Трек заезда. Если гоночный уже играет — НЕ трогаем: Main перезагружает
## сцену (смена трассы по сети, рестарт заезда, переход из лобби), и
## музыка не должна начинаться заново на каждой загрузке.
func play_race() -> void:
	if _silent:
		return
	if _player.playing and RACE.has(_current):
		return
	next_race()


## Поставить СЛЕДУЮЩИЙ гоночный трек: случайный из RACE. Очередь
## перемешана, поэтому подряд один и тот же не попадётся.
func next_race() -> void:
	if _silent:
		return
	if _queue.is_empty():
		_refill()
	_play(_queue.pop_front(), false)


func stop() -> void:
	if _player:
		_player.stop()
	_current = ""


## Перемешать очередь заново, не повторив тот трек, что только что играл.
func _refill() -> void:
	_queue = RACE.duplicate()
	_queue.shuffle()
	if _queue.size() > 1 and _queue[0] == _current:
		_queue.push_back(_queue.pop_front())


func _play(path: String, loop: bool) -> void:
	if _silent or path.is_empty():
		return
	if path == _current and _player.playing:
		return    # уже играет — не начинать с начала (возврат в гараж)
	var stream: AudioStream = ResourceLoader.load(path) as AudioStream
	if stream == null:
		push_warning("Музыка не найдена: %s" % path)
		return
	# Зацикливание — свойство самого потока, не проигрывателя.
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	_current = path
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if _player.playing:
		_tween.tween_property(_player, "volume_db", QUIET_DB, FADE)
		_tween.tween_callback(_swap.bind(stream))
	else:
		_swap(stream)
		_player.volume_db = QUIET_DB
	_tween.tween_property(_player, "volume_db", VOLUME_DB, FADE)


func _swap(stream: AudioStream) -> void:
	_player.stream = stream
	_player.play()


## Гоночный трек не зациклен — доиграл, ставим следующий из очереди.
func _on_finished() -> void:
	if _current != MENU:
		next_race()
