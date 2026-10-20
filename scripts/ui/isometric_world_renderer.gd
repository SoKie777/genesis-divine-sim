class_name IsometricWorldRenderer
extends Node2D
## Moteur de rendu 2.5D isométrique hybride (Prismes 2.5D + Sprites 3D Blender + Couches Analytiques).
## Lit WorldState et affiche le relief, l'eau animée, la biomasse, les cités 3D Blender,
## les caravanes marchandes, les portails cosmologiques, les entités spirituelles et les armées.

signal tile_clicked(x: int, y: int, button_index: int)
signal tile_hovered(x: int, y: int)
signal right_click_cancel()

const TILE_W: float = 58.0
const TILE_H: float = 29.0
const ELEV_SCALE: float = 36.0

var state: WorldState = null
var camera_offset: Vector2 = Vector2(760.0, 140.0)
var camera_zoom: float = 0.92
var hovered_tile: Vector2i = Vector2i(-1, -1)
var selected_tile: Vector2i = Vector2i(-1, -1)
var brush_radius: int = 2
var show_borders: bool = true
var show_trade_routes: bool = true
var overlay_mode: String = "BIOME"

var _anim_time: float = 0.0
var _is_panning: bool = false
var _pan_drag_distance: float = 0.0
var _is_left_down: bool = false
var _left_down_pos: Vector2 = Vector2.ZERO
var _left_drag_distance: float = 0.0
var _last_painted_tile: Vector2i = Vector2i(-1, -1)
var is_observe_mode: bool = true

# Support Multi-Touch Android (Pinch-to-Zoom & Pan à 2 doigts)
var _touches: Dictionary = {}
var _last_pinch_dist: float = 0.0

# Textures 3D isométriques générées via Blender 5.2
var _blender_textures: Dictionary = {}


func _ready() -> void:
	_load_blender_sprites()


func _load_blender_sprites() -> void:
	var sprite_names: Array[String] = ["village", "city", "sanctuary", "portal", "spirit", "army", "ruin", "tree_forest"]
	for s_name in sprite_names:
		var res_path: String = "res://assets/sprites/%s.png" % s_name
		if ResourceLoader.exists(res_path):
			var loaded_tex: Resource = load(res_path)
			if loaded_tex is Texture2D:
				_blender_textures[s_name] = loaded_tex
				continue
		var abs_path: String = ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				_blender_textures[s_name] = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_anim_time += delta
	_handle_keyboard_pan(delta)
	queue_redraw()


func center_camera_on_world() -> void:
	if state == null:
		return
	var vp_size := Vector2(1600.0, 950.0)
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 10.0:
			vp_size = rect_size
	var mid_iso: Vector2 = _grid_to_iso_raw(int(state.width / 2), int(state.height / 2), 0.0)
	camera_offset = vp_size * 0.5 - mid_iso * camera_zoom + Vector2(-80.0, 10.0)


func center_on_tile(tx: int, ty: int) -> void:
	if state == null or not state.is_valid_coord(tx, ty):
		return
	var vp_size := Vector2(1600.0, 950.0)
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 10.0:
			vp_size = rect_size
	var t: Dictionary = state.get_tile(tx, ty)
	var elev: float = maxf(0.0, float(t.get("elevation", 0.0)))
	var iso: Vector2 = _grid_to_iso_raw(tx, ty, elev)
	camera_offset = vp_size * 0.5 - iso * camera_zoom


