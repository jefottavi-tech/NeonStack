import 'dart:math';

import 'package:neon_stack/game/world.dart';

/// A timing autopilot with human-like imperfection: it aims for dead centre
/// but taps up to [error] seconds early or late (uniform), and now and then
/// slips by [slip] seconds. It also waits out the pendulum blade.
/// Returns the world when the level clears or is lost (or time runs out).
World autoplay(int level, {int seed = 1, double error = 0.022, double slip = 0.06, double limit = 300, bool revive = false}) {
  final rng = Random(seed * 7919 + level);
  final world = World(Run(level: level), rng: Random(seed + level));
  const dt = 1 / 120;
  var aimFor = -1;
  var aim = 0.0;
  var prev = double.nan;
  while (world.time < limit && !world.cleared) {
    if (world.over) {
      if (!revive || world.run.revived) break;
      world.run.revived = true;
      world.revive();
    }
    final m = world.mover;
    if (m != null) {
      if (m.id != aimFor) {
        aimFor = m.id;
        final e = rng.nextDouble() < 0.1 ? slip : error;
        aim = (rng.nextDouble() * 2 - 1) * e; // seconds early (+) or late (-)
        prev = double.nan;
      }
      // Tap when the block is `aim` seconds away from centre on its way in.
      final lead = world.offset + world.moverVelocity * aim;
      if (!prev.isNaN && prev.sign != lead.sign && world.dropSafe) world.drop();
      prev = lead;
    }
    world.update(dt);
    world.events.clear();
  }
  return world;
}
