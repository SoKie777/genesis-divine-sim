class_name GeopoliticsMilitarySystem
extends RefCounted
## Système géopolitique, gouvernemental, diplomatique et militaire.
## Modélise l'évolution des régimes politiques, les révolutions internes,
## la diplomatie à information imparfaite, la logistique militaire et les guerres causales.


static func update_monthly_geopolitics(state: WorldState, rng: DeterministicRNG) -> void:
	var active_civs: Array[Dictionary] = []
	for c_id in state.civilizations.keys():
		var civ: Dictionary = state.civilizations[c_id]
		if bool(civ.get("alive", false)):
			active_civs.append(civ)

	# 1. Évolution institutionnelle, stabilité interne et révolutions
	for civ in active_civs:
		_update_internal_politics(state, rng, civ)

	# 2. Relations diplomatiques, traités et déclarations de guerre causales
	var conflict_mult: float = clampf(float(state.natural_laws.get("conflict_propensity", 1.0)), 0.1, 3.0)
	for i in range(active_civs.size()):
		var civ_a: Dictionary = active_civs[i]
		for j in range(i + 1, active_civs.size()):
			var civ_b: Dictionary = active_civs[j]
			_evaluate_bilateral_diplomacy(state, rng, civ_a, civ_b, conflict_mult)


static func update_weekly_military(state: WorldState, rng: DeterministicRNG) -> void:
	var army_ids: Array = state.armies.keys()
	for a_id in army_ids:
		if not state.armies.has(a_id):
			continue
		var army: Dictionary = state.armies[a_id]
		var civ_id: int = int(army["civ_id"])
		if not state.civilizations.has(civ_id) or not bool(state.civilizations[civ_id].get("alive", false)):
			state.armies.erase(a_id)
			continue

		var manpower: int = int(army["manpower"])
		if manpower <= 5:
			state.armies.erase(a_id)
			continue

		var ax: int = int(army["tile_x"])
		var ay: int = int(army["tile_y"])
		var tx: int = int(army["target_x"])
		var ty: int = int(army["target_y"])

		# Logistique : ravitaillement selon que l'armée est en territoire allié ou ennemi
		var cur_tile: Dictionary = state.get_tile(ax, ay)
		var owner_id: int = int(cur_tile.get("owner_civ_id", -1))
		if owner_id == civ_id:
			army["supply"] = clampf(float(army["supply"]) + 8.0, 0.0, 100.0)
		else:
			var terrain_drain: float = 6.5 if String(cur_tile.get("biome", "")) in ["DESERT", "MOUNTAIN", "TUNDRA"] else 3.2
			army["supply"] = clampf(float(army["supply"]) - terrain_drain, 0.0, 100.0)

		if float(army["supply"]) <= 5.0:
			# Attrition logistique faute de ravitaillement
			var attrition: int = maxi(2, int(round(float(manpower) * 0.08)))
			army["manpower"] = maxi(0, manpower - attrition)
			army["morale"] = clampf(float(army["morale"]) - 0.08, 0.1, 1.0)
			state.record_diagnostic(
				"GeopoliticsMilitarySystem",
				String(army["name"]),
				"Attrition logistique (-%d soldats)" % attrition,
				["Ravitaillement épuisé (%.1f%%) en territoire hostile/difficile" % float(army["supply"])]
			)

		# Déplacement vers la cible
		if ax != tx or ay != ty:
			var step_x: int = clampi(tx - ax, -1, 1)
			var step_y: int = clampi(ty - ay, -1, 1)
			var nx: int = ax + step_x
			var ny: int = ay + step_y
			if state.is_valid_coord(nx, ny):
				army["tile_x"] = nx
				army["tile_y"] = ny
				ax = nx
				ay = ny

		# Résolution de bataille ou de siège à l'arrivée sur la cible
		if Vector2i(ax, ay).distance_to(Vector2i(tx, ty)) <= 1.2:
			_resolve_army_engagement(state, rng, army)