func _handle_keyboard_pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y -= 1.0
	if dir != Vector2.ZERO:
		camera_offset += dir.normalized() * 560.0 * delta


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return

	# 1. Gestes Multi-Touch natifs Android (Pinch-to-Zoom à 2 doigts)
	if event is InputEventScreenTouch:
		var st_ev: InputEventScreenTouch = event
		if st_ev.pressed:
			_touches[st_ev.index] = st_ev.position
			if _touches.size() == 2:
				var pts: Array = _touches.values()
				_last_pinch_dist = Vector2(pts[0]).distance_to(Vector2(pts[1]))
		else:
			_touches.erase(st_ev.index)
			if _touches.size() < 2:
				_last_pinch_dist = 0.0

	elif event is InputEventScreenDrag:
		var sd_ev: InputEventScreenDrag = event
		_touches[sd_ev.index] = sd_ev.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var p0 := Vector2(pts[0])
			var p1 := Vector2(pts[1])
			var new_dist: float = p0.distance_to(p1)
			var mid: Vector2 = (p0 + p1) * 0.5
			if _last_pinch_dist > 10.0 and new_dist > 10.0:
				var factor: float = clampf(new_dist / _last_pinch_dist, 0.85, 1.18)
				_zoom_at_point(factor, mid)
			_last_pinch_dist = new_dist
			camera_offset += sd_ev.relative * 0.5
			return

	# 2. Souris & Touch émulé (1 doigt : Glisser pour déplacer en mode Observer, ou Peindre en mode Pouvoir)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at_point(1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at_point(1.0 / 1.12, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_is_panning = true
				_pan_drag_distance = 0.0
			else:
				_is_panning = false
				if mb.button_index == MOUSE_BUTTON_RIGHT and _pan_drag_distance < 6.0:
					right_click_cancel.emit()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_left_down = true
				_left_down_pos = mb.position
				_left_drag_distance = 0.0
				if not is_observe_mode and _touches.size() < 2:
					var coord: Vector2i = screen_to_grid(mb.position)
					if state.is_valid_coord(coord.x, coord.y):
						selected_tile = coord
						_last_painted_tile = coord
						tile_clicked.emit(coord.x, coord.y, MOUSE_BUTTON_LEFT)
			else:
				if _is_left_down and is_observe_mode and _left_drag_distance < 12.0 and _touches.size() < 2:
					var coord2: Vector2i = screen_to_grid(mb.position)
					if state.is_valid_coord(coord2.x, coord2.y):
						selected_tile = coord2
						tile_clicked.emit(coord2.x, coord2.y, MOUSE_BUTTON_LEFT)
				_is_left_down = false
				_last_painted_tile = Vector2i(-1, -1)

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _touches.size() >= 2:
			return
		if _is_panning:
			camera_offset += mm.relative
			_pan_drag_distance += mm.relative.length()
		elif _is_left_down and is_observe_mode:
			camera_offset += mm.relative
			_left_drag_distance += mm.relative.length()

		var coord: Vector2i = screen_to_grid(mm.position)
		if coord != hovered_tile:
			hovered_tile = coord
			if state.is_valid_coord(coord.x, coord.y):
				tile_hovered.emit(coord.x, coord.y)
				if _is_left_down and not is_observe_mode and coord != _last_painted_tile:
					_last_painted_tile = coord
					tile_clicked.emit(coord.x, coord.y, MOUSE_BUTTON_LEFT)


func _zoom_at_point(factor: float, screen_pos: Vector2) -> void:
	var old_zoom: float = camera_zoom
	camera_zoom = clampf(camera_zoom * factor, 0.38, 2.5)
	var ratio: float = camera_zoom / old_zoom
	camera_offset = screen_pos - (screen_pos - camera_offset) * ratio


func _grid_to_iso_raw(gx: float, gy: float, elev: float = 0.0) -> Vector2:
	var ix: float = (gx - gy) * (TILE_W * 0.5)
	var iy: float = (gx + gy) * (TILE_H * 0.5) - elev * ELEV_SCALE
	return Vector2(ix, iy)


func grid_to_screen(gx: float, gy: float, elev: float = 0.0) -> Vector2:
	return _grid_to_iso_raw(gx, gy, elev) * camera_zoom + camera_offset


func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var local: Vector2 = (screen_pos - camera_offset) / camera_zoom
	var gx_f: float = (local.x / (TILE_W * 0.5) + local.y / (TILE_H * 0.5)) * 0.5
	var gy_f: float = (local.y / (TILE_H * 0.5) - local.x / (TILE_W * 0.5)) * 0.5
	return Vector2i(int(round(gx_f)), int(round(gy_f)))


