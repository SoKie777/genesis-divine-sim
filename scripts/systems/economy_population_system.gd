class_name EconomyPopulationSystem
extends RefCounted
## Système économique, démographique et urbain réel.
## Aucune ressource n'est décorative : chaque établissement récolte sur son territoire,
## transforme ses matières premières, commerce avec ses partenaires, nourrit sa population,
## construit ses infrastructures, subit les famines/épidémies et essaimerait des colonies.


static func update_monthly_economy_and_population(state: WorldState, rng: DeterministicRNG) -> void:
	var settlement_ids: Array = state.settlements.keys()
	var global_fert_mod: float = float(state.natural_laws.get("fertility_global_modifier", 1.0))
	var life_mult: float = clampf(float(state.natural_laws.get("lifespan_multiplier", 1.0)), 0.3, 5.0)

	# 1. Production, transformation et consommation locale par établissement
	for s_id in settlement_ids:
		var settlement: Dictionary = state.settlements[s_id]
		if String(settlement.get("tier", "RUIN")) == "RUIN":
			continue

		var civ_id: int = int(settlement["civ_id"])
		var civ: Dictionary = state.civilizations.get(civ_id, {})
		var techs: Array = civ.get("technologies", [])
		var buildings: Array = settlement.get("buildings", [])
		var pop: int = maxi(0, int(settlement.get("population", 0)))
		if pop <= 0:
			_collapse_settlement_to_ruin(state, settlement, "Extinction démographique complète")
			continue

		var sx: int = int(settlement["tile_x"])
		var sy: int = int(settlement["tile_y"])
		var center_tile: Dictionary = state.get_tile(sx, sy)
		var work_tiles: Array[Dictionary] = state.get_neighbors(sx, sy, 2)
		if not center_tile.is_empty():
			work_tiles.push_front(center_tile)

		var sum_fertility: float = 0.0
		var sum_wood_potential: float = 0.0
		var sum_stone_potential: float = 0.0
		var sum_ore_potential: float = 0.0
		var sum_fish_potential: float = 0.0
		var river_count: int = 0

		for wt in work_tiles:
			var elev: float = float(wt["elevation"])
			var biome: String = String(wt["biome"])
			if elev >= 0.0:
				sum_fertility += float(wt["fertility"])
				if bool(wt["has_river"]):
					river_count += 1
				if biome in ["FOREST", "SWAMP"]:
					sum_wood_potential += float(wt["biomass_flora"]) * 0.025
				elif biome == "PLAINS":
					sum_wood_potential += float(wt["biomass_flora"]) * 0.006

				var m_type: String = String(wt.get("mineral_type", "NONE"))
				var m_res: float = float(wt.get("mineral_reserve", 0.0))
				if m_res > 1.0:
					if m_type == "STONE":
						sum_stone_potential += 1.4
					elif m_type in ["IRON", "GOLD", "AETHERIUM"]:
						sum_ore_potential += 1.25
						sum_stone_potential += 0.5
			else:
				sum_fish_potential += 0.9 + float(wt.get("fauna_count", 0)) * 0.015

		var avg_fert: float = (sum_fertility / float(maxi(1, work_tiles.size()))) * global_fert_mod
		var season_agri_mod: float = 1.0
		match state.season:
			"Printemps": season_agri_mod = 1.18
			"Été": season_agri_mod = 1.25
			"Automne": season_agri_mod = 1.12
			"Hiver": season_agri_mod = 0.48

		# Modificateurs technologiques et d'infrastructures
		var agri_mult: float = 1.0
		if techs.has("AGRICULTURE"):
			agri_mult += 0.38
		if techs.has("IRRIGATION"):
			agri_mult += 0.28
		if buildings.has("IRRIGATION"):
			agri_mult += 0.30
		if buildings.has("GRANARY"):
			agri_mult += 0.12

		var stocks: Dictionary = settlement["stocks"]
		var tool_bonus: float = 1.0 + clampf(float(stocks.get("tools", 0.0)) / float(maxi(20, pop)), 0.0, 0.45)
		var aura_bonus: float = 1.0 + clampf(float(center_tile.get("divine_aura", 0.0)) * 0.40, -0.35, 0.65)

		var workforce: float = float(pop) * 0.58
		var food_prod: float = (workforce * 1.32 * avg_fert * season_agri_mod * agri_mult * tool_bonus * aura_bonus) + sum_fish_potential * 8.5 + float(river_count) * 4.5
		var wood_prod: float = clampf(workforce * 0.14 * (0.4 + sum_wood_potential * 0.18) * tool_bonus, 1.5, 160.0)
		var stone_prod: float = clampf(workforce * 0.08 * (0.3 + sum_stone_potential * 0.25) * tool_bonus, 0.8, 120.0)
		var ore_prod: float = clampf(workforce * 0.06 * (sum_ore_potential * 0.35) * (1.35 if techs.has("METALLURGY") else 0.7), 0.0, 95.0)

		# Transformation artisanale : Minerai + Bois -> Outils
		var tools_prod: float = 0.0
		var forge_mult: float = 1.45 if buildings.has("FORGE") else 0.85
		if float(stocks["ore"]) > 2.0 and float(stocks["wood"]) > 3.0:
			var smelt_amount: float = minf(float(stocks["ore"]) * 0.22, workforce * 0.05 * forge_mult)
			stocks["ore"] = maxf(0.0, float(stocks["ore"]) - smelt_amount)
			stocks["wood"] = maxf(0.0, float(stocks["wood"]) - smelt_amount * 0.5)
			tools_prod = smelt_amount * (1.5 if techs.has("METALLURGY") else 1.0)

		var wealth_prod: float = workforce * 0.07 * (1.45 if buildings.has("MARKET") else 1.0) * (1.25 if techs.has("WRITING") else 1.0)

		# Prélèvement écologique léger sur la tuile centrale (déforestation / épuisement si surexploitation)
		if not center_tile.is_empty() and float(center_tile["elevation"]) >= 0.0:
			center_tile["biomass_flora"] = maxf(4.0, float(center_tile["biomass_flora"]) - wood_prod * 0.03)
			if pop > 650 and techs.has("MACHINERY"):
				center_tile["pollution"] = clampf(float(center_tile.get("pollution", 0.0)) + 0.008, 0.0, 1.0)

		# Consommation mensuelle réelle
		var food_needed: float = float(pop) * 0.92
		var wood_needed: float = float(pop) * (0.12 if state.season == "Hiver" else 0.05)
		var tool_wear: float = float(stocks["tools"]) * 0.04

		var net_food_balance: float = food_prod - food_needed
		var prod_balance_ratio: float = food_prod / maxf(1.0, food_needed)
		var food_available: float = maxf(0.0, float(stocks["food"]) + food_prod)
		var food_ratio: float = clampf(food_available / maxf(1.0, food_needed), 0.0, 3.0)

		stocks["food"] = maxf(0.0, food_available - food_needed)
		stocks["wood"] = maxf(0.0, float(stocks["wood"]) + wood_prod - wood_needed)
		stocks["stone"] = maxf(0.0, float(stocks["stone"]) + stone_prod)
		stocks["ore"] = maxf(0.0, float(stocks["ore"]) + ore_prod)
		stocks["tools"] = maxf(0.0, float(stocks["tools"]) + tools_prod - tool_wear)
		stocks["wealth"] = maxf(0.0, float(stocks["wealth"]) + wealth_prod)

		# Plafond de stockage de nourriture (dépend du Grenier et de la Poterie)
		var max_food_storage: float = float(pop) * (4.8 if buildings.has("GRANARY") else 2.6) * (1.25 if techs.has("POTTERY") else 1.0)
		stocks["food"] = minf(float(stocks["food"]), max_food_storage)

		settlement["last_production"] = {
			"food": snappedf(food_prod, 0.1),
			"wood": snappedf(wood_prod, 0.1),
			"stone": snappedf(stone_prod, 0.1),
			"ore": snappedf(ore_prod, 0.1),
			"tools": snappedf(tools_prod, 0.1),
			"wealth": snappedf(wealth_prod, 0.1)
		}
		settlement["last_consumption"] = {
			"food": snappedf(food_needed, 0.1),
			"wood": snappedf(wood_needed, 0.1)
		}

		# 2. Démographie causale (Natalité, Mortalité, Épidémies, Migrations)
		var sp: Dictionary = state.species.get(int(settlement["species_id"]), {})
		var base_repro: float = float(sp.get("reproduction_rate", 0.03))
		var births: int = 0
		var deaths: int = 0

		# Mortalité naturelle modulée par l'espérance de vie et les conditions sanitaires/climatiques
		var natural_death_rate: float = (0.0085 / life_mult) * (1.25 if prod_balance_ratio < 0.75 else 1.0)
		deaths += int(round(float(pop) * natural_death_rate))

		# Effet du bilan alimentaire mensuel et des réserves sur la natalité et la famine
		if food_ratio >= 0.95 and prod_balance_ratio >= 0.65:
			var surplus_factor: float = clampf(prod_balance_ratio * 0.65 + food_ratio * 0.22 + avg_fert * 0.35, 0.25, 2.4)
			births = maxi(0, int(round(float(pop) * base_repro * 0.40 * surplus_factor)))
			if net_food_balance < 0.0:
				births = int(floor(float(births) * 0.45))
		elif food_ratio < 0.85 or prod_balance_ratio < 0.50:
			var famine_severity: float = clampf(1.0 - minf(food_ratio, prod_balance_ratio), 0.1, 0.9)
			var famine_deaths: int = maxi(2, int(round(float(pop) * famine_severity * 0.14)))
			deaths += famine_deaths

			state.record_diagnostic(
				"EconomyPopulationSystem",
				String(settlement["name"]),
				"Crise de famine (%d décès)" % famine_deaths,
				[
					"Ratio alimentaire %.2f (Production %.1f vs Besoin %.1f)" % [food_ratio, food_prod, food_needed],
					"Fertilité locale moyenne %.2f (%s)" % [avg_fert, state.season]
				]
			)
			# Prière d'urgence en cas de famine grave
			if rng.randf_channel("society") < 0.42:
				CultureReligionSystem.spawn_prayer(
					state,
					civ_id,
					int(settlement["id"]),
					"FAMINE_RELIEF",
					"Famine à %s" % String(settlement["name"]),
					"Les greniers de %s sont vides (%d morts de faim). Le peuple implore une récolte miraculeuse ou la pluie." % [
						String(settlement["name"]), famine_deaths
					],
					0.90
				)
			# Migration de survie d'une partie des habitants affamés
			_attempt_crisis_migration(state, settlement, int(round(float(pop) * 0.08)))

		# Gestion des épidémies actives
		var plague: float = float(settlement.get("active_plague_severity", 0.0))
		if plague > 0.01:
			var med_protection: float = 0.55 if techs.has("MEDICINE") else 1.0
			var plague_deaths: int = maxi(1, int(round(float(pop) * plague * 0.11 * med_protection)))
			deaths += plague_deaths
			settlement["active_plague_severity"] = maxf(0.0, plague - (0.09 if techs.has("MEDICINE") else 0.04))
			if plague > 0.35 and rng.randf_channel("society") < 0.35:
				CultureReligionSystem.spawn_prayer(
					state,
					civ_id,
					int(settlement["id"]),
					"PLAGUE_CURE",
					"Pestilence sur %s" % String(settlement["name"]),
					"Une fièvre mortelle ravage %s. Les habitants supplient le Ciel de purifier les airs." % String(settlement["name"]),
					0.95
				)

		pop = maxi(0, pop + births - deaths)
		settlement["population"] = pop
		if pop <= 0:
			_collapse_settlement_to_ruin(state, settlement, "Famine ou pestilence fatale")
			continue

		# 3. Mise à jour des classes sociales et de l'opinion publique
		_update_social_opinion(settlement, food_ratio, plague)

		# 4. Évolution du rang urbain et constructions autonomes
		_update_urban_tier_and_buildings(state, rng, settlement, civ)

		# 5. Expansion coloniale autonome si la cité est surpeuplée et prospère
		if pop >= 380 and float(stocks["food"]) > float(pop) * 1.4 and int(civ.get("settlement_ids", []).size()) < 6:
			if rng.randf_channel("society") < 0.18:
				_attempt_found_colony(state, rng, settlement, civ)

		# 5b. Domestication animale et fouilles archéologiques des ruines proches (Phases 3 & 6)
		_check_domestication_and_ruins(state, rng, settlement, civ, work_tiles)

	# 6. Réseaux commerciaux inter-établissements et lancement de caravanes
	_process_trade_networks(state)

	# 7. Mise à jour du compteur de population de chaque espèce sapiente
	for sp_id in state.species.keys():
		var sp: Dictionary = state.species[sp_id]
		if bool(sp.get("is_sapient", false)):
			sp["total_population"] = 0
	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		if String(s.get("tier", "RUIN")) != "RUIN":
			var sp_id: int = int(s["species_id"])
			if state.species.has(sp_id):
				state.species[sp_id]["total_population"] = int(state.species[sp_id]["total_population"]) + int(s["population"])


