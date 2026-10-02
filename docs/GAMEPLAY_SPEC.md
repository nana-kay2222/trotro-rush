# TROTRO RUSH — AUTHORITATIVE GAMEPLAY SPECIFICATION

> Supplied by the project owner (2026-09-30). **Read this before modifying gameplay
> systems.** It describes intended behavior, not suggestions. It takes precedence
> over GAME_SPEC.md and AUDIT_AND_PLAN.md on gameplay logic.

## 1. Core game concept
Arcade-style Ghanaian driving game. The trotro drives continuously forward on a 3-lane road. **The player does not manually control acceleration or braking**; the game moves the trotro forward automatically. The player's main driving responsibility is lateral positioning: move left, move right, change lanes, avoid traffic, avoid potholes, enter passenger pickup bays, react quickly to roadside passengers. Tension comes from managing lateral movement while the vehicle is continuously moving forward.

## 2. Automatic forward driving
Always moving forward during normal gameplay. No accelerator button, no throttle to hold. The game controls forward speed automatically. There is a base driving speed that changes automatically based on events:
- normal driving → normal automatic speed
- speeding state → higher automatic speed
- successful skill pickup → temporary boost
- police interaction → temporary interruption
- other explicitly defined gameplay effects → modify speed automatically

**Do not add:** accelerator button, brake button, manual braking, reverse, manual gear control.

## 3. Player control
Primary direct input is horizontal movement (left/right across the road) to change lanes, avoid hazards, overtake traffic, position beside passengers and enter pickup bays. Skill is about timing and positioning, not engine speed.

## 4. Speeding
Automatic, not manually activated. The game places the player into a speeding state via its automatic driving-speed logic. No "speed" button. While speeding: faster movement, less reaction time, hazards more dangerous, recklessness can increase. The player can still steer while speeding.

## 5. Recklessness meter
Increases from sustained speeding, near misses, dangerous proximity to traffic, other defined reckless events. Should not constantly punish normal driving. When full: police system triggers → police motorbike approaches/intercepts → player stopped temporarily → fine deducted from score → player resumes automatic forward driving. Consequence system, not combat/chase.

## 6. Passengers — core mechanic
Passengers appear at the roadside and indicate they want the player's trotro. Limited window. The player reacts while moving automatically and steers toward the passenger's pickup bay.

## 7. How pickup works — proximity-based
**No pickup button.** The game continuously checks the player's position relative to the passenger's pickup area.

```text
Passenger appears → begins hailing → pickup window active → player sees/hears
→ steers toward pickup bay → enters pickup area → sufficiently close to passenger/pickup target
→ pickup automatically triggers → passenger boards → fare awarded → player continues driving
```

## 8. Pickup bay behavior
The passenger does not stand in an active lane. Each opportunity has a designated roadside pocket/bay. The player steers from the lanes into it. It is a safe stopping area beside the lanes; normal traffic continues through the lanes. **The bay is not a fourth driving lane.**

```text
┌───────┬───────┬───────┐
│ Lane 1│ Lane 2│ Lane 3│
└───────┴───────┴───────┘
                 \
              ┌─────────┐
              │ PICKUP  │
              │   BAY   │
              └─────────┘
                  ↑ passenger
```

## 9. Pickup window
Short time to reach the passenger: "I see the passenger — can I get across the road and into the bay before I pass them?" The opportunity ends when the player passes the pickup location, the timer expires, or another valid condition is no longer met. A miss costs only the fare; the game continues immediately. Never stop the game for a miss.

## 10. Automatic pickup conditions
```text
passenger.is_available
  AND pickup_window.is_active
  AND player_is_inside_pickup_bay
  AND distance(player, passenger_target) <= pickup_radius
  AND player_is_appropriately_positioned
→ pickup_success()
```
The radius is tuned during testing.

## 11. Fare
Successful pickup → fare added to score. Missed → zero. No passenger economy.