func _draw() -> void:
	if state == null or state.tiles.is_empty():
		return

	var hw: float = (TILE_W * 0.5) * camera_zoom
	var hh: float = (TILE_H * 0.5) * camera_zoom
	var font: Font = ThemeDB.fallback_font

	# 1. Rendu des tuiles 2.5D isométriques dans l'ordre du peintre
	for y in range(state.height):
		for x in range(state.width):
			var tile: Dictionary = state.tiles[y * state.width + x]
			var raw_elev: float = float(tile["elevation"])
			var draw_elev: float = maxf(0.0, raw_elev)
			if raw_elev < 0.0:
				draw_elev = sin(_anim_time * 2.2 + float(x) * 0.45 + float(y) * 0.45) * 0.025

			var center: Vector2 = grid_to_screen(float(x), float(y), draw_elev)
			var base_center: Vector2 = grid_to_screen(float(x), float(y), -0.09)

			var top_pts := PackedVector2Array([
				center + Vector2(0.0, -hh),
				center + Vector2(hw, 0.0),
				center + Vector2(0.0, hh),
				center + Vector2(-hw, 0.0)
			])

			var top_col: Color = _get_tile_color(tile)

			if base_center.y > center.y + 1.0:
				var left_face := PackedVector2Array([
					center + Vector2(-hw, 0.0),
					center + Vector2(0.0, hh),
					base_center + Vector2(0.0, hh),
					base_center + Vector2(-hw, 0.0)
				])
				var right_face := PackedVector2Array([
					center + Vector2(0.0, hh),
					center + Vector2(hw, 0.0),
					base_center + Vector2(hw, 0.0),
					base_center + Vector2(0.0, hh)
				])
				draw_colored_polygon(left_face, top_col.darkened(0.30))
				draw_colored_polygon(right_face, top_col.darkened(0.45))

			draw_colored_polygon(top_pts, top_col)

			# Fleuves animés
			if bool(tile["has_river"]) and raw_elev >= 0.0 and overlay_mode in ["BIOME", "MOISTURE", "FERTILITY"]:
				var river_col := Color(0.22, 0.72, 0.98, 0.90)
				draw_line(center + Vector2(-hw * 0.36, -hh * 0.25), center + Vector2(hw * 0.36, hh * 0.25), river_col, maxf(2.0, 3.4 * camera_zoom))

			# Frontières politiques
			var owner_id: int = int(tile.get("owner_civ_id", -1))
			if show_borders and owner_id != -1 and state.civilizations.has(owner_id):
				var civ_col: Color = state.civilizations[owner_id]["color"]
				draw_polyline(PackedVector2Array([
					top_pts[0], top_pts[1], top_pts[2], top_pts[3], top_pts[0]
				]), Color(civ_col.r, civ_col.g, civ_col.b, 0.40), maxf(1.0, 1.35 * camera_zoom))

			if overlay_mode == "BIOME":
				_draw_tile_details(tile, center, hw, hh)

	# 2. Routes commerciales et caravanes marchandes en mouvement
	if show_trade_routes:
		for s_id in state.settlements.keys():
			var s: Dictionary = state.settlements[s_id]
			if String(s.get("tier", "RUIN")) == "RUIN":
				continue
			var sx: int = int(s["tile_x"])
			var sy: int = int(s["tile_y"])
			var st: Dictionary = state.get_tile(sx, sy)
			var p1: Vector2 = grid_to_screen(float(sx), float(sy), maxf(0.0, float(st.get("elevation", 0.0))))
			for partner_id in s.get("trade_partners", []):
				if int(partner_id) > int(s_id) and state.settlements.has(partner_id):
					var ps: Dictionary = state.settlements[partner_id]
					if String(ps.get("tier", "RUIN")) == "RUIN":
						continue
					var px: int = int(ps["tile_x"])
					var py: int = int(ps["tile_y"])
					var pt: Dictionary = state.get_tile(px, py)
					var p2: Vector2 = grid_to_screen(float(px), float(py), maxf(0.0, float(pt.get("elevation", 0.0))))
					draw_dashed_line(p1, p2, Color(0.98, 0.84, 0.38, 0.45), maxf(1.5, 2.0 * camera_zoom), 6.0 * camera_zoom)

		for c in state.caravans:
			var prog: float = clampf(float(c.get("progress", 0.0)) + fmod(_anim_time * 0.25, 0.25), 0.0, 1.0)
			var cx: float = lerpf(float(c["x"]), float(c["target_x"]), prog)
			var cy: float = lerpf(float(c["y"]), float(c["target_y"]), prog)
			var cpos: Vector2 = grid_to_screen(cx, cy, 0.15)
			draw_circle(cpos, 4.2 * camera_zoom, Color(1.0, 0.88, 0.32))
			draw_arc(cpos, 5.2 * camera_zoom, 0.0, TAU, 12, Color(0.15, 0.12, 0.05, 0.9), 1.4 * camera_zoom)

	# 3. Portails cosmologiques (Sprites 3D Blender)
	for portal in state.portals:
		var px: int = int(portal["x"])
		var py: int = int(portal["y"])
		var pt: Dictionary = state.get_tile(px, py)
		if not pt.is_empty():
			var p_center: Vector2 = grid_to_screen(float(px), float(py), maxf(0.0, float(pt["elevation"])))
			_draw_sprite_or_fallback("portal", p_center + Vector2(0.0, -14.0 * camera_zoom), 42.0 * camera_zoom)

	# 4. Établissements (Villages, Cités, Temples, Ruines avec Sprites 3D Blender)
	for s_id in state.settlements.keys():
		var s: Dictionary = state.settlements[s_id]
		_draw_settlement(s, hw, hh, font)

	# 5. Armées en campagne
	for a_id in state.armies.keys():
		var army: Dictionary = state.armies[a_id]
		_draw_army(army, hw, hh, font)

	# 6. Entités spirituelles autonomes
	for sp_id in state.spiritual_entities.keys():
		var ent: Dictionary = state.spiritual_entities[sp_id]
		_draw_spiritual_entity(ent, hw, hh, font)

	# 7. Impulsions visuelles et Textes flottants causaux sur la carte
	for pulse in state.visual_pulses:
		var px: int = int(pulse["x"])
		var py: int = int(pulse["y"])
		var pt: Dictionary = state.get_tile(px, py)
		var pos: Vector2 = grid_to_screen(float(px), float(py), maxf(0.0, float(pt.get("elevation", 0.0))))
		var ttl: float = float(pulse["ttl"])
		var progress: float = 1.0 - clampf(ttl / 1.8, 0.0, 1.0)
		var col: Color = pulse["color"]
		var rad: float = (20.0 + progress * 55.0 * float(pulse["radius"])) * camera_zoom
		draw_arc(pos, rad, 0.0, TAU, 36, Color(col.r, col.g, col.b, clampf(ttl, 0.0, 0.9)), 3.0 * camera_zoom)
		var lbl: String = String(pulse.get("label", ""))
		if not lbl.is_empty():
			draw_string_outline(font, pos + Vector2(-45.0, -24.0 - progress * 25.0), lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, 3, Color.BLACK)
			draw_string(font, pos + Vector2(-45.0, -24.0 - progress * 25.0), lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1, 1, 1, clampf(ttl, 0.0, 1.0)))

	for ft in state.floating_texts:
		var fx: float = float(ft["x"])
		var fy: float = float(ft["y"])
		var ttl2: float = float(ft["ttl"])
		var max_ttl: float = maxf(0.1, float(ft.get("max_ttl", 2.4)))
		var prog2: float = 1.0 - (ttl2 / max_ttl)
		var fpos: Vector2 = grid_to_screen(fx, fy, 0.35) + Vector2(-36.0, -28.0 - prog2 * 32.0)
		var fcol: Color = ft["color"]
		fcol.a = clampf(ttl2 / 1.2, 0.0, 1.0)
		draw_string_outline(font, fpos, String(ft["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, fcol.a))
		draw_string(font, fpos, String(ft["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, fcol)

	# 8. Aperçu du pinceau divin et de la sélection
	if state.is_valid_coord(hovered_tile.x, hovered_tile.y):
		_draw_brush_preview(hovered_tile.x, hovered_tile.y, brush_radius, hw, hh)
	if state.is_valid_coord(selected_tile.x, selected_tile.y):
		var st: Dictionary = state.get_tile(selected_tile.x, selected_tile.y)
		var sc: Vector2 = grid_to_screen(float(selected_tile.x), float(selected_tile.y), maxf(0.0, float(st.get("elevation", 0.0))))
		draw_polyline(PackedVector2Array([
			sc + Vector2(0.0, -hh),
			sc + Vector2(hw, 0.0),
			sc + Vector2(0.0, hh),
			sc + Vector2(-hw, 0.0),
			sc + Vector2(0.0, -hh)
		]), Color(1.0, 0.92, 0.35, 0.95), 2.8 * camera_zoom)


func _draw_sprite_or_fallback(sprite_key: String, center_pos: Vector2, size_px: float, modulate_col: Color = Color.WHITE) -> bool:
	if _blender_textures.has(sprite_key):
		var tex: Texture2D = _blender_textures[sprite_key]
		var rect := Rect2(center_pos - Vector2(size_px * 0.5, size_px * 0.55), Vector2(size_px, size_px))
		draw_texture_rect(tex, rect, false, modulate_col)
		return true
	return false


func _get_tile_color(tile: Dictionary) -> Color:
	var biome: String = String(tile["biome"])
	var elev: float = float(tile["elevation"])

	match overlay_mode:
		"ELEVATION":
			if elev < 0.0:
				return Color(0.05, 0.18, 0.45).lerp(Color(0.18, 0.48, 0.78), clampf(elev + 1.0, 0.0, 1.0))
			return Color(0.22, 0.62, 0.28).lerp(Color(0.95, 0.95, 0.98), clampf(elev, 0.0, 1.0))
		"TEMPERATURE":
			var t_norm: float = clampf((float(tile["temperature"]) + 20.0) / 60.0, 0.0, 1.0)
			return Color(0.18, 0.45, 0.98).lerp(Color(0.96, 0.22, 0.18), t_norm)
		"MOISTURE":
			var m_norm: float = clampf(float(tile["water_table"]), 0.0, 1.0)
			return Color(0.82, 0.68, 0.38).lerp(Color(0.12, 0.58, 0.96), m_norm)
		"FERTILITY":
			if elev < 0.0:
				return Color(0.08, 0.16, 0.28)
			var f_norm: float = clampf(float(tile["fertility"]), 0.0, 1.0)
			return Color(0.45, 0.32, 0.22).lerp(Color(0.18, 0.88, 0.32), f_norm)
		"POPULATION":
			var s_id: int = int(tile.get("settlement_id", -1))
			if s_id != -1 and state.settlements.has(s_id):
				var pop: int = int(state.settlements[s_id].get("population", 0))
				var p_norm: float = clampf(float(pop) / 800.0, 0.15, 1.0)
				return Color(0.98, 0.85, 0.22).lerp(Color(0.98, 0.18, 0.28), p_norm)
			return Color(0.12, 0.15, 0.22) if elev >= 0.0 else Color(0.06, 0.09, 0.15)
		"CIVILIZATION":
			var owner_id: int = int(tile.get("owner_civ_id", -1))
			if owner_id != -1 and state.civilizations.has(owner_id):
				var c: Color = state.civilizations[owner_id]["color"]
				return c.darkened(0.15)
			return Color(0.22, 0.25, 0.30) if elev >= 0.0 else Color(0.08, 0.12, 0.20)
		"RELIGION":
			var owner_id2: int = int(tile.get("owner_civ_id", -1))
			if owner_id2 != -1 and state.civilizations.has(owner_id2):
				var rel_id: int = int(state.civilizations[owner_id2].get("state_religion_id", -1))
				if rel_id != -1 and state.religions.has(rel_id):
					return state.religions[rel_id]["color"]
			return Color(0.20, 0.22, 0.28) if elev >= 0.0 else Color(0.08, 0.12, 0.20)
		"WEALTH":
			var s_id2: int = int(tile.get("settlement_id", -1))
			if s_id2 != -1 and state.settlements.has(s_id2):
				var w: float = float(state.settlements[s_id2]["stocks"].get("wealth", 0.0))
				return Color(0.35, 0.42, 0.25).lerp(Color(1.0, 0.84, 0.15), clampf(w / 300.0, 0.0, 1.0))
			return Color(0.15, 0.18, 0.22) if elev >= 0.0 else Color(0.07, 0.10, 0.16)

	var base: Color
	match biome:
		"OCEAN": base = Color(0.09, 0.26, 0.54)
		"SHALLOW_WATER": base = Color(0.16, 0.44, 0.72)
		"BEACH": base = Color(0.86, 0.78, 0.54)
		"PLAINS": base = Color(0.42, 0.72, 0.34)
		"FOREST": base = Color(0.20, 0.52, 0.26)
		"SWAMP": base = Color(0.26, 0.44, 0.34)
		"DESERT": base = Color(0.86, 0.70, 0.40)
		"TUNDRA": base = Color(0.78, 0.84, 0.88)
		"MOUNTAIN": base = Color(0.52, 0.50, 0.54)
		"VOLCANIC": base = Color(0.38, 0.18, 0.18)
		_: base = Color(0.4, 0.6, 0.4)

	if elev >= 0.0:
		if state.season == "Hiver" and biome in ["PLAINS", "FOREST", "MOUNTAIN"]:
			base = base.lerp(Color(0.90, 0.94, 0.98), 0.22)
		elif state.season == "Automne" and biome in ["PLAINS", "FOREST"]:
			base = base.lerp(Color(0.82, 0.56, 0.24), 0.16)

	return base


func _draw_tile_details(tile: Dictionary, center: Vector2, hw: float, hh: float) -> void:
	if camera_zoom < 0.46:
		return

	var biome: String = String(tile["biome"])
	var flora: float = float(tile.get("biomass_flora", 0.0))
	var s_id: int = int(tile.get("settlement_id", -1))

	if s_id == -1 and biome in ["FOREST", "SWAMP", "PLAINS"] and flora >= 35.0:
		var tree_tint: Color = Color.WHITE if state.season != "Automne" else Color(1.0, 0.78, 0.55)
		var sprite_sz: float = clampf((flora / 100.0) * 32.0 * camera_zoom, 14.0, 36.0)
		if not _draw_sprite_or_fallback("tree_forest", center + Vector2(0.0, -6.0 * camera_zoom), sprite_sz, tree_tint):
			var tree_col: Color = Color(0.14, 0.42, 0.18) if state.season != "Automne" else Color(0.76, 0.44, 0.16)
			var tree_size: float = clampf((flora / 100.0) * 7.5 * camera_zoom, 2.5, 9.0)
			draw_circle(center + Vector2(-hw * 0.22, -hh * 0.18), tree_size, tree_col)
			if flora > 65.0:
				draw_circle(center + Vector2(hw * 0.20, -hh * 0.08), tree_size * 0.85, tree_col.lightened(0.08))

	var min_type: String = String(tile.get("mineral_type", "NONE"))
	if s_id == -1 and min_type != "NONE" and float(tile.get("mineral_reserve", 0.0)) > 10.0:
		var m_col: Color = Color(0.68, 0.70, 0.74)
		if min_type == "IRON":
			m_col = Color(0.78, 0.46, 0.32)
		elif min_type == "GOLD":
			m_col = Color(0.98, 0.84, 0.22)
		elif min_type == "AETHERIUM":
			m_col = Color(0.45, 0.92, 0.98)
		draw_circle(center + Vector2(0.0, hh * 0.22), 3.4 * camera_zoom, m_col)

	var fauna_cnt: int = int(tile.get("fauna_count", 0))
	if s_id == -1 and fauna_cnt > 8 and camera_zoom >= 0.62:
		var f_id: int = int(tile.get("fauna_species_id", -1))
		var f_col: Color = Color(0.95, 0.88, 0.72)
		if f_id == 3:
			f_col = Color(0.55, 0.55, 0.62)
		elif f_id == 5:
			f_col = Color(0.55, 0.96, 0.98)
		var drift_x: float = sin(_anim_time * 1.6 + float(tile["id"])) * 3.0 * camera_zoom
		draw_circle(center + Vector2(drift_x, 0.0), 2.5 * camera_zoom, f_col)

	if int(tile.get("sacred_site_id", -1)) != -1 and s_id == -1:
		if not _draw_sprite_or_fallback("sanctuary", center + Vector2(0.0, -10.0 * camera_zoom), 36.0 * camera_zoom):
			draw_circle(center + Vector2(0.0, -8.0 * camera_zoom), 5.5 * camera_zoom, Color(0.98, 0.90, 0.42, 0.9))


func _draw_settlement(s: Dictionary, hw: float, _hh: float, font: Font) -> void:
	var sx: int = int(s["tile_x"])
	var sy: int = int(s["tile_y"])
	var tile: Dictionary = state.get_tile(sx, sy)
	if tile.is_empty():
		return

	var center: Vector2 = grid_to_screen(float(sx), float(sy), maxf(0.0, float(tile["elevation"])))
	var tier: String = String(s.get("tier", "VILLAGE"))
	var civ_id: int = int(s["civ_id"])
	var civ_col: Color = state.civilizations.get(civ_id, {}).get("color", Color.WHITE)

	if tier == "RUIN":
		if not _draw_sprite_or_fallback("ruin", center + Vector2(0.0, -8.0 * camera_zoom), 34.0 * camera_zoom):
			draw_rect(Rect2(center - Vector2(6.0, 6.0) * camera_zoom, Vector2(12.0, 8.0) * camera_zoom), Color(0.42, 0.40, 0.38))
		return

	var buildings: Array = s.get("buildings", [])
	if buildings.has("WALLS"):
		draw_arc(center, hw * 0.62, 0.0, TAU, 24, Color(civ_col.r, civ_col.g, civ_col.b, 0.68), 2.2 * camera_zoom)

	var sprite_key: String = "village"
	var sprite_size: float = 38.0 * camera_zoom
	if buildings.has("MONUMENT"):
		sprite_key = "sanctuary"
		sprite_size = 46.0 * camera_zoom
	elif tier in ["TOWN", "CITY", "METROPOLIS"]:
		sprite_key = "city"
		sprite_size = 46.0 * camera_zoom

	if not _draw_sprite_or_fallback(sprite_key, center + Vector2(0.0, -10.0 * camera_zoom), sprite_size):
		var b_size: float = 10.0 * camera_zoom
		draw_rect(Rect2(center - Vector2(b_size * 0.5, b_size * 0.8), Vector2(b_size, b_size * 0.8)), Color(0.92, 0.88, 0.80))
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-b_size * 0.65, -b_size * 0.8),
			center + Vector2(0.0, -b_size * 1.45),
			center + Vector2(b_size * 0.65, -b_size * 0.8)
		]), civ_col)

	if camera_zoom >= 0.52:
		var badge_text: String = "%s • %d" % [String(s["name"]), int(s["population"])]
		var label_pos: Vector2 = center + Vector2(-44.0, -sprite_size * 0.65 - 6.0)
		draw_string_outline(font, label_pos, badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0.04, 0.06, 0.10, 0.95))
		draw_string(font, label_pos, badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, civ_col.lightened(0.38))


func _draw_army(army: Dictionary, _hw: float, _hh: float, font: Font) -> void:
	var ax: int = int(army["tile_x"])
	var ay: int = int(army["tile_y"])
	var tile: Dictionary = state.get_tile(ax, ay)
	if tile.is_empty():
		return
	var pos: Vector2 = grid_to_screen(float(ax), float(ay), maxf(0.0, float(tile["elevation"]))) + Vector2(0.0, -14.0 * camera_zoom)
	var civ_id: int = int(army["civ_id"])
	var civ_col: Color = state.civilizations.get(civ_id, {}).get("color", Color.RED)

	if not _draw_sprite_or_fallback("army", pos, 32.0 * camera_zoom):
		draw_circle(pos, 7.0 * camera_zoom, civ_col)
		draw_arc(pos, 7.5 * camera_zoom, 0.0, TAU, 16, Color.WHITE, 1.8 * camera_zoom)

	if camera_zoom >= 0.58:
		var txt: String = "⚔ %d" % int(army["manpower"])
		draw_string_outline(font, pos + Vector2(-18.0, -14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(font, pos + Vector2(-18.0, -14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, civ_col.lightened(0.4))


func _draw_spiritual_entity(ent: Dictionary, _hw: float, _hh: float, _font: Font) -> void:
	var sx: int = int(ent["tile_x"])
	var sy: int = int(ent["tile_y"])
	var tile: Dictionary = state.get_tile(sx, sy)
	if tile.is_empty():
		return
	var float_y: float = sin(_anim_time * 3.0 + float(ent["id"])) * 5.0 * camera_zoom
	var pos: Vector2 = grid_to_screen(float(sx), float(sy), maxf(0.0, float(tile["elevation"]))) + Vector2(0.0, -18.0 * camera_zoom + float_y)
	if not _draw_sprite_or_fallback("spirit", pos, 34.0 * camera_zoom):
		draw_circle(pos, 6.5 * camera_zoom, Color(0.52, 0.94, 0.98, 0.45))
		draw_circle(pos, 3.5 * camera_zoom, Color(0.95, 0.98, 1.0, 0.95))


func _draw_brush_preview(cx: int, cy: int, radius: int, hw: float, hh: float) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx: int = cx + dx
			var ny: int = cy + dy
			if not state.is_valid_coord(nx, ny):
				continue
			if Vector2(cx, cy).distance_to(Vector2(nx, ny)) <= float(radius) + 0.35:
				var t: Dictionary = state.get_tile(nx, ny)
				var sc: Vector2 = grid_to_screen(float(nx), float(ny), maxf(0.0, float(t.get("elevation", 0.0))))
				draw_polyline(PackedVector2Array([
					sc + Vector2(0.0, -hh),
					sc + Vector2(hw, 0.0),
					sc + Vector2(0.0, hh),
					sc + Vector2(-hw, 0.0),
					sc + Vector2(0.0, -hh)
				]), Color(0.38, 0.86, 0.98, 0.72), 1.8 * camera_zoom)
