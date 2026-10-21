class_name MainGame
extends Control
## Interface Divine Ergonomique, Épurée et Intuitive (GENESIS).
## Conçue pour laisser 85%+ de l'écran au monde isométrique vivant :
## - Barre supérieure compacte avec pilules interactives et contrôle du temps.
## - Dock inférieur centré par grandes familles de pouvoirs (masqué en mode Observation).
## - Tiroir latéral droit escamotable (Tab) avec cartes visuelles aérées et actions rapides en 1 clic.
## - Guide de prise en main rapide et infobulle flottante de survol.

var sim: WorldSimulation
var renderer: IsometricWorldRenderer

var active_power_id: String = "OBSERVE"
var active_domain_filter: String = "OBSERVATION"
var active_power_intensity: float = 1.0
var active_event_filter: String = "ALL"

var inspected_tile: Vector2i = Vector2i(24, 18)
var inspected_civ_id: int = -1
var inspected_religion_id: int = -1
var inspected_individual_id: int = -1

# Barre supérieure
var _top_bar: PanelContainer
var _lbl_world_title: Label
var _lbl_date_era: Label
var _btn_pill_pop: Button
var _btn_pill_civs: Button
var _btn_pill_rel: Button
var _btn_pill_wars: Button
var _btn_pill_prayers: Button
var _opt_overlay: OptionButton
var _btn_toggle_drawer: Button

# Dock inférieur & sous-barre contextuelle de pouvoirs
var _dock_panel: PanelContainer
var _nav_panel: PanelContainer
var _subbar_panel: PanelContainer
var _power_buttons_hbox: HBoxContainer
var _lbl_active_power_hint: Label
var _slider_radius: HSlider
var _lbl_radius_val: Label
var _slider_intensity: HSlider
var _lbl_intensity_val: Label
var _category_buttons: Dictionary = {}
var _last_prayers_signature: String = ""
var _last_selectors_signature: String = ""

# Tiroir latéral droit escamotable
var _right_drawer: PanelContainer
var _drawer_tabs: TabContainer
var _rtl_inspector: RichTextLabel
var _opt_inspect_civ: OptionButton
var _opt_inspect_rel: OptionButton
var _opt_inspect_ind: OptionButton
var _prayers_vbox: VBoxContainer
var _rtl_chronicles: RichTextLabel
var _rtl_diagnostics: RichTextLabel

# Bandeau d'état / survol en bas à gauche
var _lbl_hover_pill: Label

# Modales (Nouvelle Genèse, Lois de la Nature, Guide de Prise en Main)
var _modal_genesis: PanelContainer
var _inp_world_name: LineEdit
var _inp_seed: SpinBox
var _opt_map_size: OptionButton
var _opt_scenario: OptionButton
var _slider_tribes: HSlider
var _chk_magic: CheckButton

var _modal_laws: PanelContainer
var _modal_help: PanelContainer

var _ui_refresh_timer: float = 0.0

