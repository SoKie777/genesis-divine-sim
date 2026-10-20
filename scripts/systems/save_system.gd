class_name SaveSystem
extends RefCounted
## Système de sauvegarde et de chargement complet, versionné et vérifiable.
## Garantit la persistance des entités, de l'état de l'horloge et des flux RNG déterministes.

const SAVE_DIR: String = "user://saves"


static func ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func get_slot_path(slot_name: String = "slot_1") -> String:
	ensure_save_dir()
	return "%s/%s.json" % [SAVE_DIR, slot_name]


static func save_to_path(file_path: String, state: WorldState, rng: DeterministicRNG) -> Dictionary:
	ensure_save_dir()
	var world_dict: Dictionary = state.to_dict()
	var rng_dict: Dictionary = rng.to_dict()
	var payload: Dictionary = {
		"format": "GENESIS_DIVINE_SAVE",
		"schema_version": WorldState.SCHEMA_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"world": world_dict,
		"rng": rng_dict
	}
	var json_body: String = JSON.stringify(payload)
	var checksum: int = json_body.hash()
	payload["checksum"] = checksum

	var final_json: String = JSON.stringify(payload, "\t")
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Impossible d'ouvrir le fichier en écriture : " + file_path}
	f.store_string(final_json)
	f.close()
	return {
		"ok": true,
		"path": file_path,
		"checksum": checksum,
		"bytes": final_json.length()
	}


static func load_from_path(file_path: String, state: WorldState, rng: DeterministicRNG) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"ok": false, "error": "Fichier de sauvegarde introuvable : " + file_path}

	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Impossible de lire le fichier : " + file_path}
	var content: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "Format JSON invalide ou corrompu."}

	var payload: Dictionary = parsed
	if String(payload.get("format", "")) != "GENESIS_DIVINE_SAVE":
		return {"ok": false, "error": "En-tête de sauvegarde non reconnu."}

	var schema_ver: int = int(payload.get("schema_version", 0))
	if schema_ver != WorldState.SCHEMA_VERSION:
		return {"ok": false, "error": "Version de schéma incompatible (%d != %d)." % [schema_ver, WorldState.SCHEMA_VERSION]}

	state.from_dict(payload.get("world", {}))
	rng.from_dict(payload.get("rng", {}))

	return {
		"ok": true,
		"path": file_path,
		"year": state.year,
		"world_name": state.world_name
	}
