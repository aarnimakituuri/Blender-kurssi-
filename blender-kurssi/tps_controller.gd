extends CharacterBody3D

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $Camera3D

@export var speed: float = 5.0
@export var sprint_multiplier: float = 2.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 10.0
@export var strafe: bool = false
@export var push_force: float = 3.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var mouse_sensitivity: float = 0.003
@export var keyboard_look_speed_deg: float = 120.0
@export var camera_distance: float = 6.0
@export var camera_height: float = 2.0
@export var min_pitch_deg: float = -60.0
@export var max_pitch_deg: float = 70.0
@export var zoom_step: float = 0.5
@export var min_camera_distance: float = 2.0
@export var max_camera_distance: float = 12.0

var camera_yaw: float = 0.0
var camera_pitch: float = deg_to_rad(2.0)

var is_jumping: bool = false

var _actions_down: Dictionary = {}

const TRACKED_ACTIONS := [
	"move_forward", "move_backwards", "move_left", "move_right", "action",
	"move_fast",
	"ui_left", "ui_right", "ui_up", "ui_down",
]

const DEFAULT_ACTION_KEYS := {
	"move_forward": KEY_W,
	"move_backwards": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"move_fast": KEY_SHIFT,
	"jump": KEY_SPACE,
	"action": KEY_F
}


func _ensure_default_action(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)


func _ready() -> void:
	for action in DEFAULT_ACTION_KEYS:
		_ensure_default_action(action, DEFAULT_ACTION_KEYS[action])

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if anim_player.has_animation("Walk"):
		anim_player.get_animation("Walk").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("Run"):
		anim_player.get_animation("Run").loop_mode = Animation.LOOP_LINEAR

	if anim_player.has_animation("Jump"):
		anim_player.get_animation("Jump").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("Push"):
		anim_player.get_animation("Push").loop_mode = Animation.LOOP_NONE

	anim_player.animation_finished.connect(_on_animation_finished)

	_update_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_actions_down.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * mouse_sensitivity
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

	for action in TRACKED_ACTIONS:
		if InputMap.has_action(action) and event.is_action(action):
			_actions_down[action] = event.is_pressed()

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_actions_down.clear()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clamp(camera_distance - zoom_step, min_camera_distance, max_camera_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clamp(camera_distance + zoom_step, min_camera_distance, max_camera_distance)


func _is_action_down(action: String) -> bool:
	return _actions_down.get(action, false)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_play_once("Jump")

	var input_forward := 0.0
	if _is_action_down("move_forward"):
		input_forward += 1.0
	if _is_action_down("move_backwards"):
		input_forward -= 1.0
	var input_strafe := 0.0
	if _is_action_down("move_right"):
		input_strafe += 1.0
	if _is_action_down("move_left"):
		input_strafe -= 1.0

	var cam_basis := camera.global_transform.basis
	var cam_forward := -cam_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var move_dir := (cam_forward * input_forward + cam_right * input_strafe)
	var current_speed := speed
	if _is_action_down("move_fast"):
		current_speed *= sprint_multiplier

	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed

		var facing_dir := cam_forward if strafe else move_dir
		var target_yaw := atan2(facing_dir.x, facing_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * rotation_speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)

	move_and_slide()

	_push_away_rigid_bodies()


func _push_away_rigid_bodies() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is RigidBody3D:
			var push_dir := -collision.get_normal()
			push_dir.y = 0.0
			collider.apply_central_impulse(push_dir * push_force)


func _process(delta: float) -> void:
	var look_step := deg_to_rad(keyboard_look_speed_deg) * delta
	if _is_action_down("ui_left"):
		camera_yaw += look_step
	if _is_action_down("ui_right"):
		camera_yaw -= look_step
	if _is_action_down("ui_up"):
		camera_pitch += look_step
	if _is_action_down("ui_down"):
		camera_pitch -= look_step
	camera_pitch = clamp(camera_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

	_update_camera()
	_update_animation()


func _update_camera() -> void:
	var pivot: Vector3 = global_position + Vector3.UP * camera_height
	var offset := Vector3(0.0, 0.0, camera_distance)
	offset = offset.rotated(Vector3.RIGHT, camera_pitch)
	offset = offset.rotated(Vector3.UP, camera_yaw)
	camera.global_position = pivot + offset
	camera.look_at(pivot, Vector3.UP)


func _update_animation() -> void:
	if is_jumping:
		return

	if _is_action_down("action"):
		_play_once("Push")
		return

	var is_moving := _is_action_down("move_forward") \
		or _is_action_down("move_backwards") \
		or _is_action_down("move_left") \
		or _is_action_down("move_right")

	if is_moving:
		var movement_animation := "Run" if _is_action_down("move_fast") \
			and anim_player.has_animation("Run") else "Walk"
		if anim_player.current_animation != movement_animation or not anim_player.is_playing():
			anim_player.play(movement_animation)
	else:
		if anim_player.current_animation != "":
			anim_player.stop()


func _play_once(anim_name: String) -> void:
	if anim_name == "Jump":
		is_jumping = true
	anim_player.play(anim_name)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Jump":
		is_jumping = false