const DOCK_CATEGORIES: Array[Dictionary] = [
	{"id": "OBSERVATION", "label": "👁 Observer", "color": Color(0.38, 0.82, 0.98)},
	{"id": "GEOGRAPHY", "label": "🏔 Terre & Eau", "color": Color(0.82, 0.65, 0.42)},
	{"id": "CLIMATE_NATURE", "label": "🌦 Climat & Vie", "color": Color(0.35, 0.88, 0.55)},
	{"id": "CIVILIZATION", "label": "🏛 Peuples & Cités", "color": Color(0.98, 0.82, 0.35)},
	{"id": "MIRACLES", "label": "✨ Miracles & Esprits", "color": Color(0.82, 0.56, 0.98)},
	{"id": "CATASTROPHES", "label": "☄ Cataclysmes", "color": Color(0.98, 0.42, 0.38)}
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sim = WorldSimulation.new()
	sim.initialize_new_world({
		"world_name": "Aethelgard",
		"seed": 424242,
		"scenario_id": "TRIBAL_DAWN",
		"width": 48,
		"height": 36,
		"initial_tribes": 4,
		"resource_abundance": 1.0,
		"magic_enabled": true
	})

	_build_clean_ui()
	renderer.state = sim.state
	renderer.is_point_over_ui_callback = _is_pos_over_ui
	renderer.center_camera_on_world()

	if not sim.state.settlements.is_empty():
		var first_s: Dictionary = sim.state.settlements.values()[0]
		inspected_tile = Vector2i(int(first_s["tile_x"]), int(first_s["tile_y"]))
		renderer.selected_tile = inspected_tile
		inspected_civ_id = int(first_s["civ_id"])

	_select_dock_category("OBSERVATION")
	_refresh_all_ui()


func _is_pos_over_ui(pos: Vector2) -> bool:
	if _modal_help != null and _modal_help.visible and _modal_help.get_global_rect().has_point(pos):
		return true
	if _modal_genesis != null and _modal_genesis.visible and _modal_genesis.get_global_rect().has_point(pos):
		return true
	if _modal_laws != null and _modal_laws.visible and _modal_laws.get_global_rect().has_point(pos):
		return true
	if _right_drawer != null and _right_drawer.visible and _right_drawer.get_global_rect().has_point(pos):
		return true
	if _top_bar != null and _top_bar.visible and _top_bar.get_global_rect().has_point(pos):
		return true
	if _subbar_panel != null and _subbar_panel.visible and _subbar_panel.get_global_rect().has_point(pos):
		return true
	if _dock_panel != null and _dock_panel.visible and _dock_panel.get_global_rect().has_point(pos):
		return true
	if _nav_panel != null and _nav_panel.visible and _nav_panel.get_global_rect().has_point(pos):
		return true
	return false


func _process(delta: float) -> void:
	var ticks_ran: int = sim.update_frame(delta)
	if ticks_ran > 0:
		renderer.request_redraw()
	_ui_refresh_timer += delta
	if ticks_ran > 0 or _ui_refresh_timer >= 0.40:
		_ui_refresh_timer = 0.0
		_refresh_top_bar()
		if _right_drawer != null and _right_drawer.visible:
			_refresh_active_drawer_tab()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event
		match ke.keycode:
			KEY_SPACE:
				_set_sim_speed(0.0 if sim.speed_multiplier > 0.0 else 1.0)
			KEY_1:
				_set_sim_speed(1.0)
			KEY_2:
				_set_sim_speed(5.0)
			KEY_3:
				_set_sim_speed(20.0)
			KEY_4:
				_set_sim_speed(100.0)
			KEY_TAB:
				_toggle_right_drawer()
			KEY_B:
				renderer.show_borders = not renderer.show_borders
			KEY_R:
				renderer.show_trade_routes = not renderer.show_trade_routes
			KEY_H:
				_modal_help.visible = not _modal_help.visible
			KEY_ESCAPE:
				_select_dock_category("OBSERVATION")
				_modal_genesis.visible = false
				_modal_laws.visible = false
				_modal_help.visible = false


func _build_clean_ui() -> void:
	# 1. Monde 2.5D Isométrique plein écran
	renderer = IsometricWorldRenderer.new()
	renderer.name = "IsometricWorldRenderer"
	add_child(renderer)
	renderer.tile_clicked.connect(_on_world_tile_clicked)
	renderer.tile_hovered.connect(_on_world_tile_hovered)
	renderer.right_click_cancel.connect(func() -> void: _select_dock_category("OBSERVATION"))

	# 2. Barre supérieure épurée (Une seule ligne fluide de 54px)
	_top_bar = _create_styled_panel(Color(0.06, 0.09, 0.15, 0.92), Color(0.88, 0.72, 0.34, 0.55), 8)
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_left = 10.0
	_top_bar.offset_right = -10.0
	_top_bar.offset_top = 8.0
	_top_bar.offset_bottom = 60.0
	add_child(_top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 6)
	_top_bar.add_child(top_hbox)

	_lbl_world_title = Label.new()
	_lbl_world_title.text = "✦ GENESIS"
	_lbl_world_title.add_theme_font_size_override("font_size", 15)
	_lbl_world_title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.42))
	top_hbox.add_child(_lbl_world_title)

	_lbl_date_era = Label.new()
	_lbl_date_era.add_theme_font_size_override("font_size", 12)
	_lbl_date_era.add_theme_color_override("font_color", Color(0.75, 0.88, 0.98))
	top_hbox.add_child(_lbl_date_era)

	# Pilules cliquables (ouvrent directement l'onglet correspondant du tiroir droit)
	_btn_pill_pop = _make_pill_button("👥 0", "Inspecter les cités et populations", func() -> void: _open_drawer_tab(0))
	top_hbox.add_child(_btn_pill_pop)

	_btn_pill_civs = _make_pill_button("👑 0", "Inspecter les royaumes et civilisations", func() -> void: _open_drawer_tab(0))
	top_hbox.add_child(_btn_pill_civs)

	_btn_pill_rel = _make_pill_button("🙏 0", "Inspecter les religions et doctrines", func() -> void: _open_drawer_tab(0))
	top_hbox.add_child(_btn_pill_rel)

	_btn_pill_wars = _make_pill_button("⚔ 0", "Voir les conflits et le comparateur", func() -> void: _open_drawer_tab(3))
	top_hbox.add_child(_btn_pill_wars)

	_btn_pill_prayers = _make_pill_button("🔔 0", "Ouvrir les prières des mortels", func() -> void: _open_drawer_tab(1))
	top_hbox.add_child(_btn_pill_prayers)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	# Contrôles temporels intuitifs
	for sc in [
		{"l": "⏸", "s": 0.0, "t": "Pause (Espace)"},
		{"l": "▶1x", "s": 1.0, "t": "Vitesse normale (1)"},
		{"l": "⏩5x", "s": 5.0, "t": "Vitesse rapide (2)"},
		{"l": "⚡20x", "s": 20.0, "t": "Vitesse accélérée (3)"},
		{"l": "✦100x", "s": 100.0, "t": "Vitesse séculaire (4)"}
	]:
		var b := Button.new()
		b.text = String(sc["l"])
		b.tooltip_text = String(sc["t"])
		var spd: float = float(sc["s"])
		b.pressed.connect(func() -> void: _set_sim_speed(spd))
		top_hbox.add_child(b)

	var b_plus1 := Button.new()
	b_plus1.text = "+1 An"
	b_plus1.tooltip_text = "Avancer instantanément d'un an"
	b_plus1.pressed.connect(func() -> void:
		sim.step_ticks(360)
		_show_toast("Saut temporel : +1 An (An %d)" % sim.state.year)
		_refresh_all_ui()
	)
	top_hbox.add_child(b_plus1)

	# Sélecteur compact de vue cartographique
	_opt_overlay = OptionButton.new()
	_opt_overlay.tooltip_text = "Changer la couche de visualisation de la carte"
	var layers: Array[Array] = [
		["BIOME", "🗺 Nature 2.5D"],
		["CIVILIZATION", "🗺 Frontières"],
		["RELIGION", "🗺 Religions"],
		["POPULATION", "🗺 Population"],
		["FERTILITY", "🗺 Fertilité"],
		["WEALTH", "🗺 Richesse"],
		["ELEVATION", "🗺 Relief"],
		["TEMPERATURE", "🗺 Climat °C"]
	]
	for idx in range(layers.size()):
		_opt_overlay.add_item(String(layers[idx][1]), idx)
		_opt_overlay.set_item_metadata(idx, String(layers[idx][0]))
	_opt_overlay.item_selected.connect(func(idx: int) -> void:
		renderer.overlay_mode = String(_opt_overlay.get_item_metadata(idx))
	)
	top_hbox.add_child(_opt_overlay)

	var b_zout := Button.new()
	b_zout.text = "➖"
	b_zout.tooltip_text = "Dézoomer"
	b_zout.pressed.connect(func() -> void: renderer._zoom_at_point(1.0 / 1.18, get_viewport_rect().size * 0.5))
	top_hbox.add_child(b_zout)

	var b_zin := Button.new()
	b_zin.text = "➕"
	b_zin.tooltip_text = "Zoomer"
	b_zin.pressed.connect(func() -> void: renderer._zoom_at_point(1.18, get_viewport_rect().size * 0.5))
	top_hbox.add_child(b_zin)

	var b_gen := Button.new()
	b_gen.text = "🌍 Genèse"
	b_gen.tooltip_text = "Créer un nouveau monde sur mesure"
	b_gen.pressed.connect(func() -> void: _modal_genesis.visible = not _modal_genesis.visible)
	top_hbox.add_child(b_gen)

	var b_laws := Button.new()
	b_laws.text = "⚖ Lois"
	b_laws.tooltip_text = "Modifier les Lois de la Nature en direct"
	b_laws.pressed.connect(func() -> void: _modal_laws.visible = not _modal_laws.visible)
	top_hbox.add_child(b_laws)

	var b_save := Button.new()
	b_save.text = "💾"
	b_save.tooltip_text = "Sauvegarder la partie"
	b_save.pressed.connect(_on_save_pressed)
	top_hbox.add_child(b_save)

	var b_load := Button.new()
	b_load.text = "📂"
	b_load.tooltip_text = "Charger la sauvegarde"
	b_load.pressed.connect(_on_load_pressed)
	top_hbox.add_child(b_load)

	var b_help := Button.new()
	b_help.text = "?"
	b_help.tooltip_text = "Guide de prise en main rapide (H)"
	b_help.pressed.connect(func() -> void: _modal_help.visible = not _modal_help.visible)
	top_hbox.add_child(b_help)

	_btn_toggle_drawer = Button.new()
	_btn_toggle_drawer.text = "📋 Infos"
	_btn_toggle_drawer.tooltip_text = "Afficher / Masquer le volet d'inspection (Tab)"
	_btn_toggle_drawer.pressed.connect(_toggle_right_drawer)
	top_hbox.add_child(_btn_toggle_drawer)

	# 3. Dock Divin Inférieur Centré (Clair, Lisible, Non Encombrant)
	var bottom_dock_wrap := VBoxContainer.new()
	bottom_dock_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_dock_wrap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom_dock_wrap.offset_left = -490.0
	bottom_dock_wrap.offset_right = 490.0
	bottom_dock_wrap.offset_top = -128.0
	bottom_dock_wrap.offset_bottom = -10.0
	bottom_dock_wrap.alignment = BoxContainer.ALIGNMENT_END
	bottom_dock_wrap.add_theme_constant_override("separation", 6)
	add_child(bottom_dock_wrap)

	# Sous-barre horizontale des pouvoirs (visible uniquement quand une catégorie de pouvoir est active)
	_subbar_panel = _create_styled_panel(Color(0.07, 0.11, 0.18, 0.95), Color(0.52, 0.76, 0.98, 0.68), 8)
	_subbar_panel.visible = false
	bottom_dock_wrap.add_child(_subbar_panel)

	var sub_vbox := VBoxContainer.new()
	sub_vbox.add_theme_constant_override("separation", 4)
	_subbar_panel.add_child(sub_vbox)

	_power_buttons_hbox = HBoxContainer.new()
	_power_buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_power_buttons_hbox.add_theme_constant_override("separation", 8)
	sub_vbox.add_child(_power_buttons_hbox)

	var brush_row := HBoxContainer.new()
	brush_row.alignment = BoxContainer.ALIGNMENT_CENTER
	brush_row.add_theme_constant_override("separation", 12)
	sub_vbox.add_child(brush_row)

	_lbl_active_power_hint = Label.new()
	_lbl_active_power_hint.add_theme_font_size_override("font_size", 12)
	_lbl_active_power_hint.add_theme_color_override("font_color", Color(0.98, 0.88, 0.48))
	brush_row.add_child(_lbl_active_power_hint)

	var lbl_r := Label.new()
	lbl_r.text = "Rayon :"
	lbl_r.add_theme_font_size_override("font_size", 12)
	brush_row.add_child(lbl_r)

	_slider_radius = HSlider.new()
	_slider_radius.min_value = 0
	_slider_radius.max_value = 6
	_slider_radius.step = 1
	_slider_radius.value = 2
	_slider_radius.custom_minimum_size = Vector2(90.0, 0.0)
	brush_row.add_child(_slider_radius)

	_lbl_radius_val = Label.new()
	_lbl_radius_val.text = "2"
	brush_row.add_child(_lbl_radius_val)
	_slider_radius.value_changed.connect(func(v: float) -> void:
		renderer.brush_radius = int(v)
		_lbl_radius_val.text = str(int(v))
	)

	var lbl_i := Label.new()
	lbl_i.text = "Force :"
	lbl_i.add_theme_font_size_override("font_size", 12)
	brush_row.add_child(lbl_i)

	_slider_intensity = HSlider.new()
	_slider_intensity.min_value = 0.5
	_slider_intensity.max_value = 2.0
	_slider_intensity.step = 0.25
	_slider_intensity.value = 1.0
	_slider_intensity.custom_minimum_size = Vector2(80.0, 0.0)
	brush_row.add_child(_slider_intensity)

	_lbl_intensity_val = Label.new()
	_lbl_intensity_val.text = "1.0x"
	brush_row.add_child(_lbl_intensity_val)
	_slider_intensity.value_changed.connect(func(v: float) -> void:
		active_power_intensity = v
		_lbl_intensity_val.text = "%.1fx" % v
	)

	# Barre principale des 6 grands domaines
	_dock_panel = _create_styled_panel(Color(0.06, 0.09, 0.15, 0.95), Color(0.92, 0.76, 0.36, 0.72), 10)
	bottom_dock_wrap.add_child(_dock_panel)

	var dock_hbox := HBoxContainer.new()
	dock_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dock_hbox.add_theme_constant_override("separation", 10)
	_dock_panel.add_child(dock_hbox)

	for cat in DOCK_CATEGORIES:
		var cid: String = String(cat["id"])
		var btn := Button.new()
		btn.text = "  %s  " % String(cat["label"])
		btn.custom_minimum_size = Vector2(142.0, 38.0)
		btn.pressed.connect(func() -> void: _select_dock_category(cid))
		dock_hbox.add_child(btn)
		_category_buttons[cid] = btn

	# 4. Pilule d'information de survol en haut à gauche sous la barre principale
	var hover_panel := _create_styled_panel(Color(0.06, 0.09, 0.15, 0.88), Color(0.38, 0.62, 0.85, 0.45), 6)
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hover_panel.offset_left = 10.0
	hover_panel.offset_top = 66.0
	hover_panel.offset_bottom = 98.0
	hover_panel.offset_right = 540.0
	add_child(hover_panel)

	_lbl_hover_pill = Label.new()
	_lbl_hover_pill.text = "Survolez ou cliquez sur le monde • Glisser/Tactile/Flèches : Caméra • Molette : Zoom"
	_lbl_hover_pill.add_theme_font_size_override("font_size", 12)
	_lbl_hover_pill.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98))
	hover_panel.add_child(_lbl_hover_pill)

	# 4b. Commandes de Navigation Caméra directes (Tactile & Clavier)
	_nav_panel = _create_styled_panel(Color(0.06, 0.09, 0.15, 0.88), Color(0.48, 0.72, 0.95, 0.55), 8)
	_nav_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_nav_panel.offset_left = 12.0
	_nav_panel.offset_top = -124.0
	_nav_panel.offset_bottom = -12.0
	_nav_panel.offset_right = 160.0
	add_child(_nav_panel)

	var nav_vbox := VBoxContainer.new()
	nav_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_vbox.add_theme_constant_override("separation", 2)
	_nav_panel.add_child(nav_vbox)

	var nav_top := HBoxContainer.new()
	nav_top.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_vbox.add_child(nav_top)
	var btn_up := Button.new()
	btn_up.text = "▲"
	btn_up.custom_minimum_size = Vector2(34.0, 28.0)
	btn_up.pressed.connect(func() -> void: renderer.pan_by_screen_delta(Vector2(0, 90)))
	nav_top.add_child(btn_up)

	var nav_mid := HBoxContainer.new()
	nav_mid.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_mid.add_theme_constant_override("separation", 4)
	nav_vbox.add_child(nav_mid)

	var btn_left := Button.new()
	btn_left.text = "◀"
	btn_left.custom_minimum_size = Vector2(34.0, 28.0)
	btn_left.pressed.connect(func() -> void: renderer.pan_by_screen_delta(Vector2(90, 0)))
	nav_mid.add_child(btn_left)

	var btn_center := Button.new()
	btn_center.text = "🎯"
	btn_center.tooltip_text = "Recentrer la caméra sur le monde"
	btn_center.custom_minimum_size = Vector2(34.0, 28.0)
	btn_center.pressed.connect(func() -> void: renderer.center_camera_on_world())
	nav_mid.add_child(btn_center)

	var btn_right := Button.new()
	btn_right.text = "▶"
	btn_right.custom_minimum_size = Vector2(34.0, 28.0)
	btn_right.pressed.connect(func() -> void: renderer.pan_by_screen_delta(Vector2(-90, 0)))
	nav_mid.add_child(btn_right)

	var nav_bot := HBoxContainer.new()
	nav_bot.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_vbox.add_child(nav_bot)
	var btn_down := Button.new()
	btn_down.text = "▼"
	btn_down.custom_minimum_size = Vector2(34.0, 28.0)
	btn_down.pressed.connect(func() -> void: renderer.pan_by_screen_delta(Vector2(0, -90)))
	nav_bot.add_child(btn_down)

	# 5. Tiroir Latéral Droit Escamotable (380px, clair et aéré, ne chevauche jamais le dock inférieur)
	_right_drawer = _create_styled_panel(Color(0.06, 0.09, 0.15, 0.94), Color(0.48, 0.68, 0.92, 0.58), 10)
	_right_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_right_drawer.offset_top = 66.0
	_right_drawer.offset_bottom = -138.0
	_right_drawer.offset_left = -388.0
	_right_drawer.offset_right = -10.0
	add_child(_right_drawer)

	var drawer_vbox := VBoxContainer.new()
	drawer_vbox.add_theme_constant_override("separation", 6)
	_right_drawer.add_child(drawer_vbox)

	var drawer_hdr := HBoxContainer.new()
	drawer_vbox.add_child(drawer_hdr)
	var lbl_dh := Label.new()
	lbl_dh.text = "✦ REGISTRE D'OMNISCIENCE"
	lbl_dh.add_theme_font_size_override("font_size", 13)
	lbl_dh.add_theme_color_override("font_color", Color(0.98, 0.86, 0.44))
	lbl_dh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_hdr.add_child(lbl_dh)

	var btn_hide_drawer := Button.new()
	btn_hide_drawer.text = "✕ Masquer (Tab)"
	btn_hide_drawer.pressed.connect(_toggle_right_drawer)
	drawer_hdr.add_child(btn_hide_drawer)

	_drawer_tabs = TabContainer.new()
	_drawer_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawer_vbox.add_child(_drawer_tabs)

	# Onglet 0 : Sélection & Actions Rapides
	var tab_inspect := VBoxContainer.new()
	tab_inspect.name = "🔍 Sélection"
	tab_inspect.add_theme_constant_override("separation", 6)
	_drawer_tabs.add_child(tab_inspect)

	# Boutons d'intervention divine rapide sur le lieu inspecté (Prise en main immédiate !)
	var quick_lbl := Label.new()
	quick_lbl.text = "Actions rapides sur le lieu sélectionné :"
	quick_lbl.add_theme_font_size_override("font_size", 12)
	quick_lbl.add_theme_color_override("font_color", Color(0.75, 0.86, 0.98))
	tab_inspect.add_child(quick_lbl)

	var quick_grid := GridContainer.new()
	quick_grid.columns = 2
	quick_grid.add_theme_constant_override("h_separation", 6)
	quick_grid.add_theme_constant_override("v_separation", 6)
	tab_inspect.add_child(quick_grid)

	for qa in [
		{"p": "BLESS_PROSPERITY", "l": "✨ Bénir & Guérir"},
		{"p": "FERTILE_RAIN", "l": "🌧 Pluie Fertile"},
		{"p": "INSPIRE_PROPHET", "l": "🌟 Inspirer Prophète"},
		{"p": "SUMMON_GUARDIAN", "l": "🕊 Gardien Céleste"}
	]:
		var qb := Button.new()
		qb.text = String(qa["l"])
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var p_code: String = String(qa["p"])
		qb.pressed.connect(func() -> void:
			var res: Dictionary = DivinePowerSystem.apply_power(
				sim.state, sim.rng, p_code, inspected_tile.x, inspected_tile.y, 2, 1.0
			)
			_show_toast(String(res.get("summary", "")))
			_refresh_all_ui()
		)
		quick_grid.add_child(qb)

	var sel_grid := GridContainer.new()
	sel_grid.columns = 2
	tab_inspect.add_child(sel_grid)

	var l_sciv := Label.new()
	l_sciv.text = "Peuple :"
	sel_grid.add_child(l_sciv)
	_opt_inspect_civ = OptionButton.new()
	_opt_inspect_civ.clip_text = true
	_opt_inspect_civ.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_inspect_civ.item_selected.connect(func(idx: int) -> void:
		inspected_civ_id = int(_opt_inspect_civ.get_item_metadata(idx))
		if sim.state.civilizations.has(inspected_civ_id):
			var cap_id: int = int(sim.state.civilizations[inspected_civ_id].get("capital_settlement_id", -1))
			if sim.state.settlements.has(cap_id):
				var cap: Dictionary = sim.state.settlements[cap_id]
				inspected_tile = Vector2i(int(cap["tile_x"]), int(cap["tile_y"]))
				renderer.selected_tile = inspected_tile
				renderer.center_on_tile(inspected_tile.x, inspected_tile.y)
		_refresh_inspector_panel()
	)
	sel_grid.add_child(_opt_inspect_civ)

	var l_srel := Label.new()
	l_srel.text = "Religion :"
	sel_grid.add_child(l_srel)
	_opt_inspect_rel = OptionButton.new()
	_opt_inspect_rel.clip_text = true
	_opt_inspect_rel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_inspect_rel.item_selected.connect(func(idx: int) -> void:
		inspected_religion_id = int(_opt_inspect_rel.get_item_metadata(idx))
		_refresh_inspector_panel()
	)
	sel_grid.add_child(_opt_inspect_rel)

	var l_sind := Label.new()
	l_sind.text = "Personnage :"
	sel_grid.add_child(l_sind)
	_opt_inspect_ind = OptionButton.new()
	_opt_inspect_ind.clip_text = true
	_opt_inspect_ind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_inspect_ind.item_selected.connect(func(idx: int) -> void:
		inspected_individual_id = int(_opt_inspect_ind.get_item_metadata(idx))
		_refresh_inspector_panel()
	)
	sel_grid.add_child(_opt_inspect_ind)

	_rtl_inspector = RichTextLabel.new()
	_rtl_inspector.bbcode_enabled = true
	_rtl_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_inspect.add_child(_rtl_inspector)

	# Onglet 1 : Prières
	var tab_prayers := VBoxContainer.new()
	tab_prayers.name = "🙏 Prières"
	_drawer_tabs.add_child(tab_prayers)
	var pray_scroll := ScrollContainer.new()
	pray_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_prayers.add_child(pray_scroll)
	_prayers_vbox = VBoxContainer.new()
	_prayers_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prayers_vbox.add_theme_constant_override("separation", 8)
	pray_scroll.add_child(_prayers_vbox)

	# Onglet 2 : Chroniques
	var tab_chron := VBoxContainer.new()
	tab_chron.name = "📜 Chroniques"
	_drawer_tabs.add_child(tab_chron)
	var filter_hbox := HBoxContainer.new()
	tab_chron.add_child(filter_hbox)
	for f_pair in [["ALL", "Tout"], ["MIRACLE", "Miracles"], ["RELIGION", "Foi"], ["WAR", "Guerres"], ["TECH", "Savoirs"]]:
		var fb := Button.new()
		fb.text = String(f_pair[1])
		var f_code: String = String(f_pair[0])
		fb.pressed.connect(func() -> void:
			active_event_filter = f_code
			_refresh_chronicles_panel()
		)
		filter_hbox.add_child(fb)

	_rtl_chronicles = RichTextLabel.new()
	_rtl_chronicles.bbcode_enabled = true
	_rtl_chronicles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_chron.add_child(_rtl_chronicles)

	# Onglet 3 : Monde & Diagnostic
	var tab_diag := VBoxContainer.new()
	tab_diag.name = "📊 Monde"
	_drawer_tabs.add_child(tab_diag)
	_rtl_diagnostics = RichTextLabel.new()
	_rtl_diagnostics.bbcode_enabled = true
	_rtl_diagnostics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_diag.add_child(_rtl_diagnostics)
	_drawer_tabs.tab_changed.connect(func(_tab: int) -> void: _refresh_active_drawer_tab())

	# 6. Modales (Genèse, Lois de la Nature, Guide de Prise en Main)
	_build_genesis_modal()
	_build_natural_laws_modal()
	_build_help_modal()


