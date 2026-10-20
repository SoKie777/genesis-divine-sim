extends SceneTree
## Suite de tests scientifiques automatisés pour GENESIS — THE DIVINE SIMULATION.
## Exécutable via : Godot_v4.7-stable_win64_console.exe --headless --path <project> -s res://tests/test_simulation.gd


func _init() -> void:
	print("=================================================================")
	print("  GENESIS — SUITE DE VÉRIFICATION SCIENTIFIQUE DU MOTEUR (MVP)")
	print("=================================================================")

	var passed: int = 0
	var failed: int = 0

	if _test_deterministic_world_generation():
		passed += 1
	else:
		failed += 1

	if _test_autonomous_evolution_over_decades():
		passed += 1
	else:
		failed += 1

	if _test_divine_powers_and_interpretations():
		passed += 1
	else:
		failed += 1

	if _test_save_and_load_integrity():
		passed += 1
	else:
		failed += 1

	if _test_causal_divergence_and_main_scene():
		passed += 1
	else:
		failed += 1

	print("-----------------------------------------------------------------")
	print("  RÉSULTAT GLOBAL : %d réussis, %d échoués" % [passed, failed])
	print("=================================================================")
	quit(0 if failed == 0 else 1)


func _test_deterministic_world_generation() -> bool:
	print("[TEST 1] Reproductibilité déterministe par graine (Seed 777888)...")
	var sim_a := WorldSimulation.new()
	sim_a.initialize_new_world({"seed": 777888, "width": 36, "height": 28, "initial_tribes": 4})
	sim_a.step_ticks(360) # 1 an complet

	var sim_b := WorldSimulation.new()
	sim_b.initialize_new_world({"seed": 777888, "width": 36, "height": 28, "initial_tribes": 4})
	sim_b.step_ticks(360) # 1 an complet

	var pop_a: int = sim_a.state.get_total_population()
	var pop_b: int = sim_b.state.get_total_population()
	var tile_check_a: float = float(sim_a.state.tiles[120]["fertility"])
	var tile_check_b: float = float(sim_b.state.tiles[120]["fertility"])

	if pop_a != pop_b or absf(tile_check_a - tile_check_b) > 0.0001:
		print("  [ÉCHEC] Divergence détectée : pop %d vs %d, fert %f vs %f" % [pop_a, pop_b, tile_check_a, tile_check_b])
		return false

	print("  [OK] Déterminisme strict validé (Population = %d, Fertilité #120 = %.4f)" % [pop_a, tile_check_a])
	return true


func _test_autonomous_evolution_over_decades() -> bool:
	print("[TEST 2] Simulation autonome sur 8 années (2880 ticks) sans intervention divine...")
	var sim := WorldSimulation.new()
	sim.initialize_new_world({"seed": 424242, "width": 44, "height": 32, "initial_tribes": 4})
	var start_pop: int = sim.state.get_total_population()
	var start_events: int = sim.state.events.size()

	sim.step_ticks(360 * 8)

	var end_pop: int = sim.state.get_total_population()
	var end_events: int = sim.state.events.size()
	var inv: Dictionary = sim.verify_world_invariants()

	if not bool(inv["ok"]):
		print("  [ÉCHEC] Invariants violés : ", inv["anomalies"])
		return false

	if end_pop <= 0 or end_events <= start_events:
		print("  [ÉCHEC] Monde figé ou éteint anormalement : pop=%d, events=%d" % [end_pop, end_events])
		return false

	print("  [OK] Monde vivant et autonome : An %d | Pop %d -> %d | Civs=%d | Religions=%d | Événements=%d" % [
		sim.state.year,
		start_pop,
		end_pop,
		sim.state.get_active_civ_count(),
		sim.state.get_active_religion_count(),
		end_events
	])
	return true


