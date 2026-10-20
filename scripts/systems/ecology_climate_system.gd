class_name EcologyClimateSystem
extends RefCounted
## Système de simulation climatique, hydrologique et écologique.
## Gère les saisons, les variations thermiques/hydriques, la régénération de la biomasse,
## la dynamique de la faune sauvage, les sécheresses naturelles et l'action des entités spirituelles.


static func update_seasonal_climate(state: WorldState, rng: DeterministicRNG) -> void:
	var season_temp_offset: float = 0.0
	var season_rain_mult: float = 1.0
	match state.season:
		"Printemps":
			season_temp_offset = 1.5
			season_rain_mult = 1.15
		"Été":
			season_temp_offset = 6.0
			season_rain_mult = 0.85
		"Automne":
			season_temp_offset = -1.0
			season_rain_mult = 1.10
		"Hiver":
			season_temp_offset = -7.5
			season_rain_mult = 0.90

	var volatility: float = float(state.natural_laws.get("climate_volatility", 1.0))
	var regen_mult: float = float(state.natural_laws.get("resource_regen_multiplier", 1.0))
	var global_fert_mod: float = float(state.natural_laws.get("fertility_global_modifier", 1.0))

	var cy: float = float(state.height) * 0.5
	for tile in state.tiles:
		var y: int = int(tile["y"])
		var elev: float = float(tile["elevation"])
		var lat_norm: float = absf((float(y) - cy) / cy)
		var base_temp: float = lerpf(30.0, -14.0, pow(lat_norm, 1.25))
		if elev > 0.0:
			base_temp -= elev * 22.0

		var drift: float = rng.randf_range_channel("climate", -1.2, 1.2) * volatility
		tile["temperature"] = clampf(base_temp + season_temp_offset + drift, -35.0, 48.0)

		if elev >= 0.0:
			var rain_drift: float = rng.randf_range_channel("climate", -0.05, 0.05) * volatility
			tile["rainfall"] = clampf(float(tile["rainfall"]) * 0.94 + (0.45 * season_rain_mult + rain_drift) * 0.06, 0.02, 1.0)

			# Régénération naturelle de la fertilité et de la flore
			var has_river: bool = bool(tile["has_river"])
			var aura: float = float(tile.get("divine_aura", 0.0))
			var target_fert: float = clampf((float(tile["rainfall"]) * 0.65 + (0.30 if has_river else 0.0) + aura * 0.25) * global_fert_mod, 0.05, 1.0)
			var poll: float = float(tile.get("pollution", 0.0))
			if poll > 0.001:
				tile["pollution"] = clampf(poll - 0.015 * regen_mult, 0.0, 1.0)
			tile["fertility"] = clampf(lerpf(float(tile["fertility"]), target_fert * (1.0 - poll * 0.5), 0.15 * regen_mult), 0.02, 1.0)

			# Recalcul cohérent du biome si le climat ou le relief a changé
			WorldGenerator.recompute_tile_biome(tile)


static func update_monthly_ecology(state: WorldState, rng: DeterministicRNG) -> void:
	var regen_mult: float = float(state.natural_laws.get("resource_regen_multiplier", 1.0))

	# Remise à zéro des compteurs globaux de population par espèce sauvage
	for sp_id in state.species.keys():
		var sp: Dictionary = state.species[sp_id]
		if not bool(sp.get("is_sapient", false)):
			sp["total_population"] = 0

	for tile in state.tiles:
		var elev: float = float(tile["elevation"])
		var biome: String = String(tile["biome"])

		# Croissance de la biomasse végétale
		if elev >= 0.0:
			var fert: float = float(tile["fertility"])
			var max_flora: float = 95.0 if biome in ["FOREST", "SWAMP"] else (62.0 if biome == "PLAINS" else 22.0)
			var flora_growth: float = fert * 2.8 * regen_mult
			if state.season == "Hiver":
				flora_growth *= 0.35
			tile["biomass_flora"] = clampf(float(tile["biomass_flora"]) + flora_growth, 2.0, max_flora)

		# Dynamique de la faune sauvage
		var fauna_id: int = int(tile.get("fauna_species_id", -1))
		var count: int = int(tile.get("fauna_count", 0))
		if fauna_id != -1 and state.species.has(fauna_id) and count > 0:
			var sp: Dictionary = state.species[fauna_id]
			var temp: float = float(tile["temperature"])
			var min_t: float = float(sp.get("preferred_temp_min", -10.0))
			var max_t: float = float(sp.get("preferred_temp_max", 35.0))
			var repro: float = float(sp.get("reproduction_rate", 0.05)) * regen_mult

			var carrying_cap: int = 90 if elev < 0.0 else int(float(tile["biomass_flora"]) * 1.1 + 10.0)
			if temp < min_t or temp > max_t:
				# Stress thermique -> déclin ou migration vers une tuile voisine plus clémente
				var loss: int = maxi(1, int(float(count) * 0.12))
				count = maxi(0, count - loss)
				_try_migrate_fauna(state, tile, fauna_id, loss)
			else:
				if count < carrying_cap:
					var births: int = maxi(1, int(round(float(count) * repro)))
					count = mini(carrying_cap, count + births)
				elif count > carrying_cap:
					count = carrying_cap

			if count <= 0:
				tile["fauna_species_id"] = -1
				tile["fauna_count"] = 0
			else:
				tile["fauna_count"] = count
				sp["total_population"] = int(sp["total_population"]) + count

	# Déplacement autonome des entités spirituelles (si le surnaturel est actif)
	if bool(state.natural_laws.get("magic_enabled", false)):
		_update_spiritual_entities(state, rng)


static func _try_migrate_fauna(state: WorldState, from_tile: Dictionary, species_id: int, migrating_count: int) -> void:
	if migrating_count <= 0:
		return
	var neighbors: Array[Dictionary] = state.get_neighbors(int(from_tile["x"]), int(from_tile["y"]), 1)
	var sp: Dictionary = state.species.get(species_id, {})
	var min_t: float = float(sp.get("preferred_temp_min", -10.0))
	var max_t: float = float(sp.get("preferred_temp_max", 35.0))
	for n in neighbors:
		var is_aquatic: bool = String(sp.get("category", "")) == "AQUATIC"
		if is_aquatic and float(n["elevation"]) >= 0.0:
			continue
		if not is_aquatic and float(n["elevation"]) < 0.0:
			continue
		var nt: float = float(n["temperature"])
		if nt >= min_t and nt <= max_t and int(n.get("fauna_species_id", -1)) in [-1, species_id]:
			n["fauna_species_id"] = species_id
			n["fauna_count"] = int(n.get("fauna_count", 0)) + migrating_count
			return


static func _update_spiritual_entities(state: WorldState, rng: DeterministicRNG) -> void:
	for sp_id in state.spiritual_entities.keys():
		var ent: Dictionary = state.spiritual_entities[sp_id]
		var tx: int = int(ent["tile_x"])
		var ty: int = int(ent["tile_y"])
		var neighbors: Array[Dictionary] = state.get_neighbors(tx, ty, 1)
		if not neighbors.is_empty() and rng.randf_channel("divine") < 0.45:
			var next_tile: Dictionary = rng.pick_random("divine", neighbors)
			ent["tile_x"] = int(next_tile["x"])
			ent["tile_y"] = int(next_tile["y"])
			next_tile["divine_aura"] = clampf(float(next_tile.get("divine_aura", 0.0)) + 0.12, -1.0, 1.0)
			if float(next_tile["elevation"]) >= 0.0:
				next_tile["fertility"] = clampf(float(next_tile["fertility"]) + 0.04, 0.0, 1.0)
