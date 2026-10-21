import 'dart:math';

import 'package:flutter/material.dart';

import '../game/levels.dart';
import '../game/world.dart';
import 'palette.dart';

/// Width of the field everything is laid out in. The field is as tall as the
/// screen allows (at least [minFieldHeight]), so phones get no letterbox bars.
const fieldWidth = 360.0;
const minFieldHeight = 560.0;

/// Maps the field into the widget: scaled to fit the width, centred.
class FieldTransform {
  FieldTransform(Size size)
      : scale = min(size.width / fieldWidth, size.height / minFieldHeight),
        size = size;

  final double scale;
  final Size size;

  double get left => (size.width - fieldWidth * scale) / 2;

  /// Field height in field units.
  double get height => size.height / scale;
}

/// Isometric projection of the tower's 3D space onto the field.
class Iso {
  const Iso({required this.cameraY, this.centreX = 180, this.anchorY = 370, this.scale = 1.25});

  /// Height (in field units) that sits at [anchorY].
  final double cameraY;
  final double centreX, anchorY, scale;

  static const _c = 0.8660254;

  Offset p(double x, double z, double y) => Offset(centreX + (x - z) * _c * scale, anchorY + (x + z) * 0.5 * scale - (y - cameraY) * scale);
}

/// Distant specks drifting with the camera.
class Starfield {
  Starfield([int seed = 11]) {
    final rng = Random(seed);
    for (var i = 0; i < 90; i++) {
      final layer = i % 3;
      _stars.add((rng.nextDouble(), rng.nextDouble(), 0.15 + layer * 0.2, 0.6 + layer * 0.45));
    }
  }

  final _stars = <(double, double, double, double)>[];

  void paint(Canvas canvas, Rect area, double scroll, double time) {
    final paint = Paint();
    for (final (x, y, depth, r) in _stars) {
      final py = (y * area.height + scroll * depth) % area.height;
      final twinkle = 0.75 + 0.25 * sin(time * 2 + x * 40);
      paint.color = Colors.white.withValues(alpha: (0.18 + r * 0.25) * twinkle);
      canvas.drawCircle(Offset(area.left + x * area.width, area.top + py), r, paint);
    }
  }
}

