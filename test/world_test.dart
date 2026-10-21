import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neon_stack/game/levels.dart';
import 'package:neon_stack/game/world.dart';

import 'bot.dart';

/// Runs the world until the block sits [offset] units from dead centre, then drops.
void dropAt(World w, double offset) {
  var prev = double.nan;
  for (var i = 0; i < 20000; i++) {
    final lead = w.offset - offset;
    if (w.mover != null && !prev.isNaN && prev.sign != lead.sign && w.dropSafe) {
      w.drop();
      return;
    }
    prev = w.mover == null ? double.nan : lead;
    w.update(1 / 600);
  }
  fail('never lined up');
}

void main() {
  test('levels 1–25, guardians included, are cleared by an imperfect autopilot', () {
    for (var level = 1; level <= 25; level++) {
      final w = autoplay(level, seed: 3);
      expect(w.cleared, isTrue, reason: 'level $level not cleared (height ${w.height}, lives ${w.lives})');
    }
  });

  test('the autopilot really is imperfect', () {
    final w = autoplay(20, seed: 3);
    expect(w.perfects, lessThan(w.height));
    final run = autoplay(18, seed: 3);
    expect(run.top.w * run.top.d, lessThan(100 * 100));
  });

  test('a sloppier player clears the early levels but hits a wall later', () {
    var early = 0, late = 0;
    for (var s = 0; s < 10; s++) {
      for (var level = 1; level <= 4; level++) {
        if (autoplay(level, seed: s, error: 0.04, slip: 0.08).cleared) early++;
      }
      for (var level = 26; level <= 29; level++) {
        if (autoplay(level, seed: s, error: 0.04, slip: 0.08).cleared) late++;
      }
    }
    expect(early, 40);
    expect(late, lessThan(20));
  });

  test('an off-centre drop slices the overhang off', () {
    final w = World(Run(), rng: Random(1));
    final before = w.top.w * w.top.d;
    dropAt(w, 20);
    expect(w.height, 1);
    final top = w.top;
    expect(top.w * top.d, closeTo(before - 20 * 100, 25));
    expect(w.pieces, isNotEmpty);
    expect(w.events, containsAll([GameEvent.place, GameEvent.slice]));
    expect(w.streak, 0);
  });

  test('a perfect drop snaps, keeps the width, and a streak grows it back', () {
    final w = World(Run(level: 9), rng: Random(1)); // narrow start: room to grow
    dropAt(w, 15);
    final narrowed = w.top.w * w.top.d;
    for (var i = 0; i < 2; i++) {
      dropAt(w, 0);
    }
    expect(w.streak, 2);
    expect(w.top.w * w.top.d, closeTo(narrowed, 0.01));
    expect(w.events, contains(GameEvent.perfect));
    w.events.clear();
    // From the third perfect on, each one widens the block (here the sliced x side on floor 5).
    dropAt(w, 0);
    dropAt(w, 0);
    expect(w.streak, 4);
    expect(w.top.w * w.top.d, greaterThan(narrowed));
    expect(w.events, contains(GameEvent.regrow));
    expect(w.top.w, lessThanOrEqualTo(w.spec.startWidth));
  });

  test('missing the tower costs a life; three misses end the level', () {
    final w = World(Run(), rng: Random(1));
    for (var i = 0; i < 3; i++) {
      dropAt(w, World.range - 1);
      expect(w.lives, 2 - i);
      expect(w.height, 0);
    }
    expect(w.over, isTrue);
    w.update(1 / 60);
    expect(w.events, contains(GameEvent.gameOver));
    expect(w.drop(), isFalse);

    w.revive();
    expect(w.over, isFalse);
    expect(w.lives, 2);
    expect(w.mover, isNotNull);
  });

  test('reaching the target clears the level, with bonuses applied once', () {
    final run = Run();
    final w = World(run, rng: Random(1));
    for (var i = 0; i < w.spec.target; i++) {
      dropAt(w, 0);
    }
    expect(w.mover, isNull);
    for (var i = 0; i < 120 && !w.cleared; i++) {
      w.update(1 / 60);
    }
    expect(w.cleared, isTrue);
    final before = run.score;
    final s = w.finish();
    expect(s.flawlessBonus, 300);
    expect(s.livesBonus, 450);
    expect(run.score, before + s.bonus);
  });

  test('a perfect drop on a gem floor grabs the gem and gives a life back', () {
    final w = World(Run(level: 2), rng: Random(1));
    expect(w.spec.has(Mod.gems), isTrue);
    dropAt(w, World.range - 1); // lose a life
    final gemFloor = w.gemFloors.first;
    while (w.floors.length < gemFloor) {
      dropAt(w, 0);
    }
    dropAt(w, 0);
    expect(w.gems, 1);
    expect(w.lives, 3);
  });

  test('perfect drops hurt the guardian; streaks hit harder', () {
    final w = World(Run(level: 5), rng: Random(1));
    final hp = w.bossHp;
    dropAt(w, 0);
    expect(w.bossHp, hp - 1);
    dropAt(w, 0);
    dropAt(w, 0);
    expect(w.bossHp, hp - 4);
    dropAt(w, 20);
    expect(w.bossHp, hp - 4);
  });

  test("dropping under the pendulum's blade shatters the block", () {
    final w = World(Run(level: 5), rng: Random(1));
    while (!w.bladeOverTower) {
      w.update(1 / 120);
    }
    expect(w.dropSafe, isFalse);
    w.drop();
    expect(w.lives, 2);
    expect(w.height, 0);
    expect(w.pieces, hasLength(2));
  });

  test('the vice squeezes a waiting block, the inverter flips it', () {
    final vice = World(Run(level: 10), rng: Random(1));
    for (var i = 0; i < 600; i++) {
      vice.update(1 / 60);
    }
    expect(vice.mover!.squeeze, lessThan(0.9));

    final inv = World(Run(level: 15), rng: Random(1));
    for (var i = 0; i < 180; i++) {
      inv.update(1 / 60);
    }
    var flips = 0;
    var dir = inv.mover!.dir;
    for (var i = 0; i < 600; i++) {
      inv.update(1 / 60);
      if (inv.events.contains(GameEvent.flipWarning)) flips++;
      inv.events.clear();
      dir = inv.mover!.dir;
    }
    expect(flips, greaterThan(0));
    expect(dir.abs(), 1);
  });

  test('wind makes the block faster one way than the other', () {
    final w = World(Run(level: 6), rng: Random(1));
    final speeds = <double>{};
    for (var i = 0; i < 240; i++) {
      w.update(1 / 60);
      speeds.add(w.moverVelocity.abs().roundToDouble());
    }
    expect(speeds.reduce(max) - speeds.reduce(min), greaterThan(40));
  });
}
