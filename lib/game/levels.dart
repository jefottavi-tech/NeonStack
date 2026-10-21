import 'dart:math';

/// Twists a regular level can add on top of plain stacking.
enum Mod {
  /// Bonus gems float beside some floors; a perfect drop there grabs one.
  gems,

  /// The block speeds up the longer you wait.
  accelerate,

  /// The block breathes: its width pulses while it slides.
  pulse,

  /// Wind speeds the block up one way and slows it the other.
  wind,

  /// The whole tower sits on a base that glides back and forth.
  sway,

  /// Fog hides the tower; only a faint outline of the top floor shows.
  fog,

  /// The tower starts narrow.
  narrow,
}

/// How the block travels over the tower.
enum Track {
  /// Along x, then z, then x... (classic).
  alternate,

  /// Always along the same axis.
  single,

  /// Along both axes at once, so a miss is sliced on two sides.
  diagonal,
}

enum BossKind { pendulum, vice, inverter, tempest, architect }

const modNames = {
  Mod.gems: 'Gems',
  Mod.accelerate: 'Rush',
  Mod.pulse: 'Pulse',
  Mod.wind: 'Wind',
  Mod.sway: 'Drift',
  Mod.fog: 'Fog',
  Mod.narrow: 'Narrow',
};

const bossNames = {
  BossKind.pendulum: 'The Pendulum',
  BossKind.vice: 'The Vice',
  BossKind.inverter: 'The Inverter',
  BossKind.tempest: 'Tempest',
  BossKind.architect: 'The Architect',
};

/// One-line rule shown when a boss appears.
const bossHints = {
  BossKind.pendulum: "Don't drop while the blade crosses",
  BossKind.vice: 'Your block shrinks while it waits',
  BossKind.inverter: 'The block flips direction on the flash',
  BossKind.tempest: 'Gusts change direction',
  BossKind.architect: 'Blade and flips together',
};

const _themes = ['Cyan', 'Magenta', 'Lime', 'Amber', 'Violet', 'Coral', 'Aqua', 'Solar', 'Rose', 'Ice', 'Ultra', 'Ember'];
const _nouns = ['Spire', 'Tower', 'Pillar', 'Beacon', 'Obelisk', 'Needle', 'Column'];

/// Everything that makes one level what it is. Built from the level number
/// alone, so a level plays the same every time.
class LevelSpec {
  const LevelSpec({
    required this.number,
    required this.mods,
    required this.path,
    required this.target,
    required this.speed,
    required this.tolerance,
    required this.startWidth,
    required this.boss,
    required this.hue,
  });

  final int number;
  final Set<Mod> mods;
  final Track path;

  /// Floors to stack to clear the level (0 on boss levels: beat the boss).
  final int target;

  /// Block speed, field units per second.
  final double speed;

  /// A drop within this many units of dead centre counts as perfect.
  final double tolerance;
  final double startWidth;
  final BossKind? boss;

  /// Theme hue, in degrees.
  final double hue;

  bool get isBoss => boss != null;

  /// Boss tier: 1 for level 5, 2 for level 10...
  int get tier => (number + 4) ~/ 5;

  bool has(Mod m) => mods.contains(m);

  int get bossHp => 8 + 3 * (tier - 1);

  String get name {
    if (isBoss) return bossNames[boss]!;
    final regular = number - number ~/ 5 - 1;
    return '${_themes[(number * 5) % _themes.length]} ${_nouns[regular % _nouns.length]}';
  }

  /// Short tags for the level intro and the break screen.
  List<String> get tags => [
        if (path == Track.diagonal) 'Diagonal',
        if (path == Track.single) 'Straight',
        for (final m in Mod.values)
          if (mods.contains(m)) modNames[m]!,
      ];

  /// A single number that rises with every regular level (for tests and tuning).
  double get difficulty => speed / 10 + mods.length * 3 + target / 4 - tolerance;

  /// Level a game over sends you back to: the one after the last boss beaten.
  static int checkpointFor(int level) => ((level - 1) ~/ 5) * 5 + 1;

  /// Mods unlocked in this order, one new twist per early level.
  static const _unlock = [Mod.gems, Mod.accelerate, Mod.pulse, Mod.wind, Mod.sway, Mod.fog, Mod.narrow];

  /// How many twists a regular level stacks.
  static int modCount(int n) => n == 1 ? 0 : (n < 11 ? 1 : (n < 21 ? 2 : (n < 41 ? 3 : 4)));

  factory LevelSpec.forLevel(int n) {
    final d = (n - 1).toDouble();
    final isBoss = n % 5 == 0;
    final boss = isBoss ? BossKind.values[(n ~/ 5 - 1) % BossKind.values.length] : null;
    // Count regular levels only, so bosses don't skip anything.
    final regular = n - n ~/ 5 - 1;
    final mods = isBoss ? <Mod>{} : _modsFor(n, regular);
    final path = isBoss || regular < 9
        ? Track.alternate
        : (regular % 4 == 1 ? Track.diagonal : (regular % 4 == 3 ? Track.single : Track.alternate));
    return LevelSpec(
      number: n,
      mods: mods,
      path: path,
      target: isBoss ? 0 : min(15 + (d * 0.9).round(), 40),
      speed: min(115 + d * 4.2, 270),
      tolerance: max(6 - d * 0.08, 3.8),
      startWidth: mods.contains(Mod.narrow) ? 78 : 100,
      boss: boss,
      hue: (190 + n * 67) % 360.0,
    );
  }

  static Set<Mod> _modsFor(int n, int regular) {
    final k = modCount(n);
    if (k == 0) return {};
    // Levels 2-9 introduce one twist each, in order.
    if (n < 11) return {_unlock[(regular - 1) % _unlock.length]};
    // Later: walk the combinations of k twists with a stride, so neighbours differ.
    final combos = _combinations(k);
    final stride = k == 2 ? 8 : (k == 3 ? 13 : 11); // coprime with 21, 35, 35
    final start = switch (k) { 2 => 11, 3 => 21, _ => 41 };
    final i = n - start - (n ~/ 5 - start ~/ 5); // index among regular levels of this band
    return combos[(i * stride) % combos.length];
  }

  static List<Set<Mod>> _combinations(int k) {
    final out = <Set<Mod>>[];
    void go(int from, List<Mod> acc) {
      if (acc.length == k) {
        out.add(acc.toSet());
        return;
      }
      for (var i = from; i < Mod.values.length; i++) {
        go(i + 1, [...acc, Mod.values[i]]);
      }
    }

    go(0, []);
    return out;
  }
}
