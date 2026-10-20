class_name DivinePowerSystem
extends RefCounted
## Système de Toute-Puissance Divine.
## Exécute les interventions directes ou subtiles du joueur sur la géographie, le climat,
## l'écologie, les civilisations, les individus, les miracles et les lois de la nature.
## Génère systématiquement :
## 1) Des effets causaux réels sur les variables du monde.
## 2) Des interprétations culturelles/religieuses différenciées chez les populations témoins.

const POWER_CATALOG: Dictionary = {
	"OBSERVE": {
		"domain": "OBSERVATION",
		"label": "👁 Observer",
		"desc": "Examine une tuile, une cité, une civilisation, une religion ou un individu sans intervenir.",
		"default_radius": 0
	},
	"RAISE_LAND": {
		"domain": "GEOGRAPHY",
		"label": "🏔 Élever Terre",
		"desc": "Élève le relief, fait émerger des îles ou dresse des chaînes de montagnes modifiant le climat.",
		"default_radius": 2
	},
	"LOWER_LAND": {
		"domain": "GEOGRAPHY",
		"label": "🌊 Creuser Mer/Vallée",
		"desc": "Abaisse l'altitude pour creuser des bassins, détourner les eaux ou ouvrir une mer intérieure.",
		"default_radius": 2
	},
	"CREATE_SPRING": {
		"domain": "GEOGRAPHY",
		"label": "💧 Source & Fleuve",
		"desc": "Fait jaillir une source d'eau douce permanente et irrigue les terres environnantes.",
		"default_radius": 1
	},
	"SPAWN_MINERALS": {
		"domain": "GEOGRAPHY",
		"label": "⛏ Filon Minéral",
		"desc": "Enrichit le sous-sol en Pierre, Fer, Or ou Aetherium pour stimuler la métallurgie.",
		"default_radius": 1
	},
	"FERTILE_RAIN": {
		"domain": "CLIMATE",
		"label": "🌧 Pluie Fertile",
		"desc": "Fait tomber une pluie bienfaisante qui met fin aux sécheresses et régénère l'humus.",
		"default_radius": 3
	},
	"HEATWAVE_DROUGHT": {
		"domain": "CLIMATE",
		"label": "☀ Sécheresse",
		"desc": "Assèche les sols, réduit l'humidité et met à l'épreuve les réserves agricoles.",
		"default_radius": 3
	},
	"GROW_FOREST": {
		"domain": "NATURE",
		"label": "🌲 Forêt Primordiale",
		"desc": "Fait croître instantanément une végétation luxuriante et restaure la biodiversité.",
		"default_radius": 2
	},
	"SPAWN_FAUNA": {
		"domain": "NATURE",
		"label": "🦌 Créer Faune",
		"desc": "Peuple la région de troupeaux sauvages ou de créatures astrales.",
		"default_radius": 2
	},
	"SPAWN_TRIBE": {
		"domain": "CIVILIZATION",
		"label": "⛺ Fonder Peuple",
		"desc": "Éveille une nouvelle tribu autonome dotée de sa langue, de son chef et de sa culture.",
		"default_radius": 0
	},
	"BLESS_PROSPERITY": {
		"domain": "MIRACLES",
		"label": "✨ Abondance & Soin",
		"desc": "Remplit les greniers, guérit les épidémies, apaise les troubles et bénit les habitants.",
		"default_radius": 2
	},
	"INSPIRE_PROPHET": {
		"domain": "MIRACLES",
		"label": "🌟 Prophète & Savoir",
		"desc": "Insuffle une révélation spirituelle ou une percée scientifique majeure à une communauté.",
		"default_radius": 1
	},
	"CELESTIAL_MIRACLE": {
		"domain": "MIRACLES",
		"label": "☀️ Prodige Céleste",
		"desc": "Manifeste un signe grandiose dans les cieux, interprété différemment selon les cultures.",
		"default_radius": 4
	},
	"BUILD_SANCTUARY": {
		"domain": "CIVILIZATION",
		"label": "🏛 Monument Sacré",
		"desc": "Bâtit un sanctuaire divin qui rayonne une aura sacrée et attire les pèlerins.",
		"default_radius": 0
	},
	"CATACLYSM_METEOR": {
		"domain": "CATASTROPHES",
		"label": "☄ Météore & Séisme",
		"desc": "Frappe la région d'un impact cosmique qui bouleverse la géographie et éprouve les empires.",
		"default_radius": 2
	},
	"UNLEASH_PLAGUE": {
		"domain": "CATASTROPHES",
		"label": "☣ Pestilence",
		"desc": "Déclenche une épidémie contagieuse qui teste la médecine, la foi et la résilience sociale.",
		"default_radius": 2
	},
	"SUMMON_GUARDIAN": {
		"domain": "MIRACLES",
		"label": "🕊 Gardien Spirituel",
		"desc": "Fait descendre une entité céleste autonome qui bénit la terre et veille sur les mortels.",
		"default_radius": 1
	},
	"OPEN_ASTRAL_PORTAL": {
		"domain": "MIRACLES",
		"label": "🌀 Portail Astral",
		"desc": "Ouvre un passage entre le monde matériel et le plan astral, diffusant une puissante aura sacrée.",
		"default_radius": 2
	},
	"ERUPT_VOLCANO": {
		"domain": "CATASTROPHES",
		"label": "🌋 Volcan & Cendres",
		"desc": "Érige un volcan en fusion : dévaste le cratère mais enrichit les terres périphériques en minerais.",
		"default_radius": 2
	},
	"GOLDEN_AGE_TRADE": {
		"domain": "CIVILIZATION",
		"label": "⚖ Âge d'Or Marchand",
		"desc": "Stimule le négoce, lance des caravanes entre cités et enrichit artisans et marchands.",
		"default_radius": 3
	}
}


