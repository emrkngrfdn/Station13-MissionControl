extends Node

signal lobby_updated(players: Array)
signal mission_started
signal telemetry_changed
signal cargo_spawned(part_data: Dictionary)
signal side_quest_triggered(quest_data: Dictionary)
signal side_quest_resolved(option_data: Dictionary)
signal mission_completed(success: bool, report: Dictionary)