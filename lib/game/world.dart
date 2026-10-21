import 'dart:math';

import 'levels.dart';

enum GameEvent { place, slice, perfect, miss, gem, regrow, bossHit, bossWarning, flipWarning, bossDown, levelClear, gameOver }

/// What carries over from one level to the next.
class Run {
  Run({this.level = 1, this.score = 0});

  int level;
  int score;

  /// One rewarded revive per run.
  bool revived = false;
}

/// One floor of the tower, in tower coordinates (centred on the base).
class Slab {
  Slab(this.x, this.z, this.w, this.d, this.floor);

  final double x, z, w, d;
  final int floor;

  double get x0 => x - w / 2;
  double get x1 => x + w / 2;
  double get z0 => z - d / 2;
  double get z1 => z + d / 2;
}

/// A sliced-off piece (or a whole missed block) tumbling down, in field
/// coordinates (the tower's sway is already applied).
class Piece {
  Piece(this.x, this.z, this.y, this.w, this.d, this.floor, this.vx, this.vz);

  double x, z, y;
  final double w, d;

  /// Floor it came from, for its colour.
  final int floor;
  double vx, vz;
  double vy = 0;
  double life = 2.2;
  double spin = 0;
}

/// The block sliding over the tower, waiting for the tap.
class Mover {
  Mover({required this.ax, required this.az, required this.s, required this.dir, required this.id});

  /// Unit direction it travels in (x, z, or the diagonal).
  final double ax, az;

  /// Position along that direction, relative to the tower centre line.
  double s;
  double dir;
  final int id;

  /// Seconds alive.
  double t = 0;

  /// Width multiplier along the travel direction (pulse, vice).
  double squeeze = 1;

  /// Inverter: seconds until the next flip, and whether the warning is showing.
  double flipIn = 99;
}

/// End-of-level numbers for the break screen.
class LevelSummary {
  const LevelSummary({required this.floors, required this.perfects, required this.bestStreak, required this.gems, required this.livesBonus, required this.flawlessBonus});

  final int floors;
  final int perfects;
  final int bestStreak;
  final int gems;
  final int livesBonus;
  final int flawlessBonus;
  int get bonus => livesBonus + flawlessBonus;
}

/// One level in play. Pure simulation; the UI calls [drop] on a tap, [update]
/// every frame, and draws the state.
class World {
  World(this.run, {Random? rng})
      : spec = LevelSpec.forLevel(run.level),
        rng = rng ?? Random() {
    floors.add(Slab(0, 0, spec.startWidth, spec.startWidth, 0));
    if (spec.isBoss) {
      bossHp = spec.bossHp;
      events.add(GameEvent.bossWarning);
      _bossEntry = bossIntro;
    } else {
      _spawn();
    }
    if (spec.has(Mod.gems)) {
      for (var f = 3; f < spec.target; f += 4) {
        gemFloors.add(f);
      }
    }
  }

  /// Half the distance a block travels, in field units.
  static const range = 105.0;

  /// Height of one floor.
  static const floorHeight = 12.0;
  static const startLives = 3;

  /// Seconds the boss card shows before the first block.
  static const bossIntro = 2.2;

  /// Perfect drops in a row before each perfect also widens the block.
  static const regrowFrom = 3;
  static const regrowBy = 7.0;

  final Run run;
  final LevelSpec spec;
  final Random rng;

  double time = 0;
  int lives = startLives;

  /// floors[0] is the base; the top is floors.last.
  final floors = <Slab>[];
  Mover? mover;
  final pieces = <Piece>[];
  final events = <GameEvent>[];

  /// Floors still holding a gem.
  final gemFloors = <int>{};

  int streak = 0, bestStreak = 0, perfects = 0, gems = 0;
  bool lostLife = false;

  /// Smoothed height the camera follows, in floors.
  double camera = 0;

  /// Effects for the renderer, seconds left.
  double perfectFlash = 0, missFlash = 0, beam = 0, bossFlash = 0;
  double shake = 0;