static func _update_internal_politics(state: WorldState, rng: DeterministicRNG, civ: Dictionary) -> void:
	var civ_id: int = int(civ["id"])
	var total_pop: int = 0
	var avg_unrest: float = 0.0
	var active_cities: int = 0
	var total_wealth: float = float(civ.get("treasury", 0.0))

	for s_id in civ["settlement_ids"]:
		if state.settlements.has(s_id):
			var s: Dictionary = state.settlements[s_id]
			if String(s.get("tier", "RUIN")) != "RUIN":
				total_pop += int(s["population"])
				avg_unrest += float(s["public_opinion"].get("unrest", 0.1))
				total_wealth += float(s["stocks"].get("wealth", 0.0))
				active_cities += 1

	if active_cities == 0:
		civ["alive"] = false
		return

	avg_unrest /= float(active_cities)
	civ["stability"] = snappedf(clampf(1.0 - avg_unrest * 0.9, 0.05, 1.0), 0.01)

	# Transition organique de forme de gouvernement selon le développement
	var old_gov: String = String(civ.get("government_type", "TRIBE"))
	var techs: Array = civ.get("technologies", [])
	var new_gov: String = old_gov

	if old_gov == "TRIBE" and total_pop >= 210:
		new_gov = "CHIEFDOM"
	elif old_gov in ["TRIBE", "CHIEFDOM"] and total_pop >= 360:
		if int(civ.get("state_religion_id", -1)) != -1 and rng.randf_channel("geopolitics") < 0.30:
			new_gov = "THEOCRACY"
		elif String(civ.get("origin_way_of_life", "")) == "MARITIME":
			new_gov = "MERCHANT_OLIGARCHY"
		else:
			new_gov = "CITY_STATE"
	elif old_gov == "CITY_STATE" and active_cities >= 2 and total_pop >= 580:
		new_gov = "KINGDOM" if rng.randf_channel("geopolitics") < 0.65 else "REPUBLIC"
	elif old_gov in ["KINGDOM", "THEOCRACY"] and active_cities >= 4 and total_pop >= 1150:
		new_gov = "EMPIRE"
	elif old_gov in ["REPUBLIC", "MERCHANT_OLIGARCHY"] and active_cities >= 4 and techs.has("PRINTING"):
		new_gov = "FEDERATION"

	if new_gov != old_gov:
		civ["government_type"] = new_gov
		var cap: Dictionary = state.settlements.get(int(civ["capital_settlement_id"]), {})
		state.record_historical_event(
			"DIPLOMACY",
			"Mutation politique : %s devient %s" % [String(civ["name"]), new_gov],
			"Sous l'effet de sa croissance (%d hab., %d cités), %s réforme ses institutions (%s -> %s)." % [
				total_pop, active_cities, String(civ["name"]), old_gov, new_gov
			],
			["Évolution démographique et urbaine", "Transformation des élites et du savoir"],
			["Nouveau régime : %s" % new_gov],
			int(cap.get("tile_x", 0)),
			int(cap.get("tile_y", 0)),
			[civ_id]
		)

	# Révolution ou réforme forcée en cas de crise grave de légitimité et d'agitation
	if avg_unrest > 0.68 and float(civ.get("legitimacy", 0.8)) < 0.48 and rng.randf_channel("geopolitics") < 0.28:
		var cap_id: int = int(civ.get("capital_settlement_id", -1))
		var rebel_leader: Dictionary = WorldGenerator.spawn_remarkable_individual(
			state, rng, civ_id, cap_id, int(civ["species_id"]), "RULER", "Refonder les institutions après la révolution"
		)
		civ["ruler_individual_id"] = int(rebel_leader["id"])
		civ["government_type"] = "REPUBLIC" if old_gov in ["KINGDOM", "EMPIRE", "THEOCRACY"] else "KINGDOM"
		civ["legitimacy"] = 0.78
		for s_id in civ["settlement_ids"]:
			if state.settlements.has(s_id):
				state.settlements[s_id]["public_opinion"]["unrest"] = 0.22

		var cap: Dictionary = state.settlements.get(cap_id, {})
		state.record_historical_event(
			"COLLAPSE",
			"Révolution politique au sein de %s !" % String(civ["name"]),
			"Porté par le mécontentement populaire, %s renverse l'ancien pouvoir et instaure le régime : %s." % [
				String(rebel_leader["name"]), String(civ["government_type"])
			],
			["Agitation sociale élevée (%.0f%%)" % (avg_unrest * 100.0), "Faible légitimité gouvernementale"],
			["Nouveau dirigeant : %s" % String(rebel_leader["name"]), "Transition vers %s" % String(civ["government_type"])],
			int(cap.get("tile_x", 0)),
			int(cap.get("tile_y", 0)),
			[civ_id],
			[int(rebel_leader["id"])]
		)


