extends RefCounted
## СГЕНЕРИРОВАНО tools/gen_env.py — руками не править.
## Куски атласов 2D-окружения трассы «neon»:
## имя -> [x, y, ширина, высота в px атласа, размер в метрах].
## У картонок размер — высота на экране, у плоских кусков — ширина.

const GROUND := "res://assets/env/neon/ground.png"

const PATCHES := {
	"car_meet": [600, 4, 286, 282, 32.0],
	"drift_spot": [4, 297, 288, 281, 30.0],
	"gas_station": [296, 297, 287, 281, 30.0],
	"garage_yard": [587, 297, 287, 279, 30.0],
	"port_yard": [4, 4, 290, 289, 34.0],
	"plaza": [890, 4, 288, 282, 34.0],
	"intersection": [298, 4, 298, 288, 34.0],
	"roof_deck": [878, 297, 290, 279, 32.0],
	"skate_plaza": [4, 582, 289, 278, 30.0],
}

const DECALS := {
	"puddle_cyan": [191, 157, 183, 104, 4.0],
	"puddle_pink": [378, 157, 184, 104, 4.0],
	"puddle_orange": [447, 4, 184, 110, 4.0],
	"oil_slick": [1009, 4, 184, 108, 3.5],
	"pool_orange": [4, 157, 183, 108, 6.0],
	"pool_blue": [822, 4, 183, 109, 6.0],
	"pool_violet": [635, 4, 183, 110, 6.0],
	"manhole": [186, 4, 108, 140, 1.6],
	"grate": [773, 157, 146, 80, 1.6],
	"crosswalk": [566, 157, 203, 87, 5.0],
	"start_line": [4, 4, 178, 149, 6.0],
	"nitro_mark": [298, 4, 145, 115, 3.0],
}

const BUILDINGS := {
	"tower_cyan": [4, 4, 155, 224, 24.0],
	"tower_slim": [163, 4, 147, 221, 26.0],
	"office_curved": [470, 4, 208, 215, 13.0],
	"tower_round": [314, 4, 152, 217, 22.0],
	"tuning_shop": [435, 232, 212, 189, 9.0],
	"car_wash": [424, 430, 207, 167, 8.0],
	"diner": [210, 430, 210, 173, 7.5],
	"nightclub": [4, 430, 202, 177, 10.0],
	"car_park": [682, 4, 216, 210, 12.0],
	"screen_store": [4, 232, 207, 194, 10.0],
	"showroom": [651, 232, 205, 189, 9.0],
	"corner_store": [215, 232, 216, 190, 8.0],
	"hotel": [860, 232, 163, 189, 16.0],
	"billboard_big": [995, 4, 123, 202, 9.0],
	"skybridge": [1027, 232, 189, 179, 12.0],
	"mast": [902, 4, 89, 203, 20.0],
}

const STREET := {
	"lamp": [4, 224, 93, 173, 6.0],
	"lamp_double": [628, 4, 98, 187, 6.0],
	"traffic_red": [1188, 4, 38, 177, 4.5],
	"traffic_yellow": [1230, 4, 33, 177, 4.5],
	"bus_stop": [305, 4, 184, 195, 3.5],
	"vending": [730, 4, 147, 182, 2.4],
	"billboard_front": [168, 4, 133, 196, 6.5],
	"billboard_back": [493, 4, 131, 193, 6.5],
	"neon_arrow": [881, 4, 108, 181, 4.5],
	"power_pole": [4, 4, 160, 216, 8.0],
	"barrier": [296, 224, 125, 144, 2.0],
	"cones": [425, 224, 190, 136, 1.5],
	"bench_bin": [101, 224, 191, 146, 1.8],
	"taxi": [619, 224, 183, 131, 2.6],
	"bus": [993, 4, 191, 178, 4.2],
}

## Лист -> [атлас, куски, плоский (лежит на земле), без освещения].
const SHEETS := {
	"patches": ["res://assets/env/neon/patches.png", PATCHES, true, false],
	"decals": ["res://assets/env/neon/decals.png", DECALS, true, false],
	"buildings": ["res://assets/env/neon/buildings.png", BUILDINGS, false, true],
	"street": ["res://assets/env/neon/street.png", STREET, false, true],
}