static func _update_social_opinion(settlement: Dictionary, food_ratio: float, plague: float) -> void:
	var opinion: Dictionary = settlement["public_opinion"]
	var econ_sat: float = clampf(food_ratio * 0.72 + clampf(float(settlement["stocks"]["wealth"]) / 250.0, 0.0, 0.28), 0.05, 1.0)
	var sec_feel: float = clampf(0.85 - plague * 0.65 + (0.12 if settlement["buildings"].has("WALLS") else 0.0), 0.05, 1.0)
	var unrest_target: float = clampf((1.0 - econ_sat) * 0.65 + (1.0 - sec_feel) * 0.35, 0.0, 1.0)

	opinion["economic_satisfaction"] = snappedf(lerpf(float(opinion["economic_satisfaction"]), econ_sat, 0.3), 0.01)
	opinion["security_feeling"] = snappedf(lerpf(float(opinion["security_feeling"]), sec_feel, 0.3), 0.01)
	opinion["unrest"] = snappedf(lerpf(float(opinion["unrest"]), unrest_target, 0.25), 0.01)
	opinion["trust_in_gov"] = snappedf(clampf(1.0 - float(opinion["unrest"]) * 0.85, 0.05, 1.0), 0.01)

	var classes: Dictionary = settlement["social_classes"]
	if classes.has("farmers"):
		classes["farmers"]["satisfaction"] = snappedf(clampf(food_ratio * 0.8, 0.1, 1.0), 0.01)
	if classes.has("merchants"):
		classes["merchants"]["satisfaction"] = snappedf(clampf(0.5 + float(settlement["stocks"]["wealth"]) / 300.0, 0.1, 1.0), 0.01)
	if classes.has("artisans"):
		classes["artisans"]["satisfaction"] = snappedf(clampf(0.5 + float(settlement["stocks"]["tools"]) / 150.0, 0.1, 1.0), 0.01)