static func _evaluate_bilateral_diplomacy(
	state: WorldState,
	rng: DeterministicRNG,
	civ_a: Dictionary,
	civ_b: Dictionary,
	conflict_mult: float
) -> void:
	var id_a: int = int(civ_a["id"])
	var id_b: int = int(civ_b["id"])

	var cap_a: Dictionary = state.settlements.get(int(civ_a["capital_settlement_id"]), {})
	var cap_b: Dictionary = state.settlements.get(int(civ_b["capital_settlement_id"]), {})
	if cap_a.is_empty() or cap_b.is_empty():
		return

	var dist: float = Vector2(int(cap_a["tile_x"]), int(cap_a["tile_y"])).distance_to(Vector2(int(cap_b["tile_x"]), int(cap_b["tile_y"])))
	if dist > 26.0:
		return # Trop éloignés pour avoir des contacts diplomatiques réguliers

	if not civ_a["diplomacy"].has(id_b):
		civ_a["diplomacy"][id_b] = {"trust": 0.5, "tension": 0.15, "stance": "NEUTRAL", "intel_level": 0.4}
	if not civ_b["diplomacy"].has(id_a):
		civ_b["diplomacy"][id_a] = {"trust": 0.5, "tension": 0.15, "stance": "NEUTRAL", "intel_level": 0.4}

	var rel_ab: Dictionary = civ_a["diplomacy"][id_b]
	var rel_ba: Dictionary = civ_b["diplomacy"][id_a]
	var current_stance: String = String(rel_ab.get("stance", "NEUTRAL"))

	var causal_tensions: Array[String] = []
	var tension_delta: float = 0.0

	# Facteur 1 : Proximité frontalière
	if dist < 11.0:
		tension_delta += 0.035 * conflict_mult
		causal_tensions.append("Concurrence frontalière directe (distance %.1f)" % dist)

	# Facteur 2 : Convergence ou divergence religieuse
	var rel_a: int = int(civ_a.get("state_religion_id", -1))
	var rel_b: int = int(civ_b.get("state_religion_id", -1))
	if rel_a != -1 and rel_b != -1:
		if rel_a == rel_b:
			tension_delta -= 0.04
			rel_ab["trust"] = clampf(float(rel_ab["trust"]) + 0.03, 0.0, 1.0)
		else:
			tension_delta += 0.03 * conflict_mult
			causal_tensions.append("Divergence doctrinale et religieuse")

	# Facteur 3 : Pénurie de ressources chez l'un des acteurs + ambition du dirigeant
	var ruler_a: Dictionary = state.individuals.get(int(civ_a.get("ruler_individual_id", -1)), {})
	var ambition_a: float = float(ruler_a.get("traits", {}).get("ambition", 0.5))
	if float(cap_a["stocks"].get("food", 100.0)) < float(cap_a["population"]) * 0.75 and ambition_a > 0.6:
		tension_delta += 0.05 * conflict_mult
		causal_tensions.append("Pression des ressources à %s et ambition du dirigeant %s" % [String(civ_a["name"]), String(ruler_a.get("name", ""))])

	var new_tension: float = clampf(float(rel_ab["tension"]) + tension_delta, 0.0, 1.0)
	rel_ab["tension"] = snappedf(new_tension, 0.01)
	rel_ba["tension"] = snappedf(new_tension, 0.01)

	# Décision diplomatique : Traité, Alliance, Guerre ou Paix
	if current_stance == "NEUTRAL":
		if new_tension < 0.25 and float(rel_ab["trust"]) > 0.58 and rng.randf_channel("geopolitics") < 0.25:
			rel_ab["stance"] = "ALLIANCE"
			rel_ba["stance"] = "ALLIANCE"
			var t_id: int = state.allocate_treaty_id()
			state.treaties[t_id] = {
				"id": t_id, "civ_a": id_a, "civ_b": id_b,
				"type": "DEFENSIVE_ALLIANCE", "signed_year": state.year, "active": true
			}
			state.record_historical_event(
				"DIPLOMACY",
				"Alliance conclue entre %s et %s" % [String(civ_a["name"]), String(civ_b["name"])],
				"Partageant des intérêts commerciaux et spirituels convergents, %s et %s signent un pacte d'alliance." % [
					String(civ_a["name"]), String(civ_b["name"])
				],
				["Confiance mutuelle (%.0f%%)" % (float(rel_ab["trust"]) * 100.0), "Échanges commerciaux actifs"],
				["Pacte de défense et d'échange"],
				int(cap_a["tile_x"]), int(cap_a["tile_y"]),
				[id_a, id_b]
			)
		elif new_tension >= 0.74 and int(cap_a["population"]) >= 130 and int(cap_b["population"]) >= 90 and rng.randf_channel("geopolitics") < 0.35 * conflict_mult:
			_declare_causal_war(state, rng, civ_a, civ_b, cap_a, cap_b, causal_tensions)

	elif current_stance == "WAR":
		# Vérifier si une armée est encore active ou en mobiliser une, sinon négocier la paix après épuisement
		var has_army_a: bool = _civ_has_active_army(state, id_a)
		if not has_army_a and int(cap_a["population"]) >= 150 and rng.randf_channel("geopolitics") < 0.45:
			_mobilize_army(state, rng, civ_a, cap_a, cap_b)
		elif rng.randf_channel("geopolitics") < 0.16:
			rel_ab["stance"] = "NEUTRAL"
			rel_ba["stance"] = "NEUTRAL"
			rel_ab["tension"] = 0.35
			rel_ba["tension"] = 0.35
			state.record_historical_event(
				"DIPLOMACY",
				"Traité de paix entre %s et %s" % [String(civ_a["name"]), String(civ_b["name"])],
				"Épuisés par l'effort de guerre, %s et %s signent une trêve." % [String(civ_a["name"]), String(civ_b["name"])],
				["Coût logistique et humain du conflit"],
				["Fin des hostilités actives"],
				int(cap_a["tile_x"]), int(cap_a["tile_y"]),
				[id_a, id_b]
			)


