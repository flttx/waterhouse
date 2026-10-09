extends SceneTree
## Run with --main-pack build/TheWaterhouse.pck; no source-root fallback is allowed.

var failures: int = 0
var checked: Dictionary = {}


func _initialize() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/audio_v2_manifest.json"))
	if not manifest is Dictionary or not manifest.get("cues") is Dictionary or not manifest.get("music") is Dictionary:
		push_error("Exported audio manifest is missing or invalid")
		quit(1)
		return
	for cue: Dictionary in manifest["cues"].values():
		for path: String in cue["files"]:
			_validate(path)
	for path: String in manifest["music"].values():
		_validate(path)
	if checked.size() != 93:
		failures += 1
		push_error("Exported package must contain all 93 runtime audio files")
	if FileAccess.file_exists("res://assets/audio/v2/source/WATER_LICENSE.txt"):
		failures += 1
		push_error("Original recording source folder should be excluded from the runtime pack")
	print("PACKAGE AUDIO: %d real exported audio resources / %d failures" % [checked.size(), failures])
	quit(1 if failures else 0)


func _validate(path: String) -> void:
	if checked.has(path):
		return
	var stream := load(path) as AudioStream
	if stream == null or stream.get_length() <= 0.0:
		failures += 1
		push_error("Exported audio cannot be decoded: " + path)
	checked[path] = true