func _build_help_modal() -> void:
	_modal_help = _create_styled_panel(Color(0.06, 0.09, 0.16, 0.97), Color(0.98, 0.84, 0.36, 0.95), 12)
	_modal_help.custom_minimum_size = Vector2(540.0, 360.0)
	_modal_help.set_anchors_preset(Control.PRESET_CENTER)
	_modal_help.offset_left = -270.0
	_modal_help.offset_right = 270.0
	_modal_help.offset_top = -180.0
	_modal_help.offset_bottom = 180.0
	_modal_help.visible = false # Accessible à tout moment via le bouton '?'
	add_child(_modal_help)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_modal_help.add_child(vb)

	var title := Label.new()
	title.text = "✦ BIENVENUE DANS GENESIS — GUIDE DE PRISE EN MAIN"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.42))
	vb.add_child(title)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rtl.text = "\n".join([
		"[b][color=#38bdf8]1. Naviguer (PC & Android Tactile) :[/color][/b]",
		"• [b]En mode 👁 Observer :[/b] Glissez à 1 doigt (ou Clic Droit / ZQSD) pour déplacer la carte. Touchez/Cliquez une cité pour l'inspecter.",
		"• [b]Zoom :[/b] Pincez à 2 doigts sur Android, utilisez la Molette, ou les boutons [b]➕ / ➖[/b] en haut.",
		"",
		"[b][color=#facc15]2. Observer et Agir (Simple & Intuitif) :[/color][/b]",
		"• En touchant une cité, le volet droit affiche ses habitants, ses stocks et [b]4 boutons d'action divine rapide en 1 clic[/b].",
		"• Choisissez une famille dans le [b]Dock du bas[/b] ([i]Terre & Eau, Climat & Vie, Peuples, Miracles, Cataclysmes[/i]) puis touchez/glissez sur la carte !",
		"",
		"[b][color=#4ade80]3. Un Monde Autonome :[/color][/b]",
		"• Même sans intervention, les peuples cultivent, commercent par caravanes, fondent des colonies, inventent des savoirs, créent des religions et vous adressent leurs [b]🙏 Prières[/b]."
	])
	vb.add_child(rtl)

	var btn_start := Button.new()
	btn_start.text = "✦ Entrer dans le Monde (Compris)"
	btn_start.custom_minimum_size = Vector2(0.0, 42.0)
	btn_start.pressed.connect(func() -> void: _modal_help.visible = false)
	vb.add_child(btn_start)


