import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'foos_engine.dart';

Paint _p(int c) => Paint()..color = Color(c);

Paint _stroke(int c, double w) => Paint()
  ..color = Color(c)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

void _man(Canvas c, double x, double y, int body, int head, bool kicking, bool top) {
  final dir = top ? 1.0 : -1.0;
  // shoulders across the rod, foot pointing toward the rival goal
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + 3, y + 6), width: 58, height: 26), const Radius.circular(12)),
      _p(0x44000000));
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: 58, height: 26), const Radius.circular(12)), _p(body));
  final foot = kicking ? 34.0 : 20.0;
  c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y + dir * foot), width: 18, height: 26), const Radius.circular(8)),
      _p(body));
  c.drawCircle(Offset(x, y), 11, _p(head));
}

void paintFoos(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as FoosSim;
  const themes = [
    [0xFF1E2A22, 0xFF3E7C4F, 0xFF367046],
    [0xFF2B2118, 0xFF5B8C5A, 0xFF507D50],
    [0xFF1C2230, 0xFF4F7D6A, 0xFF46705F],
    [0xFF2A2230, 0xFF6A8F5E, 0xFF5E8154],
  ];
  final th = themes[s.level.theme % 4];
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), _p(th[0]));
  const pitch = Rect.fromLTRB(kL, kT, kR, kB);
  // wooden frame
  c.drawRRect(RRect.fromRectAndRadius(pitch.inflate(40), const Radius.circular(24)), _p(0xFF7A5230));
  c.drawRRect(RRect.fromRectAndRadius(pitch.inflate(28), const Radius.circular(18)), _p(0xFF8D6240));
  // grass stripes
  for (var i = 0; i < 10; i++) {
    final y0 = kT + (kB - kT) * i / 10;
    c.drawRect(Rect.fromLTRB(kL, y0, kR, y0 + (kB - kT) / 10), _p(i.isEven ? th[1] : th[2]));
  }
  final line = _stroke(0xCCF1F1EE, 5);
  c.drawRect(pitch, line);
  c.drawLine(const Offset(kL, kMid), const Offset(kR, kMid), line);
  c.drawCircle(const Offset(500, kMid), 90, line);
  c.drawRect(const Rect.fromLTRB(500 - 230, kT, 500 + 230, kT + 150), line);
  c.drawRect(const Rect.fromLTRB(500 - 230, kB - 150, 500 + 230, kB), line);
  // goals
  c.drawRect(const Rect.fromLTRB(500 - kGoalHalf, kT - 36, 500 + kGoalHalf, kT), _p(0xFF22252A));
  c.drawRect(const Rect.fromLTRB(500 - kGoalHalf, kB, 500 + kGoalHalf, kB + 36), _p(0xFF22252A));
  // ball shadow before rods so men stand above it
  c.drawCircle(Offset(s.bx + 4, s.by + 6), kBallR, _p(0x55000000));
  c.drawCircle(Offset(s.bx, s.by), kBallR, _p(0xFFF5F3EE));
  c.drawCircle(Offset(s.bx - 6, s.by - 6), kBallR * 0.35, _p(0x33000000));
  // rods and men
  for (var i = 0; i < kRods.length; i++) {
    final r = kRods[i];
    c.drawLine(Offset(kL - 60, r.y), Offset(kR + 60, r.y), _stroke(0xFFB8BCC2, 9));
    c.drawLine(Offset(kL - 60, r.y - 3), Offset(kR + 60, r.y - 3), _stroke(0x66FFFFFF, 2));
    final mine = r.owner == 0;
    final kicking = mine ? s.kick > 0 : s.cpuKick > 0;
    for (final (mx, my) in s.men(i)) {
      _man(c, mx, my, mine ? 0xFF3B6EA5 : 0xFFB5504A, 0xFFE8C9A8, kicking, !mine);
    }
    // handles at the side of each team
    final hx = mine ? kR + 70 : kL - 70;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(hx, r.y), width: 44, height: 24), const Radius.circular(10)),
        _p(0xFF2F3237));
  }
  if (s.boost > 0) {
    c.drawCircle(Offset(s.bx, s.by), kBallR + 10 + 4 * math.sin(t * 10), _stroke(0xCCE9C46A, 5));
  }
  paintText(c, '${s.cpuGoals}', const Offset(500, 90), 56, Colors.white70);
  paintText(c, '${s.myGoals}', const Offset(500, 1510), 56, Colors.white);
  if (s.flashTicks > 0) {
    paintText(c, s.flash, const Offset(500, kMid), 90, Colors.white.withValues(alpha: (s.flashTicks / 60).clamp(0.0, 1.0)));
  }
}

Sfx? foosSound(ArcadeSim sim) => switch ((sim as FoosSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.combo,
      3 => Sfx.error,
      4 => Sfx.place,
      _ => null,
    };
