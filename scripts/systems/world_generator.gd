class_name WorldGenerator
extends RefCounted
## Générateur procédural déterministe d'univers (Géologie, Hydrologie, Biomes, Espèces, Scénarios).

const CIV_PALETTE: Array[Color] = [
	Color(0.92, 0.34, 0.34),
	Color(0.24, 0.68, 0.95),
	Color(0.95, 0.74, 0.22),
	Color(0.32, 0.85, 0.52),
	Color(0.75, 0.44, 0.96),
	Color(0.96, 0.54, 0.24),
	Color(0.25, 0.86, 0.82),
	Color(0.92, 0.42, 0.74)
]

const CIV_PREFIXES: Array[String] = [
	"Aethel", "Sol", "Vael", "Khar", "Thal", "Nym", "Or", "Zul", "Drak", "Elen", "Myr", "Kael"
]
const CIV_SUFFIXES: Array[String] = [
	"gard", "aris", "ia", "heim", "dor", "os", "une", "ath", "ora", "vann", "is", "on"
]

const PERSON_FIRST_NAMES: Array[String] = [
	"Alaric", "Seraphina", "Kaelen", "Lyra", "Theron", "Isolde", "Orin", "Vespera",
	"Cassian", "Elowen", "Darius", "Miriel", "Solon", "Nyxia", "Beren", "Aurelia",
	"Malakor", "Sylvara", "Evander", "Talia", "Zephyr", "Calista", "Gideon", "Astrid"
]
const PERSON_EPITHETS: Array[String] = [
	"l'Éveillé", "le Bâtisseur", "le Juste", "l'Oracle", "le Sage", "le Conquérant",
	"le Pieux", "le Clairvoyant", "des Tempêtes", "du Fleuve", "de l'Aube", "l'Ancien"
]