static func _declare_causal_war(
	state: WorldState,
	rng: DeterministicRNG,
	civ_a: Dictionary,
	civ_b: Dictionary,
	cap_a: Dictionary,
	cap_b: Dictionary,
	causes: Array[String]
) -> void:
	var id_a: int = int(civ_a["id"])
	var id_b: int = int(civ_b["id"])
	civ_a["diplomacy"][id_b]["stance"] = "WAR"
	civ_b["diplomacy"][id_a]["stance"] = "WAR"

	if causes.is_empty():
		causes.append("Rivalité géopolitique et territoriale")

	var ev: Dictionary = state.record_historical_event(
		"WAR",
		"Guerre déclarée : %s contre %s" % [String(civ_a["name"]), String(civ_b["name"])],
		"%s entre en guerre contre %s." % [String(civ_a["name"]), String(civ_b["name"])],
		causes,
		["Mobilisation militaire et rupture du commerce"],
		int(cap_a["tile_x"]),
		int(cap_a["tile_y"]),
		[id_a, id_b]
	)
	state.record_diagnostic(
		"GeopoliticsMilitarySystem",
		"%s -> %s" % [String(civ_a["name"]), String(civ_b["name"])],
		"Déclaration de guerre (Événement #%d)" % int(ev["id"]),
		causes
	)

	# Prière de protection adressée par la cible
	CultureReligionSystem.spawn_prayer(
		state,
		id_b,
		int(cap_b["id"]),
		"WAR_PROTECTION",
		"Invasion contre %s" % String(cap_b["name"]),
		"Les armées de %s marchent sur %s ! Le peuple implore une intervention divine pour protéger ses murailles." % [
			String(civ_a["name"]), String(cap_b["name"])
		],
		0.88
	)

	_mobilize_army(state, rng, civ_a, cap_a, cap_b, int(ev["id"]))