func _select_dock_category(category_id: String) -> void:
	active_domain_filter = category_id
	for cid in _category_buttons.keys():
		var b: Button = _category_buttons[cid]
		b.modulate = Color(1.0, 0.92, 0.48) if cid == category_id else Color(0.88, 0.92, 0.98)

	if category_id == "OBSERVATION":
		active_power_id = "OBSERVE"
		renderer.is_observe_mode = true
		renderer.brush_radius = 0
		_subbar_panel.visible = false
		_show_toast("Mode Observation : Touchez/Cliquez une cité pour l'inspecter, glissez pour déplacer la carte.")
		return

	renderer.is_observe_mode = false
	_subbar_panel.visible = true
	for child in _power_buttons_hbox.get_children():
		child.queue_free()

	var matching_powers: Array[String] = []
	for p_id in DivinePowerSystem.POWER_CATALOG.keys():
		if p_id == "OBSERVE":
			continue
		var info: Dictionary = DivinePowerSystem.POWER_CATALOG[p_id]
		var dom: String = String(info["domain"])
		if category_id == "CLIMATE_NATURE" and dom in ["CLIMATE", "NATURE"]:
			matching_powers.append(p_id)
		elif dom == category_id:
			matching_powers.append(p_id)

	if not matching_powers.is_empty() and not matching_powers.has(active_power_id):
		active_power_id = matching_powers[0]
		var def_rad: int = int(DivinePowerSystem.POWER_CATALOG[active_power_id].get("default_radius", 2))
		_slider_radius.value = def_rad
		renderer.brush_radius = def_rad

	for p_id in matching_powers:
		var info: Dictionary = DivinePowerSystem.POWER_CATALOG[p_id]
		var pb := Button.new()
		pb.text = String(info["label"])
		pb.tooltip_text = String(info["desc"])
		pb.custom_minimum_size = Vector2(0.0, 32.0)
		if p_id == active_power_id:
			pb.modulate = Color(1.0, 0.92, 0.45)
		var code: String = p_id
		pb.pressed.connect(func() -> void:
			active_power_id = code
			var dr: int = int(DivinePowerSystem.POWER_CATALOG[code].get("default_radius", 2))
			_slider_radius.value = dr
			renderer.brush_radius = dr
			_select_dock_category(category_id)
		)
		_power_buttons_hbox.add_child(pb)

	var active_info: Dictionary = DivinePowerSystem.POWER_CATALOG.get(active_power_id, {})
	_lbl_active_power_hint.text = "✦ %s — %s" % [
		String(active_info.get("label", "")),
		String(active_info.get("desc", ""))
	]