static func generate_world(state: WorldState, rng: DeterministicRNG, config: Dictionary = {}) -> void:
	state.world_seed = int(config.get("seed", state.world_seed))
	state.world_name = String(config.get("world_name", "Aethelgard"))
	state.scenario_id = String(config.get("scenario_id", "TRIBAL_DAWN"))
	state.width = int(config.get("width", 48))
	state.height = int(config.get("height", 36))
	var initial_tribes: int = int(config.get("initial_tribes", 4))
	var resource_abundance: float = float(config.get("resource_abundance", 1.0))
	var magic_enabled: bool = bool(config.get("magic_enabled", true))

	rng.setup(state.world_seed)

	state.current_tick = 0
	state.year = 1
	state.month = 1
	state.day = 1
	state.season = "Printemps"
	state.era_name = "Âge de la Genèse"

	state.natural_laws["magic_enabled"] = magic_enabled
	state.natural_laws["resource_regen_multiplier"] = clampf(resource_abundance, 0.4, 3.0)

	state.tiles.clear()
	state.species.clear()
	state.settlements.clear()
	state.civilizations.clear()
	state.individuals.clear()
	state.religions.clear()
	state.armies.clear()
	state.treaties.clear()
	state.prayers.clear()
	state.spiritual_entities.clear()
	state.events.clear()
	state.divine_actions.clear()
	state.history_snapshots.clear()
	state.diagnostic_logs.clear()
	state.visual_pulses.clear()

	state._next_species_id = 1
	state._next_settlement_id = 1
	state._next_civ_id = 1
	state._next_individual_id = 1
	state._next_religion_id = 1
	state._next_army_id = 1
	state._next_treaty_id = 1
	state._next_prayer_id = 1
	state._next_event_id = 1
	state._next_spirit_id = 1

	# 1. Bruit procédural déterministe pour l'élévation, l'humidité et la température
	var elev_noise := FastNoiseLite.new()
	elev_noise.seed = state.world_seed
	elev_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev_noise.frequency = 0.055
	elev_noise.fractal_octaves = 4

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = state.world_seed + 1337
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.12

	var moist_noise := FastNoiseLite.new()
	moist_noise.seed = state.world_seed + 7919
	moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moist_noise.frequency = 0.065

	var cx: float = float(state.width) * 0.5
	var cy: float = float(state.height) * 0.5

	for y in range(state.height):
		var lat_norm: float = absf((float(y) - cy) / cy) # 0 à l'équateur, 1 aux pôles
		for x in range(state.width):
			var dx: float = (float(x) - cx) / cx
			var dy: float = (float(y) - cy) / cy
			var edge_dist: float = sqrt(dx * dx * 0.85 + dy * dy * 0.85)
			var island_mask: float = clampf(1.12 - pow(edge_dist, 1.85), -0.7, 1.0)

			var raw_elev: float = elev_noise.get_noise_2d(float(x), float(y)) * 0.78 + detail_noise.get_noise_2d(float(x), float(y)) * 0.22
			var elevation: float = clampf((raw_elev + 0.22) * island_mask - (0.35 if edge_dist > 0.88 else 0.0), -1.0, 1.0)

			var base_temp: float = lerpf(31.0, -14.0, pow(lat_norm, 1.25))
			if elevation > 0.0:
				base_temp -= elevation * 22.0

			var rainfall: float = clampf((moist_noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5, 0.05, 0.98)
			if elevation < 0.0:
				rainfall = 1.0

			var tile: Dictionary = {
				"id": y * state.width + x,
				"x": x,
				"y": y,
				"elevation": elevation,
				"water_table": clampf(rainfall * 0.75 + (0.25 if elevation < 0.08 else 0.0), 0.0, 1.0),
				"has_river": false,
				"temperature": base_temp,
				"rainfall": rainfall,
				"fertility": 0.0,
				"biome": "OCEAN",
				"biomass_flora": 0.0,
				"fauna_species_id": -1,
				"fauna_count": 0,
				"mineral_type": "NONE",
				"mineral_reserve": 0.0,
				"pollution": 0.0,
				"owner_civ_id": -1,
				"settlement_id": -1,
				"sacred_site_id": -1,
				"divine_aura": 0.0
			}
			state.tiles.append(tile)

	# 2. Génération hydrologique : fleuves s'écoulant des montagnes vers la mer
	_carve_rivers(state, rng)

	# 3. Calcul des biomes, de la fertilité et des gisements minéraux
	for i in range(state.tiles.size()):
		var tile: Dictionary = state.tiles[i]
		recompute_tile_biome(tile, true)
		_assign_initial_minerals(tile, rng, resource_abundance, magic_enabled)

	# 4. Création du catalogue initial d'espèces vivantes
	_create_initial_species(state, rng, magic_enabled)

	# 5. Scénario de départ (Tribus, Empires anciens ou Monde vierge)
	if state.scenario_id == "VIRGIN_WORLD":
		initial_tribes = 0
	elif state.scenario_id == "ANCIENT_EMPIRES":
		initial_tribes = maxi(initial_tribes, 5)

	if initial_tribes > 0:
		_spawn_initial_societies(state, rng, initial_tribes)

	if magic_enabled or state.scenario_id == "SUPERNATURAL_AGE":
		_spawn_initial_spirits(state, rng, 3)

	state.record_historical_event(
		"GENESIS",
		"La Genèse d'%s" % state.world_name,
		"Le monde d'%s a émergé du néant sous l'impulsion divine (Graine %d, Scénario %s)." % [
			state.world_name, state.world_seed, state.scenario_id
		],
		["Impulsion créatrice primordiale", "Lois physiques et biologiques établies"],
		["%d espèces vivantes" % state.species.size(), "%d peuples initiaux" % state.civilizations.size()],
		int(state.width / 2),
		int(state.height / 2),
		[],
		[],
		true
	)


static func recompute_tile_biome(tile: Dictionary, initialize_fertility: bool = false) -> void:
	var elev: float = float(tile.get("elevation", 0.0))
	var temp: float = float(tile.get("temperature", 15.0))
	var rain: float = float(tile.get("rainfall", 0.5))
	var has_river: bool = bool(tile.get("has_river", false))

	if elev < -0.22:
		tile["biome"] = "OCEAN"
		if initialize_fertility:
			tile["fertility"] = 0.15
			tile["biomass_flora"] = 10.0
		return
	elif elev < 0.0:
		tile["biome"] = "SHALLOW_WATER"
		if initialize_fertility:
			tile["fertility"] = 0.35
			tile["biomass_flora"] = 22.0
		return

	var river_bonus: float = 0.28 if has_river else 0.0
	var moisture: float = clampf(rain + river_bonus, 0.0, 1.0)
	tile["water_table"] = moisture

	if elev > 0.72:
		if temp > 18.0 and moisture < 0.38:
			tile["biome"] = "VOLCANIC"
			if initialize_fertility:
				tile["fertility"] = 0.30
				tile["biomass_flora"] = 5.0
		else:
			tile["biome"] = "MOUNTAIN"
			if initialize_fertility:
				tile["fertility"] = 0.18
				tile["biomass_flora"] = 12.0
	elif elev < 0.055 and not has_river:
		tile["biome"] = "BEACH"
		if initialize_fertility:
			tile["fertility"] = 0.32
			tile["biomass_flora"] = 18.0
	elif temp < -2.0:
		tile["biome"] = "TUNDRA"
		if initialize_fertility:
			tile["fertility"] = 0.22
			tile["biomass_flora"] = 20.0
	elif moisture < 0.26 and temp > 16.0:
		tile["biome"] = "DESERT"
		if initialize_fertility:
			tile["fertility"] = 0.12 if not has_river else 0.78
			tile["biomass_flora"] = 8.0 if not has_river else 55.0
	elif moisture > 0.76 and elev < 0.25 and temp > 8.0:
		tile["biome"] = "SWAMP"
		if initialize_fertility:
			tile["fertility"] = 0.58
			tile["biomass_flora"] = 75.0
	elif moisture > 0.52 and temp > 2.0:
		tile["biome"] = "FOREST"
		if initialize_fertility:
			tile["fertility"] = clampf(0.68 + river_bonus * 0.5, 0.0, 1.0)
			tile["biomass_flora"] = 80.0
	else:
		tile["biome"] = "PLAINS"
		if initialize_fertility:
			tile["fertility"] = clampf(0.62 + river_bonus * 0.7, 0.0, 1.0)
			tile["biomass_flora"] = 48.0


static func _carve_rivers(state: WorldState, rng: DeterministicRNG) -> void:
	var candidates: Array[Dictionary] = []
	for t in state.tiles:
		if float(t["elevation"]) > 0.48:
			candidates.append(t)
	if candidates.is_empty():
		return

	var num_rivers: int = clampi(int(candidates.size() / 9), 3, 9)
	for _r in range(num_rivers):
		var start_tile: Dictionary = rng.pick_random("terrain", candidates)
		var cx: int = int(start_tile["x"])
		var cy: int = int(start_tile["y"])
		var visited: Dictionary = {}
		for _step in range(36):
			var cur: Dictionary = state.get_tile(cx, cy)
			if cur.is_empty() or float(cur["elevation"]) < 0.0:
				break
			cur["has_river"] = true
			cur["water_table"] = clampf(float(cur["water_table"]) + 0.35, 0.0, 1.0)
			visited[cur["id"]] = true

			var neighbors: Array[Dictionary] = state.get_neighbors(cx, cy, 1)
			var lowest_n: Dictionary = {}
			var lowest_elev: float = float(cur["elevation"]) + 0.05
			for n in neighbors:
				if visited.has(n["id"]):
					continue
				var ne: float = float(n["elevation"])
				if ne < lowest_elev:
					lowest_elev = ne
					lowest_n = n
			if lowest_n.is_empty():
				break
			cx = int(lowest_n["x"])
			cy = int(lowest_n["y"])


static func _assign_initial_minerals(tile: Dictionary, rng: DeterministicRNG, abundance: float, magic_enabled: bool) -> void:
	var elev: float = float(tile["elevation"])
	if elev < 0.0:
		tile["mineral_type"] = "NONE"
		tile["mineral_reserve"] = 0.0
		return

	var roll: float = rng.randf_channel("terrain")
	if elev > 0.55:
		if magic_enabled and roll < 0.08 * abundance:
			tile["mineral_type"] = "AETHERIUM"
			tile["mineral_reserve"] = rng.randf_range_channel("terrain", 180.0, 420.0) * abundance
		elif roll < 0.25 * abundance:
			tile["mineral_type"] = "GOLD"
			tile["mineral_reserve"] = rng.randf_range_channel("terrain", 220.0, 500.0) * abundance
		elif roll < 0.62 * abundance:
			tile["mineral_type"] = "IRON"
			tile["mineral_reserve"] = rng.randf_range_channel("terrain", 350.0, 800.0) * abundance
		else:
			tile["mineral_type"] = "STONE"
			tile["mineral_reserve"] = rng.randf_range_channel("terrain", 500.0, 1100.0) * abundance
	elif elev > 0.22:
		if roll < 0.14 * abundance:
			tile["mineral_type"] = "IRON"
			tile["mineral_reserve"] = rng.randf_range_channel("terrain", 250.0, 600.0) * abundance
		elif roll < 0.36 * abundance:
			tile["mineral_type"] = "STONE"
			tile["mineral_reserve"] = rng.randf_range_channel("terrain", 350.0, 750.0) * abundance


static func _create_initial_species(state: WorldState, rng: DeterministicRNG, magic_enabled: bool) -> void:
	# 1. Humains (Espèce intelligente fondatrice)
	var human_id: int = state.allocate_species_id()
	state.species[human_id] = {
		"id": human_id,
		"name": "Humains",
		"category": "SAPIENT_HUMANOID",
		"is_sapient": true,
		"diet": "OMNIVORE",
		"preferred_temp_min": -5.0,
		"preferred_temp_max": 35.0,
		"base_lifespan_years": 68,
		"reproduction_rate": 0.032,
		"cognitive_capacity": 1.0,
		"social_tendency": 0.9,
		"supernatural_sensitivity": 0.5,
		"domesticated_by_civs": [],
		"total_population": 0,
		"adaptation_traits": ["Polyvalence", "Transmission Culturelle"]
	}

	# 2. Aurochs & Cerfs des Plaines (Grands Herbivores domesticables)
	var herb_id: int = state.allocate_species_id()
	state.species[herb_id] = {
		"id": herb_id,
		"name": "Aurochs des Plaines",
		"category": "MAMMAL",
		"is_sapient": false,
		"diet": "HERBIVORE",
		"preferred_temp_min": -2.0,
		"preferred_temp_max": 30.0,
		"base_lifespan_years": 18,
		"reproduction_rate": 0.08,
		"cognitive_capacity": 0.25,
		"social_tendency": 0.85,
		"supernatural_sensitivity": 0.2,
		"domesticated_by_civs": [],
		"total_population": 0,
		"adaptation_traits": ["Troupeau", "Force de Trait"]
	}

	# 3. Loups Sombres (Prédateurs forestiers)
	var pred_id: int = state.allocate_species_id()
	state.species[pred_id] = {
		"id": pred_id,
		"name": "Loups Cendrés",
		"category": "MAMMAL",
		"is_sapient": false,
		"diet": "CARNIVORE",
		"preferred_temp_min": -18.0,
		"preferred_temp_max": 24.0,
		"base_lifespan_years": 14,
		"reproduction_rate": 0.05,
		"cognitive_capacity": 0.4,
		"social_tendency": 0.75,
		"supernatural_sensitivity": 0.4,
		"domesticated_by_civs": [],
		"total_population": 0,
		"adaptation_traits": ["Meute", "Endurance Hivernale"]
	}

	# 4. Bancs Argentés (Faune aquatique)
	var fish_id: int = state.allocate_species_id()
	state.species[fish_id] = {
		"id": fish_id,
		"name": "Léviathans & Bancs Argentés",
		"category": "AQUATIC",
		"is_sapient": false,
		"diet": "OMNIVORE",
		"preferred_temp_min": -4.0,
		"preferred_temp_max": 32.0,
		"base_lifespan_years": 12,
		"reproduction_rate": 0.11,
		"cognitive_capacity": 0.15,
		"social_tendency": 0.9,
		"supernatural_sensitivity": 0.1,
		"domesticated_by_civs": [],
		"total_population": 0,
		"adaptation_traits": ["Migration Marine"]
	}

	if magic_enabled:
		var spirit_beast_id: int = state.allocate_species_id()
		state.species[spirit_beast_id] = {
			"id": spirit_beast_id,
			"name": "Cerfs Astraux",
			"category": "FANTASTIC",
			"is_sapient": false,
			"diet": "AETHERIC",
			"preferred_temp_min": -20.0,
			"preferred_temp_max": 40.0,
			"base_lifespan_years": 240,
			"reproduction_rate": 0.02,
			"cognitive_capacity": 0.85,
			"social_tendency": 0.5,
			"supernatural_sensitivity": 1.0,
			"domesticated_by_civs": [],
			"total_population": 0,
			"adaptation_traits": ["Aura Sacrée", "Régénération Forestière"]
		}

	# Répartition de la faune sur la carte
	for tile in state.tiles:
		var biome: String = String(tile["biome"])
		var roll: float = rng.randf_channel("ecology")
		if biome in ["OCEAN", "SHALLOW_WATER"] and roll < 0.35:
			tile["fauna_species_id"] = fish_id
			tile["fauna_count"] = rng.randi_range_channel("ecology", 25, 90)
		elif biome == "PLAINS" and roll < 0.42:
			tile["fauna_species_id"] = herb_id
			tile["fauna_count"] = rng.randi_range_channel("ecology", 20, 75)
		elif biome == "FOREST" and roll < 0.45:
			if magic_enabled and roll < 0.07:
				tile["fauna_species_id"] = 5
				tile["fauna_count"] = rng.randi_range_channel("ecology", 6, 18)
			elif roll < 0.25:
				tile["fauna_species_id"] = pred_id
				tile["fauna_count"] = rng.randi_range_channel("ecology", 12, 35)
			else:
				tile["fauna_species_id"] = herb_id
				tile["fauna_count"] = rng.randi_range_channel("ecology", 18, 60)


static func _spawn_initial_societies(state: WorldState, rng: DeterministicRNG, count: int) -> void:
	var fertile_tiles: Array[Dictionary] = []
	for tile in state.tiles:
		var biome: String = String(tile["biome"])
		if biome in ["PLAINS", "FOREST", "BEACH"] and float(tile["fertility"]) >= 0.48:
			fertile_tiles.append(tile)

	if fertile_tiles.is_empty():
		return

	var chosen_coords: Array[Vector2i] = []
	for i in range(count):
		var best_tile: Dictionary = {}
		var best_score: float = -999.0
		for _attempt in range(35):
			var cand: Dictionary = rng.pick_random("society", fertile_tiles)
			var pos := Vector2i(int(cand["x"]), int(cand["y"]))
			var min_dist: float = 999.0
			for existing in chosen_coords:
				min_dist = minf(min_dist, pos.distance_to(existing))
			if min_dist < 7.0:
				continue
			var score: float = float(cand["fertility"]) * 2.0 + (0.6 if bool(cand["has_river"]) else 0.0) + minf(min_dist * 0.08, 1.2)
			if score > best_score:
				best_score = score
				best_tile = cand
		if best_tile.is_empty():
			best_tile = rng.pick_random("society", fertile_tiles)
		chosen_coords.append(Vector2i(int(best_tile["x"]), int(best_tile["y"])))
		found_new_civilization_at(state, rng, int(best_tile["x"]), int(best_tile["y"]), 1, state.scenario_id == "ANCIENT_EMPIRES")


static func found_new_civilization_at(
	state: WorldState,
	rng: DeterministicRNG,
	x: int,
	y: int,
	species_id: int = 1,
	advanced_start: bool = false
) -> Dictionary:
	var tile: Dictionary = state.get_tile(x, y)
	if tile.is_empty() or float(tile["elevation"]) < 0.0:
		return {}

	var civ_id: int = state.allocate_civ_id()
	var prefix: String = String(rng.pick_random("society", CIV_PREFIXES))
	var suffix: String = String(rng.pick_random("society", CIV_SUFFIXES))
	var civ_name: String = prefix + suffix
	var color: Color = CIV_PALETTE[(civ_id - 1) % CIV_PALETTE.size()]

	var way_of_life: String = _determine_origin_way_of_life(state, x, y)
	var gov_type: String = "KINGDOM" if advanced_start else "TRIBE"
	var initial_techs: Array[String] = ["FIRE_MAKING"]
	if way_of_life == "RIVER_AGRICULTURE" or advanced_start:
		initial_techs.append("AGRICULTURE")
	if way_of_life == "MARITIME":
		initial_techs.append("NAVIGATION")
	if way_of_life == "MOUNTAIN_MINING":
		initial_techs.append("POTTERY")
	if advanced_start:
		for t_name in ["POTTERY", "IRRIGATION", "METALLURGY", "WRITING"]:
			if not initial_techs.has(t_name):
				initial_techs.append(t_name)

	var civ: Dictionary = {
		"id": civ_id,
		"name": civ_name,
		"color": color,
		"species_id": species_id,
		"capital_settlement_id": -1,
		"ruler_individual_id": -1,
		"founded_year": state.year,
		"alive": true,
		"origin_way_of_life": way_of_life,
		"government_type": gov_type,
		"legitimacy": 0.82,
		"stability": 0.85,
		"centralization": 0.55 if advanced_start else 0.28,
		"state_religion_id": -1,
		"religious_policy": "PLURALIST",
		"culture": {
			"language_name": "Langue " + prefix + "ienne",
			"architecture_style": _architecture_for_way(way_of_life),
			"core_values": _values_for_way(way_of_life),
			"science_attitude": "COOPERATIVE"
		},
		"technologies": initial_techs,
		"research_progress": {},
		"treasury": 180.0 if advanced_start else 45.0,
		"settlement_ids": [],
		"diplomacy": {},
		"historical_grievances": []
	}
	state.civilizations[civ_id] = civ

	var start_pop: int = 340 if advanced_start else 110
	var settlement: Dictionary = create_settlement(state, rng, civ_id, species_id, x, y, civ_name + "-Prime", start_pop, true)
	civ["capital_settlement_id"] = int(settlement["id"])

	# Création du fondateur / premier dirigeant
	var ruler: Dictionary = spawn_remarkable_individual(
		state, rng, civ_id, int(settlement["id"]), species_id, "RULER", "Fondateur de " + civ_name
	)
	civ["ruler_individual_id"] = int(ruler["id"])

	# Création d'une croyance ancestrale en mode Empires Anciens ou Âge Surnaturel
	if advanced_start or state.scenario_id == "SUPERNATURAL_AGE":
		var rel: Dictionary = CultureReligionSystem.found_religion(
			state, rng, civ_id, int(settlement["id"]), int(ruler["id"]), "Tradition Ancestrale"
		)
		if not rel.is_empty():
			civ["state_religion_id"] = int(rel["id"])

	return civ


static func create_settlement(
	state: WorldState,
	rng: DeterministicRNG,
	civ_id: int,
	species_id: int,
	x: int,
	y: int,
	settlement_name: String,
	initial_pop: int = 90,
	is_capital: bool = false
) -> Dictionary:
	var s_id: int = state.allocate_settlement_id()
	var tier: String = "VILLAGE" if initial_pop < 250 else "TOWN"
	var buildings: Array[String] = ["GRANARY"]
	if initial_pop >= 250:
		buildings.append("MARKET")
		buildings.append("SHRINE")

	var settlement: Dictionary = {
		"id": s_id,
		"name": settlement_name,
		"civ_id": civ_id,
		"species_id": species_id,
		"tile_x": x,
		"tile_y": y,
		"is_capital": is_capital,
		"tier": tier,
		"founded_year": state.year,
		"population": initial_pop,
		"age_distribution": {"youth": 0.34, "adults": 0.54, "elders": 0.12},
		"social_classes": {
			"farmers": {"share": 0.62, "satisfaction": 0.78},
			"artisans": {"share": 0.14, "satisfaction": 0.75},
			"merchants": {"share": 0.08, "satisfaction": 0.76},
			"elites": {"share": 0.06, "satisfaction": 0.84},
			"clergy": {"share": 0.05, "satisfaction": 0.80},
			"scholars": {"share": 0.05, "satisfaction": 0.77}
		},
		"stocks": {
			"food": float(initial_pop) * 2.2,
			"water": float(initial_pop) * 2.0,
			"wood": 85.0,
			"stone": 50.0,
			"ore": 20.0,
			"tools": 25.0,
			"wealth": 40.0
		},
		"last_production": {"food": 0.0, "wood": 0.0, "stone": 0.0, "ore": 0.0, "tools": 0.0, "wealth": 0.0},
		"last_consumption": {"food": 0.0, "wood": 0.0},
		"buildings": buildings,
		"religious_composition": {},
		"public_opinion": {
			"trust_in_gov": 0.80,
			"economic_satisfaction": 0.78,
			"security_feeling": 0.82,
			"unrest": 0.08
		},
		"sanitation": 0.75,
		"active_plague_severity": 0.0,
		"trade_partners": []
	}
	state.settlements[s_id] = settlement

	var center_tile: Dictionary = state.get_tile(x, y)
	if not center_tile.is_empty():
		center_tile["settlement_id"] = s_id
		center_tile["owner_civ_id"] = civ_id

	for n_tile in state.get_neighbors(x, y, 2):
		if float(n_tile["elevation"]) >= 0.0 and int(n_tile["owner_civ_id"]) == -1:
			n_tile["owner_civ_id"] = civ_id

	if state.civilizations.has(civ_id):
		var civ: Dictionary = state.civilizations[civ_id]
		if not civ["settlement_ids"].has(s_id):
			civ["settlement_ids"].append(s_id)
		var state_rel: int = int(civ.get("state_religion_id", -1))
		if state_rel != -1:
			settlement["religious_composition"][state_rel] = 0.75

	return settlement


static func spawn_remarkable_individual(
	state: WorldState,
	rng: DeterministicRNG,
	civ_id: int,
	settlement_id: int,
	species_id: int,
	role: String,
	goal_desc: String
) -> Dictionary:
	var ind_id: int = state.allocate_individual_id()
	var first_name: String = String(rng.pick_random("individual", PERSON_FIRST_NAMES))
	var epithet: String = String(rng.pick_random("individual", PERSON_EPITHETS))
	var sp: Dictionary = state.species.get(species_id, {})
	var base_life: int = int(sp.get("base_lifespan_years", 68))
	var life_mult: float = float(state.natural_laws.get("lifespan_multiplier", 1.0))
	var max_age: int = maxi(25, int(round(float(base_life) * life_mult * rng.randf_range_channel("individual", 0.88, 1.18))))
	var start_age: int = rng.randi_range_channel("individual", 19, 34)

	var civ: Dictionary = state.civilizations.get(civ_id, {})
	var rel_id: int = int(civ.get("state_religion_id", -1))

	var ind: Dictionary = {
		"id": ind_id,
		"name": "%s %s" % [first_name, epithet],
		"species_id": species_id,
		"civ_id": civ_id,
		"settlement_id": settlement_id,
		"religion_id": rel_id,
		"birth_year": state.year - start_age,
		"age": start_age,
		"max_age": max_age,
		"alive": true,
		"role": role,
		"traits": {
			"courage": snappedf(rng.randf_range_channel("individual", 0.25, 0.95), 0.01),
			"prudence": snappedf(rng.randf_range_channel("individual", 0.25, 0.95), 0.01),
			"curiosity": snappedf(rng.randf_range_channel("individual", 0.25, 0.95), 0.01),
			"ambition": snappedf(rng.randf_range_channel("individual", 0.25, 0.95), 0.01),
			"empathy": snappedf(rng.randf_range_channel("individual", 0.25, 0.95), 0.01),
			"religiosity": snappedf(rng.randf_range_channel("individual", 0.15, 0.95), 0.01),
			"charisma": snappedf(rng.randf_range_channel("individual", 0.30, 0.98), 0.01)
		},
		"belief_profile": {
			"personal_conviction": snappedf(rng.randf_range_channel("individual", 0.3, 0.9), 0.01),
			"ritual_practice": snappedf(rng.randf_range_channel("individual", 0.2, 0.9), 0.01),
			"institutional_trust": snappedf(rng.randf_range_channel("individual", 0.3, 0.85), 0.01),
			"scepticism": snappedf(rng.randf_range_channel("individual", 0.1, 0.75), 0.01)
		},
		"blessed_by_god": false,
		"known_facts": [],
		"current_goal": goal_desc,
		"relationships": {},
		"biography_events": []
	}
	state.individuals[ind_id] = ind
	return ind


static func _spawn_initial_spirits(state: WorldState, rng: DeterministicRNG, count: int) -> void:
	var spirit_names: Array[String] = ["Sylphide d'Émeraude", "Gardien du Mont Sacré", "Veilleur Astral", "Esprit des Eaux Primordiales"]
	for i in range(count):
		var sp_id: int = state.allocate_spirit_id()
		var tx: int = rng.randi_range_channel("divine", 4, state.width - 5)
		var ty: int = rng.randi_range_channel("divine", 4, state.height - 5)
		state.spiritual_entities[sp_id] = {
			"id": sp_id,
			"name": spirit_names[i % spirit_names.size()],
			"entity_type": "LOCUS_SPIRIT",
			"plane": "SPIRITUAL",
			"tile_x": tx,
			"tile_y": ty,
			"power_level": 0.75,
			"autonomous_goal": "PROTECT_NATURE",
			"perceived_by_religions": []
		}
		var tile: Dictionary = state.get_tile(tx, ty)
		if not tile.is_empty():
			tile["divine_aura"] = clampf(float(tile.get("divine_aura", 0.0)) + 0.45, -1.0, 1.0)


static func _determine_origin_way_of_life(state: WorldState, x: int, y: int) -> String:
	var center: Dictionary = state.get_tile(x, y)
	var neighbors: Array[Dictionary] = state.get_neighbors(x, y, 2)
	var has_coast: bool = false
	var mountain_count: int = 0
	var forest_count: int = 0
	for n in neighbors:
		var b: String = String(n["biome"])
		if b in ["OCEAN", "SHALLOW_WATER"]:
			has_coast = true
		elif b == "MOUNTAIN":
			mountain_count += 1
		elif b == "FOREST":
			forest_count += 1
	if bool(center.get("has_river", false)):
		return "RIVER_AGRICULTURE"
	if has_coast:
		return "MARITIME"
	if mountain_count >= 3:
		return "MOUNTAIN_MINING"
	if forest_count >= 4:
		return "FOREST_CLAN"
	return "PASTORAL"


static func _architecture_for_way(way: String) -> String:
	match way:
		"RIVER_AGRICULTURE": return "Briques d'argile et terrasses fluviales"
		"MARITIME": return "Ports à colonnades et charpentes navales"
		"MOUNTAIN_MINING": return "Citadelles taillées dans le roc"
		"FOREST_CLAN": return "Sanctuaires de bois sculpté"
		_: return "Pavillons nomades et enceintes de pierre"


static func _values_for_way(way: String) -> Array[String]:
	match way:
		"RIVER_AGRICULTURE": return ["Harmonie Hydraulique", "Abondance Collective"]
		"MARITIME": return ["Exploration", "Négoce Cosmopolite"]
		"MOUNTAIN_MINING": return ["Maîtrise de la Forge", "Endurance"]
		"FOREST_CLAN": return ["Symbiose Sylvestre", "Mémoire des Ancêtres"]
		_: return ["Liberté des Steppes", "Hospitalité"]
