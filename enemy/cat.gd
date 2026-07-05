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

@export_group("Debug")
## Dev-only vision cone overlay. Off by default so it never shows in a real
## build; toggled at runtime with F1. Reads the live vision values so the drawn
## cone always matches actual detection.
@export var debug_cone_visible: bool = false

## Ray origin height above the cat origin, roughly its head.
const EYE_HEIGHT: float = 0.4
## Target height on the player, matching the player's camera anchor.
const PLAYER_ANCHOR_HEIGHT: float = 0.15
## Lookahead along the path used to face the direction of travel.
const FACING_LOOKAHEAD: float = 0.2

## Debug cone overlay tuning. Segments only affect the drawn mesh, not detection.
const DEBUG_CONE_SEGMENTS: int = 24
## Idle overlay colour, translucent so the scene reads through it.
const DEBUG_CONE_COLOR: Color = Color(0.2, 0.8, 1.0, 0.15)
## Overlay colour while the player is spotted.
const DEBUG_CONE_SPOTTED_COLOR: Color = Color(1.0, 0.25, 0.2, 0.28)

@onready var _path: Path3D = get_node_or_null(patrol_path) as Path3D
@onready var _player: Node3D = get_node_or_null(target) as Node3D
@onready var _respawn: Node3D = get_node_or_null(respawn_point) as Node3D

# Distance travelled along the baked curve; wraps to loop.
var _offset: float = 0.0
# True while the player is currently within the cone with clear line of sight.
var _seen: bool = false
# Time accumulated while seen this stretch.
var _grace: float = 0.0

# Dev-only cone overlay. Built at ready, hidden unless debug_cone_visible.
var _debug_cone: MeshInstance3D = null
var _debug_cone_material: StandardMaterial3D = null

func _ready() -> void:
	if _path != null and _path.curve != null:
		# Snap to the start of the path so the first frame is already on it.
		_place_on_path(0.0)
	_build_debug_cone()
	# Reuse the existing detection signal to tint the overlay when spotted.
	spotted.connect(_on_spotted)

func _physics_process(delta: float) -> void:
	_patrol(delta)
	_update_vision(delta)
	_update_debug_tint()

func _unhandled_input(event: InputEvent) -> void:
	# F1 toggles the dev overlay. No input-map action so it never affects gameplay.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		debug_cone_visible = not debug_cone_visible
		if _debug_cone != null:
			_debug_cone.visible = debug_cone_visible

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

func _build_debug_cone() -> void:
	# Generate a cone matching the detection test: apex at the eye, axis along
	# forward (-Z), slant edges reaching exactly vision_range at the cone rim.
	_debug_cone_material = StandardMaterial3D.new()
	_debug_cone_material.albedo_color = DEBUG_CONE_COLOR
	_debug_cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_cone_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var half: float = deg_to_rad(vision_angle_deg) * 0.5
	var base_dist: float = vision_range * cos(half)
	var base_radius: float = vision_range * sin(half)
	var apex: Vector3 = Vector3.ZERO
	var base_center: Vector3 = Vector3(0.0, 0.0, -base_dist)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(DEBUG_CONE_SEGMENTS):
		var a0: float = TAU * float(i) / float(DEBUG_CONE_SEGMENTS)
		var a1: float = TAU * float(i + 1) / float(DEBUG_CONE_SEGMENTS)
		var p0: Vector3 = Vector3(cos(a0) * base_radius, sin(a0) * base_radius, -base_dist)
		var p1: Vector3 = Vector3(cos(a1) * base_radius, sin(a1) * base_radius, -base_dist)
		# Side face and base cap. Material is double-sided, so winding is irrelevant.
		st.add_vertex(apex)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(base_center)
		st.add_vertex(p1)
		st.add_vertex(p0)

	_debug_cone = MeshInstance3D.new()
	_debug_cone.name = "DebugVisionCone"
	_debug_cone.mesh = st.commit()
	_debug_cone.material_override = _debug_cone_material
	# Same origin as the sight ray so the drawn cone lines up with detection.
	_debug_cone.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	_debug_cone.visible = debug_cone_visible
	add_child(_debug_cone)

func _on_spotted() -> void:
	# Tint red the moment the player is first seen.
	if _debug_cone_material != null:
		_debug_cone_material.albedo_color = DEBUG_CONE_SPOTTED_COLOR

func _update_debug_tint() -> void:
	# Revert to the idle colour once sight is lost. Reads _seen only; no gameplay.
	if _debug_cone_material != null and not _seen:
		_debug_cone_material.albedo_color = DEBUG_CONE_COLOR
