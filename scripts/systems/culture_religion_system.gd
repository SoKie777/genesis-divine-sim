class_name CultureReligionSystem
extends RefCounted
## Système culturel, scientifique, individuel et religieux.
## Gère :
## - Le cycle de vie, la succession et l'émergence des individus remarquables.
## - La découverte, la diffusion commerciale et la perte éventuelle des technologies.
## - L'architecture complète des religions (10 composantes), les prophètes, la diffusion,
##   les schismes doctrinaux et la génération causale de prières adressées au joueur.

const TECH_CATALOG: Dictionary = {
	"AGRICULTURE": {"cost": 70.0, "prereqs": [], "desc": "Domestication des semences et culture céréalière"},
	"POTTERY": {"cost": 80.0, "prereqs": [], "desc": "Conservation durable des grains et de l'eau"},
	"NAVIGATION": {"cost": 95.0, "prereqs": [], "desc": "Cabotage côtier, pêche hauturière et commerce maritime"},
	"IRRIGATION": {"cost": 120.0, "prereqs": ["AGRICULTURE"], "desc": "Canaux hydrauliques et maîtrise des crues"},
	"METALLURGY": {"cost": 135.0, "prereqs": ["POTTERY"], "desc": "Fonte des métaux, outils durables et armement"},
	"WRITING": {"cost": 155.0, "prereqs": ["POTTERY"], "desc": "Codification des lois, chroniques et textes sacrés"},
	"MATHEMATICS": {"cost": 190.0, "prereqs": ["WRITING"], "desc": "Géométrie, comptabilité marchande et astronomie"},
	"MEDICINE": {"cost": 210.0, "prereqs": ["WRITING"], "desc": "Herboristerie savante, hygiène urbaine et endiguement des pestes"},
	"ARCHITECTURE": {"cost": 230.0, "prereqs": ["MATHEMATICS", "METALLURGY"], "desc": "Merveilles monumentales, aqueducs et citadelles"},
	"PRINTING": {"cost": 290.0, "prereqs": ["WRITING", "METALLURGY"], "desc": "Diffusion rapide des écrits, des sciences et des réformes religieuses"},
	"MACHINERY": {"cost": 360.0, "prereqs": ["MATHEMATICS", "METALLURGY"], "desc": "Mécanisation artisanale et moulins hydrauliques"},
	"SCIENTIFIC_METHOD": {"cost": 450.0, "prereqs": ["PRINTING", "MATHEMATICS"], "desc": "Enquête empirique sur les lois de la nature"}
}

const RELIGION_NAMES_PREFIX: Array[String] = [
	"Ordre de", "Voie de", "Enfants de", "Culte de", "Alliance de", "Fraternité de", "Sagesse de"
]
const RELIGION_NAMES_CORE: Array[String] = [
	"la Flamme Éternelle", "la Source Céleste", "l'Harmonie Cosmique", "la Lumière Invaincue",
	"l'Arbre-Monde", "l'Étoile Astrale", "l'Aube Dorée", "la Foudre Céleste"
]


static func update_quarterly_culture_and_religion(state: WorldState, rng: DeterministicRNG) -> void:
	# 1. Recherche technologique et diffusion par les routes commerciales
	for c_id in state.civilizations.keys():
		var civ: Dictionary = state.civilizations[c_id]
		if not bool(civ.get("alive", false)):
			continue
		_update_civilization_research(state, rng, civ)

	# 2. Naissance spontanée de croyances, diffusion religieuse et schismes
	_update_religions_and_diffusion(state, rng)

	# 3. Expiration des prières anciennes non traitées (avec conséquences sur la foi/interprétation)
	_update_pending_prayers(state, rng)


