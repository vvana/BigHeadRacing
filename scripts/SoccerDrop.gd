class_name SoccerDrop
extends WeaponBox
## Бонус в футболе: тот же золотой куб, но ПАДАЕТ С НЕБА в случайную точку
## поля и ОДНОРАЗОВЫЙ — подобравший забирает его целиком (в гонке бокс
## общий и вечный, тут он добыча: за ним идёт борьба). Пока падает, на
## газоне пульсирует метка-кольцо. Невостребованный бонус тает через LIFE.

const FALL_SPEED := 14.0     # м/с
const GROUND_Y := 0.85       # высота покоя куба над газоном
const LIFE := 25.0           # сколько лежит, если никто не взял, с

var fall_from := 24.0        # с какой высоты падает (стендам можно меньше)

var _landed := false
var _life := LIFE
var _ring: MeshInstance3D


func _ready() -> void:
	super()
	position.y = GROUND_Y + fall_from
	if not Net.is_server():
		_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.1
		torus.outer_radius = 1.45
		_ring.mesh = torus
		_ring.top_level = true
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring.material_override = mat
		add_child(_ring)


func _physics_process(delta: float) -> void:
	if not _landed:
		position.y -= FALL_SPEED * delta
		if position.y <= GROUND_Y:
			position.y = GROUND_Y
			_landed = true
			if not Net.is_server():
				FxKit.ring(get_parent(), global_position, 2.0,
						Color(1.0, 0.85, 0.2))
	else:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
	if _ring != null:
		var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 160.0)
		_ring.global_position = Vector3(global_position.x, 0.08,
				global_position.z)
		_ring.scale = Vector3(pulse, 0.25, pulse)
		# Последние секунды кольцо и куб мигают — бонус вот-вот растает.
		if _landed and _life < 4.0:
			var blink := fmod(_life, 0.4) > 0.2
			_ring.visible = blink
			if _mesh != null:
				_mesh.visible = blink


## Бонус одноразовый: выдали оружие — куб исчезает. Родительский _give сам
## решает, выдавать ли (личный откат) — сверяем, выдал ли, по смене оружия
## нельзя (могло совпасть), поэтому смотрим на след в _next_pickup.
func _give(car: Car) -> void:
	var id := car.get_instance_id()
	var before: float = _next_pickup.get(id, 0.0)
	super(car)
	if _next_pickup.get(id, 0.0) != before:
		queue_free()