static func _update_urban_tier_and_buildings(
	state: WorldState,
	rng: DeterministicRNG,
	settlement: Dictionary,
	civ: Dictionary
) -> void:
	var pop: int = int(settlement["population"])
	var old_tier: String = String(settlement["tier"])
	var new_tier: String = old_tier
	if pop < 70:
		new_tier = "CAMP"
	elif pop < 220:
		new_tier = "VILLAGE"
	elif pop < 520:
		new_tier = "TOWN"
	elif pop < 1100:
		new_tier = "CITY"
	else:
		new_tier = "METROPOLIS"

	if new_tier != old_tier:
		settlement["tier"] = new_tier
		if new_tier in ["CITY", "METROPOLIS"] and old_tier in ["VILLAGE", "TOWN"]:
			state.record_historical_event(
				"SETTLEMENT",
				"%s devient une grande %s" % [String(settlement["name"]), new_tier],
				"Portée par ses surplus agricoles et son commerce, %s atteint %d habitants." % [String(settlement["name"]), pop],
				["Croissance démographique soutenue", "Surplus économiques"],
				["Nouvelles institutions urbaines", "Rayonnement régional accru"],
				int(settlement["tile_x"]),
				int(settlement["tile_y"]),
				[int(settlement["civ_id"])]
			)

	# Construction autonome d'infrastructures selon les besoins et les stocks réels
	var stocks: Dictionary = settlement["stocks"]
	var buildings: Array = settlement["buildings"]
	var techs: Array = civ.get("technologies", [])

	if not buildings.has("IRRIGATION") and techs.has("IRRIGATION") and float(stocks["wood"]) >= 45.0 and float(stocks["stone"]) >= 30.0:
		stocks["wood"] = float(stocks["wood"]) - 45.0
		stocks["stone"] = float(stocks["stone"]) - 30.0
		buildings.append("IRRIGATION")
	elif not buildings.has("SHRINE") and pop >= 115 and float(stocks["stone"]) >= 35.0:
		stocks["stone"] = float(stocks["stone"]) - 35.0
		buildings.append("SHRINE")
	elif not buildings.has("MARKET") and pop >= 170 and float(stocks["wood"]) >= 50.0:
		stocks["wood"] = float(stocks["wood"]) - 50.0
		buildings.append("MARKET")
	elif not buildings.has("FORGE") and techs.has("METALLURGY") and float(stocks["stone"]) >= 50.0 and float(stocks["ore"]) >= 25.0:
		stocks["stone"] = float(stocks["stone"]) - 50.0
		stocks["ore"] = float(stocks["ore"]) - 25.0
		buildings.append("FORGE")
	elif not buildings.has("WALLS") and pop >= 260 and float(stocks["stone"]) >= 75.0:
		stocks["stone"] = float(stocks["stone"]) - 75.0
		buildings.append("WALLS")
	elif not buildings.has("TEMPLE") and pop >= 320 and int(civ.get("state_religion_id", -1)) != -1 and float(stocks["stone"]) >= 90.0:
		stocks["stone"] = float(stocks["stone"]) - 90.0
		buildings.append("TEMPLE")
	elif not buildings.has("ACADEMY") and techs.has("WRITING") and pop >= 340 and float(stocks["wealth"]) >= 95.0:
		stocks["wealth"] = float(stocks["wealth"]) - 95.0
		buildings.append("ACADEMY")

	# Prélèvement fiscal vers le trésor de l'État
	if not civ.is_empty():
		var tax: float = float(stocks["wealth"]) * 0.08 * float(civ.get("centralization", 0.4))
		stocks["wealth"] = maxf(0.0, float(stocks["wealth"]) - tax)
		civ["treasury"] = float(civ.get("treasury", 0.0)) + tax