  int bossHp = 0;
  double _bossEntry = 0;
  double _gustTimer = 3;
  double gustDir = 1;
  int _moverIds = 0;

  double? _clearTime;
  bool cleared = false;
  bool _overSent = false;
  bool get over => lives <= 0;

  Slab get top => floors.last;

  /// Floors stacked so far (the base doesn't count).
  int get height => floors.length - 1;

  bool get bossReady => spec.isBoss && _bossEntry <= 0;

  // ---- level twists ----

  /// Base glide, as an offset along (1, -1): purely sideways on screen.
  double get sway => spec.has(Mod.sway) ? sin(time * 1.3) * 22 : 0;
  double get swayX => sway;
  double get swayZ => -sway;

  /// Wind velocity along +axis.
  double get wind {
    if (spec.boss == BossKind.tempest) return gustDir * (55 + 15 * spec.tier.clamp(1, 5));
    if (!spec.has(Mod.wind)) return 0;
    return spec.speed * 0.32 * (0.65 + 0.35 * sin(time * 0.8));
  }

  bool get _hasBlade => spec.boss == BossKind.pendulum || spec.boss == BossKind.architect;
  bool get _hasFlips => spec.boss == BossKind.inverter || spec.boss == BossKind.architect;

  double get _bladePeriod => (spec.boss == BossKind.architect ? 3.2 : 2.7) - 0.12 * min(spec.tier, 6);

  /// Pendulum angle, -1..1 of its full swing.
  double get blade => _hasBlade ? sin(2 * pi * time / _bladePeriod) : 0;
  static const bladeDanger = 0.3;

  /// True while the blade sweeps over the tower: a drop now gets shattered.
  bool get bladeOverTower => _hasBlade && bossReady && bossHp > 0 && blade.abs() < bladeDanger;

  /// Whether a drop right now is safe from boss hazards (used by the bot and HUD).
  bool get dropSafe => !bladeOverTower;

  // ---- input ----

  /// The tap. Returns true if a block was dropped.
  bool drop() {
    final m = mover;
    if (m == null || cleared || over || _clearTime != null) return false;
    if (bladeOverTower) {
      _shatter(m);
    } else {
      _land(m);
    }
    mover = null;
    if (!over && _clearTime == null) _spawn();
    return true;
  }

  /// Offset between the block and the top floor along the travel direction if
  /// dropped now (0 = dead centre).
  double get offset {
    final m = mover;
    if (m == null) return 0;
    return m.s - _topAlong(m);
  }

  /// Signed block speed right now, units per second along its direction.
  double get moverVelocity {
    final m = mover;
    if (m == null) return 0;
    return m.dir * _speed(m) + wind;
  }

  double _topAlong(Mover m) => (top.x + swayX) * m.ax + (top.z + swayZ) * m.az;

  // ---- simulation ----

  void update(double dt) {
    if (cleared) return;
    time += dt;
    shake = max(0, shake - dt * 30);
    perfectFlash = max(0, perfectFlash - dt);
    missFlash = max(0, missFlash - dt);
    beam = max(0, beam - dt);
    bossFlash = max(0, bossFlash - dt);
    camera += (height - camera) * min(1, dt * 5);
    _updatePieces(dt);

    if (over) {
      if (!_overSent) {
        _overSent = true;
        events.add(GameEvent.gameOver);
      }
      return;
    }
    if (spec.isBoss && _bossEntry > 0) {
      _bossEntry -= dt;
      if (_bossEntry <= 0) _spawn();
    }
    if (spec.boss == BossKind.tempest) {
      _gustTimer -= dt;
      if (_gustTimer <= 0) {
        gustDir = -gustDir;
        _gustTimer = 2.4 + rng.nextDouble() * 1.6 - 0.15 * spec.tier;
        events.add(GameEvent.flipWarning);
      }
    }
    final m = mover;
    if (m != null) _move(m, dt);

    if (_clearTime != null) {
      _clearTime = _clearTime! + dt;
      if (_clearTime! > 1.3) {
        cleared = true;
        events.add(GameEvent.levelClear);
      }
    }
  }

