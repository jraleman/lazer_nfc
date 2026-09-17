extends SceneTree

## Rebuild the printable labels from the same palette used by the live game.

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const Glyph = preload("res://games/lazer_nfc/ui/shape_glyph.gd")
const OUTPUT := "res://games/lazer_nfc/assets/tag-sheet.svg"


func _initialize() -> void:
	var parts := PackedStringArray([
		'<svg xmlns="http://www.w3.org/2000/svg" width="210mm" height="297mm" viewBox="0 0 840 1188">',
		'<rect width="840" height="1188" fill="#ffffff"/>',
		'<g font-family="sans-serif" text-anchor="middle" fill="#102632">',
		'<text x="420" y="38" font-size="25" font-weight="bold">LaZer NFC - the little laboratory</text>',
		'<text x="420" y="63" font-size="14">Base labels first. Dark / Base / Light use one / two / three dots.</text>',
		'<text x="420" y="87" font-size="14">Keep tags at least 15 cm apart. Place them comfortably within reach.</text>',
	])
	for hue_index in Palette.HUES.size():
		var hue: StringName = Palette.HUES[hue_index]
		for shade in 3:
			var id := Palette.id_for(hue, shade)
			var x := 24 + shade * 272
			var y := 110 + hue_index * 146
			parts.append('<g transform="translate(%d %d)">' % [x, y])
			parts.append('<rect width="248" height="128" rx="10" fill="#%s" stroke="#102632" stroke-width="2" stroke-dasharray="4 3"/>' % Palette.color(id).to_html(false))
			parts.append('<circle cx="52" cy="61" r="35" fill="white"/>')
			var points := PackedStringArray()
			for point: Vector2 in Glyph.polygon(id, Vector2.ZERO, 25.0):
				points.append("%.2f,%.2f" % [point.x, point.y])
			parts.append('<polygon transform="translate(52 61)" fill="#102632" points="%s"/>' % " ".join(points))
			parts.append('<rect x="99" y="21" width="136" height="84" rx="8" fill="white"/>')
			parts.append('<text x="167" y="48" font-size="17" font-weight="bold">%s</text>' % Palette.label(id).xml_escape())
			parts.append('<text x="167" y="69" font-size="12">%s</text>' % ["DARK", "BASE", "LIGHT"][shade])
			for dot in shade + 1:
				var dx := 167 - shade * 8 + dot * 16
				parts.append('<circle cx="%d" cy="88" r="4" fill="#102632"/>' % dx)
			parts.append("</g>")
	parts.append('<text x="420" y="1162" font-size="13">Attach NFC stickers to the backs. These labels are not NFC tags.</text>')
	parts.append("</g></svg>")
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if output == null:
		printerr("Could not write tag sheet: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	output.store_string("\n".join(parts))
	output.close()
	print("Rendered %s" % OUTPUT)
	quit(0)