static func _attempt_crisis_migration(state: WorldState, from_settlement: Dictionary, migrants: int) -> void:
	if migrants <= 3 or int(from_settlement["population"]) <= migrants + 15:
		return
	var best_target: Dictionary = {}
	var best_score: float = -999.0
	var fx: int = int(from_settlement["tile_x"])
	var fy: int = int(from_settlement["tile_y"])

	for other_id in state.settlements.keys():
		if int(other_id) == int(from_settlement["id"]):
			continue
		var cand: Dictionary = state.settlements[other_id]
		if String(cand.get("tier", "RUIN")) == "RUIN":
			continue
		var dist: float = Vector2(fx, fy).distance_to(Vector2(int(cand["tile_x"]), int(cand["tile_y"])))
		if dist > 18.0:
			continue
		var food_surplus: float = float(cand["stocks"].get("food", 0.0)) - float(cand["population"])
		var score: float = food_surplus * 0.5 - dist * 4.0
		if score > best_score and food_surplus > 25.0:
			best_score = score
			best_target = cand

	if not best_target.is_empty():
		from_settlement["population"] = int(from_settlement["population"]) - migrants
		best_target["population"] = int(best_target["population"]) + migrants
		state.record_diagnostic(
			"EconomyPopulationSystem",
			String(from_settlement["name"]),
			"Migration de %d réfugiés vers %s" % [migrants, String(best_target["name"])],
			["Déficit alimentaire critique à %s" % String(from_settlement["name"]), "Surplus disponible à %s" % String(best_target["name"])]
		)


