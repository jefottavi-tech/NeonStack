import 'package:flutter_test/flutter_test.dart';
import 'package:neon_stack/game/levels.dart';

void main() {
  test('a guardian every fifth level, cycling through all five', () {
    for (var n = 1; n <= 50; n++) {
      expect(LevelSpec.forLevel(n).isBoss, n % 5 == 0, reason: 'level $n');
    }
    expect({for (var n = 5; n <= 25; n += 5) LevelSpec.forLevel(n).boss}, BossKind.values.toSet());
  });

  test('guardians come back stronger', () {
    for (var n = 10; n <= 50; n += 5) {
      final a = LevelSpec.forLevel(n - 5), b = LevelSpec.forLevel(n);
      expect(b.bossHp, greaterThan(a.bossHp), reason: 'level $n');
      expect(b.speed, greaterThanOrEqualTo(a.speed), reason: 'level $n');
    }
  });

  test('every regular level is different from all others in the first 50', () {
    final names = <String>{};
    final layouts = <String>{};
    LevelSpec? prev;
    for (var n = 1; n <= 50; n++) {
      final s = LevelSpec.forLevel(n);
      if (s.isBoss) continue;
      expect(names.add(s.name), isTrue, reason: 'level $n reuses the name ${s.name}');
      final layout = '${s.mods.map((m) => m.name).toList()..sort()} ${s.path} ${s.target} ${s.speed}';
      expect(layouts.add(layout), isTrue, reason: 'level $n');
      if (prev != null && n > 2) {
        expect(s.mods, isNot(equals(prev.mods)), reason: 'level $n has the same twists as level ${prev.number}');
        expect(s.hue, isNot(prev.hue), reason: 'level $n');
      }
      prev = s;
    }
  });

  test('every twist shows up early, alone first, then combined', () {
    final seen = <Mod>{};
    for (var n = 2; n <= 9; n++) {
      final s = LevelSpec.forLevel(n);
      if (s.isBoss) continue;
      expect(s.mods, hasLength(1), reason: 'level $n');
      seen.addAll(s.mods);
    }
    expect(seen, Mod.values.toSet());
    expect({for (var n = 11; n <= 30; n++) LevelSpec.forLevel(n).path}, Track.values.toSet());
  });

  test('difficulty never goes down', () {
    LevelSpec? prev;
    for (var n = 1; n <= 60; n++) {
      final b = LevelSpec.forLevel(n);
      if (b.isBoss) continue;
      if (prev != null) {
        final a = prev;
        expect(b.speed, greaterThanOrEqualTo(a.speed), reason: 'level $n');
        expect(b.target, greaterThanOrEqualTo(a.target), reason: 'level $n');
        expect(b.tolerance, lessThanOrEqualTo(a.tolerance), reason: 'level $n');
        expect(b.mods.length, greaterThanOrEqualTo(a.mods.length), reason: 'level $n');
        // Strictly harder every level until the speed and height caps (around level 38).
        expect(b.difficulty, n <= 37 ? greaterThan(a.difficulty) : greaterThanOrEqualTo(a.difficulty), reason: 'level $n');
      }
      prev = b;
    }
    expect(LevelSpec.forLevel(1).target, 15);
    expect(LevelSpec.forLevel(39).target, 40);
  });

  test('checkpoints are the level after each boss', () {
    expect([1, 4, 5, 6, 10, 11, 14].map(LevelSpec.checkpointFor), [1, 1, 1, 6, 6, 11, 11]);
  });
}
