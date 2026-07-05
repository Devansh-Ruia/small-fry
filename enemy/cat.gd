extends CharacterBody3D
## Single patrol cat. Follows a fixed authored path at constant speed and spots
## the player with a forward vision cone plus line-of-sight. It never leaves the
## path to chase: detection is the only interaction. On caught it resets the
## player to the respawn point. Audio is signals only, no playback here.

## Emitted once when the player first enters sight (unseen to seen).
signal spotted
## Emitted when the grace window elapses while the player is still seen.
signal caught
## Emitted every physics frame with the current cat-to-player distance.
signal distance_changed(distance: float)

@export_group("Patrol")
## Constant speed along the path, metres/second.
@export var patrol_speed: float = 1.2
## The Path3D whose curve this cat loops along. Authored per room.
@export var patrol_path: NodePath

@export_group("Vision")
## Maximum sight distance, metres.
@export var vision_range: float = 5.0
## Full width of the forward cone, degrees. Half of this is the edge angle.
@export var vision_angle_deg: float = 60.0
## Seconds the player must stay seen before being caught. Break sight or leave
## the cone within this window and they escape.
@export var spotted_grace_seconds: float = 0.4

@export_group("References")
## The player node the cat watches for.
@export var target: NodePath
## Marker the player is reset to on caught. A node so it can be moved later.
@export var respawn_point: NodePath

## Ray origin height above the cat origin, roughly its head.
const EYE_HEIGHT: float = 0.4
## Target height on the player, matching the player's camera anchor.
const PLAYER_ANCHOR_HEIGHT: float = 0.15
## Lookahead along the path used to face the direction of travel.
const FACING_LOOKAHEAD: float = 0.2

@onready var _path: Path3D = get_node_or_null(patrol_path) as Path3D
@onready var _player: Node3D = get_node_or_null(target) as Node3D
@onready var _respawn: Node3D = get_node_or_null(respawn_point) as Node3D

# Distance travelled along the baked curve; wraps to loop.
var _offset: float = 0.0
# True while the player is currently within the cone with clear line of sight.
var _seen: bool = false
# Time accumulated while seen this stretch.
var _grace: float = 0.0

func _ready() -> void:
	if _path != null and _path.curve != null:
		# Snap to the start of the path so the first frame is already on it.
		_place_on_path(0.0)

func _physics_process(delta: float) -> void:
	_patrol(delta)
	_update_vision(delta)

func _patrol(delta: float) -> void:
	if _path == null or _path.curve == null:
		return
	var length: float = _path.curve.get_baked_length()
	if length <= 0.0:
		return
	_offset = fmod(_offset + patrol_speed * delta, length)
	_place_on_path(_offset)

func _place_on_path(offset: float) -> void:
	var length: float = _path.curve.get_baked_length()
	global_position = _path.to_global(_path.curve.sample_baked(offset))
	# Face a point slightly ahead so the cone points along travel. Wrap the
	# lookahead so it stays valid across the loop seam.
	var ahead: float = fmod(offset + FACING_LOOKAHEAD, length)
	var ahead_point: Vector3 = _path.to_global(_path.curve.sample_baked(ahead))
	if global_position.distance_to(ahead_point) > 0.001:
		look_at(ahead_point, Vector3.UP)

func _update_vision(delta: float) -> void:
	if _player == null:
		return
	var eye: Vector3 = global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	var target_point: Vector3 = _player.global_position + Vector3(0.0, PLAYER_ANCHOR_HEIGHT, 0.0)
	var to_player: Vector3 = target_point - eye
	var distance: float = to_player.length()
	distance_changed.emit(distance)

	var sees: bool = _can_see(eye, target_point, to_player, distance)
	if sees:
		if not _seen:
			_seen = true
			_grace = 0.0
			spotted.emit()
		_grace += delta
		if _grace >= spotted_grace_seconds:
			_catch()
	elif _seen:
		# Lost sight before the grace elapsed: the player escaped.
		_seen = false
		_grace = 0.0

func _can_see(eye: Vector3, target_point: Vector3, to_player: Vector3, distance: float) -> bool:
	if distance > vision_range or distance <= 0.0:
		return false
	# Inside the cone: angle between forward (-Z) and the player direction.
	var forward: Vector3 = -global_transform.basis.z
	var dir: Vector3 = to_player / distance
	if forward.dot(dir) < cos(deg_to_rad(vision_angle_deg) * 0.5):
		return false
	# Clear line of sight: walls and furniture (layer 1) block the ray.
	var query := PhysicsRayQueryParameters3D.create(eye, target_point)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == _player

func _catch() -> void:
	if _player != null and _respawn != null:
		_player.global_position = _respawn.global_position
		if _player is CharacterBody3D:
			_player.velocity = Vector3.ZERO
	caught.emit()
	# Re-arm so the cat can catch again on the next patrol pass.
	_seen = false
	_grace = 0.0
