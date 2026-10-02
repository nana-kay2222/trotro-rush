#!/usr/bin/env python3
"""
Trotro Rush 3D Prototype - Modular Building Texture Pipeline
Extracts clean, perspective-rectified, orthographic textures from approved 2D source artwork.
Each texture corresponds directly to a specific 3D surface:
- Side walls (long rectangular facade)
- Front/end facades (short entrance facade)
- Roof surfaces (corrugated pitch)
- Architectural details
"""

import os
from PIL import Image

def process_compound_house():
    src_path = 'assets/buildings/compound_house/compound_house_small_original.png'
    if not os.path.exists(src_path):
        print(f"Error: {src_path} not found.")
        return
        
    im = Image.open(src_path)
    print(f"Processing compound house from {src_path} (size: {im.size})...")
    
    # 1. Long Side Wall (Orthographic rectification of wall between eave and foundation plinth)
    # Four corners in source artwork:
    # Top-Left: (58, 436), Bottom-Left: (58, 606)
    # Bottom-Right: (1342, 648), Top-Right: (1342, 368)
    tl_side = (58, 436)
    bl_side = (58, 606)
    br_side = (1342, 648)
    tr_side = (1342, 368)
    quad_side = (tl_side[0], tl_side[1], bl_side[0], bl_side[1], br_side[0], br_side[1], tr_side[0], tr_side[1])
    
    # 1600x380 (aspect ratio ~ 4.21:1 for 16m x 3.8m 3D wall)
    side_wall = im.transform((1600, 380), Image.QUAD, quad_side, resample=Image.BICUBIC)
    side_path = 'assets/buildings/compound_house/house_side_wall_modular.png'
    side_wall.save(side_path)
    print(f"Saved: {side_path} ({side_wall.size})")
    
    # 2. Front Entrance Facade (Veranda + Bedroom Window Wall)
    # Four corners in source artwork:
    # Top-Left: (1485, 348), Bottom-Left: (1485, 655)
    # Bottom-Right: (1735, 635), Top-Right: (1735, 348)
    tl_front = (1485, 348)
    bl_front = (1485, 655)
    br_front = (1735, 635)
    tr_front = (1735, 348)
    quad_front = (tl_front[0], tl_front[1], bl_front[0], bl_front[1], br_front[0], br_front[1], tr_front[0], tr_front[1])
    
    # 800x580 (aspect ratio ~ 1.38:1 for 5.0m x 3.6m 3D front wall)
    front_facade = im.transform((800, 580), Image.QUAD, quad_front, resample=Image.BICUBIC)
    front_path = 'assets/buildings/compound_house/house_front_facade_modular.png'
    front_facade.save(front_path)
    print(f"Saved: {front_path} ({front_facade.size})")
    
    # 3. Triangular Gable Texture (Upper gable stucco with fascia bargeboard)
    # In source: Peak at (1630, 235), Left at (1485, 348), Right at (1735, 348)
    gable_crop = im.crop((1485, 230, 1740, 355))
    gable_path = 'assets/buildings/compound_house/house_gable_modular.png'
    gable_crop.save(gable_path)
    print(f"Saved: {gable_path} ({gable_crop.size})")


def process_mosque():
    src_path = 'assets/buildings/mosque/mosque_original.png'
    if not os.path.exists(src_path):
        print(f"Error: {src_path} not found.")
        return
        
    im = Image.open(src_path)
    print(f"Processing mosque from {src_path} (size: {im.size})...")
    
    # 1. Long Prayer Hall Side Wall (5 pointed window bays)
    # Top-Left: (70, 436), Bottom-Left: (70, 695)
    # Bottom-Right: (1720, 695), Top-Right: (1720, 330)
    tl_side = (70, 436)
    bl_side = (70, 695)
    br_side = (1720, 695)
    tr_side = (1720, 330)
    quad_side = (tl_side[0], tl_side[1], bl_side[0], bl_side[1], br_side[0], br_side[1], tr_side[0], tr_side[1])
    
    # 1600x400 (4:1 aspect ratio for 18m x 4.5m prayer hall)
    side_wall = im.transform((1600, 400), Image.QUAD, quad_side, resample=Image.BICUBIC)
    side_path = 'assets/buildings/mosque/mosque_side_wall_modular.png'
    side_wall.save(side_path)
    print(f"Saved: {side_path} ({side_wall.size})")
    
    # 2. Single Window Bay (For tower base or flexible facade modules)
    # Crop middle bay #3 (width 320, height 400)
    single_bay = side_wall.crop((640, 0, 960, 400))
    bay_path = 'assets/buildings/mosque/mosque_wall_bay_single.png'
    single_bay.save(bay_path)
    print(f"Saved: {bay_path} ({single_bay.size})")
    
    # 3. Front Entrance Portal (Grand multi-foil archway, timber doors, and fretwork balustrades)
    # Four corners in source:
    # Top-Left: (1850, 360), Bottom-Left: (1850, 695)
    # Bottom-Right: (2160, 695), Top-Right: (2160, 390)
    tl_front = (1850, 360)
    bl_front = (1850, 695)
    br_front = (2160, 695)
    tr_front = (2160, 390)
    quad_front = (tl_front[0], tl_front[1], bl_front[0], bl_front[1], br_front[0], br_front[1], tr_front[0], tr_front[1])
    
    # 800x600 (4:3 aspect ratio)
    front_portal = im.transform((800, 600), Image.QUAD, quad_front, resample=Image.BICUBIC)
    portal_path = 'assets/buildings/mosque/mosque_front_facade_modular.png'
    front_portal.save(portal_path)
    print(f"Saved: {portal_path} ({front_portal.size})")

if __name__ == '__main__':
    process_compound_house()
    process_mosque()
    print("--- Modular Texture Generation Complete ---")
