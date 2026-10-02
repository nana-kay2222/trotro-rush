#!/usr/bin/env python3
"""
Trotro Rush 3D Prototype - Compound House Derived Textures Pipeline
Extracts clean, perspective-rectified, orthographic textures and architectural cards
from approved source artwork in assets/buildings/compound_house/.
"""

import os
from PIL import Image, ImageDraw

def build_textures():
    src_small = 'assets/buildings/compound_house/compound_house_small_original.png'
    src_large = 'assets/buildings/compound_house/compound_house_large_original.png'
    
    if not os.path.exists(src_small):
        print(f"Error: {src_small} not found.")
        return
        
    im_small = Image.open(src_small).convert('RGBA')
    print(f"Loaded small source artwork: {src_small}, size={im_small.size}")
    
    # ----------------------------------------------------
    # 1. compound_side_wall.png (1600x400)
    # Long roadside wall: 5 louvered windows, AC unit, electric meter, breeze holes, downspout, plinth
    # ----------------------------------------------------
    tl_side = (58, 436)
    bl_side = (58, 606)
    br_side = (1342, 648)
    tr_side = (1342, 368)
    quad_side = (tl_side[0], tl_side[1], bl_side[0], bl_side[1], br_side[0], br_side[1], tr_side[0], tr_side[1])
    side_wall = im_small.transform((1600, 400), Image.QUAD, quad_side, resample=Image.BICUBIC)
    side_path = 'assets/buildings/compound_house/compound_side_wall.png'
    side_wall.save(side_path)
    print(f"Saved: {side_path}")
    
    # ----------------------------------------------------
    # 2. compound_front_facade.png (800x600)
    # Front building surface behind attached porch card
    # Right half: ochre wall, red wainscot, bedroom window, terracotta potted plants
    # Left half: matching stucco wall & red wainscot with recessed front door
    # ----------------------------------------------------
    tl_right = (1680, 365)
    bl_right = (1680, 640)
    br_right = (1730, 636)
    tr_right = (1730, 365)
    quad_right = (tl_right[0], tl_right[1], bl_right[0], bl_right[1], br_right[0], br_right[1], tr_right[0], tr_right[1])
    right_wall = im_small.transform((380, 600), Image.QUAD, quad_right, resample=Image.BICUBIC)
    
    tl_plain = (310, 420)
    bl_plain = (310, 620)
    br_plain = (460, 625)
    tr_plain = (460, 410)
    quad_plain = (tl_plain[0], tl_plain[1], bl_plain[0], bl_plain[1], br_plain[0], br_plain[1], tr_plain[0], tr_plain[1])
    plain_wall = im_small.transform((420, 600), Image.QUAD, quad_plain, resample=Image.BICUBIC)
    
    front_facade = Image.new('RGB', (800, 600))
    front_facade.paste(plain_wall.convert('RGB'), (0, 0))
    front_facade.paste(right_wall.convert('RGB'), (420, 0))
    
    # Recessed front door
    draw_f = ImageDraw.Draw(front_facade)
    door_rect = [230, 160, 340, 535]
    draw_f.rectangle(door_rect, fill=(45, 26, 22))
    draw_f.rectangle(door_rect, outline=(75, 42, 35), width=6)
    draw_f.rectangle([242, 175, 328, 315], outline=(32, 18, 15), width=4)
    draw_f.rectangle([242, 335, 328, 515], outline=(32, 18, 15), width=4)
    draw_f.ellipse([315, 345, 325, 355], fill=(185, 145, 50))
    
    # Soft ambient shade under porch attachment
    ao = Image.new('RGBA', (800, 600), (0, 0, 0, 0))
    ao_d = ImageDraw.Draw(ao)
    ao_d.rectangle([0, 0, 420, 540], fill=(0, 0, 0, 35))
    front_facade.paste(Image.composite(Image.new('RGB', (800, 600), (0, 0, 0)), front_facade, ao.split()[3]), (0, 0))
    
    front_path = 'assets/buildings/compound_house/compound_front_facade.png'
    front_facade.save(front_path)
    print(f"Saved: {front_path}")
    
    # ----------------------------------------------------
    # 3. compound_porch_card.png (512x768, RGBA with alpha)
    # The transparent foreground architectural card:
    # Begins at the horizontal porch awning beam (y=85), removing the duplicate 2D roof slice
    # Contains: Porch awning beam & arches, columns, turned balustrade, entrance steps, blue glazed flower pot, doorway
    # Clean transparent margins on all sides!
    # ----------------------------------------------------
    tl_p = (1470, 345) # Starts right at the wooden porch awning beam
    bl_p = (1470, 672)
    br_p = (1684, 650)
    tr_p = (1684, 345)
    quad_p = (tl_p[0], tl_p[1], bl_p[0], bl_p[1], br_p[0], br_p[1], tr_p[0], tr_p[1])
    porch_rect = im_small.transform((512, 768), Image.QUAD, quad_p, resample=Image.BICUBIC)
    
    porch_card = porch_rect.copy()
    p_pix = porch_card.load()
    
    for y in range(768):
        for x in range(512):
            r, g, b, a = p_pix[x, y]
            
            # Outside right column
            if x > 465:
                p_pix[x, y] = (r, g, b, 0)
                continue
                
            # Outside left edge
            if x < 6:
                p_pix[x, y] = (r, g, b, 0)
                continue
                
            # Top edge above wooden beam
            if y < 6:
                p_pix[x, y] = (r, g, b, 0)
                continue
                
            # Anti-aliasing on outer boundary
            edge_d = min(x - 6, 465 - x, y - 6)
            if edge_d < 3:
                alpha = int(edge_d * 80)
                p_pix[x, y] = (r, g, b, max(0, min(255, alpha)))
            else:
                p_pix[x, y] = (r, g, b, 255)
                
    porch_card_path = 'assets/buildings/compound_house/compound_porch_card.png'
    porch_card.save(porch_card_path)
    print(f"Saved: {porch_card_path}")
    
    # ----------------------------------------------------
    # 4. compound_porch_side.png (256x768, RGBA with alpha)
    # The shallow side return connecting front card to main wall
    # Contains: downspout, side arch, side balustrade, foundation
    # ----------------------------------------------------
    tl_s = (1340, 345)
    bl_s = (1340, 672)
    br_s = (1472, 672)
    tr_s = (1472, 345)
    quad_s = (tl_s[0], tl_s[1], bl_s[0], bl_s[1], br_s[0], br_s[1], tr_s[0], tr_s[1])
    side_rect = im_small.transform((256, 768), Image.QUAD, quad_s, resample=Image.BICUBIC)
    
    side_card = side_rect.copy()
    s_pix = side_card.load()
    for y in range(768):
        for x in range(256):
            r, g, b, a = s_pix[x, y]
            if x < 4 or x > 252 or y < 6:
                s_pix[x, y] = (r, g, b, 0)
            else:
                s_pix[x, y] = (r, g, b, 255)
                
    side_return_path = 'assets/buildings/compound_house/compound_porch_side.png'
    side_card.save(side_return_path)
    print(f"Saved: {side_return_path}")
    
    # ----------------------------------------------------
    # 5. compound_roof.png (512x512)
    # ----------------------------------------------------
    roof_src = 'assets/buildings/compound_house/roof_red_corrugated.png'
    if os.path.exists(roof_src):
        roof_im = Image.open(roof_src).convert('RGB')
        roof_path = 'assets/buildings/compound_house/compound_roof.png'
        roof_im.save(roof_path)
        print(f"Saved: {roof_path}")
        
    # ----------------------------------------------------
    # 6. compound_boundary_wall.png (1024x256)
    # ----------------------------------------------------
    if os.path.exists(src_large):
        im_large = Image.open(src_large).convert('RGBA')
        tl_wall = (185, 470)
        bl_wall = (185, 625)
        br_wall = (1460, 620)
        tr_wall = (1460, 465)
        quad_wall = (tl_wall[0], tl_wall[1], bl_wall[0], bl_wall[1], br_wall[0], br_wall[1], tr_wall[0], tr_wall[1])
        wall_tex = im_large.transform((1024, 256), Image.QUAD, quad_wall, resample=Image.BICUBIC)
        wall_path = 'assets/buildings/compound_house/compound_boundary_wall.png'
        wall_tex.save(wall_path)
        print(f"Saved: {wall_path}")

if __name__ == '__main__':
    build_textures()
    print("--- Derived Textures Pipeline Complete ---")