static func update_yearly_individuals(state: WorldState, rng: DeterministicRNG) -> void:
	var life_mult: float = clampf(float(state.natural_laws.get("lifespan_multiplier", 1.0)), 0.3, 5.0)

	for ind_id in state.individuals.keys():
		var ind: Dictionary = state.individuals[ind_id]
		if not bool(ind.get("alive", false)):
			continue

		ind["age"] = int(ind["age"]) + 1
		var effective_max_age: int = int(round(float(ind.get("max_age", 68)) * (1.25 if bool(ind.get("blessed_by_god", false)) else 1.0)))

		if int(ind["age"]) >= effective_max_age:
			_handle_individual_death(state, rng, ind, "Vieillesse naturelle")

	# Émergence possible de nouveaux personnages historiques selon le contexte
	for c_id in state.civilizations.keys():
		var civ: Dictionary = state.civilizations[c_id]
		if not bool(civ.get("alive", false)):
			continue

		var active_inds: int = 0
		for ind_id in state.individuals.keys():
			var ind: Dictionary = state.individuals[ind_id]
			if bool(ind.get("alive", false)) and int(ind["civ_id"]) == int(c_id):
				active_inds += 1

		if active_inds < 4 and rng.randf_channel("individual") < 0.32 * (1.0 / life_mult):
			var cap_id: int = int(civ.get("capital_settlement_id", -1))
			if state.settlements.has(cap_id):
				var roles: Array[String] = ["SCHOLAR", "PROPHET", "GENERAL", "MERCHANT"]
				var role: String = String(rng.pick_random("individual", roles))
				var goal: String = "Faire progresser les arts et le savoir" if role == "SCHOLAR" else (
					"Guider les âmes vers la transcendance" if role == "PROPHET" else (
						"Protéger les frontières de %s" % String(civ["name"]) if role == "GENERAL" else "Étendre les routes marchandes"
					)
				)
				var new_ind: Dictionary = WorldGenerator.spawn_remarkable_individual(
					state, rng, int(c_id), cap_id, int(civ["species_id"]), role, goal
				)
				if role == "PROPHET" and int(civ.get("state_religion_id", -1)) == -1 and rng.randf_channel("religion") < 0.65:
					var new_rel: Dictionary = found_religion(
						state, rng, int(c_id), cap_id, int(new_ind["id"]), "Révélation Intérieure"
					)
					if not new_rel.is_empty():
						civ["state_religion_id"] = int(new_rel["id"])


static func _handle_individual_death(state: WorldState, rng: DeterministicRNG, ind: Dictionary, cause: String) -> void:
	ind["alive"] = false
	var civ_id: int = int(ind["civ_id"])
	var s_id: int = int(ind["settlement_id"])
	var sx: int = 0
	var sy: int = 0
	if state.settlements.has(s_id):
		sx = int(state.settlements[s_id]["tile_x"])
		sy = int(state.settlements[s_id]["tile_y"])

	# Transcendance spirituelle si la loi de la nature l'autorise et que l'individu est béni ou prophète
	if bool(state.natural_laws.get("mortality_can_transcend", false)) and (bool(ind.get("blessed_by_god", false)) or String(ind["role"]) == "PROPHET"):
		var sp_id: int = state.allocate_spirit_id()
		state.spiritual_entities[sp_id] = {
			"id": sp_id,
			"name": "Esprit Ascendant de " + String(ind["name"]),
			"entity_type": "ASCENDED_SAINT",
			"plane": "CELESTIAL",
			"tile_x": sx,
			"tile_y": sy,
			"power_level": 0.85,
			"autonomous_goal": "INSPIRE_MORTALS",
			"perceived_by_religions": [int(ind.get("religion_id", -1))]
		}

	# Si c'était le dirigeant d'une civilisation, organiser la succession
	if state.civilizations.has(civ_id):
		var civ: Dictionary = state.civilizations[civ_id]
		if int(civ.get("ruler_individual_id", -1)) == int(ind["id"]) and bool(civ.get("alive", false)):
			var cap_id: int = int(civ.get("capital_settlement_id", s_id))
			var successor: Dictionary = WorldGenerator.spawn_remarkable_individual(
				state, rng, civ_id, cap_id, int(civ["species_id"]), "RULER", "Consolider l'héritage de " + String(civ["name"])
			)
			civ["ruler_individual_id"] = int(successor["id"])
			# Risque de baisse temporaire de légitimité lors d'une succession
			civ["legitimacy"] = clampf(float(civ.get("legitimacy", 0.8)) - 0.08, 0.25, 1.0)
			state.record_historical_event(
				"BIOGRAPHY",
				"Succession à la tête de %s" % String(civ["name"]),
				"À la mort de %s (%s), %s accède au pouvoir selon les institutions (%s)." % [
					String(ind["name"]), cause, String(successor["name"]), String(civ.get("government_type", "TRIBE"))
				],
				["Décès de %s à %d ans" % [String(ind["name"]), int(ind["age"])]],
				["Nouveau dirigeant : %s" % String(successor["name"])],
				sx,
				sy,
				[civ_id],
				[int(ind["id"]), int(successor["id"])]
			)