static func _attempt_found_colony(state: WorldState, rng: DeterministicRNG, mother_city: Dictionary, civ: Dictionary) -> void:
	var mx: int = int(mother_city["tile_x"])
	var my: int = int(mother_city["tile_y"])
	var candidates: Array[Dictionary] = []

	for dy in range(-9, 10):
		for dx in range(-9, 10):
			var nx: int = mx + dx
			var ny: int = my + dy
			if not state.is_valid_coord(nx, ny):
				continue
			var d: float = Vector2(mx, my).distance_to(Vector2(nx, ny))
			if d < 5.0 or d > 9.5:
				continue
			var t: Dictionary = state.get_tile(nx, ny)
			if float(t["elevation"]) < 0.0 or int(t["settlement_id"]) != -1:
				continue
			if float(t["fertility"]) < 0.42:
				continue
			# Vérifier qu'aucun autre établissement n'est trop proche
			var too_close: bool = false
			for n_tile in state.get_neighbors(nx, ny, 3):
				if int(n_tile["settlement_id"]) != -1:
					too_close = true
					break
			if not too_close:
				candidates.append(t)

	if candidates.is_empty():
		return

	var target_tile: Dictionary = rng.pick_random("society", candidates)
	var colonists: int = 85
	mother_city["population"] = int(mother_city["population"]) - colonists
	mother_city["stocks"]["food"] = maxf(0.0, float(mother_city["stocks"]["food"]) - 120.0)
	mother_city["stocks"]["wood"] = maxf(0.0, float(mother_city["stocks"]["wood"]) - 40.0)

	var colony_idx: int = int(civ.get("settlement_ids", []).size()) + 1
	var suffix: String = String(rng.pick_random("society", ["Val", "Port", "Fort", "bourg", "clair", "rive", "mont"]))
	var colony_name: String = "%s-%s-%d" % [String(civ["name"]).substr(0, 5), suffix, colony_idx]

	var new_settlement: Dictionary = WorldGenerator.create_settlement(
		state,
		rng,
		int(civ["id"]),
		int(civ["species_id"]),
		int(target_tile["x"]),
		int(target_tile["y"]),
		colony_name,
		colonists,
		false
	)

	state.record_historical_event(
		"SETTLEMENT",
		"Fondation coloniale de %s" % colony_name,
		"Des colons partis de %s ont fondé %s pour exploiter de nouvelles terres fertiles." % [
			String(mother_city["name"]), colony_name
		],
		["Pression démographique à %s" % String(mother_city["name"]), "Terres fertiles disponibles (%0.2f)" % float(target_tile["fertility"])],
		["Expansion territoriale de %s" % String(civ["name"])],
		int(target_tile["x"]),
		int(target_tile["y"]),
		[int(civ["id"])]
	)
	state.add_visual_pulse(int(target_tile["x"]), int(target_tile["y"]), civ["color"], 2.2, "Nouvelle Colonie")
	if not new_settlement.is_empty():
		mother_city["trade_partners"].append(int(new_settlement["id"]))
		new_settlement["trade_partners"].append(int(mother_city["id"]))


