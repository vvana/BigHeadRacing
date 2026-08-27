extends Node3D
## Автотест: В СЕТЕВОЙ ИГРЕ МАШИНА НЕ ПРОЕЗЖАЕТ СКВОЗЬ СОПЕРНИКА.
##
## 26.08 марионеток сделали полностью не твёрдыми для решателя, чтобы они
## перестали выдавливать игрока диким импульсом при телепорте к снимку.
## Побочный итог, на который сразу пожаловался игрок: «столкновений нет в
## сетевом режиме, проезжаю сквозь машины». Толчок-то остался (своя логика
## _bounce_off_cars), но ГЕОМЕТРИЯ мешать перестала — кузов проходил насквозь.
##
## Стенд: своя машина (её физику на клиенте считает он сам) едет прямо в
## марионетку, стоящую поперёк. Проверяем две вещи разом:
##   1) СКВОЗЬ НЕ ПРОЕХАЛИ — машина не оказалась по ту сторону соперника;
##   2) кузова не слиплись — центры не сближались ближе CONTACT_MIN.
##
## Запуск: godot --headless --path . res://tools/TestPuppetSolid.tscn

const APPROACH := 14.0     # с какой скоростью таранит, м/с
const CONTACT_MIN := 1.0   # ближе этого центры кузовов сходиться не должны
const WATCH := 150         # кадров наблюдения после разгона

var _main: Node3D
var _frame := 0
var _me: Car
var _puppet: Car
var _dir := Vector3.ZERO
var _puppet_s := 0.0       # марионетка вдоль оси тарана
var _my_max_s := -1e9      # как далеко по этой оси я уехал
var _min_gap := 1e9


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_me = _main._cars[0]
		_puppet = _main._cars[1]
		# Лишние машины глушим и увозим, чтобы не лезли в замер.
		for i in range(2, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false
			extra.global_position = Vector3(150, 2, 150 + i * 8)
		_me.controls_enabled = false
		_puppet.controls_enabled = false
		_puppet.net_make_puppet()
		return
	if _frame == 40:
		# Марионетка — в 9 м прямо по курсу, стоит поперёк (борт ко мне).
		_dir = -_me.global_transform.basis.z
		_dir.y = 0.0
		_dir = _dir.normalized()
		var at: Vector3 = _me.global_position + _dir * 9.0
		at.y = _me.global_position.y
		var across := Quaternion(Vector3.UP, PI * 0.5) \
				* _me.global_transform.basis.get_rotation_quaternion()
		_puppet.net_apply_snapshot(at, across, Vector3.ZERO)
		_puppet_s = _dir.dot(at)
		# Разгон точно в неё.
		_me.linear_velocity = _dir * APPROACH
		_me.reset_speed_memory()
		print("таран: соперник в 9.0 м по курсу, скорость %.1f м/с" % APPROACH)
		return
	if _frame > 40 and _frame <= 40 + WATCH:
		# Марионетка стоит: снимки не приходят, поэтому держим её на месте
		# сами — иначе экстраполяция уведёт её и таран станет нечестным.
		_puppet.net_apply_snapshot(_puppet.global_position,
				_puppet.global_transform.basis.get_rotation_quaternion(),
				Vector3.ZERO)
		_min_gap = minf(_min_gap, _plan_dist(
				_me.global_position, _puppet.global_position))
		_my_max_s = maxf(_my_max_s, _dir.dot(_me.global_position))
		return
	if _frame == 41 + WATCH:
		# «Проехал сквозь» = мой центр оказался ЗА центром соперника по оси
		# тарана. Отскок или остановка перед ним держат разность < 0.
		var through := _my_max_s - _puppet_s
		var solid := through < 0.0
		var not_merged := _min_gap >= CONTACT_MIN
		print("дальше соперника на %.2f м (сквозь = больше 0), "
				% through + "минимальный зазор центров %.2f м" % _min_gap)
		print("PUPPETSOLID TEST: %s" % ("PASS" if solid and not_merged
				else "FAIL — сквозь=%s слиплись=%s"
				% [str(not solid), str(not not_merged)]))
		get_tree().quit(0 if solid and not_merged else 1)


func _plan_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