func _toggle_right_drawer() -> void:
	_right_drawer.visible = not _right_drawer.visible
	_btn_toggle_drawer.text = "📋 Infos" if _right_drawer.visible else "📋 Ouvrir Infos"


func _open_drawer_tab(tab_idx: int) -> void:
	_right_drawer.visible = true
	_drawer_tabs.current_tab = tab_idx
	_refresh_all_ui()


func _make_pill_button(txt: String, tooltip: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = tooltip
	b.pressed.connect(callback)
	return b


func _build_genesis_modal() -> void:
	_modal_genesis = _create_styled_panel(Color(0.07, 0.10, 0.17, 0.98), Color(0.95, 0.80, 0.35, 0.92), 12)
	_modal_genesis.custom_minimum_size = Vector2(460.0, 410.0)
	_modal_genesis.set_anchors_preset(Control.PRESET_CENTER)
	_modal_genesis.offset_left = -230.0
	_modal_genesis.offset_right = 230.0
	_modal_genesis.offset_top = -205.0
	_modal_genesis.offset_bottom = 205.0
	_modal_genesis.visible = false
	add_child(_modal_genesis)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_modal_genesis.add_child(vbox)

	var title := Label.new()
	title.text = "🌍 CRÉATION D'UN NOUVEL UNIVERS (GENÈSE)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.44))
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	var l1 := Label.new()
	l1.text = "Nom de l'Univers :"
	grid.add_child(l1)
	_inp_world_name = LineEdit.new()
	_inp_world_name.text = "Aethelgard"
	_inp_world_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_inp_world_name)

	var l2 := Label.new()
	l2.text = "Graine (Seed) :"
	grid.add_child(l2)
	var seed_hbox := HBoxContainer.new()
	grid.add_child(seed_hbox)
	_inp_seed = SpinBox.new()
	_inp_seed.min_value = 1
	_inp_seed.max_value = 99999999
	_inp_seed.value = 424242
	_inp_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_hbox.add_child(_inp_seed)
	var btn_rand_seed := Button.new()
	btn_rand_seed.text = "🎲"
	btn_rand_seed.pressed.connect(func() -> void: _inp_seed.value = randi_range(10000, 9999999))
	seed_hbox.add_child(btn_rand_seed)

	var l3 := Label.new()
	l3.text = "Dimensions du Monde :"
	grid.add_child(l3)
	_opt_map_size = OptionButton.new()
	_opt_map_size.add_item("Petit (36×28)", 0)
	_opt_map_size.add_item("Moyen (48×36)", 1)
	_opt_map_size.add_item("Vaste (60×44)", 2)
	_opt_map_size.selected = 1
	grid.add_child(_opt_map_size)

	var l4 := Label.new()
	l4.text = "Scénario Initial :"
	grid.add_child(l4)
	_opt_scenario = OptionButton.new()
	_opt_scenario.add_item("Aube Tribale (Tribus autonomes)", 0)
	_opt_scenario.set_item_metadata(0, "TRIBAL_DAWN")
	_opt_scenario.add_item("Monde Vierge (Création pure)", 1)
	_opt_scenario.set_item_metadata(1, "VIRGIN_WORLD")
	_opt_scenario.add_item("Empires Anciens (Royaumes & Cultes)", 2)
	_opt_scenario.set_item_metadata(2, "ANCIENT_EMPIRES")
	_opt_scenario.add_item("Âge Surnaturel (Esprits & Magie)", 3)
	_opt_scenario.set_item_metadata(3, "SUPERNATURAL_AGE")
	grid.add_child(_opt_scenario)

	var l5 := Label.new()
	l5.text = "Peuples au départ :"
	grid.add_child(l5)
	_slider_tribes = HSlider.new()
	_slider_tribes.min_value = 1
	_slider_tribes.max_value = 7
	_slider_tribes.step = 1
	_slider_tribes.value = 4
	grid.add_child(_slider_tribes)

	var l6 := Label.new()
	l6.text = "Surnaturel & Magie :"
	grid.add_child(l6)
	_chk_magic = CheckButton.new()
	_chk_magic.button_pressed = true
	_chk_magic.text = "Activer Plans Spirituels & Miracles"
	grid.add_child(_chk_magic)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var btn_create := Button.new()
	btn_create.text = "✦ Que la Lumière Soit (Générer)"
	btn_create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_create.pressed.connect(_on_generate_world_confirmed)
	btn_row.add_child(btn_create)

	var btn_close := Button.new()
	btn_close.text = "Fermer"
	btn_close.pressed.connect(func() -> void: _modal_genesis.visible = false)
	btn_row.add_child(btn_close)


