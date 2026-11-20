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
signal remote_player_updated(peer_id: int, state: Dictionary)
signal remote_player_left(peer_id: int)
signal network_states_requested(scene_tag: String)
signal box_picked_up(box_id: String, peer_id: int)
signal box_dropped(box_id: String, pos: Vector2)
signal box_installed(box_id: String)
signal room_returned_to_lobby

