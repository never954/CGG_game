extends Node
## Input map, registered at startup so every binding lives in one readable place.
## Keyboard and gamepad are both supported. (Project > Project Settings > Input Map
## shows the same actions inside the editor while the game runs.)

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE],
	"attack": [KEY_J],
	"heavy": [KEY_L],
	"block": [KEY_K],
	"dodge": [KEY_SHIFT],
	"interact": [KEY_E],
	"special": [KEY_U, KEY_I],
	"pause": [KEY_ESCAPE, KEY_P],
}

const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"attack": [JOY_BUTTON_X],
	"heavy": [JOY_BUTTON_Y],
	"dodge": [JOY_BUTTON_B],
	"block": [JOY_BUTTON_RIGHT_SHOULDER],
	"interact": [JOY_BUTTON_LEFT_SHOULDER],
	"special": [JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_BACK],
	"pause": [JOY_BUTTON_START],
}

const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}


func _ready() -> void:
	for action: String in KEYS:
		_ensure(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
	for action: String in PAD_BUTTONS:
		_ensure(action)
		for button in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button as JoyButton
			InputMap.action_add_event(action, ev)
	for action: String in PAD_AXES:
		_ensure(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = int(PAD_AXES[action][0]) as JoyAxis
		ev.axis_value = float(PAD_AXES[action][1])
		InputMap.action_add_event(action, ev)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
