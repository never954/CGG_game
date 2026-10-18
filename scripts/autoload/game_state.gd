extends Node
## Progress that lives across scenes and play sessions: the current level, the last
## shrine touched, health, spirit orbs, keys and recovered memories. It is saved to
## user://save.cfg whenever something important happens.
## Also owns hit-stop: a brief near-freeze of game time that makes big hits land.

signal changed

const SAVE_PATH := "user://save.cfg"
const LEVEL_COUNT := 5
const MAX_HP := 5
const MAX_STAMINA := 100.0
const MAX_SPIRIT := 100.0

## Powers the hunter gets back with each recovered memory.
const POWERS := {
	1: "vault",          # Staff Vault: a second jump in mid-air
	2: "air_dash",       # Air Dash: Shift in mid-air, cuts through enemies
	3: "spirit_wave",    # Spirit Wave: the heavy smash sends a shockwave along the ground
	4: "koax_blessing",  # Koax's Blessing: the spirit meter fills 50% faster
}

var level: int = 1
var checkpoint: int = -1            ## index of the last shrine lit in this level (-1 = level start)
var hp: int = MAX_HP
var orbs: int = 0
var keys: int = 0
var memories: Array[int] = []       ## levels whose memory eye has been recovered
var deaths: int = 0
var spirit: float = 0.0             ## fills by fighting; full = Moon Breaker special (U)
var best_level: int = 1             ## furthest level reached (chapter select)

var _hitstop_token: int = 0


func new_game() -> void:
	level = 1
	checkpoint = -1
	hp = MAX_HP
	orbs = 0
	keys = 0
	memories.clear()
	deaths = 0
	spirit = 0.0
	save_game()
	changed.emit()


func start_level(n: int) -> void:
	level = n
	best_level = maxi(best_level, n)
	checkpoint = -1
	keys = 0
	hp = MAX_HP
	save_game()
	changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "level", level)
	cf.set_value("progress", "checkpoint", checkpoint)
	cf.set_value("progress", "orbs", orbs)
	cf.set_value("progress", "memories", memories)
	cf.set_value("progress", "deaths", deaths)
	cf.set_value("progress", "best_level", best_level)
	cf.save(SAVE_PATH)


func load_game() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return false
	level = int(cf.get_value("progress", "level", 1))
	checkpoint = int(cf.get_value("progress", "checkpoint", -1))
	orbs = int(cf.get_value("progress", "orbs", 0))
	memories.assign(cf.get_value("progress", "memories", []))
	deaths = int(cf.get_value("progress", "deaths", 0))
	best_level = int(cf.get_value("progress", "best_level", level))
	hp = MAX_HP
	keys = 0
	changed.emit()
	return true


## Chapter select: start level n with the memories (and so the powers) of the levels before it.
func start_chapter(n: int) -> void:
	for i in range(1, n):
		if not memories.has(i):
			memories.append(i)
	spirit = 0.0
	start_level(n)


func has_power(power: String) -> bool:
	for lvl: int in POWERS:
		if POWERS[lvl] == power:
			return memories.has(lvl)
	return false


func add_spirit(amount: float) -> void:
	if amount > 0.0 and has_power("koax_blessing"):
		amount *= 1.5
	spirit = clampf(spirit + amount, 0.0, MAX_SPIRIT)


func add_orbs(n: int) -> void:
	orbs += n
	add_spirit(2.0 * n)
	changed.emit()


func add_key() -> void:
	keys += 1
	changed.emit()


func use_key() -> bool:
	if keys <= 0:
		return false
	keys -= 1
	changed.emit()
	return true


func heal(n: int) -> void:
	hp = mini(MAX_HP, hp + n)
	changed.emit()


func damage(n: int) -> void:
	hp = maxi(0, hp - n)
	changed.emit()


func recover_memory(lvl: int) -> void:
	if not memories.has(lvl):
		memories.append(lvl)
	save_game()
	changed.emit()


func reach_checkpoint(index: int) -> void:
	checkpoint = index
	hp = MAX_HP
	save_game()
	changed.emit()


## Slow the game to `time_scale` for `duration` real seconds. Overlapping calls are
## safe: only the most recent one restores normal speed.
func hitstop(duration: float, time_scale: float = 0.05) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0
