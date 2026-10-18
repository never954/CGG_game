extends Node3D
## Runs one level: builds it from its map, puts the hunter at the start (or at the
## last shrine lit, when continuing), points the camera, plays the story, and handles
## death, memories, the exit, the final boss and the ending.
## Reachable by other nodes through the "game" group.

const PLAYER := preload("res://scenes/actors/player.tscn")
const TITLE_SCENE := "res://scenes/ui/title.tscn"

@onready var level: LevelBuilder = $Level
@onready var rig: CameraRig = $CameraRig
@onready var hud: Hud = $Hud
@onready var dialogue: DialogueBox = $Dialogue
@onready var menus: Menus = $Menus

var player: Player
var story: Dictionary = {}
var _hints: Array = []
var _boss: Enemy
var _boss_met := false
var _ending := false


func _ready() -> void:
	add_to_group("game")
	get_tree().paused = false
	Engine.time_scale = 1.0
	story = DialogueBox.load_story()

	level.level_index = GameState.level
	level.build()
	rig.level_bounds = level.bounds
	rig.set_motes_color(level.theme["motes"])

	player = PLAYER.instantiate()
	player.position = _start_position()
	add_child(player)
	player.died.connect(_on_player_died)
	rig.set_target(player)

	menus.retry.connect(_retry)
	menus.continue_next.connect(_next_level)
	menus.quit_to_title.connect(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	menus.can_pause = func() -> bool: return not dialogue.is_open() and player.state != Player.State.DEAD

	for e in get_tree().get_nodes_in_group("enemy"):
		if e is ToadKing:
			_boss = e

	Audio.music(level.theme["music"])
	var info := _level_info()
	hud.show_title(str(info.get("name", "")), str(info.get("subtitle", "")))
	_hints = (story.get("hints", {}) as Dictionary).get(str(GameState.level), []).duplicate()
	if GameState.checkpoint < 0:
		get_tree().create_timer(1.6, false).timeout.connect(talk.bind("level_%d_intro" % GameState.level))


func _start_position() -> Vector3:
	var at := level.spawn_point
	for s in level.shrines:
		if s.get("index") <= GameState.checkpoint:
			s.call("set_lit")
			at = s.global_position + Vector3(1.2, 0.0, 0.0)
	return at


func _level_info() -> Dictionary:
	var levels: Array = story.get("levels", [])
	return levels[GameState.level - 1] if GameState.level - 1 < levels.size() else {}


func _process(_delta: float) -> void:
	if player == null or _ending:
		return
	# story hints along the way
	while not _hints.is_empty() and player.global_position.x > float(_hints[0][0]):
		hud.show_hint(str(_hints[0][1]), 4.5)
		_hints.pop_front()
	# fell out of the world
	if player.global_position.y < level.bounds.position.y - 6.0:
		player.drown()
	# the final boss introduces itself
	if _boss != null and not _boss_met and is_instance_valid(_boss) \
			and absf(_boss.global_position.x - player.global_position.x) < 14.0:
		_boss_met = true
		get_tree().call_group("camera", "add_trauma", 0.6)
		Audio.sfx("croak", 6.0, 0.0)
		hud.show_boss("THE TOAD KING", 1.0)
		talk("level_5_boss")


## Play a conversation from story.json; the world waits while it is on screen.
func talk(key: String, then: Callable = Callable()) -> void:
	if not story.has(key):
		if then.is_valid():
			then.call()
		return
	player.set_talking(true)
	get_tree().paused = true
	dialogue.play(key, func() -> void:
		get_tree().paused = false
		player.set_talking(false)
		if then.is_valid():
			then.call())


func memory_found() -> void:
	GameState.recover_memory(GameState.level)
	get_tree().call_group("camera", "add_trauma", 0.35)
	GameState.hitstop(0.5, 0.2)
	talk("level_%d_memory" % GameState.level, func() -> void:
		var power: Variant = (story.get("powers", {}) as Dictionary).get(str(GameState.level))
		if power is Array:                         # each memory returns a power
			hud.show_title(str(power[0]), str(power[1]))
			Audio.sfx("shrine")
			hud.show_hint("Memory recovered. Find the way out of this land.", 6.0)
		else:
			hud.show_hint("Memory recovered. Find the way out of this land.", 4.0))


func level_complete() -> void:
	Audio.sfx("level_clear")
	player.set_talking(true)
	var memories: Array = story.get("memories", [])
	var text := str(memories[GameState.level - 1]) if GameState.level - 1 < memories.size() else ""
	await get_tree().create_timer(0.8).timeout
	menus.show_level_complete(str(_level_info().get("name", "")), text)


func _next_level() -> void:
	if GameState.level >= GameState.LEVEL_COUNT:
		get_tree().change_scene_to_file(TITLE_SCENE)
		return
	GameState.start_level(GameState.level + 1)
	get_tree().reload_current_scene()


func boss_defeated() -> void:
	_ending = true
	GameState.recover_memory(GameState.level)
	Audio.music("music_title")
	await get_tree().create_timer(2.6).timeout
	talk("level_5_memory", func() -> void:
		menus.can_pause = func() -> bool: return false
		menus.show_ending(story.get("ending", [])))


func _on_player_died() -> void:
	GameState.deaths += 1
	GameState.save_game()
	menus.show_game_over()


func _retry() -> void:
	GameState.hp = GameState.MAX_HP
	GameState.keys = 0
	get_tree().reload_current_scene()
