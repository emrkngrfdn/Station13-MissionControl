extends PanelContainer

@onready var title_label: Label = %QuestTitle
@onready var desc_label: Label = %QuestDesc
@onready var options_box: VBoxContainer = %OptionsBox
@onready var feedback_label: Label = %QuestFeedback

var _resolved_quest_ids: Array[String] = []
var _current_quest: Dictionary = {}

func _ready() -> void:
	visible = false
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.side_quest_triggered.connect(open_quest)
	EventBus.mission_started.connect(_reset_quests)

func _reset_quests() -> void:
	_resolved_quest_ids.clear()

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name in ["POWER_LAB", "BRIEFING"]:
		var quests: Array = GameState.get_available_side_quests_for_mission()
		for q in quests:
			var q_id: String = q.get("id", "")
			if not _resolved_quest_ids.has(q_id):
				if terminal_name == "BRIEFING" or q.get("room", "") == terminal_name:
					open_quest(q)
					return

func open_quest(quest_data: Dictionary) -> void:
	_current_quest = quest_data
	visible = true
	title_label.text = quest_data.get("title", "MÜHENDİSLİK KARARI")
	desc_label.text = quest_data.get("description", "")
	feedback_label.text = ""

	for child in options_box.get_children():
		child.queue_free()

	for opt in quest_data.get("options", []):
		var btn := Button.new()
		btn.text = opt.get("label", "Seçenek")
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_option_chosen.bind(opt))
		options_box.add_child(btn)

func _on_option_chosen(opt: Dictionary) -> void:
	var q_id: String = _current_quest.get("id", "")
	if q_id != "" and not _resolved_quest_ids.has(q_id):
		_resolved_quest_ids.append(q_id)
	GameState.apply_side_quest_option(opt)
	visible = false

func _on_close_pressed() -> void:
	visible = false
