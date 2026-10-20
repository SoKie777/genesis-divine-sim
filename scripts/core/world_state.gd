class_name WorldState
extends RefCounted
## État persistant complet et sérialisable du monde simulé.
## Totalement découplé du rendu graphique pour garantir l'autonomie,
## la performance headless et la fiabilité des sauvegardes.

const SCHEMA_VERSION: int = 1

# Métadonnées du monde et configuration de partie
var world_name: String = "Aethelgard"
var world_seed: int = 424242
var scenario_id: String = "TRIBAL_DAWN"
var width: int = 48
var height: int = 36

# Horloge déterministe
var current_tick: int = 0
var year: int = 1
var month: int = 1 # 1..12
var day: int = 1   # 1..30
var season: String = "Printemps" # Printemps, Été, Automne, Hiver
var era_name: String = "Âge de l'Aube"

# Compteurs d'identifiants uniques stables
var _next_species_id: int = 1
var _next_settlement_id: int = 1
var _next_civ_id: int = 1
var _next_individual_id: int = 1
var _next_religion_id: int = 1
var _next_army_id: int = 1
var _next_treaty_id: int = 1
var _next_prayer_id: int = 1
var _next_event_id: int = 1
var _next_spirit_id: int = 1

# Lois de la nature (modifiables en temps réel par le joueur)
var natural_laws: Dictionary = {
	"lifespan_multiplier": 1.0,
	"resource_regen_multiplier": 1.0,
	"climate_volatility": 1.0,
	"magic_enabled": true,
	"prophetic_dreams_enabled": true,
	"mortality_can_transcend": true,
	"fertility_global_modifier": 1.0,
	"conflict_propensity": 1.0
}

# Grille spatiale (index = y * width + x)
var tiles: Array[Dictionary] = []

# Entités du monde indexées par ID entier stable
var species: Dictionary = {}        # int -> Dictionary (SpeciesData)
var settlements: Dictionary = {}    # int -> Dictionary (SettlementData)
var civilizations: Dictionary = {}  # int -> Dictionary (CivilizationData)
var individuals: Dictionary = {}    # int -> Dictionary (IndividualData)
var religions: Dictionary = {}      # int -> Dictionary (ReligionData)
var armies: Dictionary = {}         # int -> Dictionary (ArmyData)
var treaties: Dictionary = {}       # int -> Dictionary (TreatyData)
var prayers: Dictionary = {}        # int -> Dictionary (PrayerData)
var spiritual_entities: Dictionary = {} # int -> Dictionary (SpiritualEntityData)

#Journal historique causal et statistiques séculaires
var events: Array[Dictionary] = []
var divine_actions: Array[Dictionary] = []
var history_snapshots: Array[Dictionary] = [] # Courbes temporelles pour comparaison
var diagnostic_logs: Array[Dictionary] = []   # Causes explicites des décisions d'IA

# Caravanes commerciales physiques et portails cosmologiques (Phases 2 & 7)
var caravans: Array[Dictionary] = []
var portals: Array[Dictionary] = []

# Effets visuels éphémères (non bloquants pour la simulation, lus par le renderer)
var visual_pulses: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []


func allocate_species_id() -> int:
	var id: int = _next_species_id
	_next_species_id += 1
	return id


func allocate_settlement_id() -> int:
	var id: int = _next_settlement_id
	_next_settlement_id += 1
	return id


func allocate_civ_id() -> int:
	var id: int = _next_civ_id
	_next_civ_id += 1
	return id


func allocate_individual_id() -> int:
	var id: int = _next_individual_id
	_next_individual_id += 1
	return id


func allocate_religion_id() -> int:
	var id: int = _next_religion_id
	_next_religion_id += 1
	return id


func allocate_army_id() -> int:
	var id: int = _next_army_id
	_next_army_id += 1
	return id


func allocate_treaty_id() -> int:
	var id: int = _next_treaty_id
	_next_treaty_id += 1
	return id


func allocate_prayer_id() -> int:
	var id: int = _next_prayer_id
	_next_prayer_id += 1
	return id


func allocate_event_id() -> int:
	var id: int = _next_event_id
	_next_event_id += 1
	return id


func allocate_spirit_id() -> int:
	var id: int = _next_spirit_id
	_next_spirit_id += 1
	return id


