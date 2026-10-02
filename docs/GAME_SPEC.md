# Trotro Rush — Detailed Game Specification & Development Guardrails

> Authoritative spec supplied by the project owner (2026-09-30). This overrides
> docs/AUDIT_AND_PLAN.md wherever they disagree. Do not invent mechanics that
> are not listed here — ask first (see §22).

## 1. What the game is
Trotro Rush is a fast-paced Ghanaian/Accra driving game built around the experience of driving a public trotro through busy urban roads while trying to collect passengers and maximize fare earnings.

The game is primarily about:
- driving forward through a 3-lane road
- weaving around traffic and hazards
- reacting quickly to passengers calling for a trotro
- crossing lanes to reach roadside pickup bays
- collecting fares
- managing risk while driving aggressively
- avoiding police fines
- achieving the highest possible fare score

The game should feel distinctly Ghanaian, not like a generic endless driving game with Ghanaian buildings pasted onto it.

## 2. Core gameplay loop
Drive → Spot passenger → React → Cross lanes → Enter pickup bay → Pick up passenger → Earn fare → Continue driving

Passengers appear along the roadside and signal that they want a ride. The player has a short reaction window. The player must:
1. Notice the passenger.
2. Determine which side of the road the passenger/pickup bay is on.
3. Move across the traffic lanes if necessary.
4. Enter the designated roadside pickup pocket.
5. Stop inside the pickup area.
6. Pick up the passenger.
7. Return to the road and continue driving.

The passenger should not be picked up by simply stopping in the middle of an active traffic lane. Missing the passenger is completely acceptable and simply means the fare opportunity is lost.

## 3. Road
- 3 active driving lanes
- roadside shoulders/edges
- designated passenger pickup pockets/bays on either side

Pickup bays are not a fourth traffic lane. Normal traffic continues through the three active lanes while the player's trotro enters a pickup pocket. The world should communicate depth and forward movement using the 3D environment and camera perspective.

## 4. Player vehicle
The player drives a trotro. The existing approved player trotro artwork is important and should be preserved and should not be redesigned casually. It should remain visually recognizable as the approved Trotro Rush trotro.

**Do NOT add a conventional brake mechanic unless explicitly requested.** Do not invent: brake buttons, handbrake, reverse, drifting.

## 5. Player controls
Keep the control scheme simple. The player primarily controls:
- **Left/right movement** — move between lanes and maneuver into pickup bays.
- **Forward movement/speed** — the trotro continuously drives forward as part of the core gameplay.

Do not independently add: brake button, reverse, handbrake, drifting, manual transmission, fuel, gears, steering wheel UI, complicated vehicle simulation. The goal is arcade-style responsive driving, not a driving simulator.

## 6. Passenger pickup system
The defining gameplay mechanic. Passengers appear beside the road and signal for the player. Example callouts: "Trotro! Trotro!", "Driver, Circle!", "Kaneshie!", "Madina!", "Boss, stop!", "Please, Circle!", "Driver, wait!"

The passenger has a limited pickup window. A successful pickup requires the player to reach the appropriate pickup bay before the opportunity expires.

- **Successful pickup** (enters the correct bay during the active window): passenger boards, fare is awarded, passenger state → picked up, player continues driving.
- **Missed pickup** (passes the passenger or timer expires): passenger is missed, no fare, gameplay continues normally.

Keep it a simple state transition; no complicated despawning systems.

## 7. Pickup bays
Roadside pockets where the trotro pulls out of active traffic. The player must maneuver into them. Bays do not block the traffic lanes. Pickups occur on both sides of the road. **Do not mechanically alternate left/right** — placement should feel natural and varied.

## 8. EMPTY / FULL
Simple load state: EMPTY → FULL. No individual passenger simulation.
- EMPTY: normal handling.
- FULL: slightly heavier — wider/slower turning response, slower lane changes, more vulnerable to damage.
Implement as a simple gameplay state, not physics.