func _build_natural_laws_modal() -> void:
	_modal_laws = _create_styled_panel(Color(0.07, 0.10, 0.17, 0.98), Color(0.45, 0.82, 0.98, 0.92), 12)
	_modal_laws.custom_minimum_size = Vector2(480.0, 400.0)
	_modal_laws.set_anchors_preset(Control.PRESET_CENTER)
	_modal_laws.offset_left = -240.0
	_modal_laws.offset_right = 240.0
	_modal_laws.offset_top = -200.0
	_modal_laws.offset_bottom = 200.0
	_modal_laws.visible = false
	add_child(_modal_laws)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_modal_laws.add_child(vbox)

	var title := Label.new()
	title.text = "⚖ ÉDITEUR DIVIN DES LOIS DE LA NATURE"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.55, 0.88, 0.98))
	vbox.add_child(title)

	var laws_def: Array[Dictionary] = [
		{"key": "lifespan_multiplier", "label": "Longévité Biologique", "min": 0.5, "max": 4.0, "step": 0.25},
		{"key": "resource_regen_multiplier", "label": "Régénération Écologique", "min": 0.4, "max": 3.0, "step": 0.2},
		{"key": "fertility_global_modifier", "label": "Fertilité Globale des Sols", "min": 0.4, "max": 2.5, "step": 0.1},
		{"key": "climate_volatility", "label": "Volatilité Climatique", "min": 0.2, "max": 2.5, "step": 0.1},
		{"key": "conflict_propensity", "label": "Propension aux Conflits", "min": 0.2, "max": 2.5, "step": 0.1}
	]

	for ld in laws_def:
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var lbl := Label.new()
		lbl.text = String(ld["label"])
		lbl.custom_minimum_size = Vector2(220.0, 0.0)
		row.add_child(lbl)

		var sl := HSlider.new()
		sl.min_value = float(ld["min"])
		sl.max_value = float(ld["max"])
		sl.step = float(ld["step"])
		sl.value = float(sim.state.natural_laws.get(String(ld["key"]), 1.0))
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sl)

		var val_lbl := Label.new()
		val_lbl.text = "%.2fx" % sl.value
		val_lbl.custom_minimum_size = Vector2(48.0, 0.0)
		row.add_child(val_lbl)

		var law_key: String = String(ld["key"])
		sl.value_changed.connect(func(v: float) -> void:
			sim.state.natural_laws[law_key] = v
			val_lbl.text = "%.2fx" % v
			_show_toast("Loi cosmique modifiée : %s = %.2fx" % [law_key, v])
		)

	var chk_transcend := CheckButton.new()
	chk_transcend.text = "Ascension des Prophètes/Saints en Esprits à leur mort"
	chk_transcend.button_pressed = bool(sim.state.natural_laws.get("mortality_can_transcend", true))
	chk_transcend.toggled.connect(func(on: bool) -> void:
		sim.state.natural_laws["mortality_can_transcend"] = on
	)
	vbox.add_child(chk_transcend)

	var btn_close := Button.new()
	btn_close.text = "Fermer l'Éditeur Cosmologique"
	btn_close.pressed.connect(func() -> void: _modal_laws.visible = false)
	vbox.add_child(btn_close)


func _on_world_tile_clicked(x: int, y: int, _button_index: int) -> void:
	inspected_tile = Vector2i(x, y)
	var t: Dictionary = sim.state.get_tile(x, y)
	if not t.is_empty():
		var s_id: int = int(t.get("settlement_id", -1))
		if s_id != -1 and sim.state.settlements.has(s_id):
			inspected_civ_id = int(sim.state.settlements[s_id]["civ_id"])
			_right_drawer.visible = true
		elif int(t.get("owner_civ_id", -1)) != -1:
			inspected_civ_id = int(t["owner_civ_id"])

	if active_power_id != "OBSERVE":
		var res: Dictionary = DivinePowerSystem.apply_power(
			sim.state,
			sim.rng,
			active_power_id,
			x,
			y,
			int(_slider_radius.value),
			active_power_intensity
		)
		_show_toast(String(res.get("summary", "")))

	_refresh_all_ui()


func _on_world_tile_hovered(x: int, y: int) -> void:
	var t: Dictionary = sim.state.get_tile(x, y)
	if t.is_empty():
		return
	var s_id: int = int(t.get("settlement_id", -1))
	var s_txt: String = ""
	if s_id != -1 and sim.state.settlements.has(s_id):
		var s: Dictionary = sim.state.settlements[s_id]
		s_txt = "  •  🏛 %s (%d hab.)" % [String(s["name"]), int(s["population"])]
	_lbl_hover_pill.text = "📍 (%d, %d) %s  •  %.1f°C  •  Fertilité %.0f%%%s" % [
		x, y, String(t["biome"]), float(t["temperature"]), float(t["fertility"]) * 100.0, s_txt
	]


func _refresh_all_ui() -> void:
	_refresh_top_bar()
	if _right_drawer != null and _right_drawer.visible:
		_refresh_active_drawer_tab()


func _refresh_active_drawer_tab() -> void:
	if _drawer_tabs == null:
		return
	match _drawer_tabs.current_tab:
		0:
			_refresh_inspector_selectors()
			_refresh_inspector_panel()
		1:
			_refresh_prayers_panel()
		2:
			_refresh_chronicles_panel()
		3:
			_refresh_diagnostics_panel()


func _refresh_top_bar() -> void:
	_lbl_world_title.text = "✦ %s" % sim.state.world_name
	var spd_txt: String = "PAUSE" if sim.speed_multiplier <= 0.001 else ("%.0fx" % sim.speed_multiplier)
	_lbl_date_era.text = "An %d (%s) [%s]" % [
		sim.state.year, sim.state.season, spd_txt
	]
	_btn_pill_pop.text = "👥 %d" % sim.state.get_total_population()
	_btn_pill_civs.text = "👑 %d" % sim.state.get_active_civ_count()
	_btn_pill_rel.text = "🙏 %d" % sim.state.get_active_religion_count()
	_btn_pill_wars.text = "⚔ %d" % sim.state.get_active_wars_count()

	var p_cnt: int = sim.state.get_pending_prayers_count()
	_btn_pill_prayers.text = "🔔 %d" % p_cnt
	_btn_pill_prayers.modulate = Color(1.0, 0.88, 0.36) if p_cnt > 0 else Color.WHITE