static func _update_civilization_research(state: WorldState, rng: DeterministicRNG, civ: Dictionary) -> void:
	var known: Array = civ["technologies"]
	var progress: Dictionary = civ["research_progress"]

	# Calcul de la capacité scientifique réelle (Population + Académies + Savants + Attitude culturelle)
	var total_pop: int = 0
	var academy_count: int = 0
	for s_id in civ["settlement_ids"]:
		if state.settlements.has(s_id):
			var s: Dictionary = state.settlements[s_id]
			if String(s.get("tier", "RUIN")) != "RUIN":
				total_pop += int(s["population"])
				if s["buildings"].has("ACADEMY"):
					academy_count += 1

	var scholar_bonus: float = 1.0
	for ind_id in state.individuals.keys():
		var ind: Dictionary = state.individuals[ind_id]
		if bool(ind.get("alive", false)) and int(ind["civ_id"]) == int(civ["id"]):
			if String(ind["role"]) == "SCHOLAR":
				scholar_bonus += 0.35 + float(ind["traits"].get("curiosity", 0.5)) * 0.3
			if bool(ind.get("blessed_by_god", false)):
				scholar_bonus += 0.25

	var research_points: float = (float(total_pop) * 0.045 + float(academy_count) * 18.0 + 6.0) * scholar_bonus

	# Choisir une technologie découvrable dont les prérequis sont remplis
	var available_techs: Array[String] = []
	for tech_id in TECH_CATALOG.keys():
		if known.has(tech_id):
			continue
		var prereqs: Array = TECH_CATALOG[tech_id]["prereqs"]
		var ok: bool = true
		for pre in prereqs:
			if not known.has(pre):
				ok = false
				break
		if ok:
			available_techs.append(tech_id)

	if not available_techs.is_empty():
		var target_tech: String = available_techs[0]
		var current_val: float = float(progress.get(target_tech, 0.0)) + research_points
		var cost: float = float(TECH_CATALOG[target_tech]["cost"])

		# Bonus de diffusion par le commerce si un partenaire commercial connaît déjà cette technologie
		for s_id in civ["settlement_ids"]:
			if state.settlements.has(s_id):
				for p_id in state.settlements[s_id].get("trade_partners", []):
					if state.settlements.has(p_id):
						var p_civ_id: int = int(state.settlements[p_id]["civ_id"])
						if state.civilizations.has(p_civ_id) and state.civilizations[p_civ_id]["technologies"].has(target_tech):
							current_val += 12.0

		if current_val >= cost:
			known.append(target_tech)
			progress.erase(target_tech)
			var cap_id: int = int(civ.get("capital_settlement_id", -1))
			var cx: int = 0
			var cy: int = 0
			if state.settlements.has(cap_id):
				cx = int(state.settlements[cap_id]["tile_x"])
				cy = int(state.settlements[cap_id]["tile_y"])

			state.record_historical_event(
				"TECH",
				"%s découvre : %s" % [String(civ["name"]), target_tech],
				"Les savants et artisans de %s ont maîtrisé %s (%s)." % [
					String(civ["name"]), target_tech, String(TECH_CATALOG[target_tech]["desc"])
				],
				["Accumulation de savoir (%d habitants, %d académies)" % [total_pop, academy_count]],
				[String(TECH_CATALOG[target_tech]["desc"])],
				cx,
				cy,
				[int(civ["id"])]
			)
			_update_world_era(state, target_tech)
		else:
			progress[target_tech] = snappedf(current_val, 0.1)


