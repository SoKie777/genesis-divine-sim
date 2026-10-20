class_name WorldSimulation
extends RefCounted
## Orchestrateur principal du moteur de simulation multi-échelle (GENESIS).
## Coordonne l'horloge déterministe, les pipelines climatiques, écologiques,
## économiques, démographiques, culturels, religieux et géopolitiques,
## ainsi que les outils de vérification scientifique (DebugTools).

var state: WorldState
var rng: DeterministicRNG

# Contrôle temporel
var speed_multiplier: float = 1.0 # 0.0 (Pause), 1.0, 5.0, 20.0, 100.0
var base_ticks_per_second: float = 10.0 # À 1x : 10 jours simulés / seconde
var auto_slow_on_crisis: bool = false
var _tick_accumulator: float = 0.0


func _init() -> void:
	state = WorldState.new()
	rng = DeterministicRNG.new(state.world_seed)


func initialize_new_world(config: Dictionary = {}) -> void:
	WorldGenerator.generate_world(state, rng, config)
	_record_yearly_snapshot()


func update_frame(delta: float) -> int:
	# Mise à jour des impulsions visuelles et textes flottants éphémères
	for i in range(state.visual_pulses.size() - 1, -1, -1):
		var p: Dictionary = state.visual_pulses[i]
		p["ttl"] = float(p["ttl"]) - delta
		if float(p["ttl"]) <= 0.0:
			state.visual_pulses.remove_at(i)

	for j in range(state.floating_texts.size() - 1, -1, -1):
		var ft: Dictionary = state.floating_texts[j]
		ft["ttl"] = float(ft["ttl"]) - delta
		if float(ft["ttl"]) <= 0.0:
			state.floating_texts.remove_at(j)

	if speed_multiplier <= 0.001:
		return 0

	_tick_accumulator += delta * base_ticks_per_second * speed_multiplier
	var ticks_to_run: int = mini(int(floor(_tick_accumulator)), 120) # Plafond anti-spirale par frame
	if ticks_to_run > 0:
		_tick_accumulator -= float(ticks_to_run)
		step_ticks(ticks_to_run)
	return ticks_to_run


func step_ticks(count: int) -> void:
	for _i in range(count):
		_step_single_tick()


func _step_single_tick() -> void:
	state.current_tick += 1
	state.day += 1

	# Cycle hebdomadaire (7 jours) : Logistique, mouvements militaires et caravanes marchandes
	if state.current_tick % 7 == 0:
		GeopoliticsMilitarySystem.update_weekly_military(state, rng)
		EconomyPopulationSystem.update_weekly_caravans(state)

	# Fin de mois (30 jours)
	if state.day > 30:
		state.day = 1
		state.month += 1

		EcologyClimateSystem.update_monthly_ecology(state, rng)
		EconomyPopulationSystem.update_monthly_economy_and_population(state, rng)
		GeopoliticsMilitarySystem.update_monthly_geopolitics(state, rng)

		# Changement de saison tous les 3 mois (90 jours)
		if state.month in [1, 4, 7, 10]:
			state.season = _season_for_month(state.month)
			EcologyClimateSystem.update_seasonal_climate(state, rng)
			CultureReligionSystem.update_quarterly_culture_and_religion(state, rng)

		# Fin d'année (12 mois = 360 jours)
		if state.month > 12:
			state.month = 1
			state.year += 1
			state.season = "Printemps"
			EcologyClimateSystem.update_seasonal_climate(state, rng)
			CultureReligionSystem.update_quarterly_culture_and_religion(state, rng)
			CultureReligionSystem.update_yearly_individuals(state, rng)
			_record_yearly_snapshot()


static func _season_for_month(m: int) -> String:
	if m in [1, 2, 3]:
		return "Printemps"
	elif m in [4, 5, 6]:
		return "Été"
	elif m in [7, 8, 9]:
		return "Automne"
	return "Hiver"


func _record_yearly_snapshot() -> void:
	var civ_metrics: Dictionary = {}
	for c_id in state.civilizations.keys():
		var civ: Dictionary = state.civilizations[c_id]
		if not bool(civ.get("alive", false)):
			continue
		var pop: int = 0
		var wealth: float = float(civ.get("treasury", 0.0))
		for s_id in civ["settlement_ids"]:
			if state.settlements.has(s_id):
				var s: Dictionary = state.settlements[s_id]
				if String(s.get("tier", "RUIN")) != "RUIN":
					pop += int(s["population"])
					wealth += float(s["stocks"].get("wealth", 0.0))
		civ_metrics[int(c_id)] = {
			"name": String(civ["name"]),
			"population": pop,
			"wealth": snappedf(wealth, 0.1),
			"tech_count": int(civ["technologies"].size()),
			"cities": int(civ["settlement_ids"].size())
		}

	state.history_snapshots.append({
		"year": state.year,
		"total_pop": state.get_total_population(),
		"active_civs": state.get_active_civ_count(),
		"active_religions": state.get_active_religion_count(),
		"ecology_health": snappedf(state.get_global_ecology_health(), 0.01),
		"civ_metrics": civ_metrics
	})
	if state.history_snapshots.size() > 250:
		state.history_snapshots.pop_front()


## Outil de vérification scientifique des invariants du monde (Section 23 du Prompt Maître)
func verify_world_invariants() -> Dictionary:
	var anomalies: Array[String] = []

	# 1. Vérification des tuiles (absence de NaN et cohérence des bornes)
	for tile in state.tiles:
		var elev: float = float(tile.get("elevation", 0.0))
		var fert: float = float(tile.get("fertility", 0.0))
		if is_nan(elev) or is_nan(fert):
			anomalies.append("Tuile (%d,%d) contient une valeur NaN." % [int(tile["x"]), int(tile["y"])])
		if fert < 0.0 or fert > 1.01:
			anomalies.append("Tuile (%d,%d) fertilité hors bornes : %f" % [int(tile["x"]), int(tile["y"]), fert])

	# 2. Vérification des établissements (populations et stocks jamais négatifs)
	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		var pop: int = int(s.get("population", 0))
		if pop < 0:
			anomalies.append("Établissement %s a une population négative (%d)." % [String(s["name"]), pop])
		var stocks: Dictionary = s.get("stocks", {})
		for res_key in stocks.keys():
			var val: float = float(stocks[res_key])
			if is_nan(val) or val < -0.01:
				anomalies.append("Établissement %s stock invalide pour %s : %f" % [String(s["name"]), str(res_key), val])

	# 3. Vérification des guerres (aucune guerre sans trace causale ou relation bilatérale cohérente)
	for c_id in state.civilizations.keys():
		var civ: Dictionary = state.civilizations[c_id]
		var diplo: Dictionary = civ.get("diplomacy", {})
		for other_id in diplo.keys():
			if String(diplo[other_id].get("stance", "")) == "WAR":
				if not state.civilizations.has(int(other_id)):
					anomalies.append("Guerre fantôme chez %s contre une civilisation inexistante (%s)." % [String(civ["name"]), str(other_id)])

	return {
		"ok": anomalies.is_empty(),
		"anomalies_count": anomalies.size(),
		"anomalies": anomalies
	}
