# Image Asset Audit & Generation Plan (2026-09-30)

Usage was checked against every `.tscn`/`.gd` reference, plus the traffic code, which builds its paths at runtime (`res://assets/vehicles/<type>/<type>_<view>.png`), plus every tool script that reads or writes images.

## Used by the game: keep (34)
| Group | Files | Notes |
|---|---|---|
| Traffic sprites | 18 (taxi, sedan, suv, pickup, van, rival_trotro × rear / left_rear_3q / right_rear_3q) | Trimmed, haze removed, 640 px, taxi and rival left/right fixed |
| Player trotro | `player_trotro_rear.png`, `shadow_blob.png` | Approved art, haze removed |
| Compound house | boundary_wall, front_facade, porch_card, porch_side, roof, side_wall | |
| Mosque | front_facade_modular, minaret, side_wall_modular, wall_bay_single, roof_green_corrugated | |
| Environment | road_3lane, curb_concrete, laterite_earth | road_3lane: **left edge line fixed from yellow to white** |

## Unused, kept on purpose (16)
- **Source artwork for the texture scripts:** `compound_house_large_original`, `compound_house_small_original`, `mosque_original`. Their rectified outputs come from these.
- **Player trotro 3/4 views** (`player_trotro_left_rear_3q`, `_right_rear_3q`): approved art, planned for steering lean.
- **Outputs of the older texture scripts (superseded, regenerable):** compound_perimeter_wall, house_front_facade_modular, house_gable_modular, house_roof, house_side_wall_modular, house_veranda, house_wall_bay, roof_red_corrugated, mosque_dome, mosque_porch, mosque_roof, mosque_wall_bay. Likely candidates for the building-kit phase, so decide then.

## Removed from the project (17): moved, not destroyed
One-off test crops that no scene, script or tool references. They're in `Documents\trotro-rush-backups\archived-test-crops\` with their `.import` files:
- front_crop_test, front_full_test
- large_veranda_test
- porch_card_raw, porch_front_test, porch_inspect, porch_side_test
- rectified_front_lower_test, rectified_side_wall_test, rectified_small_front_test
- test_facade_crop, test_facade_natural, test_porch_crop, test_side_return, test_wall_clean, test_wall_coping
- mosque_entrance_crop_test

## Missing assets the spec needs (planned in tools/imagegen/jobs.json)
| Pri | Asset | Why | Gen calls |
|---|---|---|---|
| 1 | Passengers hailing (3 variants, one sheet) | Phase 2 core mechanic | 1 |
| 1 | Pothole decal | Phase 3 hazard | 1 |
| 2 | Palm, plantain, neem billboards (sheet) | The current 3D palms are visibly crude | 1 |
| 2 | Passengers set B (headload, elder, office) | Variety | 1 |
| 2 | Okada motorbike: rear + left 3/4; right view mirrored locally | Traffic type listed in spec §11 | 2 |
| 3 | Police motorbike: rear + left 3/4; right view mirrored locally | Phase 4 | 2 |
| 3 | Bus stop sign | Bay readability | 1 |
| 4 | Roadside props sheet (kiosk, polytank, orange stall) | Phase 6 identity | 1 |
| 4 | Low vegetation sheet (grass, bush, weeds) | Phase 6 verges | 1 |

That's 11 generation calls in total, with an estimated ceiling of **$0.35**. The hard budget is $3.00.

## Deliberately not generated
- **Extra in-between angle views for the traffic cars** (for example 15° views). The current angle problem comes from how the code picks a view: it ignores distance. That's fixable in code for free. New angle images would take about 12 calls and risk not matching the approved art. Revisit only if the code fix isn't enough.
- **Stalled vehicles:** reuse the traffic sprites with hazard lights.
- **The other 19 buildings:** approved source art already exists in the web reference folder.
- **Road texture:** fixed locally, no generation needed.
