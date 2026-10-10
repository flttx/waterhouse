extends Node
## Shared pursuit budget. It never hides enemies or disables their perception.
## Native physics time pauses with the world; warning reservations expire if sight is lost.
var max_pursuers: int = 1
var respite_seconds: float = 7.0
var warning_seconds: float = 1.4
var _clock: float = 0.0
var _rest_until: float = 0.0
var _active: Dictionary = {}
var _pending: Dictionary = {}
var _recent: Dictionary = {}


func reset_run(difficulty: String) -> void:
	max_pursuers = 2 if difficulty == "abyss" else 1
	respite_seconds = 10.0 if difficulty == "exploration" else (4.0 if difficulty == "abyss" else 7.0)
	warning_seconds = 0.9 if difficulty == "abyss" else 1.4
	_clock = 0.0
	_rest_until = 0.0
	_active.clear()
	_pending.clear()
	_recent.clear()


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	_clock += delta
	for actor in _active.keys():
		if not is_instance_valid(actor) or not actor.enabled or not actor.encounter_is_active():
			_active.erase(actor)
			if is_instance_valid(actor):
				_recent[actor] = _clock + respite_seconds + 3.0
			if _active.is_empty():
				_rest_until = _clock + respite_seconds
	for actor in _pending.keys():
		if not is_instance_valid(actor) or _clock - float(_pending[actor][1]) > 1.2:
			_pending.erase(actor)


func request_pursuit(actor: Node3D) -> bool:
	if _active.has(actor):
		return true
	# The last aggressor yields three extra seconds so another territory can lead.
	if _clock < float(_recent.get(actor, 0.0)) or _clock < _rest_until or _active.size() >= max_pursuers:
		_pending.erase(actor)
		return false
	if not _pending.has(actor):
		_pending[actor] = [_clock, _clock]
		actor.emit_signal("omen", actor.global_position, 0.7)
		return false
	_pending[actor][1] = _clock
	if _clock - float(_pending[actor][0]) < warning_seconds:
		return false
	_active[actor] = true
	_pending.erase(actor)
	return true
