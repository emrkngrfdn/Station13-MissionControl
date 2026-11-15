extends Node

signal lobby_updated(players: Array)
signal mission_started
signal telemetry_changed
signal cargo_spawned(part_data: Dictionary)
signal side_quest_triggered(quest_data: Dictionary)
signal side_quest_resolved(option_data: Dictionary)
signal mission_completed(success: bool, report: Dictionary)
signal terminal_opened(terminal_name: String)
signal launch_site_changed(site_data: Dictionary)
signal rocket_changed(rocket_data: Dictionary)
signal network_status_changed(status_text: String, is_online: bool)
signal crisis_alert(crisis_code: String)
signal status_message(msg: String, is_error: bool)