static func _process_trade_networks(state: WorldState) -> void:
	var active_settlements: Array[Dictionary] = []
	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		if String(s.get("tier", "RUIN")) != "RUIN":
			active_settlements.append(s)

	for i in range(active_settlements.size()):
		var a: Dictionary = active_settlements[i]
		var partners: Array = a.get("trade_partners", [])
		for j in range(i + 1, active_settlements.size()):
			var b: Dictionary = active_settlements[j]
			var dist: float = Vector2(int(a["tile_x"]), int(a["tile_y"])).distance_to(Vector2(int(b["tile_x"]), int(b["tile_y"])))
			if dist > 14.0:
				continue

			var civ_a: int = int(a["civ_id"])
			var civ_b: int = int(b["civ_id"])
			var can_trade: bool = (civ_a == civ_b)
			if not can_trade and state.civilizations.has(civ_a):
				var diplo: Dictionary = state.civilizations[civ_a].get("diplomacy", {}).get(civ_b, {})
				if String(diplo.get("stance", "NEUTRAL")) in ["TRADE", "ALLIANCE", "NEUTRAL"]:
					can_trade = true

			if can_trade:
				if not partners.has(int(b["id"])):
					partners.append(int(b["id"]))
				if not b["trade_partners"].has(int(a["id"])):
					b["trade_partners"].append(int(a["id"]))

				# Échange réel de nourriture contre minerai/richesse et envoi de caravane visible
				var a_food: float = float(a["stocks"]["food"])
				var b_food: float = float(b["stocks"]["food"])
				if a_food > b_food + 60.0 and float(b["stocks"]["wealth"]) > 8.0:
					var transfer: float = minf(22.0, (a_food - b_food) * 0.15)
					a["stocks"]["food"] = a_food - transfer
					b["stocks"]["food"] = b_food + transfer
					a["stocks"]["wealth"] = float(a["stocks"]["wealth"]) + 4.5
					b["stocks"]["wealth"] = maxf(0.0, float(b["stocks"]["wealth"]) - 3.0)
					_spawn_caravan(state, a, b, "Nourriture & Grain")
				elif b_food > a_food + 60.0 and float(a["stocks"]["wealth"]) > 8.0:
					var transfer2: float = minf(22.0, (b_food - a_food) * 0.15)
					b["stocks"]["food"] = b_food - transfer2
					a["stocks"]["food"] = a_food + transfer2
					b["stocks"]["wealth"] = float(b["stocks"]["wealth"]) + 4.5
					a["stocks"]["wealth"] = maxf(0.0, float(a["stocks"]["wealth"]) - 3.0)
					_spawn_caravan(state, b, a, "Outils & Épices")