static func apply_power(
	state: WorldState,
	rng: DeterministicRNG,
	power_id: String,
	center_x: int,
	center_y: int,
	radius: int = 2,
	intensity: float = 1.0
) -> Dictionary:
	if not state.is_valid_coord(center_x, center_y):
		return {"ok": false, "summary": "Coordonnées hors carte."}

	var affected_tiles: Array[Dictionary] = _collect_tiles_in_radius(state, center_x, center_y, radius)
	var affected_settlements: Array[Dictionary] = _collect_settlements_in_radius(state, center_x, center_y, maxi(radius, 2))
	var witness_civs: Array[int] = []
	for s in affected_settlements:
		var cid: int = int(s["civ_id"])
		if not witness_civs.has(cid):
			witness_civs.append(cid)

	var summary: String = ""
	var event_category: String = "MIRACLE"
	var pulse_color := Color(0.95, 0.82, 0.32)

	match power_id:
		"RAISE_LAND":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				var falloff: float = float(item["falloff"])
				t["elevation"] = clampf(float(t["elevation"]) + 0.28 * intensity * falloff, -1.0, 1.0)
				WorldGenerator.recompute_tile_biome(t)
			summary = "Élévation tectonique autour de (%d, %d)." % [center_x, center_y]
			event_category = "GENESIS"
			pulse_color = Color(0.75, 0.58, 0.36)

		"LOWER_LAND":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				var falloff: float = float(item["falloff"])
				t["elevation"] = clampf(float(t["elevation"]) - 0.28 * intensity * falloff, -1.0, 1.0)
				if float(t["elevation"]) < 0.0:
					t["has_river"] = false
				WorldGenerator.recompute_tile_biome(t)
			summary = "Affaissement géologique et ouverture de bassin à (%d, %d)." % [center_x, center_y]
			event_category = "GENESIS"
			pulse_color = Color(0.24, 0.62, 0.94)

		"CREATE_SPRING":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				if float(t["elevation"]) >= 0.0:
					t["has_river"] = true
					t["rainfall"] = clampf(float(t["rainfall"]) + 0.35 * intensity, 0.0, 1.0)
					t["fertility"] = clampf(float(t["fertility"]) + 0.35 * intensity, 0.0, 1.0)
					WorldGenerator.recompute_tile_biome(t)
			summary = "Jaillissement d'une source sacrée et fertilisation des berges à (%d, %d)." % [center_x, center_y]
			pulse_color = Color(0.22, 0.85, 0.98)

		"SPAWN_MINERALS":
			var mineral_types: Array[String] = ["IRON", "GOLD", "STONE"]
			if bool(state.natural_laws.get("magic_enabled", false)):
				mineral_types.append("AETHERIUM")
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				if float(t["elevation"]) >= 0.0:
					t["mineral_type"] = String(rng.pick_random("divine", mineral_types))
					t["mineral_reserve"] = float(t.get("mineral_reserve", 0.0)) + 450.0 * intensity
			summary = "Apparition de riches filons minéraux autour de (%d, %d)." % [center_x, center_y]
			pulse_color = Color(0.95, 0.78, 0.24)

		"FERTILE_RAIN":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				var falloff: float = float(item["falloff"])
				t["rainfall"] = clampf(float(t["rainfall"]) + 0.38 * intensity * falloff, 0.0, 1.0)
				if float(t["elevation"]) >= 0.0:
					t["fertility"] = clampf(float(t["fertility"]) + 0.30 * intensity * falloff, 0.0, 1.0)
					t["biomass_flora"] = clampf(float(t["biomass_flora"]) + 24.0 * intensity * falloff, 0.0, 100.0)
					WorldGenerator.recompute_tile_biome(t)
			for s in affected_settlements:
				s["stocks"]["food"] = float(s["stocks"]["food"]) + 90.0 * intensity
				s["stocks"]["water"] = float(s["stocks"]["water"]) + 120.0 * intensity
			summary = "Pluie céleste bienfaisante sur (%d, %d) : terres irriguées et récoltes sauvées." % [center_x, center_y]
			pulse_color = Color(0.32, 0.78, 0.98)

		"HEATWAVE_DROUGHT":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				var falloff: float = float(item["falloff"])
				t["temperature"] = clampf(float(t["temperature"]) + 9.0 * intensity * falloff, -35.0, 50.0)
				t["rainfall"] = clampf(float(t["rainfall"]) - 0.42 * intensity * falloff, 0.02, 1.0)
				if float(t["elevation"]) >= 0.0:
					t["fertility"] = clampf(float(t["fertility"]) - 0.32 * intensity * falloff, 0.02, 1.0)
					t["biomass_flora"] = maxf(2.0, float(t["biomass_flora"]) - 28.0 * intensity * falloff)
					WorldGenerator.recompute_tile_biome(t)
			for s in affected_settlements:
				s["stocks"]["food"] = maxf(0.0, float(s["stocks"]["food"]) * (1.0 - 0.35 * clampf(intensity, 0.2, 1.5)))
			summary = "Sécheresse ardente déclenchée autour de (%d, %d)." % [center_x, center_y]
			event_category = "CATASTROPHE"
			pulse_color = Color(0.96, 0.48, 0.18)

		"GROW_FOREST":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				if float(t["elevation"]) >= 0.0:
					t["rainfall"] = maxf(float(t["rainfall"]), 0.62)
					t["fertility"] = clampf(float(t["fertility"]) + 0.28 * intensity, 0.0, 1.0)
					t["biomass_flora"] = 95.0
					t["pollution"] = 0.0
					WorldGenerator.recompute_tile_biome(t)
			summary = "Éclosion d'une forêt primordiale autour de (%d, %d)." % [center_x, center_y]
			pulse_color = Color(0.24, 0.88, 0.46)

		"SPAWN_FAUNA":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				if float(t["elevation"]) < 0.0:
					t["fauna_species_id"] = 4
					t["fauna_count"] = int(t.get("fauna_count", 0)) + int(45.0 * intensity)
				else:
					var sp_id: int = 5 if (bool(state.natural_laws.get("magic_enabled", false)) and rng.randf_channel("divine") < 0.35 and state.species.has(5)) else 2
					t["fauna_species_id"] = sp_id
					t["fauna_count"] = int(t.get("fauna_count", 0)) + int(40.0 * intensity)
			summary = "Multiplication miraculeuse de la faune sauvage autour de (%d, %d)." % [center_x, center_y]
			pulse_color = Color(0.45, 0.92, 0.55)

		"SPAWN_TRIBE":
			var center_tile: Dictionary = state.get_tile(center_x, center_y)
			if float(center_tile.get("elevation", -1.0)) < 0.0:
				center_tile["elevation"] = 0.24
				center_tile["fertility"] = 0.68
				WorldGenerator.recompute_tile_biome(center_tile)
			var new_civ: Dictionary = WorldGenerator.found_new_civilization_at(state, rng, center_x, center_y, 1, false)
			if not new_civ.is_empty():
				witness_civs.append(int(new_civ["id"]))
				summary = "Naissance divine du peuple de %s à (%d, %d)." % [String(new_civ["name"]), center_x, center_y]
			else:
				summary = "Impossible de fonder une tribu sur cette tuile."
			pulse_color = Color(0.98, 0.85, 0.35)

		"BLESS_PROSPERITY":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				t["divine_aura"] = clampf(float(t.get("divine_aura", 0.0)) + 0.45 * intensity, -1.0, 1.0)
				if float(t["elevation"]) >= 0.0:
					t["fertility"] = clampf(float(t["fertility"]) + 0.25 * intensity, 0.0, 1.0)
			for s in affected_settlements:
				s["stocks"]["food"] = float(s["stocks"]["food"]) + 240.0 * intensity
				s["stocks"]["wood"] = float(s["stocks"]["wood"]) + 80.0 * intensity
				s["stocks"]["tools"] = float(s["stocks"]["tools"]) + 45.0 * intensity
				s["stocks"]["wealth"] = float(s["stocks"]["wealth"]) + 90.0 * intensity
				s["active_plague_severity"] = 0.0
				s["public_opinion"]["unrest"] = maxf(0.0, float(s["public_opinion"]["unrest"]) - 0.35)
				s["public_opinion"]["economic_satisfaction"] = 0.95
			summary = "Bénédiction d'abondance, de guérison et de paix civile sur (%d, %d)." % [center_x, center_y]
			pulse_color = Color(0.98, 0.88, 0.36)

		"INSPIRE_PROPHET":
			if affected_settlements.is_empty():
				summary = "Aucune communauté à proximité de (%d, %d) pour recevoir l'inspiration." % [center_x, center_y]
			else:
				var target_s: Dictionary = affected_settlements[0]
				var cid: int = int(target_s["civ_id"])
				var civ: Dictionary = state.civilizations.get(cid, {})
				var prophet: Dictionary = WorldGenerator.spawn_remarkable_individual(
					state, rng, cid, int(target_s["id"]), int(target_s["species_id"]), "PROPHET", "Transmettre la Révélation Céleste"
				)
				prophet["blessed_by_god"] = true
				var rel_id: int = CultureReligionSystem.get_dominant_religion_in_settlement(target_s)
				if rel_id == -1:
					var new_rel: Dictionary = CultureReligionSystem.found_religion(
						state, rng, cid, int(target_s["id"]), int(prophet["id"]), "Révélation Divine Directe accordée à " + String(prophet["name"])
					)
					if not new_rel.is_empty() and int(civ.get("state_religion_id", -1)) == -1:
						civ["state_religion_id"] = int(new_rel["id"])
				else:
					var rel: Dictionary = state.religions[rel_id]
					rel["sacred_texts"].append("Prophétie inspirée de %s (An %d)" % [String(prophet["name"]), state.year])
					# Une nouvelle révélation peut soit renforcer la foi, soit diviser les interprètes
					if rng.randf_channel("religion") < 0.30:
						rel["internal_unity"] = clampf(float(rel["internal_unity"]) - 0.25, 0.15, 1.0)
				# Bonus de savoir scientifique simultané
				if not civ.is_empty():
					for tech_key in civ["research_progress"].keys():
						civ["research_progress"][tech_key] = float(civ["research_progress"][tech_key]) + 95.0 * intensity
				summary = "%s s'éveille à %s sous l'inspiration divine !" % [String(prophet["name"]), String(target_s["name"])]
			pulse_color = Color(0.76, 0.52, 0.98)

		"CELESTIAL_MIRACLE":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				t["divine_aura"] = clampf(float(t.get("divine_aura", 0.0)) + 0.65 * intensity, -1.0, 1.0)
			for s in affected_settlements:
				var cid: int = int(s["civ_id"])
				var rel_id: int = CultureReligionSystem.get_dominant_religion_in_settlement(s)
				if rel_id == -1:
					var civ: Dictionary = state.civilizations.get(cid, {})
					var ruler_id: int = int(civ.get("ruler_individual_id", -1))
					var new_rel: Dictionary = CultureReligionSystem.found_religion(
						state, rng, cid, int(s["id"]), ruler_id, "Apparition Lumineuse dans le Ciel de " + String(s["name"])
					)
					if not new_rel.is_empty() and int(civ.get("state_religion_id", -1)) == -1:
						civ["state_religion_id"] = int(new_rel["id"])
				else:
					s["religious_composition"][rel_id] = clampf(float(s["religious_composition"].get(rel_id, 0.5)) + 0.25, 0.0, 1.0)
					CultureReligionSystem._normalize_religious_composition(s["religious_composition"])
			summary = "Un prodige céleste flamboie au-dessus de (%d, %d) devant %d cités témoins." % [
				center_x, center_y, affected_settlements.size()
			]
			pulse_color = Color(0.99, 0.92, 0.48)

		"BUILD_SANCTUARY":
			var center_t: Dictionary = state.get_tile(center_x, center_y)
			if float(center_t.get("elevation", -1.0)) < 0.0:
				center_t["elevation"] = 0.18
				WorldGenerator.recompute_tile_biome(center_t)
			center_t["sacred_site_id"] = state.current_tick + 1
			center_t["divine_aura"] = 1.0
			for s in affected_settlements:
				if not s["buildings"].has("MONUMENT"):
					s["buildings"].append("MONUMENT")
				if not s["buildings"].has("TEMPLE"):
					s["buildings"].append("TEMPLE")
			summary = "Un Sanctuaire Monumental immortel a été érigé en (%d, %d)." % [center_x, center_y]
			pulse_color = Color(0.45, 0.95, 0.92)

		"CATACLYSM_METEOR":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				var falloff: float = float(item["falloff"])
				t["elevation"] = clampf(float(t["elevation"]) - 0.36 * intensity * falloff, -1.0, 1.0)
				t["temperature"] = clampf(float(t["temperature"]) + 14.0 * falloff, -35.0, 55.0)
				t["biomass_flora"] = maxf(0.0, float(t["biomass_flora"]) - 75.0 * falloff)
				t["divine_aura"] = -0.65
				if falloff > 0.65 and float(t["elevation"]) >= 0.0:
					t["mineral_type"] = "AETHERIUM" if bool(state.natural_laws.get("magic_enabled", false)) else "IRON"
					t["mineral_reserve"] = 600.0
				WorldGenerator.recompute_tile_biome(t)
			for s in affected_settlements:
				var loss: int = int(round(float(s["population"]) * 0.38 * clampf(intensity, 0.4, 1.5)))
				s["population"] = maxi(0, int(s["population"]) - loss)
				s["stocks"]["food"] = maxf(0.0, float(s["stocks"]["food"]) * 0.4)
				s["public_opinion"]["unrest"] = clampf(float(s["public_opinion"]["unrest"]) + 0.35, 0.0, 1.0)
				if int(s["population"]) <= 0:
					EconomyPopulationSystem._collapse_settlement_to_ruin(state, s, "Impact cataclysmique de météore")
			summary = "Cataclysme cosmique frappant (%d, %d) : cratère, ruines et riches dépôts sidéraux." % [center_x, center_y]
			event_category = "CATASTROPHE"
			pulse_color = Color(0.98, 0.24, 0.22)

		"UNLEASH_PLAGUE":
			for s in affected_settlements:
				s["active_plague_severity"] = clampf(0.68 * intensity, 0.2, 1.0)
			summary = "Épidémie surnaturelle répandue autour de (%d, %d) (%d cités touchées)." % [
				center_x, center_y, affected_settlements.size()
			]
			event_category = "CATASTROPHE"
			pulse_color = Color(0.62, 0.88, 0.22)

		"SUMMON_GUARDIAN":
			var sp_id: int = state.allocate_spirit_id()
			state.spiritual_entities[sp_id] = {
				"id": sp_id,
				"name": "Séraphin Gardien d'%s" % state.world_name,
				"entity_type": "GUARDIAN_AVATAR",
				"plane": "CELESTIAL",
				"tile_x": center_x,
				"tile_y": center_y,
				"power_level": 1.0,
				"autonomous_goal": "PROTECT_MORTALS",
				"perceived_by_religions": []
			}
			for item in affected_tiles:
				item["tile"]["divine_aura"] = 1.0
				if float(item["tile"]["elevation"]) >= 0.0:
					item["tile"]["fertility"] = clampf(float(item["tile"]["fertility"]) + 0.35, 0.0, 1.0)
			state.add_floating_text(center_x, center_y, "🕊 Gardien Céleste !", Color(0.55, 0.95, 1.0))
			summary = "Un Gardien Céleste autonome est descendu en (%d, %d)." % [center_x, center_y]
			pulse_color = Color(0.52, 0.94, 0.98)

		"OPEN_ASTRAL_PORTAL":
			state.portals.append({
				"x": center_x,
				"y": center_y,
				"plane": "ASTRAL",
				"power": intensity,
				"founded_year": state.year
			})
			var ct: Dictionary = state.get_tile(center_x, center_y)
			if not ct.is_empty():
				ct["sacred_site_id"] = state.current_tick + 100
				ct["divine_aura"] = 1.0
				if float(ct["elevation"]) >= 0.0:
					ct["mineral_type"] = "AETHERIUM"
					ct["mineral_reserve"] = 800.0
			state.add_floating_text(center_x, center_y, "🌀 Portail Astral !", Color(0.78, 0.52, 0.98))
			summary = "Ouverture d'un Portail Cosmologique vers le Plan Astral en (%d, %d)." % [center_x, center_y]
			pulse_color = Color(0.76, 0.44, 0.98)

		"ERUPT_VOLCANO":
			for item in affected_tiles:
				var t: Dictionary = item["tile"]
				var falloff: float = float(item["falloff"])
				if falloff > 0.62:
					t["elevation"] = clampf(float(t["elevation"]) + 0.48 * intensity, 0.76, 1.0)
					t["temperature"] = 36.0
					t["rainfall"] = 0.15
					t["biome"] = "VOLCANIC"
					t["mineral_type"] = "GOLD"
					t["mineral_reserve"] = 750.0
				else:
					if float(t["elevation"]) >= 0.0:
						t["fertility"] = clampf(float(t["fertility"]) + 0.28, 0.0, 1.0) # Cendres volcaniques fertiles à moyen terme
						WorldGenerator.recompute_tile_biome(t)
			for s in affected_settlements:
				var loss: int = int(round(float(s["population"]) * 0.25))
				s["population"] = maxi(10, int(s["population"]) - loss)
			state.add_floating_text(center_x, center_y, "🌋 Éruption Volcanique !", Color(0.98, 0.38, 0.18))
			summary = "Éruption volcanique en (%d, %d) : dôme de lave au centre et cendres minérales fertiles en périphérie." % [center_x, center_y]
			event_category = "CATASTROPHE"
			pulse_color = Color(0.98, 0.35, 0.15)

		"GOLDEN_AGE_TRADE":
			for s in affected_settlements:
				s["stocks"]["wealth"] = float(s["stocks"]["wealth"]) + 150.0 * intensity
				s["stocks"]["tools"] = float(s["stocks"]["tools"]) + 60.0 * intensity
				s["stocks"]["food"] = float(s["stocks"]["food"]) + 120.0 * intensity
				if not s["buildings"].has("MARKET"):
					s["buildings"].append("MARKET")
			if affected_settlements.size() >= 2:
				EconomyPopulationSystem._spawn_caravan(state, affected_settlements[0], affected_settlements[1], "Or & Soieries")
			state.add_floating_text(center_x, center_y, "⚖ Âge d'Or Marchand !", Color(0.98, 0.86, 0.28))
			summary = "Âge d'Or Marchand insufflé autour de (%d, %d) (%d cités stimulées)." % [
				center_x, center_y, affected_settlements.size()
			]
			pulse_color = Color(0.98, 0.84, 0.24)

		_:
			return {"ok": true, "summary": "Observation de (%d, %d)." % [center_x, center_y]}

	# Génération des interprétations mortelles selon la culture et le niveau scientifique de chaque civilisation témoin
	var interpretations: Dictionary = _build_mortal_interpretations(state, rng, power_id, event_category, witness_civs)

	state.add_visual_pulse(center_x, center_y, pulse_color, float(maxi(1, radius)) * 1.35, String(POWER_CATALOG.get(power_id, {}).get("label", power_id)))

	state.divine_actions.push_front({
		"tick": state.current_tick,
		"year": state.year,
		"power_id": power_id,
		"x": center_x,
		"y": center_y,
		"radius": radius,
		"intensity": intensity,
		"summary": summary
	})

	state.record_historical_event(
		event_category,
		"Intervention Divine : %s" % String(POWER_CATALOG.get(power_id, {}).get("label", power_id)),
		summary,
		["Volonté Divine directe du Joueur (Rayon %d, Intensité %.1f)" % [radius, intensity]],
		["%d tuiles modifiées" % affected_tiles.size(), "%d cités affectées" % affected_settlements.size()],
		center_x,
		center_y,
		witness_civs,
		[],
		true,
		interpretations
	)

	CultureReligionSystem._recompute_religion_believer_counts(state)
	return {"ok": true, "summary": summary, "interpretations": interpretations}


