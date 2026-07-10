extends Node
## Global audio singleton (autoload). Owns the music loop, the per-room ambient
## bed, fridge hum, and randomized drip, plus a by-name one-shot SFX player on the
## SFX bus. Levels are exported so they can be balanced in the inspector without
## re-editing the audio files.

const MUSIC_STREAM: String = "res://soundtrack/amb+mustest1.mp3"
const AMBIENT_STREAM: String = "res://soundtrack/ambience_test1.mp3"
const FRIDGE_STREAM: String = "res://soundtrack/fridge_1.mp3"
const DRIP_STREAM: String = "res://soundtrack/drip3.mp3"

# One-shot SFX addressable by name, all played on the SFX bus.
const SFX_STREAMS: Dictionary = {
	"tiny_sqz": "res://soundtrack/tiny_sqz.mp3",
}

@export_group("Volumes")
## Music sits low under everything else.
@export var music_volume_db: float = -18.0
@export var ambient_volume_db: float = -8.0
@export var fridge_volume_db: float = -12.0
@export var drip_volume_db: float = -6.0
@export var sfx_volume_db: float = 0.0

@export_group("Drip timing")
## Random gap between drips, in seconds.
@export var drip_min_seconds: float = 8.0
@export var drip_max_seconds: float = 20.0

var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _fridge: AudioStreamPlayer
var _drip: AudioStreamPlayer
var _drip_timer: Timer

func _ready() -> void:
	randomize()
	_music = _make_player(MUSIC_STREAM, "Music", music_volume_db)
	_ambient = _make_player(AMBIENT_STREAM, "Ambient", ambient_volume_db)
	_fridge = _make_player(FRIDGE_STREAM, "Ambient", fridge_volume_db)
	_drip = _make_player(DRIP_STREAM, "Ambient", drip_volume_db)

	_drip_timer = Timer.new()
	_drip_timer.one_shot = true
	_drip_timer.timeout.connect(_on_drip_timeout)
	add_child(_drip_timer)

	# No scene transitions in scope, so each room boots as its own main scene:
	# starting at boot is the same as starting on room load.
	start_music()
	start_room_ambient()

func _make_player(stream_path: String, bus: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(stream_path)
	p.bus = bus
	p.volume_db = volume_db
	add_child(p)
	return p

func start_music() -> void:
	if not _music.playing:
		_music.play()

func stop_music() -> void:
	_music.stop()

func start_room_ambient() -> void:
	if not _ambient.playing:
		_ambient.play()
	if not _fridge.playing:
		_fridge.play()
	_drip_timer.start(randf_range(drip_min_seconds, drip_max_seconds))

func stop_room_ambient() -> void:
	_ambient.stop()
	_fridge.stop()
	_drip.stop()
	_drip_timer.stop()

func _on_drip_timeout() -> void:
	_drip.play()
	# Reschedule the next drip at a fresh random interval.
	_drip_timer.start(randf_range(drip_min_seconds, drip_max_seconds))

func play_sfx(sfx_name: String) -> void:
	if not SFX_STREAMS.has(sfx_name):
		push_warning("play_sfx: unknown sfx '%s'" % sfx_name)
		return
	# Transient player so overlapping one-shots do not cut each other off.
	var p := AudioStreamPlayer.new()
	p.stream = load(SFX_STREAMS[sfx_name])
	p.bus = "SFX"
	p.volume_db = sfx_volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
