import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:oyun_langirt/src/foos_engine.dart';
import 'package:oyun_langirt/src/rules.dart';

void main() {
  final rules = FoosRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  FoosSim fresh([int n = 1]) => FoosSim(rules.build(planner.spec(n)).puzzle);

  test('eight rods, alternating sides like a real table', () {
    expect(kRods.length, 8);
    expect(kRods.where((r) => r.owner == 0).length, 4);
    expect(kRods.first.owner, 0);
    expect(kRods.last.owner, 1);
  });

  test('the finger slides the player rods within their range', () {
    final s = fresh();
    for (var i = 0; i < 30; i++) {
      s.tick(const ArcadeInput(down: true, x: 900, y: 1500));
    }
    for (var i = 0; i < kRods.length; i++) {
      if (kRods[i].owner == 0) expect(s.off[i], kRods[i].range);
    }
  });

  test('a tap kicks the ball forward from the man in front of it', () {
    final s = fresh();
    s.pause = 0;
    s.bx = 500;
    s.by = 540 - 40; // just in front of the player's centre forward
    s.vx = 0;
    s.vy = 0;
    s.tick(const ArcadeInput(down: true, x: 500, y: 1500, tap: true));
    expect(s.vy, lessThan(-20));
    expect(s.shots, 1);
  });

  test('a ball in the rival slot is a goal', () {
    final s = fresh();
    s.pause = 0;
    s.bx = 500;
    s.by = kT + 30;
    s.vx = 0;
    s.vy = -25;
    s.off[7] = 170; // keeper out of the way
    final before = s.goalsScored;
    for (var i = 0; i < 10 && s.goalsScored == before; i++) {
      s.tick(const ArcadeInput(down: true, x: 500, y: 1500));
    }
    expect(s.goalsScored, before + 1);
  });

  test('autopilot wins the first matches and late levels', () {
    for (final n in [1, 2, 3, 4, 5, 6, 30, 200, 5000]) {
      final s = fresh(n);
      expect(runBot(s, rules.bot, 60 * 60 * 10).won, isTrue, reason: 'level $n');
    }
  });
}
