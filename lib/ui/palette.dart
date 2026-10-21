import 'package:flutter/material.dart';

const background = Color(0xFF07060F);
const accent = Color(0xFF3CF0FF); // cyan
const hot = Color(0xFFFF3B8B); // danger magenta
const gold = Color(0xFFFFD447);
const lime = Color(0xFF7CFF6B);

/// Boss colours by [BossKind] index.
const bossColors = <Color>[
  Color(0xFFFF4F6D), // pendulum
  Color(0xFFFFA62B), // vice
  Color(0xFFB57BFF), // inverter
  Color(0xFF4FD8FF), // tempest
  Color(0xFFFF4FD8), // architect
];

/// Neon colour of a floor: the level hue drifting up the tower.
Color floorColor(double hue, int floor) => HSVColor.fromAHSV(1, (hue + floor * 7) % 360, 0.72, 1).toColor();

/// Dark sky tint for a level.
Color levelTint(double hue) => HSVColor.fromAHSV(1, hue, 0.75, 0.24).toColor();

TextStyle neon(double size, {Color color = accent, FontWeight weight = FontWeight.w900, double spacing = 2}) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: size * 0.5)],
    );
