extends CharacterBody3D
## Shared player controller for the mouse-scale slice.
## Every knob that affects feel is exported so it can be tuned in the inspector
## while the game runs, without touching this script.

@export_group("Movement")
## Ground speed when walking (metres/second). The character is ~0.3 m tall.
@export var walk_speed: float = 1.5
## Ground speed while the run action is held.
@export var run_speed: float = 3.0
## How fast velocity ramps up toward the target speed. Higher feels snappier.
@export var acceleration: float = 10.0
## How fast velocity bleeds off when no input is held. Higher stops sooner.
@export var friction: float = 12.0
## Downward acceleration. Lower feels floatier.
@export var gravity: float = 9.8
## Upward velocity of the small hop. Keep it low, this is not a platformer.
@export var jump_velocity: float = 2.0

@export_group("Camera")
## Distance from the player along the camera's line to the ground.
@export var camera_distance: float = 4.0
## Pitch of the camera in degrees. Negative looks down at the player.
@export var camera_angle_deg: float = -55.0
## How quickly the camera eases toward the player. Higher is stiffer.
@export var camera_follow_smoothing: float = 8.0

@onready var _mesh: Node3D = $Mesh
@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	# The camera lives in world space so it trails the player smoothly instead of
	# being rigidly welded to the body.
	_camera.top_level = true
	_snap_camera()

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_move(delta)
	move_and_slide()
	_face_move_direction(delta)
	_follow_with_camera(delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

func _handle_jump() -> void:
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

func _handle_move(delta: float) -> void:
	# Input maps to world axes; the camera has no yaw, so "forward" is always -Z
	# (away from the camera, toward the exit side of the room).
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
	if direction.length() > 1.0:
		direction = direction.normalized()

	var target_speed: float = run_speed if Input.is_action_pressed("run") else walk_speed
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if direction != Vector3.ZERO:
		horizontal = horizontal.move_toward(direction * target_speed, acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

func _face_move_direction(delta: float) -> void:
	# Turn the visual mesh toward travel. The capsule is round so this is invisible
	# now, but it gives the future art a facing to inherit.
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > 0.05:
		var target_yaw: float = atan2(horizontal.x, horizontal.z)
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_yaw, 12.0 * delta)

func _camera_offset() -> Vector3:
	# Convert distance + pitch into a fixed offset behind and above the player.
	var pitch: float = deg_to_rad(camera_angle_deg)
	var back: float = camera_distance * cos(pitch)
	var up: float = -camera_distance * sin(pitch)
	return Vector3(0.0, up, back)

func _snap_camera() -> void:
	_camera.global_position = global_position + _camera_offset()
	_camera.look_at(global_position, Vector3.UP)

func _follow_with_camera(delta: float) -> void:
	var target: Vector3 = global_position + _camera_offset()
	var weight: float = clamp(camera_follow_smoothing * delta, 0.0, 1.0)
	_camera.global_position = _camera.global_position.lerp(target, weight)
	_camera.look_at(global_position, Vector3.UP)