func _refresh_inspector_selectors() -> void:
	if _opt_inspect_civ == null or _opt_inspect_rel == null or _opt_inspect_ind == null:
		return
	var sig: String = "%d_%d_%d" % [sim.state.civilizations.size(), sim.state.religions.size(), sim.state.individuals.size()]
	if sig == _last_selectors_signature and _opt_inspect_civ.item_count > 0:
		return
	_last_selectors_signature = sig

	_opt_inspect_civ.clear()
	var civ_idx: int = 0
	for c_id in sim.state.civilizations.keys():
		var c: Dictionary = sim.state.civilizations[c_id]
		var status_tag: String = "" if bool(c.get("alive", false)) else " (Éteinte)"
		_opt_inspect_civ.add_item("%s [%s]%s" % [String(c["name"]), String(c["government_type"]), status_tag], civ_idx)
		_opt_inspect_civ.set_item_metadata(civ_idx, int(c_id))
		if int(c_id) == inspected_civ_id:
			_opt_inspect_civ.selected = civ_idx
		civ_idx += 1
	if inspected_civ_id == -1 and civ_idx > 0:
		inspected_civ_id = int(_opt_inspect_civ.get_item_metadata(0))

	_opt_inspect_rel.clear()
	var rel_idx: int = 0
	for r_id in sim.state.religions.keys():
		var r: Dictionary = sim.state.religions[r_id]
		_opt_inspect_rel.add_item("%s (%d fidèles)" % [String(r["name"]), int(r.get("total_believers", 0))], rel_idx)
		_opt_inspect_rel.set_item_metadata(rel_idx, int(r_id))
		if int(r_id) == inspected_religion_id:
			_opt_inspect_rel.selected = rel_idx
		rel_idx += 1
	if inspected_religion_id == -1 and rel_idx > 0:
		inspected_religion_id = int(_opt_inspect_rel.get_item_metadata(0))

	_opt_inspect_ind.clear()
	var ind_idx: int = 0
	for i_id in sim.state.individuals.keys():
		var ind: Dictionary = sim.state.individuals[i_id]
		if not bool(ind.get("alive", false)):
			continue
		_opt_inspect_ind.add_item("%s (%s, %d ans)" % [String(ind["name"]), String(ind["role"]), int(ind["age"])], ind_idx)
		_opt_inspect_ind.set_item_metadata(ind_idx, int(i_id))
		if int(i_id) == inspected_individual_id:
			_opt_inspect_ind.selected = ind_idx
		ind_idx += 1
	if inspected_individual_id == -1 and ind_idx > 0:
		inspected_individual_id = int(_opt_inspect_ind.get_item_metadata(0))


func _refresh_inspector_panel() -> void:
	if _rtl_inspector == null:
		return
	var lines: PackedStringArray = PackedStringArray()

	var tile: Dictionary = sim.state.get_tile(inspected_tile.x, inspected_tile.y)
	if not tile.is_empty():
		var s_id: int = int(tile.get("settlement_id", -1))
		if s_id != -1 and sim.state.settlements.has(s_id):
			var s: Dictionary = sim.state.settlements[s_id]
			var stocks: Dictionary = s["stocks"]
			var prod: Dictionary = s["last_production"]
			var cons: Dictionary = s["last_consumption"]
			lines.append("[b][color=#facc15]🏛 CITÉ : %s (%s)[/color][/b]" % [String(s["name"]), String(s["tier"])])
			lines.append("• [b]Habitants :[/b] %d  |  [b]Satisfaction :[/b] %.0f%%  |  [b]Agitation :[/b] %.0f%%" % [
				int(s["population"]),
				float(s["public_opinion"]["economic_satisfaction"]) * 100.0,
				float(s["public_opinion"]["unrest"]) * 100.0
			])
			lines.append("• [b]Nourriture :[/b] %.0f ([color=#4ade80]+%.1f[/color] / [color=#f87171]-%.1f[/color])" % [
				float(stocks["food"]), float(prod.get("food", 0.0)), float(cons.get("food", 0.0))
			])
			lines.append("• [b]Matériaux :[/b] Bois %.0f • Pierre %.0f • Minerai %.0f • Outils %.0f • Or %.0f" % [
				float(stocks["wood"]), float(stocks["stone"]), float(stocks["ore"]), float(stocks["tools"]), float(stocks["wealth"])
			])
			lines.append("• [b]Infrastructures :[/b] %s\n" % ", ".join(s["buildings"]))

		lines.append("[b][color=#38bdf8]🌍 TERRAIN (%d, %d) — %s[/color][/b]" % [inspected_tile.x, inspected_tile.y, String(tile["biome"])])
		lines.append("• [b]Climat :[/b] %.1f °C • Pluie %.0f%% • Fertilité %.0f%%" % [
			float(tile["temperature"]), float(tile["rainfall"]) * 100.0, float(tile["fertility"]) * 100.0
		])
		lines.append("• [b]Ressources :[/b] Flore %.0f/100 • Faune %d • %s (%.0f)" % [
			float(tile["biomass_flora"]), int(tile["fauna_count"]), String(tile["mineral_type"]), float(tile["mineral_reserve"])
		])

	if sim.state.civilizations.has(inspected_civ_id):
		var civ: Dictionary = sim.state.civilizations[inspected_civ_id]
		var ruler: Dictionary = sim.state.individuals.get(int(civ.get("ruler_individual_id", -1)), {})
		lines.append("\n[b][color=#f472b6]👑 PEUPLE : %s (%s)[/color][/b]" % [String(civ["name"]), String(civ["government_type"])])
		lines.append("• [b]Dirigeant :[/b] %s  |  [b]Stabilité :[/b] %.0f%%  |  [b]Trésor :[/b] %.0f" % [
			String(ruler.get("name", "Conseil")), float(civ["stability"]) * 100.0, float(civ["treasury"])
		])
		lines.append("• [b]Identité :[/b] %s (%s)" % [
			String(civ["culture"]["language_name"]), ", ".join(civ["culture"]["core_values"])
		])
		lines.append("• [b]Savoirs (%d) :[/b] %s" % [
			civ["technologies"].size(), ", ".join(civ["technologies"])
		])

	if sim.state.religions.has(inspected_religion_id):
		var rel: Dictionary = sim.state.religions[inspected_religion_id]
		lines.append("\n[b][color=#c084fc]🙏 CROYANCE : %s[/color][/b]" % String(rel["name"]))
		lines.append("• [b]Doctrine :[/b] %s (%d fidèles • Unité %.0f%%)" % [
			String(rel["theology_type"]), int(rel["total_believers"]), float(rel["internal_unity"]) * 100.0
		])
		lines.append("• [b]Vision :[/b] %s" % String(rel["divine_nature"]))
		lines.append("• [b]Éthique & Rites :[/b] %s | %s" % [
			", ".join(rel["ethics"]), ", ".join(rel["rites"])
		])

	if sim.state.individuals.has(inspected_individual_id):
		var ind: Dictionary = sim.state.individuals[inspected_individual_id]
		var tr: Dictionary = ind["traits"]
		lines.append("\n[b][color=#4ade80]👤 PERSONNAGE : %s (%s)[/color][/b]" % [String(ind["name"]), String(ind["role"])])
		lines.append("• [b]Âge :[/b] %d / %d ans  |  [b]Ambition :[/b] %s" % [
			int(ind["age"]), int(ind["max_age"]), String(ind["current_goal"])
		])
		lines.append("• [b]Caractère :[/b] Courage %.0f%% • Sagesse %.0f%% • Charisme %.0f%%" % [
			float(tr["courage"]) * 100.0, float(tr["curiosity"]) * 100.0, float(tr["charisma"]) * 100.0
		])

	_rtl_inspector.text = "\n".join(lines)


