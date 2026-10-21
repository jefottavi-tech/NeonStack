# Neon Stack

One-tap neon tower stacking by Kallistesoft. Play it at https://stack.kallistesoft.ca.

- A block slides over the tower; tap (or Space) to drop it. Whatever hangs over
  is sliced off and falls; the next block is what's left. A drop within a few
  units of centre is a PERFECT: it snaps, chimes one note higher per perfect in a
  row, and from the third perfect in a row each one widens the block again.
- Each level has a target height (15 floors at level 1, rising to 40) shown as a
  progress bar and a gold finish line. 3 lives per level: a block that misses the
  tower entirely costs one.
- Every level is built from its number: speed and target rise, the perfect window
  shrinks, and twists stack up (one at a time on levels 2–9, two from level 11,
  three from 21, four from 41): Gems (perfect drop there = +250 and a life back),
  Rush (block accelerates), Pulse (block width breathes), Wind, Drift (moving base),
  Fog, Narrow start; plus Diagonal and Straight tracks. Each level has its own colour.
- Every 5th level is a guardian with an HP bar that only perfect drops damage
  (2 damage on a streak): The Pendulum (a blade sweeps over the tower: don't drop
  under it), The Vice (a waiting block shrinks), The Inverter (the block flips
  direction on a flash), Tempest (gusts change direction), The Architect (blade +
  flips). They cycle with more HP and faster hazards.
- Game over sends you back to the level after the last guardian beaten; one
  rewarded revive per run (2 lives, same tower).
- Between levels, a break screen with an `AdSlot` (300×250) placeholder and
  `AdService.showInterstitial()` on Continue. Both are no-ops until an ad network
  is wired in (`lib/services/ad_service.dart`, `lib/ui/ad_slot.dart`).

## Code

- `lib/game/levels.dart`: level specs built from the level number.
- `lib/game/world.dart`: the whole simulation (pure Dart, tested).
- `lib/ui/`: screens and the isometric canvas renderer. No image assets: everything is drawn.
- `tools/make_sfx.py`: synthesizes the sound effects into `assets/sfx`.
- `test/bot.dart`: a timing autopilot with human-like error, used to prove levels 1–25 are clearable.

## Run

```
flutter test
flutter run -d chrome
```

Every push to `main` builds and deploys the web version to GitHub Pages
(`.github/workflows/web.yml`).
