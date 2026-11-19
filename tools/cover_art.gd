extends RefCounted

## The lab's original memory bots, with their real friendly expressions and note badges.
const Helpers = preload("res://tools/cover_art_helpers.gd")
const Bot = preload("res://games/lazer_nfc/arena/memory_bot.gd")


## A sunny science-toy box rather than a distant board.
static func design() -> Dictionary:
	return {
		"paper": Color("e7f2d5"), "ink": Color("24515c"), "accent": Color("f29a78"),
		"motif": "bubbles", "camera": Vector3(12, 11, -5),
		"photo": Rect2(-5, 310, 1034, 635),
		"lettering": [
			{"text": "LaZer", "at": Vector2(57, 217), "size": 228, "font": "round"},
			{"text": "NFC", "at": Vector2(66, 326), "size": 96, "font": "mono"},
			{"text": "LISTEN. REMEMBER. REPEAT.", "at": Vector2(64, 982),
				"size": 35, "font": "mono"},
		],
	}


## Supporting red/yellow bots use public, revealed notes; no hidden sequence is read.
static func build(parent: Node) -> Node:
	var root := Helpers.group(parent)
	for index in 3:
		var bot := Bot.new()
		root.add_child(bot)
		bot.build(false)
		if index == 0:
			bot.welcome()
		else:
			bot.set_note(&"red" if index == 1 else &"yellow")
		bot.pose(0.8, 0.3, &"happy", true)
		bot.position = [Vector3(0, 0, 0.4), Vector3(-1.5, 0.15, -0.5),
			Vector3(1.5, 0.3, -0.6)][index]
		bot.scale = Vector3.ONE * (1.0 if index == 0 else 0.7)
		bot.rotation_degrees.z = [0, 12, -10][index]
	return root