static func _update_world_era(state: WorldState, discovered_tech: String) -> void:
	match discovered_tech:
		"METALLURGY":
			if state.era_name in ["Âge de la Genèse", "Âge de l'Aube"]:
				state.era_name = "Âge du Bronze et du Fer"
		"WRITING":
			if state.era_name != "Âge des Empires Savants":
				state.era_name = "Âge des Chroniques Écrites"
		"PRINTING", "MACHINERY":
			state.era_name = "Âge des Académies et des Machines"
		"SCIENTIFIC_METHOD":
			state.era_name = "Âge de la Raison et des Sciences"


static func found_religion(
	state: WorldState,
	rng: DeterministicRNG,
	civ_id: int,
	settlement_id: int,
	founder_id: int,
	origin_cause: String,
	parent_religion_id: int = -1
) -> Dictionary:
	var rel_id: int = state.allocate_religion_id()
	var prefix: String = String(rng.pick_random("religion", RELIGION_NAMES_PREFIX))
	var core: String = String(rng.pick_random("religion", RELIGION_NAMES_CORE))
	var rel_name: String = "%s %s" % [prefix, core]

	var theologies: Array[String] = ["MONOTHEIST", "POLYTHEIST", "ANIMIST", "PANTHEIST", "ANCESTOR_WORSHIP", "NON_THEIST_PHILOSOPHY"]
	var theo_type: String = String(rng.pick_random("religion", theologies))
	var colors: Array[Color] = [
		Color(0.98, 0.82, 0.28),
		Color(0.45, 0.85, 0.98),
		Color(0.88, 0.48, 0.96),
		Color(0.42, 0.94, 0.65),
		Color(0.98, 0.56, 0.38)
	]

	var sx: int = 0
	var sy: int = 0
	var tile_idx: int = 0
	if state.settlements.has(settlement_id):
		sx = int(state.settlements[settlement_id]["tile_x"])
		sy = int(state.settlements[settlement_id]["tile_y"])
		tile_idx = state.get_tile_index(sx, sy)

	var rel: Dictionary = {
		"id": rel_id,
		"name": rel_name,
		"color": colors[(rel_id - 1) % colors.size()],
		"founded_year": state.year,
		"founder_individual_id": founder_id,
		"origin_settlement_id": settlement_id,
		"parent_religion_id": parent_religion_id,
		"theology_type": theo_type,
		"cosmology": "L'univers est né d'un souffle primordial révélé lors de : %s." % origin_cause,
		"divine_nature": _describe_divine_nature(theo_type),
		"spiritual_anthropology": "Les mortels sont les gardiens du sens et sont jugés selon leurs actes.",
		"ethics": [
			String(rng.pick_random("religion", ["Hospitalité sacrée", "Partage des récoltes", "Quête de vérité", "Respect des anciens"])),
			String(rng.pick_random("religion", ["Protection de la terre", "Fidélité aux serments", "Tempérance", "Courage face aux épreuves"]))
		],
		"rites": [
			String(rng.pick_random("religion", ["Offrandes des équinoxes", "Chants de l'Aube", "Pèlerinage au sanctuaire", "Veillée des étoiles"]))
		],
		"institutions": String(rng.pick_random("religion", ["SHAMANIC_CIRCLE", "DECENTRALIZED_PRIESTS", "HIERARCHICAL_CHURCH", "MONASTIC_ORDERS"])),
		"sacred_texts": ["Livre de la Fondation (%s, An %d)" % [origin_cause, state.year]],
		"internal_unity": 0.88,
		"schism_tensions": [],
		"holy_site_tiles": [tile_idx],
		"total_believers": 0
	}
	state.religions[rel_id] = rel

	if state.settlements.has(settlement_id):
		var comp: Dictionary = state.settlements[settlement_id]["religious_composition"]
		comp[rel_id] = clampf(float(comp.get(rel_id, 0.0)) + 0.65, 0.0, 1.0)
		_normalize_religious_composition(comp)

	if state.individuals.has(founder_id):
		state.individuals[founder_id]["religion_id"] = rel_id

	var civ_name: String = String(state.civilizations.get(civ_id, {}).get("name", "Peuple Local"))
	state.record_historical_event(
		"RELIGION" if parent_religion_id == -1 else "SCHISM",
		"Naissance spirituelle : %s" % rel_name,
		"Une nouvelle tradition (%s) émerge au sein de %s suite à : %s." % [theo_type, civ_name, origin_cause],
		[origin_cause],
		["Doctrine : %s" % rel["divine_nature"]],
		sx,
		sy,
		[civ_id],
		[founder_id] if founder_id != -1 else []
	)
	_recompute_religion_believer_counts(state)
	return rel


