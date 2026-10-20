class_name DeterministicRNG
extends RefCounted
## Générateur pseudo-aléatoire déterministe multi-canal.
## Sépare les flux aléatoires par système (terrain, climat, écologie, société, religion, géopolitique)
## afin de garantir la reproductibilité complète d'un monde à partir de sa graine (seed).

var master_seed: int = 104729
var _streams: Dictionary = {}

const CHANNELS: Array[String] = [
	"terrain",
	"climate",
	"ecology",
	"economy",
	"society",
	"individual",
	"religion",
	"geopolitics",
	"divine"
]


func _init(seed_value: int = 104729) -> void:
	setup(seed_value)


func setup(seed_value: int) -> void:
	master_seed = seed_value
	_streams.clear()
	for i in range(CHANNELS.size()):
		var channel: String = CHANNELS[i]
		var rng := RandomNumberGenerator.new()
		# Dérivation déterministe par canal par hachage arithmétique stable
		var derived_seed: int = abs((seed_value * 1103515245 + (i + 1) * 1234567) % 2147483647)
		if derived_seed == 0:
			derived_seed = (i + 1) * 99991
		rng.seed = derived_seed
		_streams[channel] = rng


func get_rng(channel: String) -> RandomNumberGenerator:
	if not _streams.has(channel):
		var rng := RandomNumberGenerator.new()
		rng.seed = abs(master_seed + channel.hash())
		_streams[channel] = rng
	return _streams[channel]


func randf_channel(channel: String) -> float:
	return get_rng(channel).randf()


func randf_range_channel(channel: String, from_val: float, to_val: float) -> float:
	return get_rng(channel).randf_range(from_val, to_val)


func randi_range_channel(channel: String, from_val: int, to_val: int) -> int:
	return get_rng(channel).randi_range(from_val, to_val)


func pick_random(channel: String, items: Array) -> Variant:
	if items.is_empty():
		return null
	var idx: int = randi_range_channel(channel, 0, items.size() - 1)
	return items[idx]


func to_dict() -> Dictionary:
	var states: Dictionary = {}
	for channel in _streams.keys():
		var rng: RandomNumberGenerator = _streams[channel]
		states[channel] = {
			"seed": str(rng.seed),
			"state": str(rng.state)
		}
	return {
		"master_seed": master_seed,
		"states": states
	}


func from_dict(data: Dictionary) -> void:
	master_seed = int(data.get("master_seed", 104729))
	setup(master_seed)
	var states: Dictionary = data.get("states", {})
	for channel in states.keys():
		if _streams.has(channel):
			var rng: RandomNumberGenerator = _streams[channel]
			var st: Dictionary = states[channel]
			rng.seed = int(st.get("seed", rng.seed))
			rng.state = int(st.get("state", rng.state))