func _test_divine_powers_and_interpretations() -> bool:
	print("[TEST 3] Causalité des Pouvoirs Divins, Miracles, Prières et Lois de la Nature...")
	var sim := WorldSimulation.new()
	sim.initialize_new_world({"seed": 123456, "width": 40, "height": 30, "initial_tribes": 3})

	var first_settlement: Dictionary = sim.state.settlements.values()[0]
	var sx: int = int(first_settlement["tile_x"])
	var sy: int = int(first_settlement["tile_y"])
	var food_before: float = float(first_settlement["stocks"]["food"])

	var res_rain: Dictionary = DivinePowerSystem.apply_power(sim.state, sim.rng, "FERTILE_RAIN", sx, sy, 3, 1.2)
	var food_after: float = float(first_settlement["stocks"]["food"])
	if not bool(res_rain["ok"]) or food_after <= food_before:
		print("  [ÉCHEC] Pluie fertile n'a pas augmenté les réserves : %.1f -> %.1f" % [food_before, food_after])
		return false

	var res_miracle: Dictionary = DivinePowerSystem.apply_power(sim.state, sim.rng, "CELESTIAL_MIRACLE", sx, sy, 4, 1.0)
	if not bool(res_miracle["ok"]) or sim.state.religions.is_empty():
		print("  [ÉCHEC] Le miracle céleste n'a pas généré ou renforcé de religion.")
		return false

	# Test des nouveaux pouvoirs spirituels, cosmologiques et géologiques (Phases 6-7)
	DivinePowerSystem.apply_power(sim.state, sim.rng, "SUMMON_GUARDIAN", sx, sy, 1, 1.0)
	DivinePowerSystem.apply_power(sim.state, sim.rng, "OPEN_ASTRAL_PORTAL", sx, sy, 2, 1.0)
	DivinePowerSystem.apply_power(sim.state, sim.rng, "GOLDEN_AGE_TRADE", sx, sy, 3, 1.0)
	if sim.state.portals.is_empty() or sim.state.spiritual_entities.is_empty():
		print("  [ÉCHEC] Le portail astral ou le gardien spirituel n'a pas été créé.")
		return false

	# Test d'une prière et de sa réponse divine
	var prayer: Dictionary = CultureReligionSystem.spawn_prayer(
		sim.state, int(first_settlement["civ_id"]), int(first_settlement["id"]),
		"FAMINE_RELIEF", "Prière de Test", "Demande d'aide", 0.85
	)
	var msg: String = DivinePowerSystem.respond_to_prayer(sim.state, sim.rng, int(prayer["id"]), "DIRECT")
	if String(sim.state.prayers[int(prayer["id"])]["status"]) != "ANSWERED_DIRECTLY":
		print("  [ÉCHEC] La prière n'a pas changé de statut correctement : ", msg)
		return false

	print("  [OK] Pouvoirs divins, miracles, interprétations et réponses aux prières validés.")
	return true


func _test_save_and_load_integrity() -> bool:
	print("[TEST 4] Intégrité de la Sauvegarde / Chargement et continuité déterministe...")
	var sim1 := WorldSimulation.new()
	sim1.initialize_new_world({"seed": 909090, "width": 36, "height": 28, "initial_tribes": 3})
	sim1.step_ticks(180)

	var save_path: String = SaveSystem.get_slot_path("autotest_slot")
	var save_res: Dictionary = SaveSystem.save_to_path(save_path, sim1.state, sim1.rng)
	if not bool(save_res["ok"]):
		print("  [ÉCHEC] Sauvegarde échouée : ", save_res.get("error", ""))
		return false

	var sim2 := WorldSimulation.new()
	var load_res: Dictionary = SaveSystem.load_from_path(save_path, sim2.state, sim2.rng)
	if not bool(load_res["ok"]):
		print("  [ÉCHEC] Chargement échoué : ", load_res.get("error", ""))
		return false

	# Avancer les deux simulations de 180 ticks supplémentaires et vérifier l'identité d'état
	sim1.step_ticks(180)
	sim2.step_ticks(180)

	if sim1.state.get_total_population() != sim2.state.get_total_population() or sim1.state.year != sim2.state.year:
		print("  [ÉCHEC] Dérive post-chargement : pop %d vs %d" % [
			sim1.state.get_total_population(), sim2.state.get_total_population()
		])
		return false

	print("  [OK] Sauvegarde et chargement 100%% fidèles (%d octets, Checksum %d)." % [
		int(save_res["bytes"]), int(save_res["checksum"])
	])
	return true


func _test_causal_divergence_and_main_scene() -> bool:
	print("[TEST 5] Divergence causale (Livrable G) & Chargement de la scène complète (main.tscn)...")
	# Deux mondes avec exactement la même graine initiale : l'un laissé autonome, l'autre frappé par une sécheresse puis béni ailleurs
	var world_silent := WorldSimulation.new()
	world_silent.initialize_new_world({"seed": 555666, "width": 40, "height": 30, "initial_tribes": 3})

	var world_intervened := WorldSimulation.new()
	world_intervened.initialize_new_world({"seed": 555666, "width": 40, "height": 30, "initial_tribes": 3})
	var s0: Dictionary = world_intervened.state.settlements.values()[0]
	DivinePowerSystem.apply_power(world_intervened.state, world_intervened.rng, "HEATWAVE_DROUGHT", int(s0["tile_x"]), int(s0["tile_y"]), 3, 1.5)
	world_intervened.state.natural_laws["resource_regen_multiplier"] = 1.8

	world_silent.step_ticks(360 * 4)
	world_intervened.step_ticks(360 * 4)

	var pop_silent: int = world_silent.state.get_total_population()
	var pop_intervened: int = world_intervened.state.get_total_population()
	if pop_silent == pop_intervened:
		print("  [ÉCHEC] Aucune divergence observée entre le monde silencieux et le monde modifié (%d)." % pop_silent)
		return false

	# Instanciation et vérification de la scène principale et du moteur de rendu 2.5D
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	if packed_scene == null:
		print("  [ÉCHEC] Impossible de charger res://scenes/main.tscn")
		return false

	var main_node: Node = packed_scene.instantiate()
	root.add_child(main_node)
	main_node._ready()
	main_node._process(0.1)
	main_node.queue_free()

	print("  [OK] Divergence causale prouvée (Monde Silencieux=%d hab. vs Monde Modifié=%d hab.) et main.tscn opérationnelle." % [
		pop_silent, pop_intervened
	])
	return true

