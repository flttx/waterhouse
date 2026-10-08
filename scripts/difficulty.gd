class_name WaterhouseDifficulty
extends RefCounted

const KEYS: PackedStringArray = ["exploration", "survival", "abyss"]
const PROFILES := {
	"exploration": {"name": "探索", "breath_seconds": 100.0, "decoys": 5, "detection_multiplier": 0.65, "speed_multiplier": 0.8, "attack_damage": 45.0, "attack_windup": 1.35, "quiet_multiplier": 1.3},
	"survival": {"name": "求生", "breath_seconds": 60.0, "decoys": 3, "detection_multiplier": 1.0, "speed_multiplier": 1.0, "attack_damage": 100.0, "attack_windup": 0.9, "quiet_multiplier": 1.0},
	"abyss": {"name": "深渊", "breath_seconds": 45.0, "decoys": 2, "detection_multiplier": 1.35, "speed_multiplier": 1.16, "attack_damage": 100.0, "attack_windup": 0.65, "quiet_multiplier": 0.8},
}


static func normalize_key(value: String) -> String:
	return value if value in KEYS else "survival"


static func profile(key: String) -> Dictionary:
	return (PROFILES[normalize_key(key)] as Dictionary).duplicate()
