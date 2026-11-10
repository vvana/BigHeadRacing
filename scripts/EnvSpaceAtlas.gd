extends RefCounted
## СГЕНЕРИРОВАНО tools/gen_env.py — руками не править.
## Куски атласов 2D-окружения трассы «space»:
## имя -> [x, y, ширина, высота в px атласа, размер в метрах].
## У картонок размер — высота на экране, у плоских кусков — ширина.

const GROUND := "res://assets/env/space/ground.png"

const NEBULAE := {
	"galaxy_spiral": [560, 350, 180, 158, 34.0],
	"nebula_pink": [4, 350, 262, 254, 44.0],
	"nebula_blue": [603, 4, 262, 260, 44.0],
	"filament": [270, 350, 286, 201, 40.0],
	"nebula_orange": [869, 4, 250, 257, 30.0],
	"starburst": [4, 4, 341, 342, 30.0],
	"ring": [349, 4, 250, 265, 28.0],
}

## Лист -> [атлас, куски, плоский (лежит на земле), без освещения,
## сложением цвета (чёрное = прозрачно)].
const SHEETS := {
	"nebulae": ["res://assets/env/space/nebulae.png", NEBULAE, true, true, true],
}