static func _describe_divine_nature(theo_type: String) -> String:
	match theo_type:
		"MONOTHEIST": return "Un Créateur suprême transcendant qui observe et juge le monde"
		"POLYTHEIST": return "Un panthéon de puissances célestes régissant les saisons et le destin"
		"ANIMIST": return "Chaque fleuve, forêt et montagne abrite un esprit vivant"
		"PANTHEIST": return "Le Divin et la Nature ne forment qu'une seule réalité indivisible"
		"ANCESTOR_WORSHIP": return "La mémoire des fondateurs guide et protège les vivants"
		_: return "Philosophie morale cherchant l'harmonie avec les lois universelles"


static func _update_religions_and_diffusion(state: WorldState, rng: DeterministicRNG) -> void:
	# 1. Naissance spontanée si aucune religion n'existe encore dans une ville ancienne
	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		if String(s.get("tier", "RUIN")) == "RUIN":
			continue
		var comp: Dictionary = s["religious_composition"]
		if comp.is_empty() and int(s["population"]) >= 130 and rng.randf_channel("religion") < 0.25:
			var civ_id: int = int(s["civ_id"])
			var civ: Dictionary = state.civilizations.get(civ_id, {})
			var ruler_id: int = int(civ.get("ruler_individual_id", -1))
			var rel: Dictionary = found_religion(state, rng, civ_id, int(s["id"]), ruler_id, "Émerveillement face à la nature et quête de sens")
			if not rel.is_empty() and int(civ.get("state_religion_id", -1)) == -1:
				civ["state_religion_id"] = int(rel["id"])

	# 2. Diffusion missionnaire et commerciale entre établissements partenaires
	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		if String(s.get("tier", "RUIN")) == "RUIN":
			continue
		var dominant_rel: int = get_dominant_religion_in_settlement(s)
		if dominant_rel == -1:
			continue
		for partner_id in s.get("trade_partners", []):
			if state.settlements.has(partner_id):
				var p_set: Dictionary = state.settlements[partner_id]
				if String(p_set.get("tier", "RUIN")) == "RUIN":
					continue
				var p_comp: Dictionary = p_set["religious_composition"]
				p_comp[dominant_rel] = float(p_comp.get(dominant_rel, 0.0)) + 0.06
				_normalize_religious_composition(p_comp)

	# 3. Dynamique interne des religions et risque de schisme doctrinal
	var rel_ids: Array = state.religions.keys()
	for r_id in rel_ids:
		var rel: Dictionary = state.religions[r_id]
		var believers: int = int(rel.get("total_believers", 0))
		if believers > 420:
			rel["internal_unity"] = clampf(float(rel.get("internal_unity", 0.85)) - 0.025, 0.15, 1.0)
		if float(rel.get("internal_unity", 0.85)) < 0.42 and rng.randf_channel("religion") < 0.30:
			_trigger_religious_schism(state, rng, rel)

	_recompute_religion_believer_counts(state)


static func _trigger_religious_schism(state: WorldState, rng: DeterministicRNG, parent_rel: Dictionary) -> void:
	# Trouver une ville où cette religion est présente pour y faire éclater la réforme
	var target_settlement: Dictionary = {}
	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		if String(s.get("tier", "RUIN")) != "RUIN" and s["religious_composition"].has(int(parent_rel["id"])):
			target_settlement = s
			break
	if target_settlement.is_empty():
		return

	parent_rel["internal_unity"] = 0.78
	var civ_id: int = int(target_settlement["civ_id"])
	var reformer: Dictionary = WorldGenerator.spawn_remarkable_individual(
		state, rng, civ_id, int(target_settlement["id"]), 1, "PROPHET", "Réformer la doctrine de " + String(parent_rel["name"])
	)
	var new_rel: Dictionary = found_religion(
		state,
		rng,
		civ_id,
		int(target_settlement["id"]),
		int(reformer["id"]),
		"Schisme doctrinal sur l'interprétation des rites et des signes divins au sein de " + String(parent_rel["name"]),
		int(parent_rel["id"])
	)
	if not new_rel.is_empty():
		state.record_diagnostic(
			"CultureReligionSystem",
			String(parent_rel["name"]),
			"Schisme donnant naissance à %s" % String(new_rel["name"]),
			["Unité doctrinale tombée sous le seuil critique", "Prédication réformatrice de %s à %s" % [String(reformer["name"]), String(target_settlement["name"])]]
		)


