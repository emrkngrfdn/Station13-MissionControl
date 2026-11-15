extends Node

var nickname: String = "Commander"
var player_id: String = ""
var full_tag: String = ""

func _ready() -> void:
	randomize()
	var code = randi_range(1000, 9999)
	player_id = str(code)
	full_tag = "%s#%s" % [nickname, player_id]

func set_nickname(new_name: String) -> void:
	if new_name.strip_edges() != "":
		nickname = new_name.strip_edges()
		full_tag = "%s#%s" % [nickname, player_id]