  double _speed(Mover m) {
    var v = spec.speed;
    if (spec.has(Mod.accelerate)) v *= min(1.9, 1 + 0.5 * m.t);
    if (spec.isBoss) v *= 0.92;
    return v;
  }

  void _move(Mover m, double dt) {
    m.t += dt;
    if (_hasFlips) {
      final before = m.flipIn;
      m.flipIn -= dt;
      if (before >= flipWarning && m.flipIn < flipWarning) events.add(GameEvent.flipWarning);
      if (m.flipIn <= 0) {
        m.dir = -m.dir;
        m.flipIn = _nextFlip();
      }
    }
    var v = m.dir * _speed(m) + wind;
    m.s += v * dt;
    // Bounce at the ends of the run.
    final centre = _topAlong(m);
    if (m.s > centre + range && v > 0) {
      m.s = centre + range;
      m.dir = -1;
    } else if (m.s < centre - range && v < 0) {
      m.s = centre - range;
      m.dir = 1;
    }
    var k = 1.0;
    if (spec.has(Mod.pulse)) k = 1 - 0.22 * (0.5 - 0.5 * cos(m.t * 2 * pi / 1.4));
    if (spec.boss == BossKind.vice) {
      final rate = 0.22 + 0.04 * spec.tier;
      k = max(0.5, 1 - rate * max(0, m.t - 1.1));
    }
    m.squeeze = k;
  }

  double _nextFlip() => max(0.9, 1.5 + rng.nextDouble() * 1.2 - 0.1 * spec.tier);

  /// Seconds before a flip that the block flashes.
  static const flipWarning = 0.4;

  bool get flipWarned => mover != null && _hasFlips && mover!.flipIn < flipWarning;

  void _spawn() {
    final f = floors.length;
    final (ax, az) = switch (spec.path) {
      Track.alternate => f.isOdd ? (1.0, 0.0) : (0.0, 1.0),
      Track.single => (1.0, 0.0),
      Track.diagonal => (sqrt1_2, sqrt1_2),
    };
    final side = f.isOdd ? -1.0 : 1.0;
    final m = Mover(ax: ax, az: az, s: 0, dir: -side, id: _moverIds++);
    m.s = _topAlong(m) + side * range;
    if (_hasFlips) m.flipIn = _nextFlip();
    mover = m;
  }

  /// The footprint the mover would have if it landed now, in tower coordinates.
  Slab moverSlab() {
    final m = mover!;
    final o = offset;
    final w = top.w * (m.ax > 0 ? m.squeeze : 1);
    final d = top.d * (m.az > 0 ? m.squeeze : 1);
    return Slab(top.x + o * m.ax, top.z + o * m.az, w, d, floors.length);
  }

  void _land(Mover m) {
    final o = offset;
    final f = floors.length;
    final slab = moverSlab();
    if (o.abs() <= spec.tolerance) {
      _perfect(m, f);
      return;
    }
    streak = 0;
    final ox0 = max(slab.x0, top.x0), ox1 = min(slab.x1, top.x1);
    final oz0 = max(slab.z0, top.z0), oz1 = min(slab.z1, top.z1);
    if (ox1 - ox0 < 1.5 || oz1 - oz0 < 1.5) {
      _miss(slab);
      return;
    }
    final kept = Slab((ox0 + ox1) / 2, (oz0 + oz1) / 2, ox1 - ox0, oz1 - oz0, f);
    floors.add(kept);
    // Whatever hangs over falls: the x overhang over the full depth, then the z overhang.
    final y = f * floorHeight;
    void cut(double x0, double x1, double z0, double z1) {
      if (x1 - x0 < 0.5 || z1 - z0 < 0.5) return;
      final cx = (x0 + x1) / 2, cz = (z0 + z1) / 2;
      pieces.add(Piece(cx + swayX, cz + swayZ, y, x1 - x0, z1 - z0, f, (cx - kept.x).sign * 25, (cz - kept.z).sign * 25));
    }

    cut(slab.x0, ox0, slab.z0, slab.z1);
    cut(ox1, slab.x1, slab.z0, slab.z1);
    cut(ox0, ox1, slab.z0, oz0);
    cut(ox0, ox1, oz1, slab.z1);
    gemFloors.remove(f);
    run.score += 10;
    shake = 3;
    events.addAll([GameEvent.place, GameEvent.slice]);
    _checkClear();
  }