static func _mobilize_army(
	state: WorldState,
	rng: DeterministicRNG,
	civ: Dictionary,
	origin_settlement: Dictionary,
	target_settlement: Dictionary,
	war_event_id: int = -1
) -> Dictionary:
	var pop: int = int(origin_settlement["population"])
	var recruits: int = clampi(int(round(float(pop) * 0.16)), 20, 180)
	if pop - recruits < 45:
		return {}

	origin_settlement["population"] = pop - recruits
	origin_settlement["stocks"]["food"] = maxf(0.0, float(origin_settlement["stocks"]["food"]) - float(recruits) * 1.1)

	var techs: Array = civ.get("technologies", [])
	var equip: float = 1.0 + (0.45 if techs.has("METALLURGY") else 0.0) + (0.25 if origin_settlement["buildings"].has("FORGE") else 0.0)

	var army_id: int = state.allocate_army_id()
	var army: Dictionary = {
		"id": army_id,
		"civ_id": int(civ["id"]),
		"commander_id": int(civ.get("ruler_individual_id", -1)),
		"name": "Ost de %s" % String(civ["name"]),
		"tile_x": int(origin_settlement["tile_x"]),
		"tile_y": int(origin_settlement["tile_y"]),
		"target_x": int(target_settlement["tile_x"]),
		"target_y": int(target_settlement["tile_y"]),
		"target_settlement_id": int(target_settlement["id"]),
		"manpower": recruits,
		"max_manpower": recruits,
		"supply": 100.0,
		"morale": 0.85,
		"experience": 0.25,
		"equipment_level": equip,
		"objective": "SIEGE",
		"causal_war_id": war_event_id
	}
	state.armies[army_id] = army
	return army


static func _civ_has_active_army(state: WorldState, civ_id: int) -> bool:
	for a_id in state.armies.keys():
		if int(state.armies[a_id]["civ_id"]) == civ_id:
			return true
	return false


