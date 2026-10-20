import bpy
import math
import os

# Répertoire de sortie des sprites 2.5D isométriques pour Godot 4
PROJECT_DIR = r"C:\Users\Chris Eric\.gemini\antigravity\scratch\genesis-divine-sim"
OUT_DIR = os.path.join(PROJECT_DIR, "assets", "sprites")
os.makedirs(OUT_DIR, exist_ok=True)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # Choix d'un moteur rapide et compatible Blender 5.2 avec transparence alpha
    available_engines = [e.identifier for e in scene.render.bl_rna.properties['engine'].enum_items]
    if 'BLENDER_EEVEE' in available_engines:
        scene.render.engine = 'BLENDER_EEVEE'
    elif 'BLENDER_EEVEE_NEXT' in available_engines:
        scene.render.engine = 'BLENDER_EEVEE_NEXT'
    else:
        scene.render.engine = 'CYCLES'
        scene.cycles.samples = 16

    scene.render.resolution_x = 128
    scene.render.resolution_y = 128
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

    # Caméra orthographique isométrique parfaitement cadrée sur la hauteur des bâtiments
    cam_data = bpy.data.cameras.new("IsoCam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 3.85
    cam_obj = bpy.data.objects.new("IsoCam", cam_data)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (4.0, -4.0, 4.35)
    cam_obj.rotation_euler = (math.radians(58.0), 0.0, math.radians(45.0))
    scene.camera = cam_obj

    # Lumière solaire chaude principale
    sun_data = bpy.data.lights.new(name="SunKey", type='SUN')
    sun_data.energy = 4.2
    sun_data.color = (1.0, 0.95, 0.86)
    sun_obj = bpy.data.objects.new(name="SunKey", object_data=sun_data)
    scene.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(42.0), math.radians(-18.0), math.radians(28.0))

    # Lumière céleste de débouchage (fill light bleutée)
    fill_data = bpy.data.lights.new(name="SkyFill", type='SUN')
    fill_data.energy = 1.6
    fill_data.color = (0.65, 0.82, 1.0)
    fill_obj = bpy.data.objects.new(name="SkyFill", object_data=fill_data)
    scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(65.0), math.radians(30.0), math.radians(-135.0))

    return scene


def make_mat(name, color, metallic=0.0, roughness=0.45, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def assign_mat(obj, mat):
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


def render_to(filename):
    path = os.path.join(OUT_DIR, filename)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"[BLENDER ASSET] Rendered: {path}")


def build_village():
    reset_scene()
    stone = make_mat("StoneBase", (0.65, 0.62, 0.58), roughness=0.8)
    walls = make_mat("WarmPlaster", (0.92, 0.86, 0.74), roughness=0.6)
    roof = make_mat("Terracotta", (0.85, 0.36, 0.22), roughness=0.5)
    gold_win = make_mat("WindowGlow", (1.0, 0.85, 0.35), emission=(1.0, 0.8, 0.3), emission_strength=3.5)

    # Socle octogonal
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=1.25, depth=0.18, location=(0, 0, 0.09))
    assign_mat(bpy.context.active_object, stone)

    # Maison principale
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.15, 0.1, 0.52))
    main_h = bpy.context.active_object
    main_h.scale = (0.65, 0.55, 0.42)
    assign_mat(main_h, walls)

    # Toit en prisme
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.82, depth=0.65, location=(-0.15, 0.1, 1.15))
    r1 = bpy.context.active_object
    r1.rotation_euler = (0, 0, math.radians(45))
    assign_mat(r1, roof)

    # Seconde chaumière
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.48, -0.35, 0.42))
    sub_h = bpy.context.active_object
    sub_h.scale = (0.42, 0.42, 0.32)
    assign_mat(sub_h, walls)

    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.58, depth=0.5, location=(0.48, -0.35, 0.92))
    r2 = bpy.context.active_object
    r2.rotation_euler = (0, 0, math.radians(45))
    assign_mat(r2, roof)

    # Lanterne sacrée
    bpy.ops.mesh.primitive_ico_sphere_add(radius=0.14, location=(-0.15, -0.45, 0.52))
    assign_mat(bpy.context.active_object, gold_win)

    render_to("village.png")


