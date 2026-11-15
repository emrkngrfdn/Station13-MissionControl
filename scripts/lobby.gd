extends Control

@onready var nickname_input: LineEdit = %NicknameInput
@onready var add_player_input: LineEdit = %AddPlayerInput
@onready var crew_list: VBoxContainer = %CrewList
@onready var mission_option: OptionButton = %MissionOption
@onready var modifier_option: OptionButton = %ModifierOption
@onready var launch_site_option: OptionButton = %LaunchSiteOption
@onready var mission_desc: Label = %MissionDesc
@onready var budget_label: Label = %BudgetLabel
@onready var leaderboard_list: VBoxContainer = %LeaderboardList

func _ready() -> void:
	nickname_input.text = PlayerProfile.nickname
	_populate_selectors()
	EventBus.lobby_updated.connect(_refresh_crew_list)
	EventBus.telemetry_changed.connect(_refresh_mission_info)
	_refresh_crew_list(GameState.lobby_players)
	_refresh_mission_info()
	_refresh_leaderboard()

func _populate_selectors() -> void:
	mission_option.clear()
	for m in GameState.missions_data.get("missions", []):
		mission_option.add_item("%s [%s]" % [m.get("name", ""), m.get("difficulty", "")])

	modifier_option.clear()
	for mod in GameState.missions_data.get("budget_modifiers", []):
		modifier_option.add_item(mod.get("name", ""))

	launch_site_option.clear()
	for site in GameState.missions_data.get("launch_sites", []):
		launch_site_option.add_item(site.get("name", ""))

func _refresh_crew_list(players: Array) -> void:
	for child in crew_list.get_children():
		child.queue_free()

	for i in range(4):
		var lbl := Label.new()
		if i < players.size():
			var p: Dictionary = players[i]
			var role_tag := " [HOST]" if p.get("is_host", false) else ""
			lbl.text = "%d. %s%s" % [i + 1, p.get("tag", ""), role_tag]
			lbl.modulate = p.get("color", Color.WHITE)
		else:
			lbl.text = "%d. [BOŞ SLOT — Oyuncu ID ile davet et]" % (i + 1)
			lbl.modulate = Color(0.55, 0.6, 0.65)
		crew_list.add_child(lbl)

func _refresh_mission_info() -> void:
	var m: Dictionary = GameState.current_mission
	mission_desc.text = "%s\nYörünge: %s | Güç: %.0f W | Kütle Limiti: %.0f kg" % [
		m.get("description", ""),
		m.get("orbit_label", ""),
		float(m.get("nominal_power_w", 0.0)),
		float(m.get("max_mass_kg", 0.0))
	]
	budget_label.text = "DİNAMİK BÜTÇE: $%.0fM | ROKET: %s" % [
		GameState.budget_m,
		GameState.selected_rocket.get("name", "-")
	]

func _refresh_leaderboard() -> void:
	for child in leaderboard_list.get_children():
		child.queue_free()

	var current_id: String = GameState.current_mission.get("id", "")
	var count := 0
	for rec in LeaderboardManager.records:
		if rec.get("mission_id", "") == current_id:
			var lbl := Label.new()
			lbl.text = "%s — %.1fs | Skor: %d" % [
				rec.get("team", ""),
				float(rec.get("time_sec", 0.0)),
				int(rec.get("score", 0))
			]
			leaderboard_list.add_child(lbl)
			count += 1
	if count == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "Henüz kayıt yok. İlk rekoru kır!"
		empty_lbl.modulate = Color(0.6, 0.65, 0.7)
		leaderboard_list.add_child(empty_lbl)

func _on_nickname_submitted(new_text: String) -> void:
	PlayerProfile.set_nickname(new_text)
	if GameState.lobby_players.size() > 0:
		GameState.lobby_players[0]["tag"] = PlayerProfile.full_tag
		_refresh_crew_list(GameState.lobby_players)

func _on_add_player_pressed() -> void:
	if GameState.add_player_to_lobby(add_player_input.text):
		add_player_input.text = ""

func _on_mission_selected(_idx: int) -> void:
	GameState.setup_mission(mission_option.selected, modifier_option.selected)
	_sync_launch_site_dropdown()
	_refresh_leaderboard()

func _on_modifier_selected(_idx: int) -> void:
	GameState.setup_mission(mission_option.selected, modifier_option.selected)

func _on_launch_site_selected(idx: int) -> void:
	var sites: Array = GameState.missions_data.get("launch_sites", [])
	if idx >= 0 and idx < sites.size():
		GameState.select_launch_site(sites[idx].get("id", ""))

func _sync_launch_site_dropdown() -> void:
	var sites: Array = GameState.missions_data.get("launch_sites", [])
	var target_id: String = GameState.selected_launch_site.get("id", "")
	for i in range(sites.size()):
		if sites[i].get("id", "") == target_id:
			launch_site_option.selected = i
			break

func _on_start_mission_pressed() -> void:
	GameState.start_mission()
	if ResourceLoader.exists("res://scenes/world/station.tscn"):
		get_tree().change_scene_to_file("res://scenes/world/station.tscn")
	else:
		mission_desc.text = "Hazır! Sıradaki adım: res://scenes/world/station.tscn sahnesini oluşturun."