## 12. Ghanaian passenger behavior
Visual hailing and/or short callouts: "Trotro! Trotro!", "Driver, Circle!", "Kaneshie!", "Madina!", "Boss, stop!", "Please, Circle!", "Driver, wait!" (destination/callout varies).

## 13. EMPTY / FULL
Binary state. A successful pickup changes EMPTY → FULL. It can later return to EMPTY "according to the game's defined passenger/drop-off logic". No individual seat simulation.

## 14. FULL handling
Slightly slower lateral response, slightly wider/heavier turning, harder to avoid hazards, more severe hazard damage. A small arcade modifier: "I'm carrying passengers now, so I need to drive more carefully."

## 15. Potholes
Static hazards in lanes, avoided purely by left/right movement. Hit → damage; hit while FULL → increased damage.

## 16. Traffic
Moves automatically in the three lanes, with varied speeds, types, spawn positions and lanes. It should force quick decisions: stay, change lane, overtake, or head for a bay. No advanced autonomous driving.

## 17. Stalled vehicles
Temporarily block a lane. The player recognizes the blocked lane and moves around it. No lane-changing AI for traffic.

## 18. Rival trotro
Rare event tied to a passenger opportunity. Rival targets the same passenger; both approach; when the opportunity closes, whichever reached the pickup target gets the fare. Simple scripted/converging movement; not a permanent race.

## 19. Last-second pickup boost
```text
pickup_window_remaining < skill_threshold AND pickup_success → temporary_speed_boost
```
Automatic; no boost button.

## 20. Police
```text
dangerous driving → recklessness increases → threshold → police intervention → fine → score decreases → driving resumes
```
No fighting, chasing or complex police AI.

## 21. Score
```text
SCORE = TOTAL FARES - TOTAL POLICE FINES
```

## 22. Camera / world
Forward-driving camera; road extends to a horizon/vanishing point; player trotro is the primary visual focus; the environment moves past to communicate speed; lightweight 3D world.

## 23. Vehicle art
Approved player trotro artwork preserved. Vehicles use 2D billboard/sprite artwork in the 3D world (traffic and rivals too).

## 24. Building art
3D wall + side-wall texture; 3D front + front-facade texture; 3D roof + roof texture; porch as a shallow 2D card. Never wrap a whole perspective building image around a box.

## 25. Vegetation
Mainly 2D billboard/card artwork (tropical trees, palms, plantain, bushes, grass, weeds, clusters) at varied depths and scales.

## 26. What the player is doing
Drive → watch the road → watch for passengers → move around traffic → avoid hazards → get into the pickup bay → automatically collect passenger → earn fare → manage risk → repeat. Not a traditional racing game; be a good but aggressive trotro driver, balancing speed vs safety, fares vs traffic, risk vs fines, fast pickup vs careful positioning.

## Owner decisions (2026-09-30), answering questions the spec left open
- **FULL → EMPTY:** passengers get off at bus bays, like in real life. When the trotro is FULL and enters a bus bay, it drops off and becomes EMPTY.
- **Run end:** the run ends mainly on **damage**: too much damage and you're done, like Subway Surfers. A run also ends if the balance goes **negative from fines**.
- **Damage:** damage visibly damages the trotro and reduces a **car health meter**. When health runs out, the run ends. This is an explicit owner change to GAME_SPEC.md §22 "no health bars".
- **Speeding (automatic):** speed slowly creeps up the longer the player drives without trouble. Above a set speed the game counts it as "speeding". A crash or a police stop drops speed back to normal.

## 27. Most important development rule
Before changing or adding gameplay code, understand the existing implementation and compare it against this spec. Do not invent mechanics. If the implementation differs, classify it as (1) intentional existing mechanic, (2) unfinished, (3) bug, or (4) accidentally introduced — do not automatically replace it. **When something is ambiguous, ask before changing intended gameplay behavior.**