static func _resolve_army_engagement(state: WorldState, rng: DeterministicRNG, army: Dictionary) -> void:
	var target_s_id: int = int(army.get("target_settlement_id", -1))
	if not state.settlements.has(target_s_id):
		state.armies.erase(int(army["id"]))
		return

	var target_s: Dictionary = state.settlements[target_s_id]
	if String(target_s.get("tier", "RUIN")) == "RUIN":
		state.armies.erase(int(army["id"]))
		return

	var attacker_civ_id: int = int(army["civ_id"])
	var defender_civ_id: int = int(target_s["civ_id"])
	if attacker_civ_id == defender_civ_id:
		# Retour au foyer : démobilisation des troupes survivantes
		target_s["population"] = int(target_s["population"]) + int(army["manpower"])
		state.armies.erase(int(army["id"]))
		return

	var atk_power: float = float(army["manpower"]) * float(army["equipment_level"]) * float(army["morale"]) * (0.5 + float(army["supply"]) / 200.0)
	var has_walls: bool = target_s["buildings"].has("WALLS")
	var def_garrison: float = float(target_s["population"]) * 0.22
	var def_power: float = def_garrison * (1.55 if has_walls else 1.0) * rng.randf_range_channel("geopolitics", 0.85, 1.2)

	var sx: int = int(target_s["tile_x"])
	var sy: int = int(target_s["tile_y"])
	var atk_civ_name: String = String(state.civilizations.get(attacker_civ_id, {}).get("name", "Assaillant"))
	var def_civ_name: String = String(state.civilizations.get(defender_civ_id, {}).get("name", "Défenseur"))

	if atk_power > def_power:
		# Prise de la cité par l'attaquant !
		var losses: int = clampi(int(round(float(army["manpower"]) * 0.35)), 5, int(army["manpower"]) - 5)
		var civ_losses: int = clampi(int(round(float(target_s["population"]) * 0.12)), 5, maxi(5, int(target_s["population"]) - 25))
		target_s["population"] = maxi(25, int(target_s["population"]) - civ_losses)

		if state.civilizations.has(defender_civ_id):
			var def_civ: Dictionary = state.civilizations[defender_civ_id]
			def_civ["settlement_ids"].erase(target_s_id)
			def_civ["historical_grievances"].append({
				"year": state.year,
				"against_civ_id": attacker_civ_id,
				"reason": "Conquête de %s" % String(target_s["name"])
			})
			if def_civ["settlement_ids"].is_empty():
				def_civ["alive"] = false

		target_s["civ_id"] = attacker_civ_id
		if state.civilizations.has(attacker_civ_id):
			var atk_civ: Dictionary = state.civilizations[attacker_civ_id]
			if not atk_civ["settlement_ids"].has(target_s_id):
				atk_civ["settlement_ids"].append(target_s_id)

		for n_tile in state.get_neighbors(sx, sy, 2):
			if int(n_tile.get("owner_civ_id", -1)) == defender_civ_id:
				n_tile["owner_civ_id"] = attacker_civ_id
		var center_t: Dictionary = state.get_tile(sx, sy)
		if not center_t.is_empty():
			center_t["owner_civ_id"] = attacker_civ_id

		state.record_historical_event(
			"WAR",
			"Prise de %s par %s" % [String(target_s["name"]), atk_civ_name],
			"Après un siège décisif (Force %.0f contre %.0f), %s s'empare de %s aux dépens de %s (%d pertes militaires)." % [
				atk_power, def_power, atk_civ_name, String(target_s["name"]), def_civ_name, losses
			],
			["Supériorité tactique et logistique de %s" % atk_civ_name],
			["Changement de souveraineté sur %s" % String(target_s["name"]), "Mémoire de grief chez %s" % def_civ_name],
			sx,
			sy,
			[attacker_civ_id, defender_civ_id]
		)
		state.add_visual_pulse(sx, sy, Color(0.95, 0.25, 0.25), 2.8, "Conquête !")
	else:
		# Le siège est repoussé !
		state.record_historical_event(
			"WAR",
			"Victoire défensive de %s à %s" % [def_civ_name, String(target_s["name"])],
			"Les défenseurs de %s ont brisé l'assaut de %s grâce à leurs fortifications et à l'usure logistique adverse." % [
				String(target_s["name"]), atk_civ_name
			],
			["Résistance des fortifications" if has_walls else "Mobilisation de la garnison locale"],
			["Retraite et dispersion de l'armée assaillante"],
			sx,
			sy,
			[attacker_civ_id, defender_civ_id]
		)
		state.add_visual_pulse(sx, sy, Color(0.35, 0.78, 0.98), 2.4, "Siège Repoussé")

	state.armies.erase(int(army["id"]))
