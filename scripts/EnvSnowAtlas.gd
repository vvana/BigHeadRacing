extends RefCounted
## СГЕНЕРИРОВАНО tools/gen_env.py — руками не править.
## Куски атласов 2D-окружения трассы «snow»:
## имя -> [x, y, ширина, высота в px атласа, размер в метрах].
## У картонок размер — высота на экране, у плоских кусков — ширина.

const GROUND := "res://assets/env/snow/ground.png"

const NATURE := {
	"spruce_tall": [4, 4, 153, 238, 9.0],
	"fir_small": [921, 246, 166, 169, 5.0],
	"fir_group": [161, 4, 195, 235, 9.0],
	"birch_frost": [559, 4, 134, 232, 7.5],
	"oak_bare": [360, 4, 195, 233, 8.0],
	"bush_snow": [714, 246, 203, 173, 3.5],
	"rowan": [697, 4, 177, 229, 6.0],
	"boulder": [464, 440, 214, 152, 3.0],
	"rocks": [4, 440, 232, 169, 3.0],
	"stump_ice": [240, 440, 220, 167, 2.6],
	"snowman": [878, 4, 193, 225, 3.2],
	"snow_fort": [4, 246, 232, 190, 2.8],
	"drift": [475, 246, 235, 179, 3.0],
	"firewood": [240, 246, 231, 184, 2.6],
	"pump_frozen": [1075, 4, 184, 225, 3.0],
}

const VILLAGE := {
	"cabin": [398, 4, 218, 235, 7.0],
	"cottage": [4, 245, 207, 213, 7.0],
	"lodge": [4, 4, 216, 237, 8.5],
	"log_hut": [215, 245, 204, 212, 6.5],
	"barn": [801, 4, 233, 230, 7.5],
	"garage_snow": [634, 245, 226, 206, 6.0],
	"xmas_tree": [224, 4, 170, 237, 6.5],
	"well": [620, 4, 177, 233, 4.2],
	"logs": [232, 462, 218, 169, 2.4],
	"sleigh": [4, 462, 224, 189, 2.6],
	"jeep": [864, 245, 243, 195, 3.0],
	"water_tower": [1038, 4, 158, 225, 7.5],
	"ski_rack": [423, 245, 207, 211, 3.0],
	"rink": [454, 462, 237, 161, 3.2],
}

const DECALS := {
	"drift_ridge": [4, 4, 229, 222, 6.0],
	"snow_pile": [416, 4, 153, 133, 3.0],
	"ice_pieces": [237, 4, 175, 142, 3.0],
}

## Лист -> [атлас, куски, плоский (лежит на земле), без освещения,
## сложением цвета (чёрное = прозрачно)].
const SHEETS := {
	"nature": ["res://assets/env/snow/nature.png", NATURE, false, false, false],
	"village": ["res://assets/env/snow/village.png", VILLAGE, false, false, false],
	"decals": ["res://assets/env/snow/decals.png", DECALS, true, false, false],
}