static func _spawn_caravan(state: WorldState, from_s: Dictionary, to_s: Dictionary, cargo: String) -> void:
	if state.caravans.size() >= 18:
		return
	var fx: float = float(from_s["tile_x"])
	var fy: float = float(from_s["tile_y"])
	var tx: float = float(to_s["tile_x"])
	var ty: float = float(to_s["tile_y"])
	for c in state.caravans:
		if int(c.get("from_id", -1)) == int(from_s["id"]) and int(c.get("to_id", -1)) == int(to_s["id"]):
			return
	state.caravans.append({
		"from_id": int(from_s["id"]),
		"to_id": int(to_s["id"]),
		"civ_id": int(from_s["civ_id"]),
		"x": fx,
		"y": fy,
		"target_x": tx,
		"target_y": ty,
		"cargo": cargo,
		"progress": 0.0
	})


static func update_weekly_caravans(state: WorldState) -> void:
	for i in range(state.caravans.size() - 1, -1, -1):
		var c: Dictionary = state.caravans[i]
		var prog: float = float(c.get("progress", 0.0)) + 0.25
		c["progress"] = prog
		if prog >= 1.0:
			state.caravans.remove_at(i)


static func _check_domestication_and_ruins(
	state: WorldState,
	rng: DeterministicRNG,
	settlement: Dictionary,
	civ: Dictionary,
	work_tiles: Array[Dictionary]
) -> void:
	if civ.is_empty():
		return
	var civ_id: int = int(civ["id"])

	# Domestication d'espèces locales (Phase 6)
	for wt in work_tiles:
		var f_id: int = int(wt.get("fauna_species_id", -1))
		if f_id in [2, 5] and state.species.has(f_id):
			var sp: Dictionary = state.species[f_id]
			var dom_list: Array = sp.get("domesticated_by_civs", [])
			if not dom_list.has(civ_id) and rng.randf_channel("ecology") < 0.08:
				dom_list.append(civ_id)
				settlement["stocks"]["food"] = float(settlement["stocks"]["food"]) + 55.0
				settlement["stocks"]["tools"] = float(settlement["stocks"]["tools"]) + 20.0
				state.record_historical_event(
					"TECH",
					"%s domestique : %s" % [String(civ["name"]), String(sp["name"])],
					"Les éleveurs de %s ont apprivoisé %s, transformant l'agriculture et le transport." % [
						String(settlement["name"]), String(sp["name"])
					],
					["Coexistence prolongée avec la faune locale"],
					["Hausse durable de la productivité agricole et logistique"],
					int(settlement["tile_x"]),
					int(settlement["tile_y"]),
					[civ_id]
				)
				state.add_floating_text(int(settlement["tile_x"]), int(settlement["tile_y"]), "🐎 Domestication !", Color(0.55, 0.95, 0.62))
				break

	# Redécouverte archéologique de ruines anciennes (Phase 3 / Section 8.4)
	for s_id in state.settlements.keys():
		var other: Dictionary = state.settlements[s_id]
		if String(other.get("tier", "")) == "RUIN":
			var dist: float = Vector2(int(settlement["tile_x"]), int(settlement["tile_y"])).distance_to(Vector2(int(other["tile_x"]), int(other["tile_y"])))
			if dist <= 6.0 and rng.randf_channel("society") < 0.06:
				settlement["stocks"]["wealth"] = float(settlement["stocks"]["wealth"]) + 60.0
				state.record_historical_event(
					"TECH",
					"Fouilles des ruines de %s" % String(other["name"]),
					"Les érudits de %s ont exploré les vestiges de %s et exhumé d'anciens manuscrits et artefacts." % [
						String(settlement["name"]), String(other["name"])
					],
					["Proximité des ruines anciennes de %s" % String(other["name"])],
					["Transmission d'héritage culturel et gain de savoir"],
					int(other["tile_x"]),
					int(other["tile_y"]),
					[civ_id]
				)
				state.add_floating_text(int(other["tile_x"]), int(other["tile_y"]), "🏺 Héritage Redécouvert", Color(0.98, 0.85, 0.42))
				break


