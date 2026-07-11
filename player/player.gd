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

@export_group("Footsteps")
## Volume of the footstep one-shot, in decibels.
@export var footstep_volume_db: float = 0.0
## Seconds between footsteps while moving on the ground.
@export var footstep_interval: float = 0.4
## Horizontal speed below which the player counts as standing still.
@export var footstep_min_speed: float = 0.3

## Height above the body origin used as the camera anchor and ray target.
const ANCHOR_HEIGHT: float = 0.15
## Gap kept between the camera and a wall it collides with.
const COLLISION_MARGIN: float = 0.1

@onready var _mesh: Node3D = $Mesh
@onready var _camera: Camera3D = $Camera3D
@onready var _footstep: AudioStreamPlayer = $Footstep
@onready var _step_timer: Timer = $StepTimer

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

	_footstep.volume_db = footstep_volume_db
	_step_timer.wait_time = footstep_interval
	_step_timer.timeout.connect(_on_step_timer_timeout)

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_move(delta)
	move_and_slide()
	_face_move_direction(delta)
	_update_camera(delta)
	_update_occluder_fade(delta)
	_update_footsteps()

func _update_footsteps() -> void:
	# Footstep cadence: a single step clip retriggered on a timer while the player
	# moves on the ground. Stops the moment they stand still or leave the floor.
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and speed > footstep_min_speed:
		if _step_timer.is_stopped():
			_footstep.play()
			_step_timer.start(footstep_interval)
	else:
		_step_timer.stop()

func _on_step_timer_timeout() -> void:
	_footstep.play()

func _on_squeeze_entered(body: Node3D) -> void:
	# Fired by a room's squeeze Area3D. Only react to this player entering it.
	if body == self:
		AudioManager.play_sfx("tiny_sqz")

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
	# Fade any occluder-group mesh whose bounding box crosses the camera→player
	# line. This is a geometric test, not a physics ray, so collision-less props
	# fade too without the player or the camera ray ever interacting with them.
	var occluding: Dictionary = {}
	var from: Vector3 = _camera.global_position
	var to: Vector3 = _camera_anchor()
	for node in get_tree().get_nodes_in_group("occluder"):
		for mesh in _fade_targets(node):
			if _segment_hits_aabb(mesh, from, to):
				occluding[mesh] = true

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

func _fade_targets(node: Node) -> Array:
	# The meshes to fade for an occluder-group node: the node itself if it renders
	# (CSG walls and furniture), otherwise the mesh instances under a prop scene
	# (glb props whose group tag sits on a plain Node3D root).
	if node is VisualInstance3D:
		return [node]
	return node.find_children("*", "MeshInstance3D", true, false)

func _segment_hits_aabb(vis: VisualInstance3D, from: Vector3, to: Vector3) -> bool:
	# Slab test of the camera→player segment against the mesh's local AABB, done in
	# local space so it handles the props' rotations and scales.
	var inv: Transform3D = vis.global_transform.affine_inverse()
	var a: Vector3 = inv * from
	var b: Vector3 = inv * to
	var box: AABB = vis.get_aabb()
	var d: Vector3 = b - a
	var lo: Vector3 = box.position
	var hi: Vector3 = box.position + box.size
	var tmin: float = 0.0
	var tmax: float = 1.0
	for axis in 3:
		if absf(d[axis]) < 1e-8:
			# Segment parallel to this slab: reject if it starts outside it.
			if a[axis] < lo[axis] or a[axis] > hi[axis]:
				return false
		else:
			var t1: float = (lo[axis] - a[axis]) / d[axis]
			var t2: float = (hi[axis] - a[axis]) / d[axis]
			if t1 > t2:
				var tmp: float = t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return false
	return true