  void _perfect(Mover m, int f) {
    streak++;
    perfects++;
    bestStreak = max(bestStreak, streak);
    var w = top.w, d = top.d;
    if (streak >= regrowFrom) {
      final cap = spec.startWidth;
      if (m.ax > 0) w = min(cap, w + regrowBy);
      if (m.az > 0) d = min(cap, d + regrowBy);
      if (w != top.w || d != top.d) events.add(GameEvent.regrow);
    }
    floors.add(Slab(top.x, top.z, w, d, f));
    perfectFlash = 0.6;
    run.score += 10 + 20 * min(streak, 5);
    events.add(GameEvent.perfect);
    if (gemFloors.remove(f)) {
      gems++;
      run.score += 250;
      if (lives < startLives) lives++;
      events.add(GameEvent.gem);
    }
    if (spec.isBoss && bossHp > 0) {
      final dmg = streak >= regrowFrom ? 2 : 1;
      bossHp = max(0, bossHp - dmg);
      beam = 0.35;
      bossFlash = 0.25;
      run.score += 100 * dmg;
      events.add(GameEvent.bossHit);
      if (bossHp == 0) {
        shake = 10;
        events.add(GameEvent.bossDown);
        _clearTime = 0;
      }
    }
    _checkClear();
  }

  void _miss(Slab slab) {
    pieces.add(Piece(slab.x + swayX, slab.z + swayZ, slab.floor * floorHeight, slab.w, slab.d, slab.floor, slab.x.sign * 30, slab.z.sign * 30));
    gemFloors.remove(slab.floor);
    _loseLife();
  }

  /// The pendulum blade cuts the block in two before it lands.
  void _shatter(Mover m) {
    final slab = moverSlab();
    final y = slab.floor * floorHeight;
    final halfW = m.ax > 0 ? slab.w / 2 : slab.w, halfD = m.az > 0 ? slab.d / 2 : slab.d;
    for (final s in [-1.0, 1.0]) {
      final cx = slab.x + (m.ax > 0 ? s * halfW / 2 : 0), cz = slab.z + (m.az > 0 ? s * halfD / 2 : 0);
      pieces.add(Piece(cx + swayX, cz + swayZ, y, halfW, halfD, slab.floor, s * m.ax * 60, s * m.az * 60));
    }
    _loseLife();
  }

  void _loseLife() {
    streak = 0;
    lives--;
    lostLife = true;
    missFlash = 0.5;
    shake = 8;
    events.add(GameEvent.miss);
  }

  void _checkClear() {
    if (!spec.isBoss && height >= spec.target && _clearTime == null) _clearTime = 0;
  }

  void _updatePieces(double dt) {
    for (final p in pieces) {
      p.vy -= 420 * dt;
      p.x += p.vx * dt;
      p.z += p.vz * dt;
      p.y += p.vy * dt;
      p.spin += dt * (p.vx + p.vz).sign * 2.5;
      p.life -= dt;
    }
    pieces.removeWhere((p) => p.life <= 0);
  }

  /// Back in after a rewarded ad: two lives, same tower.
  void revive() {
    lives = 2;
    _overSent = false;
    streak = 0;
    if (mover == null && _clearTime == null && (!spec.isBoss || _bossEntry <= 0)) _spawn();
  }

  /// Applies the end-of-level bonus once and returns the numbers.
  LevelSummary finish() {
    final s = LevelSummary(
      floors: height,
      perfects: perfects,
      bestStreak: bestStreak,
      gems: gems,
      livesBonus: lives * 150,
      flawlessBonus: lostLife ? 0 : 300,
    );
    run.score += s.bonus;
    return s;
  }
}
