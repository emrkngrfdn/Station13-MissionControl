extends Node

var nickname: String = "Commander"
var player_id: String = ""
var full_tag: String = ""

func _ready() -> void:
	randomize()
	var code: int = randi_range(1000, 9999)
	player_id = str(code)
	full_tag = "%s#%s" % [nickname, player_id]

func set_nickname(new_name: String) -> void:
	var cleaned: String = new_name.strip_edges()
	if cleaned == "":
		return
	if cleaned.contains("#"):
		var parts: PackedStringArray = cleaned.split("#", false, 1)
		if parts.size() == 2 and parts[0].strip_edges() != "" and parts[1].strip_edges() != "":
			nickname = parts[0].strip_edges()
			player_id = parts[1].strip_edges()
		else:
			nickname = cleaned.replace("#", "")
	else:
		nickname = cleaned
	full_tag = "%s#%s" % [nickname, player_id]

func normalize_tag(raw_tag: String) -> String:
	var cleaned: String = raw_tag.strip_edges()
	if cleaned == "":
		return ""
	if cleaned.contains("#"):
		var parts: PackedStringArray = cleaned.split("#", false, 1)
		var name_part: String = parts[0].strip_edges()
		var id_part: String = parts[1].strip_edges() if parts.size() > 1 else ""
		if name_part == "":
			return ""
		if id_part == "":
			id_part = str(randi_range(1000, 9999))
		return "%s#%s" % [name_part, id_part]
	return "%s#%d" % [cleaned, randi_range(1000, 9999)]
