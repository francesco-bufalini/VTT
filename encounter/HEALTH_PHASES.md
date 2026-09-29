# Kaos health and finale

- Giant starts with 202 HP. Each explicit GM advance heals up to 10 HP before
  deciding movement. Actual healing is subtracted from damage since the last advance.
  With a threshold of 100, 100 damage then 10 healing is not a slow; 110 is.
- Reaching step zero starts the automatic climb and ends the approach, not combat.
  Kaos is centred in front of Klothis (same X and facial height), facing her.
- Zero giant HP petrifies him immediately at his current location, including before
  reaching the sphere. No further regeneration or approach movement is possible.
- The head breaks into animated stone fragments. The shoulder grid's central gap
  gains floor collision and visible cells. A Large Kaos token spawns there with 200 HP.
  Excess damage from the giant's killing blow does not transfer to this token.
- The existing Kaos damage selector targets the current form. Breaking all three
  seals, or reducing the Large form to zero HP, ends the encounter and blocks gameplay
  input/physics while keeping the result, camera and save/load accessible.
- The selector names the current form explicitly. Applying damage clears the amount,
  so a second click cannot accidentally spend the same 202 damage on the new token.
- Save format 2 includes HP, petrification, end reason and the Large token's position,
  orientation and flying condition. Format 1 saves remain readable; their old
  'finished at arrival' flag no longer ends the battle.

Inspector settings: EncounterProgressController > config > giant_max_hp,
regeneration_per_round, avatar_max_hp, and existing slow_damage_threshold.

Focused test: encounter/tests/health_phase_test.gd. Covers healing/slow boundaries,
early and on-sphere petrification, support, no duplicate spawn on load, both endings,
reset and vertical alignment; exports three scene screenshots.

Visual changes: hero_costume.gd removes Klothis's staff and spear and gives Kaos's
belt/sash a smooth torso-only fit. kaos_climb.gd removes the lateral offset.
New petrification.gd reuses the sphere's stone textures and Kaos's original visual.
