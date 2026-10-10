extends SceneTree
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	game.selected_difficulty = "survival"
	game.start_run()
	game.set_process(false)
	game.player.enabled = false
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	var director = game.encounter_director
	director.set_physics_process(false)
	var first = game.creature
	var second = game.enemies[1]
	first.state = first.State.PATROL
	second.state = second.State.PATROL
	check(director.max_pursuers == 1, "survival permits one active pursuer")
	for enemy in game.enemies:
		check(enemy.encounter_director == director, "every actor shares the game encounter director")
	first._set_state(first.State.CHASE)
	check(first.state == first.State.PATROL, "first sight gives an omen before chase")
	for step in 9:
		director.advance(0.18)
		first._set_state(first.State.CHASE)
	check(first.state == first.State.CHASE, "continued exposure after warning permits pursuit")
	for step in 12:
		director.advance(0.18)
		second._set_state(second.State.CHASE)
	check(second.state == second.State.PATROL, "another predator keeps its current behavior while budget is full")
	first._set_state(first.State.SEARCH)
	director.advance(0.18)
	second._set_state(second.State.CHASE)
	check(second.state == second.State.PATROL, "losing pursuit grants global breathing room")
	director.advance(7.1)
	second._set_state(second.State.CHASE)
	first._set_state(first.State.CHASE)
	check(first.state == first.State.SEARCH, "last aggressor yields priority to another predator")
	for step in 9:
		director.advance(0.18)
		second._set_state(second.State.CHASE)
	check(second.state == second.State.CHASE, "another predator can lead after respite")
	director.reset_run("abyss")
	first.state = first.State.PATROL
	second.state = second.State.PATROL
	for step in 7:
		first._set_state(first.State.CHASE)
		second._set_state(second.State.CHASE)
		director.advance(0.18)
	check(first.state == first.State.CHASE and second.state == second.State.CHASE, "abyss allows two concurrent pursuers")
	director.reset_run("survival")
	first.state = first.State.PATROL
	first._set_state(first.State.CHASE)
	director.advance(1.3)
	first._set_state(first.State.CHASE)
	check(first.state == first.State.PATROL, "broken exposure expires its warning instead of banking immediate pursuit")
	# Noise cadence must work for the blind whale, without requiring visual ticks.
	director.reset_run("survival")
	var whale = game.enemies[3]
	whale.state = whale.State.PATROL
	whale.global_position = Vector3(130, -12, 48)
	game.player.global_position = Vector3(140, -12, 48)
	game.player.in_water = true
	whale._refresh_player_properties()
	whale.awareness = 0.9
	for beat in 4:
		whale._noise_cooldown = 0.0
		whale.hear_noise(game.player.global_position, 1.5)
		for tick in 5:
			director.advance(0.17)
	check(whale.state == whale.State.CHASE, "blind whale can gain pursuit with ordinary 0.85 second water-noise cadence")
	# Compare native visual sensing at one fixed visible location, varying only speed.
	first.encounter_director = null
	first.global_position = Vector3(-12, -5, 12)
	first._heading = Vector3.RIGHT
	first.state = first.State.PATROL
	game.player.global_position = Vector3(-5, -5.75, 12)
	game.player.light_on = false
	first._refresh_player_properties()
	await physics_frame
	game.player.velocity = Vector3(2.4, 0, 0)
	first.awareness = 0.0
	first._sense_player(0.16)
	var quiet_gain: float = first.awareness
	game.player.velocity = Vector3(3.8, 0, 0)
	first.awareness = 0.0
	first._sense_player(0.16)
	check(quiet_gain > 0.0 and quiet_gain < first.awareness * 0.65, "normal 2.4m/s unlit swimming builds awareness slower than sprint swimming")
	# Isolated native collider tests hearing transmission at the same source distance.
	first.global_position = Vector3(500, -5, 500)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(512, -5, 500)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 10, 10)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	first.state = first.State.PATROL
	first._noise_cooldown = 0.0
	first.hear_noise(Vector3(525, -5, 500), 1.0)
	check(first.state == first.State.PATROL, "real concrete collider attenuates distant sound below hearing range")
	wall.queue_free()
	await physics_frame
	await physics_frame
	first._noise_cooldown = 0.0
	first.hear_noise(Vector3(525, -5, 500), 1.0)
	check(first.state == first.State.INVESTIGATE, "same noise without collider triggers investigation")
	first.encounter_director = director
	var hunter = game.enemies[5]
	hunter.state = hunter.State.CHASE
	hunter._seen = false
	hunter._quiet = 0.0
	hunter.hear_noise(hunter.global_position + Vector3(1, 0, 0), 1.2)
	check(hunter.state == hunter.State.INVESTIGATE and hunter._windup < 0.0, "loud decoy redirects hunter after line of sight is lost")
	# Real pause semantics: director inherits PAUSABLE even though game is ALWAYS.
	director.set_physics_process(true)
	paused = true
	var clock_before: float = director._clock
	for step in 5:
		await process_frame
	check(director._clock == clock_before, "pause freezes warning and respite clocks")
	paused = false
	game.start_run()
	check(director._active.is_empty() and director._pending.is_empty() and director._recent.is_empty(), "retry clears reservations and all cooldowns")
	check(director._clock == 0.0 and director._rest_until == 0.0, "retry starts fresh simulation time")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("ENCOUNTER TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