## 9. Damage
From collisions, potholes, dangerous driving interactions. Simple and readable. **Damage is more severe while FULL** — reuse the damage calculation with a multiplier. No deformation or mechanical simulation.

## 10. Potholes
Appear in lanes, require maneuvering around, cause damage when hit, greater consequences when FULL, visually obvious enough to react to.

## 11. Traffic
Uses the three active lanes. Types: taxis, sedans, SUVs, pickups, vans, other trotros, motorbikes. Busy and varied without sophisticated AI. Needs only: lane assignment, forward movement, speed variation, reasonable spacing, spawning/despawning.

## 12. Stalled vehicles
Occasionally a vehicle stalls, blocking one lane as a temporary hazard. Simple logic: normal traffic avoids spawning into a blocked lane. No rerouting/merging AI.

## 13. Rival trotro
Rare event, not a permanent competitor. Occasionally targets the same passenger: identify target passenger → move rival toward the pickup area → compare who reaches it → award the fare accordingly. No sophisticated pathfinding.

## 14. Skill boost
A successful last-second pickup can trigger a brief, clearly communicated speed boost. Not a power-up system.

## 15. Recklessness / police
Recklessness meter increases from sustained speeding, near misses, reckless driving. When full, a police motorbike can pull the player over → fine deducted directly from score → player continues driving. Lightweight. No chases, wanted levels, weapons, complex police AI or arrests.

## 16. Scoring
**Final score = Fares earned − Police fines.** No other score systems.

## 17. Visual direction
Stylized lightweight 3D world with 2D artwork integrated; production engine Godot.
- 3D (simple/low-poly): road, roadside terrain, buildings, walls, major structures, architectural silhouettes.
- 2D (billboards/cards): player trotro, traffic vehicles, passengers, vegetation where appropriate, architectural details, signs, small props.
Do not replace the rendering strategy without explicit approval.

## 18. Buildings
Simple 3D geometry + correctly mapped 2D artwork. **Do NOT wrap an entire perspective building PNG around a box.** Instead: simple 3D wall/body, simple 3D roof, appropriate side-wall texture, appropriate front/facade texture, compound walls where appropriate, shallow 2D cards for porches, doors, windows, balustrades and small details. Approved building artwork is source artwork; do not redesign it unnecessarily.

## 19. Environment
Communicate Accra/Ghana through: compound houses, shops, commercial blocks, churches, mosques, fuel stations, pharmacies, provision shops, mechanic shops, chop bars, roadside stalls, market structures, compound walls, utility poles, tropical vegetation, palms, roadside grass, dusty/urban roadside details. Varied, not repeated generic assets.

## 20. Ghanaian identity
Core requirement: architecture, businesses, vegetation, road details, roadside behavior, passenger callouts, trotro visual culture, traffic mix, environmental details. Not a generic American/European endless runner with Ghanaian textures.

## 21. Already decided
Godot is the engine · lightweight 3D world · player drives a trotro · 3 active lanes · passenger pickup is the defining mechanic · pickup bays separate from lanes · pickups on both sides · EMPTY/FULL states · FULL affects handling and damage · potholes are hazards · stalled vehicles are hazards · rival trotros are rare events · last-second pickups can give a short boost · recklessness can lead to police fines · final score = fares − fines · lightweight and mobile-friendly.

## 22. Development rule
**Do not invent new gameplay mechanics.** Do not independently add: braking, reverse, fuel, drifting, nitrous systems, weapons, missions, shops, upgrades, vehicle customization, health bars, complicated physics, complicated AI, extra currencies, new scoring systems. If a new mechanic seems necessary, stop and ask before implementing it.

## 23. Production priority
1. Core gameplay working
2. Passenger pickup feeling good
3. Responsive driving
4. Strong Ghanaian identity
5. Clear visual readability
6. Performance
7. Polish
8. Extra features last

Do not rewrite or replace existing working systems just to make the code more elaborate. Inspect the existing project first and make the smallest appropriate change.