def build_city():
    reset_scene()
    marble = make_mat("Marble", (0.88, 0.87, 0.84), roughness=0.35)
    imperial_roof = make_mat("ImperialBlue", (0.20, 0.48, 0.85), metallic=0.25, roughness=0.3)
    gold = make_mat("GoldTrim", (0.98, 0.80, 0.25), metallic=0.85, roughness=0.2, emission=(0.9, 0.7, 0.2), emission_strength=1.2)

    # Rempart circulaire
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=1.35, depth=0.36, location=(0, 0, 0.18))
    assign_mat(bpy.context.active_object, marble)

    # Donjon central
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.85))
    keep = bpy.context.active_object
    keep.scale = (0.62, 0.62, 0.68)
    assign_mat(keep, marble)

    # Dôme impérial
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.52, location=(0, 0, 1.52))
    assign_mat(bpy.context.active_object, imperial_roof)

    # Flèche dorée
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.18, depth=0.55, location=(0, 0, 2.1))
    assign_mat(bpy.context.active_object, gold)

    # 4 Tours d'angle
    for tx, ty in [(-0.78, -0.78), (0.78, -0.78), (-0.78, 0.78), (0.78, 0.78)]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.26, depth=1.05, location=(tx, ty, 0.55))
        assign_mat(bpy.context.active_object, marble)
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.34, depth=0.45, location=(tx, ty, 1.28))
        assign_mat(bpy.context.active_object, imperial_roof)

    render_to("city.png")


def build_sanctuary():
    reset_scene()
    obsidian = make_mat("SacredStone", (0.92, 0.90, 0.85), roughness=0.25)
    gold = make_mat("CelestialGold", (1.0, 0.84, 0.28), metallic=0.9, roughness=0.15)
    crystal = make_mat("AetherCrystal", (0.35, 0.92, 1.0), roughness=0.1, emission=(0.35, 0.92, 1.0), emission_strength=5.0)

    # Degrés de la ziggourat sacrée
    for i, rad in enumerate([1.3, 0.98, 0.68]):
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=rad, depth=0.25, location=(0, 0, 0.12 + i * 0.25))
        assign_mat(bpy.context.active_object, obsidian if i % 2 == 0 else gold)

    # Obélisque de cristal flottant
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.38, depth=1.45, location=(0, 0, 1.55))
    ob = bpy.context.active_object
    ob.rotation_euler = (0, 0, math.radians(45))
    assign_mat(ob, crystal)

    # Anneau solaire
    bpy.ops.mesh.primitive_torus_add(major_radius=0.72, minor_radius=0.06, location=(0, 0, 1.45), rotation=(math.radians(35), math.radians(20), 0))
    assign_mat(bpy.context.active_object, gold)

    render_to("sanctuary.png")


def build_portal():
    reset_scene()
    stone = make_mat("AncientArch", (0.38, 0.34, 0.48), roughness=0.4)
    vortex = make_mat("AstralVortex", (0.75, 0.38, 1.0), emission=(0.78, 0.42, 1.0), emission_strength=6.5)
    gold = make_mat("RuneGold", (0.98, 0.82, 0.32), metallic=0.85, roughness=0.2)

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=1.25, depth=0.20, location=(0, 0, 0.1))
    assign_mat(bpy.context.active_object, stone)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.95, minor_radius=0.16, location=(0, 0, 1.15), rotation=(math.radians(90), 0, math.radians(-45)))
    assign_mat(bpy.context.active_object, stone)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.78, minor_radius=0.07, location=(0, 0, 1.15), rotation=(math.radians(90), 0, math.radians(-45)))
    assign_mat(bpy.context.active_object, gold)

    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.72, depth=0.06, location=(0, 0, 1.15), rotation=(math.radians(90), 0, math.radians(-45)))
    assign_mat(bpy.context.active_object, vortex)

    render_to("portal.png")