/// Draws one box: top face plus the two faces turned toward the viewer.
void drawBox(Canvas canvas, Iso iso, double x, double z, double w, double d, double y0, double y1, Color color,
    {double alpha = 1, bool glow = false, bool edges = true}) {
  final ax = x - w / 2, bx = x + w / 2, az = z - d / 2, bz = z + d / 2;
  final t0 = iso.p(ax, az, y1), t1 = iso.p(bx, az, y1), t2 = iso.p(bx, bz, y1), t3 = iso.p(ax, bz, y1);
  final b1 = iso.p(bx, az, y0), b2 = iso.p(bx, bz, y0), b3 = iso.p(ax, bz, y0);
  final hsv = HSVColor.fromColor(color);
  Color shade(double v, double s) => hsv.withValue((hsv.value * v).clamp(0, 1)).withSaturation((hsv.saturation * s).clamp(0, 1)).toColor().withValues(alpha: alpha);
  final paint = Paint();
  final top = Path()..addPolygon([t0, t1, t2, t3], true);
  if (glow) {
    canvas.drawPath(
      Path()..addPolygon([t0, t1, b1, b2, b3, t3], true),
      Paint()
        ..color = color.withValues(alpha: 0.45 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }
  // Right face (x = bx) and left face (z = bz).
  canvas.drawPath(Path()..addPolygon([t1, t2, b2, b1], true), paint..color = shade(0.42, 1));
  canvas.drawPath(Path()..addPolygon([t3, t2, b2, b3], true), paint..color = shade(0.62, 1));
  canvas.drawPath(top, paint..color = shade(1, 0.55));
  if (edges) {
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withValues(alpha: 0.55 * alpha);
    canvas.drawPath(top, edge);
    canvas.drawLine(t2, b2, edge..color = Colors.white.withValues(alpha: 0.25 * alpha));
  }
}

class TowerPainter extends CustomPainter {
  TowerPainter(this.world, this.stars, {required Listenable repaint}) : super(repaint: repaint);

  final World world;
  final Starfield stars;

  static final _labels = <String, TextPainter>{};

  /// Visible field height, in field units (set each paint).
  double fieldH = 640;

  @override
  void paint(Canvas canvas, Size size) {
    final w = world;
    final spec = w.spec;
    final tint = levelTint(spec.hue);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background, tint, background],
          stops: const [0, 0.55, 1],
        ).createShader(Offset.zero & size),
    );
    stars.paint(canvas, Offset.zero & size, w.camera * World.floorHeight * 2, w.time);

    final t = FieldTransform(size);
    fieldH = t.height;
    canvas.save();
    canvas.translate(t.left, 0);
    canvas.scale(t.scale);
    if (w.shake > 0) {
      final r = Random(w.time.hashCode);
      canvas.translate((r.nextDouble() - 0.5) * w.shake, (r.nextDouble() - 0.5) * w.shake);
    }
    final iso = Iso(cameraY: (w.camera + 1) * World.floorHeight, anchorY: fieldH * 0.6);
    final topSurface = w.floors.length * World.floorHeight;
    final topX = w.top.x + w.swayX, topZ = w.top.z + w.swayZ;

    _wind(canvas, w);
    // Pieces behind the tower first, the rest after.
    final behind = w.pieces.where((p) => p.x + p.z < topX + topZ).toList();
    final front = w.pieces.where((p) => p.x + p.z >= topX + topZ).toList();
    for (final p in behind) {
      _piece(canvas, iso, p);
    }
    _tower(canvas, iso, w);
    // The finish line shows up once it's within reach.
    if (!spec.isBoss && w.height < spec.target && spec.target - w.height <= 10) _finishLine(canvas, iso, w);
    _gems(canvas, iso, w);
    if (spec.has(Mod.fog)) _fog(canvas, iso, w, topSurface);
    _ripple(canvas, iso, w, topSurface);
    for (final p in front) {
      _piece(canvas, iso, p);
    }
    if (w.mover != null) _mover(canvas, iso, w);
    if (spec.isBoss) _guardian(canvas, iso, w, topSurface);
    _popup(canvas, iso, w, topSurface);
    canvas.restore();

    if (w.missFlash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.transparent, hot.withValues(alpha: w.missFlash * 0.7)],
            stops: const [0.55, 1],
          ).createShader(Offset.zero & size),
      );
    }
  }

  void _tower(Canvas canvas, Iso iso, World w) {
    final hue = w.spec.hue;
    final sx = w.swayX, sz = w.swayZ;
    // The pedestal: a dark column reaching below the screen.
    final base = w.floors.first;
    drawBox(canvas, iso, base.x + sx, base.z + sz, base.w, base.d, -900, World.floorHeight, const Color(0xFF2A2440));
    // Neon rim around the pedestal top.
    final rim = Path()
      ..addPolygon([
        iso.p(base.x0 + sx, base.z0 + sz, World.floorHeight),
        iso.p(base.x1 + sx, base.z0 + sz, World.floorHeight),
        iso.p(base.x1 + sx, base.z1 + sz, World.floorHeight),
        iso.p(base.x0 + sx, base.z1 + sz, World.floorHeight),
      ], true);
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = floorColor(hue, 0),
    );
    // Only floors that can be on screen (about 26 below the camera).
    final first = max(1, w.camera.floor() - (fieldH / 14).ceil());
    for (var i = first; i < w.floors.length; i++) {
      final f = w.floors[i];
      final isTop = i == w.floors.length - 1;
      drawBox(canvas, iso, f.x + sx, f.z + sz, f.w, f.d, i * World.floorHeight, (i + 1) * World.floorHeight, floorColor(hue, i),
          glow: isTop && !w.spec.has(Mod.fog));
    }
  }

  void _mover(Canvas canvas, Iso iso, World w) {
    final m = w.mover!;
    final slab = w.moverSlab();
    final y0 = slab.floor * World.floorHeight;
    var color = floorColor(w.spec.hue, slab.floor);
    if (w.spec.boss == BossKind.vice && m.squeeze < 1) color = Color.lerp(color, bossColors[BossKind.vice.index], (1 - m.squeeze) * 2)!;
    if (w.flipWarned && (w.time * 16).floor().isEven) color = Colors.white;
    drawBox(canvas, iso, slab.x + w.swayX, slab.z + w.swayZ, slab.w, slab.d, y0, y0 + World.floorHeight, color, glow: true);
  }

  void _piece(Canvas canvas, Iso iso, Piece p) {
    final a = (p.life / 0.6).clamp(0.0, 1.0);
    drawBox(canvas, iso, p.x, p.z, p.w, p.d, p.y, p.y + World.floorHeight, floorColor(world.spec.hue, p.floor), alpha: a, edges: a > 0.5);
  }

  void _finishLine(Canvas canvas, Iso iso, World w) {
    final y = (w.spec.target + 1) * World.floorHeight;
    final r = w.spec.startWidth / 2 + 12;
    final cx = w.swayX, cz = w.swayZ;
    final pts = [iso.p(cx - r, cz - r, y), iso.p(cx + r, cz - r, y), iso.p(cx + r, cz + r, y), iso.p(cx - r, cz + r, y)];
    if (pts.every((p) => p.dy < -20 || p.dy > fieldH + 20)) return;
    final pulse = 0.6 + 0.4 * sin(w.time * 4);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = gold.withValues(alpha: pulse);
    // Dashed diamond.
    for (var i = 0; i < 4; i++) {
      final a = pts[i], b = pts[(i + 1) % 4];
      for (var k = 0; k < 10; k += 2) {
        canvas.drawLine(Offset.lerp(a, b, k / 10)!, Offset.lerp(a, b, (k + 1) / 10)!, paint);
      }
    }
    _label(canvas, 'FINISH', pts[0] + const Offset(0, -12), gold.withValues(alpha: pulse), 11, centre: true);
  }

  void _gems(Canvas canvas, Iso iso, World w) {
    for (final f in w.gemFloors) {
      final c = iso.p(w.swayX + 64, w.swayZ - 64, (f + 0.5) * World.floorHeight) + Offset(0, sin(w.time * 3 + f) * 4);
      if (c.dy < -20 || c.dy > fieldH + 20) continue;
      final next = f == w.floors.length;
      final s = next ? 9.0 : 7.0;
      final gem = Path()
        ..moveTo(c.dx, c.dy - s)
        ..lineTo(c.dx + s * 0.75, c.dy)
        ..lineTo(c.dx, c.dy + s)
        ..lineTo(c.dx - s * 0.75, c.dy)
        ..close();
      canvas.drawPath(
        gem,
        Paint()
          ..color = lime.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(gem, Paint()..color = next ? lime : lime.withValues(alpha: 0.6));
      canvas.drawLine(Offset(c.dx - s * 0.75, c.dy), Offset(c.dx + s * 0.75, c.dy), Paint()..color = Colors.white70);
    }
  }

  void _fog(Canvas canvas, Iso iso, World w, double topSurface) {
    final y = iso.p(0, 0, topSurface).dy - 50;
    final rect = Rect.fromLTRB(-40, y, fieldWidth + 40, fieldH + 40);
    final fogColor = HSVColor.fromAHSV(1, w.spec.hue, 0.25, 0.32).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fogColor.withValues(alpha: 0), fogColor.withValues(alpha: 0.93), fogColor.withValues(alpha: 0.97)],
          stops: const [0, 0.12, 1],
        ).createShader(rect),
    );
    // A faint outline of the top floor is all you get.
    final f = w.top;
    final sx = w.swayX, sz = w.swayZ;
    final outline = Path()
      ..addPolygon([
        iso.p(f.x0 + sx, f.z0 + sz, topSurface),
        iso.p(f.x1 + sx, f.z0 + sz, topSurface),
        iso.p(f.x1 + sx, f.z1 + sz, topSurface),
        iso.p(f.x0 + sx, f.z1 + sz, topSurface),
      ], true);
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.32 + 0.1 * sin(w.time * 3)),
    );
  }

  void _ripple(Canvas canvas, Iso iso, World w, double topSurface) {
    if (w.perfectFlash <= 0) return;
    final f = w.top;
    final k = 1 - w.perfectFlash / 0.6;
    final grow = 4 + k * 26;
    final sx = f.x + w.swayX, sz = f.z + w.swayZ;
    final hw = f.w / 2 + grow, hd = f.d / 2 + grow;
    final path = Path()
      ..addPolygon([
        iso.p(sx - hw, sz - hd, topSurface),
        iso.p(sx + hw, sz - hd, topSurface),
        iso.p(sx + hw, sz + hd, topSurface),
        iso.p(sx - hw, sz + hd, topSurface),
      ], true);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - k) + 1
        ..color = Colors.white.withValues(alpha: 1 - k),
    );
  }

  void _popup(Canvas canvas, Iso iso, World w, double topSurface) {
    if (w.perfectFlash <= 0) return;
    final k = 1 - w.perfectFlash / 0.6;
    final c = iso.p(w.top.x + w.swayX, w.top.z + w.swayZ, topSurface) + Offset(0, -70 - k * 24);
    final a = (w.perfectFlash / 0.3).clamp(0.0, 1.0);
    final text = w.streak > 1 ? 'PERFECT ×${w.streak}' : 'PERFECT';
    _label(canvas, text, c, (w.streak >= World.regrowFrom ? gold : Colors.white).withValues(alpha: a), 18, centre: true);
  }

  /// Streaks drifting with the wind, along the block's path.
  void _wind(Canvas canvas, World w) {
    final v = w.wind;
    if (v == 0) return;
    final m = w.mover;
    final ax = m?.ax ?? 1, az = m?.az ?? 0;
    // Screen direction of +axis.
    final dir = Offset((ax - az) * 0.866, (ax + az) * 0.5);
    final n = dir / dir.distance;
    final paint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final rng = Random(3);
    for (var i = 0; i < 12; i++) {
      final base = Offset(rng.nextDouble() * 520 - 80, rng.nextDouble() * fieldH);
      final travel = (w.time * v.abs() * 2.2 + i * 37) % 520;
      final p = base + n * (v.sign * travel - 260);
      final len = 14 + v.abs() * 0.18;
      paint.color = Colors.white.withValues(alpha: 0.14 + 0.14 * (i % 3) / 2);
      canvas.drawLine(p, p - n * v.sign * len, paint);
    }
  }

  void _guardian(Canvas canvas, Iso iso, World w, double topSurface) {
    final kind = w.spec.boss!;
    final color = bossColors[kind.index];
    final entry = (w.time / World.bossIntro).clamp(0.0, 1.0);
    final c = Offset(180, -60 + 180 * Curves.easeOutBack.transform(entry) + sin(w.time * 1.6) * 5);
    final hit = w.bossFlash > 0;
    final down = w.bossHp == 0;
    final body = hit ? Colors.white : color;
    final glow = Paint()
      ..color = color.withValues(alpha: down ? 0.2 : 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = body.withValues(alpha: down ? 0.3 : 1);
    final fill = Paint()..color = Color.lerp(background, color, 0.25)!.withValues(alpha: down ? 0.4 : 0.95);

    // Blade first, so the guardian sits on top of its pivot.
    if (w.bladeOverTower || (w.spec.boss == BossKind.pendulum || w.spec.boss == BossKind.architect)) {
      if (!down && w.bossReady) _blade(canvas, iso, w, c, topSurface, color);
    }

    final spin = w.time * (kind == BossKind.inverter ? -0.8 : 0.5);
    Path poly(int sides, double r, double rot) {
      final p = Path();
      for (var i = 0; i < sides; i++) {
        final a = rot + i * 2 * pi / sides;
        final o = c + Offset(cos(a), sin(a)) * r;
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      return p..close();
    }

    final shape = switch (kind) {
      BossKind.pendulum => poly(3, 36, pi / 2),
      BossKind.vice => poly(4, 36, pi / 4),
      BossKind.inverter => poly(6, 34, spin),
      BossKind.tempest => poly(8, 34, spin),
      BossKind.architect => poly(5, 38, spin),
    };
    canvas.drawPath(shape, glow);
    canvas.drawPath(shape, fill);
    canvas.drawPath(shape, stroke);
    if (kind == BossKind.architect || kind == BossKind.tempest) {
      canvas.drawPath(poly(kind == BossKind.tempest ? 4 : 5, 22, -spin * 1.5), stroke..strokeWidth = 1.5);
    }
    if (kind == BossKind.vice && w.mover != null) {
      // Jaws closing in as the block shrinks.
      final gap = 46 * w.mover!.squeeze + 8;
      final jaw = Paint()
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = body;
      canvas.drawLine(c + Offset(-gap - 14, 22), c + Offset(-gap, 40), jaw);
      canvas.drawLine(c + Offset(gap + 14, 22), c + Offset(gap, 40), jaw);
    }
    // The eye, following the block.
    final look = w.mover == null ? 0.0 : (w.offset / World.range).clamp(-1.0, 1.0) * 6;
    canvas.drawCircle(c, 10, Paint()..color = Colors.white.withValues(alpha: down ? 0.3 : 1));
    canvas.drawCircle(c + Offset(look, 1), 5, Paint()..color = down ? Colors.black26 : (w.flipWarned ? hot : Colors.black));

    if (w.beam > 0) {
      final from = iso.p(w.top.x + w.swayX, w.top.z + w.swayZ, topSurface);
      final a = w.beam / 0.35;
      canvas.drawLine(
        from,
        c,
        Paint()
          ..strokeWidth = 14 * a
          ..color = Colors.white.withValues(alpha: 0.35 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawLine(from, c, Paint()..strokeWidth = 3 * a..color = Colors.white.withValues(alpha: a));
    }
  }

  void _blade(Canvas canvas, Iso iso, World w, Offset pivot, double topSurface, Color color) {
    const swing = 1.05; // radians at full swing
    final angle = w.blade * swing;
    final reach = iso.p(0, 0, topSurface + World.floorHeight * 1.5).dy - pivot.dy;
    final tip = pivot + Offset(sin(angle), cos(angle)) * reach;
    final danger = w.bladeOverTower;
    final c = danger ? hot : color.withValues(alpha: 0.85);
    canvas.drawLine(pivot, tip, Paint()..strokeWidth = 3.5..color = c.withValues(alpha: 0.75));
    canvas.drawCircle(tip, 7, Paint()..color = c);
    // The blade: a glowing bar across the tip, as wide as a block.
    final across = Offset(cos(angle), -sin(angle));
    final a = tip - across * 80, b = tip + across * 80;
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = danger ? 22 : 14
        ..strokeCap = StrokeCap.round
        ..color = c.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawLine(a, b, Paint()..strokeWidth = 6..strokeCap = StrokeCap.round..color = danger ? Colors.white : c);
  }

  void _label(Canvas canvas, String text, Offset at, Color color, double size, {bool centre = false}) {
    final key = '$text|${color.toARGB32()}|$size';
    final tp = _labels.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(text: text, style: neon(size, color: color, spacing: 2)),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    if (_labels.length > 200) _labels.clear();
    tp.paint(canvas, centre ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(TowerPainter old) => old.world != world;
}

/// The home screen's decorative tower, slowly breathing.
class DecorTowerPainter extends CustomPainter {
  DecorTowerPainter(this.anim, this.stars) : super(repaint: anim);

  final Animation<double> anim;
  final Starfield stars;

  @override
  void paint(Canvas canvas, Size size) {
    final time = anim.value * 60;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background, levelTint(285), background],
          stops: const [0, 0.7, 1],
        ).createShader(Offset.zero & size),
    );
    stars.paint(canvas, Offset.zero & size, time * 8, time);
    final iso = Iso(cameraY: 0, centreX: size.width / 2, anchorY: size.height + 70, scale: 1.1);
    final rng = Random(4);
    var x = 0.0, z = 0.0, w = 100.0, d = 100.0;
    drawBox(canvas, iso, 0, 0, 100, 100, -400, 0, const Color(0xFF2A2440), alpha: 0.6);
    for (var i = 0; i < 12; i++) {
      final cut = rng.nextDouble() * 6;
      if (i.isOdd) {
        w -= cut;
        x += cut / 2 * (rng.nextBool() ? 1 : -1);
      } else {
        d -= cut;
        z += cut / 2 * (rng.nextBool() ? 1 : -1);
      }
      final y = i * World.floorHeight;
      drawBox(canvas, iso, x, z, w, d, y, y + World.floorHeight, floorColor(285 + time * 3, i), alpha: 0.28);
    }
  }

  @override
  bool shouldRepaint(DecorTowerPainter old) => false;
}