static func respond_to_prayer(
	state: WorldState,
	rng: DeterministicRNG,
	prayer_id: int,
	response_mode: String # DIRECT, SIGN, SILENCE
) -> String:
	if not state.prayers.has(prayer_id):
		return "Prière introuvable."
	var p: Dictionary = state.prayers[prayer_id]
	if String(p.get("status", "")) != "PENDING":
		return "Cette prière a déjà reçu une réponse."

	var s_id: int = int(p["settlement_id"])
	var px: int = int(p["tile_x"])
	var py: int = int(p["tile_y"])
	var category: String = String(p["category"])

	if response_mode == "DIRECT":
		p["status"] = "ANSWERED_DIRECTLY"
		match category:
			"FAMINE_RELIEF", "DROUGHT_RAIN":
				apply_power(state, rng, "FERTILE_RAIN", px, py, 2, 1.2)
				apply_power(state, rng, "BLESS_PROSPERITY", px, py, 1, 1.0)
			"PLAGUE_CURE":
				apply_power(state, rng, "BLESS_PROSPERITY", px, py, 2, 1.2)
			"WAR_PROTECTION":
				apply_power(state, rng, "BUILD_SANCTUARY", px, py, 1, 1.0)
				apply_power(state, rng, "BLESS_PROSPERITY", px, py, 2, 1.0)
			_:
				apply_power(state, rng, "INSPIRE_PROPHET", px, py, 1, 1.0)
		return "Prière exaucée directement à (%d, %d) : les fidèles célèbrent la grâce divine !" % [px, py]

	elif response_mode == "SIGN":
		p["status"] = "ANSWERED_SIGN"
		apply_power(state, rng, "CELESTIAL_MIRACLE", px, py, 3, 1.0)
		if state.settlements.has(s_id):
			var s: Dictionary = state.settlements[s_id]
			s["stocks"]["food"] = float(s["stocks"]["food"]) + 65.0
		return "Un signe céleste mystérieux a été envoyé en réponse à la prière : les théologiens débattent de son sens."

	else:
		p["status"] = "IGNORED"
		var rel_id: int = int(p.get("religion_id", -1))
		if state.religions.has(rel_id):
			var rel: Dictionary = state.religions[rel_id]
			rel["internal_unity"] = clampf(float(rel["internal_unity"]) - 0.08, 0.15, 1.0)
		return "Vous gardez le silence face à la prière. Certains fidèles persévèrent, d'autres doutent ou cherchent des solutions humaines."


