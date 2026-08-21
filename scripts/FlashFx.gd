class_name FlashFx
extends AnimatedSprite3D
## Мультяшный взрыв-вспышка: анимация 9 кадров из атласа Epic Toon FX
## (explosion_round 3×3), билборд, красится в цвет эффекта (взрыв —
## оранжевый, заморозка — голубой, буст — бирюзовый и т.д.).
## Сигнатура spawn прежняя — все вызовы по коду работают как раньше.

const SHEET := "res://assets/fx/explosion_3x3.png"
const FPS := 20.0  # 9 кадров ≈ 0.45 с


static func spawn(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	var fx := FlashFx.new()
	var sheet: Texture2D = load(SHEET)
	var fw := sheet.get_width() / 3
	var fh := sheet.get_height() / 3
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", FPS)
	frames.set_animation_loop("default", false)
	for i in 9:
		var at := AtlasTexture.new()
		at.atlas = sheet
		@warning_ignore("integer_division")
		at.region = Rect2((i % 3) * fw, (i / 3) * fh, fw, fh)
		frames.add_frame("default", at)
	fx.sprite_frames = frames
	fx.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fx.shaded = false
	fx.modulate = color
	# Поперечник взрыва ~2.6 радиуса вспышки (по старой сфере с твином ×3).
	fx.pixel_size = radius * 2.6 / float(fw)
	parent.add_child(fx)
	fx.global_position = pos
	fx.play("default")
	fx.animation_finished.connect(fx.queue_free)