def build_spirit():
    reset_scene()
    core = make_mat("SeraphCore", (0.85, 0.98, 1.0), emission=(0.55, 0.95, 1.0), emission_strength=7.0)
    ring_mat = make_mat("OphanimGold", (1.0, 0.88, 0.38), metallic=0.9, roughness=0.15, emission=(1.0, 0.82, 0.28), emission_strength=2.2)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.45, location=(0, 0, 1.15))
    assign_mat(bpy.context.active_object, core)

    for rx, ry, rz in [(45, 0, 0), (-45, 35, 0), (0, 65, 45)]:
        bpy.ops.mesh.primitive_torus_add(
            major_radius=0.88,
            minor_radius=0.055,
            location=(0, 0, 1.15),
            rotation=(math.radians(rx), math.radians(ry), math.radians(rz))
        )
        assign_mat(bpy.context.active_object, ring_mat)

    render_to("spirit.png")


def build_army():
    reset_scene()
    steel = make_mat("Steel", (0.78, 0.82, 0.88), metallic=0.85, roughness=0.22)
    crimson = make_mat("WarBanner", (0.92, 0.22, 0.22), roughness=0.4, emission=(0.6, 0.1, 0.1), emission_strength=0.8)
    gold = make_mat("HiltGold", (0.98, 0.80, 0.24), metallic=0.9, roughness=0.2)

    # Bouclier héraldique incliné
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.78, depth=0.16, location=(0, 0, 0.95), rotation=(math.radians(65), 0, math.radians(-45)))
    assign_mat(bpy.context.active_object, crimson)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.78, minor_radius=0.08, location=(0, 0, 0.95), rotation=(math.radians(65), 0, math.radians(-45)))
    assign_mat(bpy.context.active_object, gold)

    # Deux lances / épées croisées
    for angle in [-32, 32]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.07, depth=2.3, location=(0, 0, 1.05), rotation=(math.radians(angle), math.radians(angle * 0.6), 0))
        assign_mat(bpy.context.active_object, steel)

    render_to("army.png")


def build_ruin():
    reset_scene()
    weathered = make_mat("WeatheredStone", (0.58, 0.56, 0.52), roughness=0.9)
    moss = make_mat("AncientMoss", (0.28, 0.52, 0.30), roughness=0.85)

    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=1.2, depth=0.16, location=(0, 0, 0.08))
    assign_mat(bpy.context.active_object, weathered)

    # Colonnes brisées
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.22, depth=1.1, location=(-0.45, 0.35, 0.6))
    assign_mat(bpy.context.active_object, weathered)

    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.22, depth=0.65, location=(0.45, 0.35, 0.38))
    assign_mat(bpy.context.active_object, weathered)

    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.20, depth=0.85, location=(0.1, -0.35, 0.25), rotation=(math.radians(78), 0, math.radians(25)))
    assign_mat(bpy.context.active_object, weathered)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.35, location=(-0.2, -0.1, 0.22))
    assign_mat(bpy.context.active_object, moss)

    render_to("ruin.png")


def build_tree_forest():
    reset_scene()
    trunk = make_mat("Bark", (0.42, 0.26, 0.15), roughness=0.85)
    foliage1 = make_mat("CanopyDark", (0.16, 0.48, 0.22), roughness=0.65)
    foliage2 = make_mat("CanopyLight", (0.26, 0.64, 0.30), roughness=0.6)

    for tx, ty, sc, mat in [(-0.35, 0.2, 1.0, foliage1), (0.38, -0.18, 0.82, foliage2), (0.05, 0.38, 0.72, foliage2)]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.14 * sc, depth=0.65 * sc, location=(tx, ty, 0.32 * sc))
        assign_mat(bpy.context.active_object, trunk)
        bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.62 * sc, depth=1.05 * sc, location=(tx, ty, 0.95 * sc))
        assign_mat(bpy.context.active_object, mat)
        bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.46 * sc, depth=0.85 * sc, location=(tx, ty, 1.42 * sc))
        assign_mat(bpy.context.active_object, mat)

    render_to("tree_forest.png")


if __name__ == "__main__":
    build_village()
    build_city()
    build_sanctuary()
    build_portal()
    build_spirit()
    build_army()
    build_ruin()
    build_tree_forest()
    print("=== TOUS LES ASSETS 3D ISOMÉTRIQUES BLENDER ONT ÉTÉ GÉNÉRÉS ===")
