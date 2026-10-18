class_name ToadKing
extends Brute
## Final boss: the Toad King, high priest of the frog cult and keeper of the last
## memory. A giant brute that also calls hopper frogs to its side.
## PHASE 2 (below half health): it roars, turns red, attacks faster, slams twice in a
## row, charges more often, bluffs its tells and summons three frogs at a time.

const HOPPER := preload("res://scenes/actors/hopper.tscn")

var _summon_cd := 8.0
var _enraged := false


func _ready() -> void:
	base_modulate = Color(1.05, 0.8, 0.85)
	super._ready()


func think(delta: float) -> void:
	if not _enraged and hp <= max_hp / 2:
		_enrage()
	_summon_cd -= delta
	if _summon_cd <= 0.0 and (state == "idle" or state == "walk") and can_see():
		_summon_cd = 7.0 if _enraged else 11.0
		_summon(3 if _enraged else 2)
	super.think(delta)


func _enrage() -> void:
	_enraged = true
	punch_windup *= 0.65
	slam_interval = 2.8
	charge_interval = 3.2
	charge_speed *= 1.25
	move_speed *= 1.35
	slam_chain = 2
	feint_chance = 0.2
	base_modulate = Color(1.35, 0.55, 0.55)
	sprite.modulate = base_modulate
	_summon_cd = 1.0
	Audio.sfx("croak", 8.0, 0.0)
	GameState.hitstop(0.5, 0.3)
	get_tree().call_group("camera", "event", "roar")
	get_tree().call_group("hud", "show_hint", "The Toad King is ENRAGED!", 2.5)


func _summon(count: int) -> void:
	Audio.sfx("croak", 4.0, 0.0)
	get_tree().call_group("camera", "add_trauma", 0.35)
	for i in count:
		var h := HOPPER.instantiate()
		h.position = global_position + Vector3([-3.5, 3.5, 0.0][i % 3], 1.5 + i, 0.0)
		get_parent().add_child(h)


func on_hit() -> void:
	get_tree().call_group("hud", "show_boss", "THE TOAD KING", float(maxi(hp, 0)) / float(max_hp))


func die() -> void:
	super.die()
	get_tree().call_group("hud", "show_boss", "THE TOAD KING", 0.0)
	get_tree().call_group("game", "boss_defeated")