static func get_dominant_religion_in_settlement(settlement: Dictionary) -> int:
	var comp: Dictionary = settlement.get("religious_composition", {})
	var best_rel: int = -1
	var best_share: float = 0.0
	for r_id in comp.keys():
		var share: float = float(comp[r_id])
		if share > best_share:
			best_share = share
			best_rel = int(r_id)
	return best_rel


static func _normalize_religious_composition(comp: Dictionary) -> void:
	var total: float = 0.0
	for k in comp.keys():
		total += maxf(0.0, float(comp[k]))
	if total <= 0.0001:
		return
	for k in comp.keys():
		comp[k] = snappedf(maxf(0.0, float(comp[k])) / total, 0.01)


static func _recompute_religion_believer_counts(state: WorldState) -> void:
	for r_id in state.religions.keys():
		state.religions[r_id]["total_believers"] = 0

	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		if String(s.get("tier", "RUIN")) == "RUIN":
			continue
		var pop: int = int(s["population"])
		var comp: Dictionary = s.get("religious_composition", {})
		for r_id in comp.keys():
			var int_r: int = int(r_id)
			if state.religions.has(int_r):
				var count: int = int(round(float(pop) * float(comp[r_id])))
				state.religions[int_r]["total_believers"] = int(state.religions[int_r]["total_believers"]) + count


static func spawn_prayer(
	state: WorldState,
	civ_id: int,
	settlement_id: int,
	category: String,
	title: String,
	description: String,
	urgency: float
) -> Dictionary:
	# Regrouper / éviter les doublons pour le même établissement et la même catégorie
	for p_id in state.prayers.keys():
		var existing: Dictionary = state.prayers[p_id]
		if existing.get("status", "") == "PENDING" and int(existing.get("settlement_id", -1)) == settlement_id and String(existing.get("category", "")) == category:
			existing["urgency"] = maxf(float(existing["urgency"]), urgency)
			existing["ticks_remaining"] = 180
			return existing

	if not state.settlements.has(settlement_id):
		return {}
	var s: Dictionary = state.settlements[settlement_id]
	var dom_rel: int = get_dominant_religion_in_settlement(s)
	var prayer_id: int = state.allocate_prayer_id()
	var prayer: Dictionary = {
		"id": prayer_id,
		"year": state.year,
		"settlement_id": settlement_id,
		"civ_id": civ_id,
		"religion_id": dom_rel,
		"petitioner_id": -1,
		"category": category,
		"urgency": snappedf(urgency, 0.01),
		"title": title,
		"description": description,
		"tile_x": int(s["tile_x"]),
		"tile_y": int(s["tile_y"]),
		"status": "PENDING",
		"ticks_remaining": 180
	}
	state.prayers[prayer_id] = prayer
	return prayer


static func _update_pending_prayers(state: WorldState, rng: DeterministicRNG) -> void:
	for p_id in state.prayers.keys():
		var p: Dictionary = state.prayers[p_id]
		if String(p.get("status", "")) != "PENDING":
			continue
		p["ticks_remaining"] = int(p.get("ticks_remaining", 90)) - 90
		if int(p["ticks_remaining"]) <= 0:
			p["status"] = "EXPIRED"
			var rel_id: int = int(p.get("religion_id", -1))
			if state.religions.has(rel_id):
				var rel: Dictionary = state.religions[rel_id]
				# Une prière non exaucée peut susciter le doute ou de nouvelles interprétations théologiques
				rel["internal_unity"] = clampf(float(rel.get("internal_unity", 0.8)) - 0.04, 0.15, 1.0)
				if rng.randf_channel("religion") < 0.35:
					rel["sacred_texts"].append("Méditation sur le Silence du Ciel (An %d)" % state.year)
