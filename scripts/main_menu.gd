extends Control

@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var status_label: Label = %MenuStatusLabel

func _ready() -> void:
	nickname_input.text = PlayerProfile.nickname
	status_label.text = "Profilin: %s" % PlayerProfile.full_tag

func _apply_nickname() -> void:
	PlayerProfile.set_nickname(nickname_input.text)
	status_label.text = "Profilin: %s" % PlayerProfile.full_tag

func _on_create_room_pressed() -> void:
	_apply_nickname()
	GameState.create_room()
	get_tree().change_scene_to_file("res://scenes/world/waiting_room.tscn")

func _on_join_room_pressed() -> void:
	_apply_nickname()
	var code := room_code_input.text.strip_edges()
	if code == "":
		status_label.text = "Lütfen bir Oda Kodu girin (örn: JPL-42)!"
		return
	GameState.join_room(code)
	get_tree().change_scene_to_file("res://scenes/world/waiting_room.tscn")

func _on_solo_quick_pressed() -> void:
	_apply_nickname()
	GameState.create_room()
	get_tree().change_scene_to_file("res://scenes/world/waiting_room.tscn")
