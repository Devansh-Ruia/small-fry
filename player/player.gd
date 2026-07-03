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
## How far the camera sits from the player when the view is unobstructed.
@export var camera_distance: float = 4.0
## Floor on the camera distance. It never pulls closer than this even against a
## wall, so the player can always see enough room ahead to plan a route.
@export var camera_min_distance: float = 2.0
## Pitch of the camera in degrees. Negative looks down at the player.
@export var camera_angle_deg: float = -55.0
## How quickly the camera eases toward the player. Higher is stiffer.
@export var camera_follow_smoothing: float = 8.0

@export_group("Occluder fade")
## Alpha a wall or furniture mesh fades to while it blocks the view.
@export var occluder_alpha: float = 0.5
## How fast meshes fade in/out. Higher is snappier; keep it smooth, not a pop.
@export var occluder_fade_speed: float = 6.0

## Height above the body origin used as the camera anchor and ray target.
const ANCHOR_HEIGHT: float = 0.15
## Gap kept between the camera and a wall it collides with.
const COLLISION_MARGIN: float = 0.1
## Safety cap on the occluder ray loop.
const MAX_OCCLUDER_STEPS: int = 8

@onready var _mesh: Node3D = $Mesh
@onready var _camera: Camera3D = $Camera3D

# Smoothed follow point the camera looks at and orbits.
var _pivot: Vector3 = Vector3.ZERO
# Smoothed camera distance, eased between the min and max so it never snaps.
var _cam_distance: float = 0.0
# Meshes currently faded, mapped to their fade material and live alpha.
var _fading: Dictionary = {}

func _ready() -> void:
	# The camera lives in world space so it trails the player smoothly rather
	# than being rigidly welded to the body.
	_camera.top_level = true
	_pivot = _camera_anchor()
	_cam_distance = camera_distance
	_place_camera()

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_move(delta)
	move_and_slide()
	_face_move_direction(delta)
	_update_camera(delta)
	_update_occluder_fade(delta)

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

func _camera_anchor() -> Vector3:
	return global_position + Vector3(0.0, ANCHOR_HEIGHT, 0.0)

func _camera_dir() -> Vector3:
	# Fixed up-and-back offset from the pitch: no yaw, so framing stays constant.
	var pitch: float = deg_to_rad(camera_angle_deg)
	return Vector3(0.0, -sin(pitch), cos(pitch)).normalized()

func _place_camera() -> void:
	_camera.global_position = _pivot + _camera_dir() * _cam_distance
	_camera.look_at(_pivot, Vector3.UP)

func _update_camera(delta: float) -> void:
	var weight: float = clamp(camera_follow_smoothing * delta, 0.0, 1.0)
	_pivot = _pivot.lerp(_camera_anchor(), weight)

	# Manual collision: cast toward the max-distance camera point and shorten to
	# the hit, but never closer than the min so the room ahead stays visible.
	var dir: Vector3 = _camera_dir()
	var desired: float = camera_distance
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_pivot, _pivot + dir * camera_distance)
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		desired = _pivot.distance_to(hit.get("position")) - COLLISION_MARGIN

	# Guard against a min set larger than the max in the inspector.
	var effective_min: float = min(camera_min_distance, camera_distance)
	var target: float = clamp(desired, effective_min, camera_distance)
	# Ease the distance so it shortens and lengthens smoothly, never snapping.
	_cam_distance = lerp(_cam_distance, target, weight)
	_place_camera()

func _update_occluder_fade(delta: float) -> void:
	# Walk the ray from the camera to the player, collecting every occluder mesh
	# in between so more than one can fade at once.
	var occluding: Dictionary = {}
	var space := get_world_3d().direct_space_state
	var from: Vector3 = _camera.global_position
	var to: Vector3 = _camera_anchor()
	var exclude: Array[RID] = [get_rid()]
	for _i in MAX_OCCLUDER_STEPS:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var node = hit.get("collider")
		if node is Node and node.is_in_group("occluder"):
			occluding[node] = true
		exclude.append(hit.get("rid"))

	# Start tracking any newly-occluding mesh, then move every tracked mesh
	# toward its target alpha (occluders already tracked fade back to opaque).
	for node in occluding:
		if not _fading.has(node):
			_fading[node] = _make_fade(node)
	for node in _fading.keys():
		if not is_instance_valid(node):
			_fading.erase(node)
			continue
		var entry: Dictionary = _fading[node]
		var target: float = occluder_alpha if occluding.has(node) else 1.0
		entry.alpha = move_toward(entry.alpha, target, occluder_fade_speed * delta)
		entry.material.albedo_color.a = entry.alpha
		if entry.alpha >= 0.999 and not occluding.has(node):
			# Fully restored: drop the override so the mesh renders as before.
			node.material_override = null
			_fading.erase(node)

func _make_fade(node: GeometryInstance3D) -> Dictionary:
	# Neutral albedo matches the default CSG greybox look; alpha starts opaque.
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	node.material_override = mat
	return {"material": mat, "alpha": 1.0}