static func _build_mortal_interpretations(
	state: WorldState,
	rng: DeterministicRNG,
	power_id: String,
	event_category: String,
	witness_civs: Array[int]
) -> Dictionary:
	var out: Dictionary = {}
	for cid in witness_civs:
		if not state.civilizations.has(cid):
			continue
		var civ: Dictionary = state.civilizations[cid]
		var civ_name: String = String(civ["name"])
		var techs: Array = civ.get("technologies", [])
		var rel_id: int = int(civ.get("state_religion_id", -1))
		var rel_name: String = String(state.religions.get(rel_id, {}).get("name", "les Esprits Ancestraux"))

		if techs.has("SCIENTIFIC_METHOD") and rng.randf_channel("society") < 0.55:
			out[civ_name] = "Les académiciens de %s y voient une anomalie physique rare et étudient ses lois causales." % civ_name
		elif event_category == "CATASTROPHE":
			out[civ_name] = "Le clergé de %s (%s) proclame qu'il s'agit d'un jugement céleste appelant à la pénitence et à la réforme." % [civ_name, rel_name]
		elif power_id in ["BLESS_PROSPERITY", "FERTILE_RAIN", "CELESTIAL_MIRACLE", "INSPIRE_PROPHET"]:
			out[civ_name] = "%s célèbre un miracle prouvant l'élection sacrée de sa tradition (%s), suscitant la jalousie de ses rivaux." % [civ_name, rel_name]
		else:
			out[civ_name] = "Les chroniqueurs de %s interprètent ce bouleversement comme un présage historique majeur." % civ_name
	return out


static func _collect_tiles_in_radius(state: WorldState, cx: int, cy: int, radius: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx: int = cx + dx
			var ny: int = cy + dy
			if not state.is_valid_coord(nx, ny):
				continue
			var dist: float = Vector2(cx, cy).distance_to(Vector2(nx, ny))
			if dist <= float(radius) + 0.35:
				var falloff: float = clampf(1.0 - (dist / float(maxi(1, radius + 1))) * 0.65, 0.25, 1.0)
				result.append({
					"tile": state.get_tile(nx, ny),
					"falloff": falloff
				})
	return result


static func _collect_settlements_in_radius(state: WorldState, cx: int, cy: int, radius: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		if String(s.get("tier", "RUIN")) == "RUIN":
			continue
		var dist: float = Vector2(cx, cy).distance_to(Vector2(int(s["tile_x"]), int(s["tile_y"])))
		if dist <= float(radius) + 1.5:
			result.append(s)
	return result