func is_valid_coord(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func get_tile_index(x: int, y: int) -> int:
	return y * width + x


func get_tile(x: int, y: int) -> Dictionary:
	if not is_valid_coord(x, y):
		return {}
	return tiles[y * width + x]


func get_neighbors(x: int, y: int, radius: int = 1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if is_valid_coord(nx, ny):
				result.append(tiles[ny * width + nx])
	return result


func add_visual_pulse(x: int, y: int, color: Color, radius: float, label: String = "") -> void:
	visual_pulses.append({
		"x": x,
		"y": y,
		"color": color,
		"radius": radius,
		"label": label,
		"ttl": 1.8
	})


func add_floating_text(x: int, y: int, text: String, color: Color = Color(1.0, 0.95, 0.65)) -> void:
	if floating_texts.size() > 40:
		floating_texts.pop_front()
	floating_texts.append({
		"x": float(x),
		"y": float(y),
		"text": text,
		"color": color,
		"ttl": 2.4,
		"max_ttl": 2.4
	})


func record_diagnostic(system_name: String, subject: String, decision: String, causal_factors: Array) -> void:
	diagnostic_logs.push_front({
		"tick": current_tick,
		"year": year,
		"season": season,
		"system": system_name,
		"subject": subject,
		"decision": decision,
		"causal_factors": causal_factors.duplicate()
	})
	if diagnostic_logs.size() > 160:
		diagnostic_logs.resize(160)


func record_historical_event(
	category: String,
	title: String,
	objective_truth: String,
	causal_factors: Array,
	consequences: Array,
	x: int,
	y: int,
	involved_civs: Array = [],
	involved_individuals: Array = [],
	is_divine_origin: bool = false,
	interpretations: Dictionary = {}
) -> Dictionary:
	var ev_id: int = allocate_event_id()
	var ev: Dictionary = {
		"id": ev_id,
		"tick": current_tick,
		"year": year,
		"month": month,
		"season": season,
		"category": category,
		"title": title,
		"objective_truth": objective_truth,
		"causal_factors": causal_factors.duplicate(),
		"consequences": consequences.duplicate(),
		"interpretations": interpretations.duplicate(true),
		"tile_x": x,
		"tile_y": y,
		"involved_civs": involved_civs.duplicate(),
		"involved_individuals": involved_individuals.duplicate(),
		"is_divine_origin": is_divine_origin
	}
	events.push_front(ev)
	if events.size() > 400:
		events.resize(400)
	return ev


func get_total_population() -> int:
	var total: int = 0
	for s_id in settlements.keys():
		var s: Dictionary = settlements[s_id]
		if s.get("tier", "RUIN") != "RUIN":
			total += int(s.get("population", 0))
	return total


func get_active_civ_count() -> int:
	var count: int = 0
	for c_id in civilizations.keys():
		if bool(civilizations[c_id].get("alive", false)):
			count += 1
	return count


func get_active_religion_count() -> int:
	var count: int = 0
	for r_id in religions.keys():
		if int(religions[r_id].get("total_believers", 0)) > 0:
			count += 1
	return count


func get_pending_prayers_count() -> int:
	var count: int = 0
	for p_id in prayers.keys():
		if prayers[p_id].get("status", "") == "PENDING":
			count += 1
	return count


func get_active_wars_count() -> int:
	var pairs: Dictionary = {}
	for c_id in civilizations.keys():
		var civ: Dictionary = civilizations[c_id]
		if not bool(civ.get("alive", false)):
			continue
		var diplo: Dictionary = civ.get("diplomacy", {})
		for other_id in diplo.keys():
			if diplo[other_id].get("stance", "NEUTRAL") == "WAR":
				var a: int = mini(int(c_id), int(other_id))
				var b: int = maxi(int(c_id), int(other_id))
				pairs["%d_%d" % [a, b]] = true
	return pairs.size()


func get_global_ecology_health() -> float:
	if tiles.is_empty():
		return 1.0
	var sum_health: float = 0.0
	var land_count: int = 0
	for t in tiles:
		if float(t.get("elevation", 0.0)) >= 0.0:
			land_count += 1
			var fert: float = float(t.get("fertility", 0.5))
			var poll: float = float(t.get("pollution", 0.0))
			sum_health += clampf(fert * (1.0 - poll), 0.0, 1.0)
	if land_count == 0:
		return 1.0
	return clampf(sum_health / float(land_count), 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"world_name": world_name,
		"world_seed": world_seed,
		"scenario_id": scenario_id,
		"width": width,
		"height": height,
		"current_tick": current_tick,
		"year": year,
		"month": month,
		"day": day,
		"season": season,
		"era_name": era_name,
		"counters": {
			"species": _next_species_id,
			"settlement": _next_settlement_id,
			"civ": _next_civ_id,
			"individual": _next_individual_id,
			"religion": _next_religion_id,
			"army": _next_army_id,
			"treaty": _next_treaty_id,
			"prayer": _next_prayer_id,
			"event": _next_event_id,
			"spirit": _next_spirit_id
		},
		"natural_laws": natural_laws.duplicate(true),
		"tiles": tiles.duplicate(true),
		"species": _serialize_int_dict(species),
		"settlements": _serialize_int_dict(settlements),
		"civilizations": _serialize_int_dict(civilizations),
		"individuals": _serialize_int_dict(individuals),
		"religions": _serialize_int_dict(religions),
		"armies": _serialize_int_dict(armies),
		"treaties": _serialize_int_dict(treaties),
		"prayers": _serialize_int_dict(prayers),
		"spiritual_entities": _serialize_int_dict(spiritual_entities),
		"events": events.duplicate(true),
		"divine_actions": divine_actions.duplicate(true),
		"history_snapshots": history_snapshots.duplicate(true),
		"diagnostic_logs": diagnostic_logs.duplicate(true),
		"caravans": caravans.duplicate(true),
		"portals": portals.duplicate(true)
	}


func from_dict(data: Dictionary) -> void:
	world_name = String(data.get("world_name", "Aethelgard"))
	world_seed = int(data.get("world_seed", 424242))
	scenario_id = String(data.get("scenario_id", "TRIBAL_DAWN"))
	width = int(data.get("width", 48))
	height = int(data.get("height", 36))
	current_tick = int(data.get("current_tick", 0))
	year = int(data.get("year", 1))
	month = int(data.get("month", 1))
	day = int(data.get("day", 1))
	season = String(data.get("season", "Printemps"))
	era_name = String(data.get("era_name", "Âge de l'Aube"))

	var counters: Dictionary = data.get("counters", {})
	_next_species_id = int(counters.get("species", 1))
	_next_settlement_id = int(counters.get("settlement", 1))
	_next_civ_id = int(counters.get("civ", 1))
	_next_individual_id = int(counters.get("individual", 1))
	_next_religion_id = int(counters.get("religion", 1))
	_next_army_id = int(counters.get("army", 1))
	_next_treaty_id = int(counters.get("treaty", 1))
	_next_prayer_id = int(counters.get("prayer", 1))
	_next_event_id = int(counters.get("event", 1))
	_next_spirit_id = int(counters.get("spirit", 1))

	var saved_laws: Dictionary = data.get("natural_laws", {})
	for k in saved_laws.keys():
		natural_laws[k] = saved_laws[k]

	tiles.clear()
	for raw_tile in data.get("tiles", []):
		tiles.append(raw_tile)

	species = _deserialize_int_dict(data.get("species", {}))
	settlements = _deserialize_int_dict(data.get("settlements", {}))
	civilizations = _deserialize_int_dict(data.get("civilizations", {}))
	individuals = _deserialize_int_dict(data.get("individuals", {}))
	religions = _deserialize_int_dict(data.get("religions", {}))
	armies = _deserialize_int_dict(data.get("armies", {}))
	treaties = _deserialize_int_dict(data.get("treaties", {}))
	prayers = _deserialize_int_dict(data.get("prayers", {}))
	spiritual_entities = _deserialize_int_dict(data.get("spiritual_entities", {}))

	events.clear()
	for ev in data.get("events", []):
		events.append(ev)

	divine_actions.clear()
	for act in data.get("divine_actions", []):
		divine_actions.append(act)

	history_snapshots.clear()
	for snap in data.get("history_snapshots", []):
		history_snapshots.append(snap)

	diagnostic_logs.clear()
	for diag in data.get("diagnostic_logs", []):
		diagnostic_logs.append(diag)

	caravans.clear()
	for c in data.get("caravans", []):
		caravans.append(c)

	portals.clear()
	for p in data.get("portals", []):
		portals.append(p)


func _serialize_int_dict(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in src.keys():
		var item: Dictionary = src[k].duplicate(true)
		if item.has("color") and item["color"] is Color:
			var c: Color = item["color"]
			item["color"] = {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
		out[str(k)] = item
	return out


func _deserialize_int_dict(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in src.keys():
		var int_key: int = int(str(k))
		var item: Dictionary = src[k].duplicate(true)
		if item.has("color") and item["color"] is Dictionary:
			var cd: Dictionary = item["color"]
			item["color"] = Color(
				float(cd.get("r", 1.0)),
				float(cd.get("g", 1.0)),
				float(cd.get("b", 1.0)),
				float(cd.get("a", 1.0))
			)
		# Normalisation des clés entières dans les sous-dictionnaires diplomatiques et religieux
		if item.has("diplomacy") and item["diplomacy"] is Dictionary:
			var norm_diplo: Dictionary = {}
			for dk in item["diplomacy"].keys():
				norm_diplo[int(str(dk))] = item["diplomacy"][dk]
			item["diplomacy"] = norm_diplo
		if item.has("religious_composition") and item["religious_composition"] is Dictionary:
			var norm_rel: Dictionary = {}
			for rk in item["religious_composition"].keys():
				norm_rel[int(str(rk))] = float(item["religious_composition"][rk])
			item["religious_composition"] = norm_rel
		if item.has("relationships") and item["relationships"] is Dictionary:
			var norm_rel_ind: Dictionary = {}
			for ik in item["relationships"].keys():
				norm_rel_ind[int(str(ik))] = float(item["relationships"][ik])
			item["relationships"] = norm_rel_ind
		out[int_key] = item
	return out
