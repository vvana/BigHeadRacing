extends RefCounted
## СГЕНЕРИРОВАНО tools/gen_env.py — руками не править.
## Куски атласов 2D-окружения трассы «grass»:
## имя -> [x, y, ширина, высота в px атласа, размер в метрах].
## У картонок размер — высота на экране, у плоских кусков — ширина.

const GROUND := "res://assets/env/grass/ground.png"
const ROAD := "res://assets/env/grass/road.png"

const STADIUM := {
	"stand_front": [409, 231, 210, 165, 6.0],
	"stand_back": [985, 231, 214, 143, 6.0],
	"stand_covered": [623, 231, 188, 162, 6.5],
	"control_tower": [289, 4, 143, 210, 9.0],
	"leaderboard": [71, 4, 58, 220, 7.0],
	"light_tower": [4, 4, 63, 223, 12.0],
	"billboard_front": [436, 4, 154, 208, 6.5],
	"billboard_back": [133, 4, 152, 213, 6.5],
	"flagman": [815, 231, 166, 145, 3.2],
	"ticket_booth": [777, 4, 168, 189, 4.2],
	"concession": [949, 4, 208, 189, 4.5],
	"merch_trailer": [4, 231, 194, 173, 3.8],
	"toilets": [202, 231, 203, 168, 3.0],
	"arch": [594, 4, 179, 192, 5.0],
}

const PIT := {
	"garages": [4, 4, 238, 204, 6.5],
	"crew_red": [428, 212, 179, 169, 2.4],
	"crew_blue": [235, 390, 178, 134, 2.2],
	"transporter": [645, 4, 226, 179, 5.0],
	"hauler": [4, 212, 214, 174, 4.0],
	"pickup_trailer": [4, 390, 227, 135, 2.8],
	"motorhome": [1052, 4, 200, 175, 4.5],
	"pace_car": [969, 212, 201, 144, 2.4],
	"safety_truck": [222, 212, 202, 170, 2.6],
	"tow_truck": [246, 4, 211, 193, 3.8],
	"fuel_cart": [611, 212, 132, 153, 2.0],
	"tyre_stack": [875, 4, 173, 178, 2.0],
	"tyre_wall": [747, 212, 218, 149, 2.0],
	"canopy": [461, 4, 180, 183, 3.6],
}

const INFIELD := {
	"camper": [462, 4, 210, 195, 4.2],
	"fans_pickup": [1018, 4, 186, 173, 3.6],
	"picnic_tent": [676, 4, 180, 183, 3.8],
	"tent": [724, 216, 188, 143, 2.4],
	"parked_cars": [491, 216, 229, 149, 2.6],
	"banners": [4, 4, 158, 208, 5.0],
	"tyre_balloon": [860, 4, 154, 174, 5.0],
	"topiary": [166, 4, 119, 205, 4.0],
	"poplars": [289, 4, 169, 205, 7.5],
	"bush": [916, 216, 145, 116, 2.2],
	"arrow_sign": [190, 216, 94, 168, 3.0],
	"medic_tent": [288, 216, 199, 168, 3.0],
	"helipad": [4, 216, 182, 170, 4.0],
}

## Лист -> [атлас, куски, плоский (лежит на земле), без освещения,
## сложением цвета (чёрное = прозрачно)].
const SHEETS := {
	"stadium": ["res://assets/env/grass/stadium.png", STADIUM, false, false, false],
	"pit": ["res://assets/env/grass/pit.png", PIT, false, false, false],
	"infield": ["res://assets/env/grass/infield.png", INFIELD, false, false, false],
}