func _refresh_prayers_panel() -> void:
	var current_sig: String = ""
	for p_id in sim.state.prayers.keys():
		var p: Dictionary = sim.state.prayers[p_id]
		if String(p.get("status", "")) == "PENDING":
			current_sig += "%d;" % int(p_id)
	if current_sig == _last_prayers_signature and _prayers_vbox.get_child_count() > 0:
		return
	_last_prayers_signature = current_sig

	for child in _prayers_vbox.get_children():
		child.queue_free()

	var pending_count: int = 0
	for p_id in sim.state.prayers.keys():
		var p: Dictionary = sim.state.prayers[p_id]
		if String(p.get("status", "")) != "PENDING":
			continue
		pending_count += 1
		var card := _create_styled_panel(Color(0.11, 0.15, 0.24, 0.95), Color(0.95, 0.78, 0.32, 0.75), 8)
		_prayers_vbox.add_child(card)

		var vb := VBoxContainer.new()
		card.add_child(vb)

		var title := Label.new()
		title.text = "🙏 %s (Urgence %.0f%%)" % [String(p["title"]), float(p["urgency"]) * 100.0]
		title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.42))
		vb.add_child(title)

		var desc := Label.new()
		desc.text = String(p["description"])
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(desc)

		var btn_row := HBoxContainer.new()
		vb.add_child(btn_row)
		var pid: int = int(p["id"])
		var px: int = int(p["tile_x"])
		var py: int = int(p["tile_y"])

		var b_direct := Button.new()
		b_direct.text = "✨ Exaucer"
		b_direct.pressed.connect(func() -> void:
			var msg: String = DivinePowerSystem.respond_to_prayer(sim.state, sim.rng, pid, "DIRECT")
			_show_toast(msg)
			_refresh_all_ui()
		)
		btn_row.add_child(b_direct)

		var b_sign := Button.new()
		b_sign.text = "🌟 Signe"
		b_sign.pressed.connect(func() -> void:
			var msg: String = DivinePowerSystem.respond_to_prayer(sim.state, sim.rng, pid, "SIGN")
			_show_toast(msg)
			_refresh_all_ui()
		)
		btn_row.add_child(b_sign)

		var b_silence := Button.new()
		b_silence.text = "🤫 Silence"
		b_silence.pressed.connect(func() -> void:
			var msg: String = DivinePowerSystem.respond_to_prayer(sim.state, sim.rng, pid, "SILENCE")
			_show_toast(msg)
			_refresh_all_ui()
		)
		btn_row.add_child(b_silence)

		var b_loc := Button.new()
		b_loc.text = "📍 Voir"
		b_loc.pressed.connect(func() -> void:
			inspected_tile = Vector2i(px, py)
			renderer.selected_tile = inspected_tile
			renderer.center_on_tile(px, py)
		)
		btn_row.add_child(b_loc)

	if pending_count == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "Aucune prière urgente en attente.\nAccélérez le temps (5x ou +1 An) pour observer l'évolution des civilisations."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_prayers_vbox.add_child(empty_lbl)


func _refresh_chronicles_panel() -> void:
	var lines: PackedStringArray = PackedStringArray()
	var shown: int = 0
	for ev in sim.state.events:
		var cat: String = String(ev["category"])
		if active_event_filter != "ALL" and cat != active_event_filter:
			continue
		shown += 1
		if shown > 40:
			break
		lines.append("[b][color=#facc15][An %d • %s] %s[/color][/b]" % [
			int(ev["year"]), String(ev["season"]), String(ev["title"])
		])
		lines.append("[color=#e2e8f0]%s[/color]" % String(ev["objective_truth"]))
		var causes: Array = ev.get("causal_factors", [])
		if not causes.is_empty():
			lines.append("[color=#94a3b8]↳ Cause : %s[/color]" % "; ".join(causes))
		var interps: Dictionary = ev.get("interpretations", {})
		for k in interps.keys():
			lines.append("[color=#c084fc]↳ Vue par %s : %s[/color]" % [str(k), String(interps[k])])
		lines.append("")

	_rtl_chronicles.text = "\n".join(lines)


func _refresh_diagnostics_panel() -> void:
	if _drawer_tabs != null and _drawer_tabs.current_tab != 3:
		return
	var lines: PackedStringArray = PackedStringArray()
	var inv: Dictionary = sim.verify_world_invariants()
	if bool(inv["ok"]):
		lines.append("[b][color=#4ade80]✔ MOTEUR CAUSAL : 100% COHÉRENT[/color][/b]\n")
	else:
		lines.append("[b][color=#f87171]⚠ ANOMALIES (%d)[/color][/b]" % int(inv["anomalies_count"]))

	lines.append("[b][color=#38bdf8]━━ PUISSANCE COMPARÉE DES CIVILISATIONS ━━[/color][/b]")
	for c_id in sim.state.civilizations.keys():
		var c: Dictionary = sim.state.civilizations[c_id]
		var pop: int = 0
		for s_id in c["settlement_ids"]:
			if sim.state.settlements.has(s_id):
				pop += int(sim.state.settlements[s_id]["population"])
		lines.append("• [b]%s[/b] (%s) : %d hab. | %d cités | %d savoirs | Or %.0f" % [
			String(c["name"]), String(c["government_type"]), pop,
			c["settlement_ids"].size(), c["technologies"].size(),
			float(c["treasury"])
		])

	lines.append("\n[b][color=#facc15]━━ RAISONS DES DÉCISIONS DE L'IA ━━[/color][/b]")
	var count: int = 0
	for d in sim.state.diagnostic_logs:
		count += 1
		if count > 20:
			break
		lines.append("[color=#cbd5e1][An %d] [b]%s[/b] : %s[/color]" % [
			int(d["year"]), String(d["subject"]), String(d["decision"])
		])
		var cf: Array = d.get("causal_factors", [])
		if not cf.is_empty():
			lines.append("[color=#94a3b8]  ↳ %s[/color]" % " | ".join(cf))

	_rtl_diagnostics.text = "\n".join(lines)


func _on_generate_world_confirmed() -> void:
	var w: int = 48
	var h: int = 36
	match _opt_map_size.selected:
		0:
			w = 36
			h = 28
		1:
			w = 48
			h = 36
		2:
			w = 60
			h = 44

	var scen: String = String(_opt_scenario.get_item_metadata(_opt_scenario.selected))
	sim.initialize_new_world({
		"world_name": _inp_world_name.text.strip_edges() if not _inp_world_name.text.strip_edges().is_empty() else "Aethelgard",
		"seed": int(_inp_seed.value),
		"scenario_id": scen,
		"width": w,
		"height": h,
		"initial_tribes": int(_slider_tribes.value),
		"resource_abundance": 1.0,
		"magic_enabled": _chk_magic.button_pressed
	})
	_modal_genesis.visible = false
	renderer.center_camera_on_world()
	_show_toast("Nouvelle Genèse accomplie : %s (Graine %d)" % [sim.state.world_name, sim.state.world_seed])
	_refresh_all_ui()


func _on_save_pressed() -> void:
	var path: String = SaveSystem.get_slot_path("slot_1")
	var res: Dictionary = SaveSystem.save_to_path(path, sim.state, sim.rng)
	if bool(res.get("ok", false)):
		_show_toast("Partie sauvegardée (%d Ko)" % int(int(res["bytes"]) / 1024))
	else:
		_show_toast("Erreur : " + String(res.get("error", "")))


func _on_load_pressed() -> void:
	var path: String = SaveSystem.get_slot_path("slot_1")
	var res: Dictionary = SaveSystem.load_from_path(path, sim.state, sim.rng)
	if bool(res.get("ok", false)):
		renderer.state = sim.state
		_show_toast("Monde '%s' rechargé à l'An %d !" % [String(res["world_name"]), int(res["year"])])
		_refresh_all_ui()
	else:
		_show_toast("Aucune sauvegarde trouvée.")


func _set_sim_speed(spd: float) -> void:
	sim.speed_multiplier = spd
	_refresh_top_bar()


func _show_toast(msg: String) -> void:
	if _lbl_hover_pill != null and not msg.is_empty():
		_lbl_hover_pill.text = "✦ " + msg


static func _create_styled_panel(bg_col: Color, border_col: Color, corner_radius: int = 8) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(corner_radius)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0
	pc.add_theme_stylebox_override("panel", sb)
	return pc