static func _collapse_settlement_to_ruin(state: WorldState, settlement: Dictionary, reason: String) -> void:
	settlement["tier"] = "RUIN"
	settlement["population"] = 0
	var sx: int = int(settlement["tile_x"])
	var sy: int = int(settlement["tile_y"])
	var civ_id: int = int(settlement["civ_id"])
	state.record_historical_event(
		"COLLAPSE",
		"Chute et abandon de %s" % String(settlement["name"]),
		"L'établissement de %s est devenu une ruine silencieuse (%s)." % [String(settlement["name"]), reason],
		[reason],
		["Ruines archéologiques laissées sur place"],
		sx,
		sy,
		[civ_id]
	)
	if state.civilizations.has(civ_id):
		var civ: Dictionary = state.civilizations[civ_id]
		civ["settlement_ids"].erase(int(settlement["id"]))
		if int(civ["settlement_ids"].size()) == 0:
			civ["alive"] = false
			state.record_historical_event(
				"COLLAPSE",
				"Extinction politique de %s" % String(civ["name"]),
				"Privée de sa dernière cité active, la civilisation de %s disparaît de la scène politique tout en laissant son héritage culturel." % String(civ["name"]),
				[reason, "Perte du dernier centre urbain"],
				["Mémoire linguistique et ruines persistantes"],
				sx,
				sy,
				[civ_id]
			)
