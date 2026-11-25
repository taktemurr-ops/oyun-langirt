import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/arcade_duel.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Table football (langırt) seen from above. Eight rods as on a real table:
/// from the bottom, the player's keeper, defence, the rival's attack, the
/// player's midfield, the rival's midfield, the player's attack, the rival's
/// defence and keeper. The finger slides all of the player's rods sideways;
/// a tap kicks with the man in front of the ball.
class FoosLevel {
  final ArcadeMeta meta;
  final int difficulty;
  final int theme;
  const FoosLevel(this.meta, this.difficulty, this.theme);
}

FoosLevel generateFoos(LevelSpec spec) => FoosLevel(ArcadeMeta.of(spec), spec.difficulty.clamp(1, 10), spec.theme % 4);

const double kL = 150, kR = 850, kT = 180, kB = 1420, kMid = 800;
const double kGoalHalf = 150, kBallR = 22, kManR = 26;
const double _friction = 0.992, _vMax = 34;

class Rod {
  final double y;
  final int owner; // 0 player, 1 rival
  final List<double> bases;
  final double range;
  const Rod(this.y, this.owner, this.bases, this.range);
}

const kRods = <Rod>[
  Rod(1360, 0, [500], 170),
  Rod(1210, 0, [340, 660], 160),
  Rod(1060, 1, [280, 500, 720], 110),
  Rod(910, 0, [200, 350, 500, 650, 800], 50),
  Rod(690, 1, [200, 350, 500, 650, 800], 50),
  Rod(540, 0, [280, 500, 720], 110),
  Rod(390, 1, [340, 660], 160),
  Rod(240, 1, [500], 170),
];

class FoosSim extends ArcadeSim implements DuelSim {
  final FoosLevel level;
  double bx = 500, by = kMid, vx = 0, vy = 0;
  final off = List<double>.filled(kRods.length, 0);
  final ov = List<double>.filled(kRods.length, 0);
  int kick = 0, cpuKick = 0, boost = 0, pause = 0, idle = 0, zone = -1;
  bool kicked = true, cpuKicked = true;
  int myGoals = 0, cpuGoals = 0, toWin = 3;
  int goalsScored = 0, goalsConceded = 0, matchesWon = 0, shots = 0, bestStreak = 0, streak = 0;
  int lastEvent = 0; // 1 kick, 2 goal for, 3 goal against, 4 bounce
  String flash = '';
  int flashTicks = 0;

  /// Çevrimiçi düello: rakip çubuklarını karşıdaki oyuncu sürer (null: yapay zekâ).
  ArcadeInput? _rival;
  bool duel = false;

  FoosSim(this.level) : super(level.meta, lives: 3) {
    _setupMatch();
  }

  int get d => level.difficulty;
  bool get matchMode => meta.goal;

  void _setupMatch() {
    myGoals = 0;
    cpuGoals = 0;
    toWin = d <= 3 ? 3 : (d <= 7 ? 4 : 5);
    _faceOff(0);
  }

  double _rnd(int k) => SeededRandom(mixSeed([meta.seed, ticks, k, 83])).nextDouble();

  /// Ball dropped at the centre, rolling toward the side that conceded.
  void _faceOff(int side) {
    bx = 500;
    by = kMid;
    vx = (_rnd(5) - 0.5) * 4;
    vy = side == 1 ? 6.0 : -6.0;
    pause = 40;
    idle = 0;
  }

  void _say(String s) {
    flash = s;
    flashTicks = 60;
  }

  /// (x, y) of every man on rod [i].
  Iterable<(double, double)> men(int i) sync* {
    final r = kRods[i];
    for (final b in r.bases) {
      yield (b + off[i], r.y);
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flashTicks > 0) flashTicks--;
    if (kick > 0) kick--;
    if (cpuKick > 0) cpuKick--;
    if (boost > 0) boost--;
    if ((input.tap || input.swipe == 0) && kick == 0) {
      kick = 8;
      kicked = false;
    }
    final rawRival = _rival;
    final rival = rawRival == null ? null : mirrorInput(rawRival);
    if (rival != null && (rival.tap || rival.swipe == 0) && cpuKick == 0) {
      cpuKick = 8;
      cpuKicked = false;
    }
    final hasX = input.down && input.hasPointer;
    for (var i = 0; i < kRods.length; i++) {
      final r = kRods[i];
      double n;
      if (r.owner == 0) {
        var t = off[i];
        if (hasX) t = clampD(input.x - 500, -r.range, r.range);
        if (input.dirX != 0) t = clampD(off[i] + input.dirX * 30, -r.range, r.range);
        n = moveToward(off[i], t, 32);
      } else if (rival != null) {
        // Karşıdaki oyuncu: kendi ekranındaki parmak, masada aynalanmış.
        var t = off[i];
        if (rival.down && rival.hasPointer) t = clampD(rival.x - 500, -r.range, r.range);
        if (rival.dirX != 0) t = clampD(off[i] + rival.dirX * 30, -r.range, r.range);
        n = moveToward(off[i], t, 32);
      } else {
        n = moveToward(off[i], _cpuTarget(i), 3.5 + d * 0.6);
      }
      ov[i] = n - off[i];
      off[i] = n;
    }
    if (rival == null) _cpuKick();
    if (pause > 0) {
      pause--;
      return;
    }
    _step();
  }

  double _cpuTarget(int i) {
    final r = kRods[i];
    var err = (_rnd(i + 40) - 0.5) * (120 - d * 5);
    var dx = 0.0;
    if (by > r.y - 60) {
      dx = shotOffset(this, 1) + err * 0.3;
      err = 0;
    }
    var best = r.bases.first;
    for (final b in r.bases) {
      if ((b + off[i] - bx).abs() < (best + off[i] - bx).abs()) best = b;
    }
    return clampD(bx - dx - best + err, -r.range, r.range);
  }

  void _cpuKick() {
    if (cpuKick > 0) return;
    var inz = -1;
    for (var i = 0; i < kRods.length; i++) {
      if (kRods[i].owner != 1) continue;
      for (final (mx, my) in men(i)) {
        if (by - my > 0 && by - my < 60 && (bx - mx).abs() < 44) inz = i;
      }
    }
    if (inz < 0) {
      zone = -1;
      return;
    }
    if (inz == zone) return;
    zone = inz;
    final p = (inz == 2 || inz == 4 ? 0.55 : 0.3) + d * 0.04;
    if (_rnd(20 + inz) < p) {
      cpuKick = 8;
      cpuKicked = false;
    }
  }

  bool _kickZone(int owner) {
    final fwd = owner == 0 ? -1.0 : 1.0;
    for (var i = 0; i < kRods.length; i++) {
      if (kRods[i].owner != owner) continue;
      for (final (mx, my) in men(i)) {
        final dy = (by - my) * fwd;
        final dx = bx - mx;
        if (dy > -8 && dy < 66 && dx.abs() < 44) {
          final sp = owner == 0 ? 30.0 + (boost > 0 ? 8 : 0) : (_rival != null ? 30.0 : 20.0 + d);
          final ax = clampD(dx / 44 * 1.1 + ov[i] * 0.03, -1.2, 1.2);
          final n = math.sqrt(ax * ax + 1);
          vx = sp * ax / n;
          vy = sp * fwd / n;
          by = my + fwd * math.max(dy, kBallR + kManR);
          lastEvent = 1;
          if (owner == 0) shots++;
          return true;
        }
      }
    }
    return false;
  }

  void _step() {
    if (kick > 0 && !kicked && _kickZone(0)) kicked = true;
    if (cpuKick > 0 && !cpuKicked && _kickZone(1)) cpuKicked = true;
    const steps = 3;
    for (var k = 0; k < steps; k++) {
      bx += vx / steps;
      by += vy / steps;
      for (var i = 0; i < kRods.length; i++) {
        for (final (mx, my) in men(i)) {
          _collide(mx, my, ov[i]);
        }
      }
      if (bx < kL + kBallR) {
        bx = kL + kBallR;
        vx = vx.abs() * 0.85;
        lastEvent = 4;
      }
      if (bx > kR - kBallR) {
        bx = kR - kBallR;
        vx = -vx.abs() * 0.85;
        lastEvent = 4;
      }
      final inGoal = (bx - 500).abs() < kGoalHalf - kBallR * 0.3;
      if (by < kT + kBallR) {
        if (inGoal) {
          if (by < kT - kBallR) {
            _point(true);
            return;
          }
        } else {
          by = kT + kBallR;
          vy = vy.abs() * 0.85;
          lastEvent = 4;
        }
      }
      if (by > kB - kBallR) {
        if (inGoal) {
          if (by > kB + kBallR) {
            _point(false);
            return;
          }
        } else {
          by = kB - kBallR;
          vy = -vy.abs() * 0.85;
          lastEvent = 4;
        }
      }
    }
    vx *= _friction;
    vy *= _friction;
    if (math.sqrt(vx * vx + vy * vy) < 0.5) {
      idle++;
      if (idle > 120) _faceOff(by > kMid ? 0 : 1);
    } else {
      idle = 0;
    }
  }

  void _collide(double mx, double my, double mvx) {
    final dx = bx - mx, dy = by - my;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist >= kBallR + kManR || dist == 0) return;
    final nx = dx / dist, ny = dy / dist;
    bx = mx + nx * (kBallR + kManR);
    by = my + ny * (kBallR + kManR);
    final rvx = vx - mvx, rvy = vy;
    final dot = rvx * nx + rvy * ny;
    if (dot < 0) {
      vx -= 1.6 * dot * nx;
      vy -= 1.6 * dot * ny;
    }
    vx += mvx * 0.3;
    final sp = math.sqrt(vx * vx + vy * vy);
    if (sp > _vMax) {
      vx *= _vMax / sp;
      vy *= _vMax / sp;
    }
  }

  void _point(bool mine) {
    if (mine) {
      myGoals++;
      goalsScored++;
      streak++;
      bestStreak = math.max(bestStreak, streak);
      score += 100 + d * 10;
      lastEvent = 2;
      _say('GOAL!');
    } else {
      cpuGoals++;
      goalsConceded++;
      streak = 0;
      lastEvent = 3;
      _say('GOAL ×');
    }
    if (!matchMode) {
      _faceOff(mine ? 1 : 0);
      if (!mine) {
        shield = 0;
        hit();
      }
      return;
    }
    if (myGoals >= toWin) {
      matchesWon++;
      score += 500;
      win();
      return;
    }
    if (cpuGoals >= toWin) {
      if (meta.zen) {
        _setupMatch();
        return;
      }
      shield = 0;
      hit();
      return;
    }
    _faceOff(mine ? 1 : 0);
  }

  // ---- DuelSim ----

  @override
  set rivalInput(ArcadeInput? input) => _rival = input;

  @override
  void enableDuel() {
    duel = true;
    lives = 1;
  }

  @override
  int get duelWinner => won ? 0 : (dead ? 1 : -1);

  @override
  List<double> netState() => [
        ticks.toDouble(), bx, by, vx, vy, ...off, ...ov, //
        kick.toDouble(), cpuKick.toDouble(), boost.toDouble(), pause.toDouble(), idle.toDouble(), zone.toDouble(),
        kicked ? 1.0 : 0.0, cpuKicked ? 1.0 : 0.0,
        myGoals.toDouble(), cpuGoals.toDouble(), toWin.toDouble(),
        flashCode(flash, _flashes).toDouble(), flashTicks.toDouble(), lastEvent.toDouble(), score.toDouble(),
        won ? 1.0 : 0.0, dead ? 1.0 : 0.0,
      ];

  @override
  void applyNetState(List<double> s) {
    const k = 5 + 2 * 8;
    if (s.length < k + 17) return;
    int n(int i) => s[i].round();
    ticks = n(0);
    bx = s[1];
    by = s[2];
    vx = s[3];
    vy = s[4];
    for (var i = 0; i < kRods.length; i++) {
      off[i] = s[5 + i];
      ov[i] = s[13 + i];
    }
    kick = n(k);
    cpuKick = n(k + 1);
    boost = n(k + 2);
    pause = n(k + 3);
    idle = n(k + 4);
    zone = n(k + 5);
    kicked = s[k + 6] > 0.5;
    cpuKicked = s[k + 7] > 0.5;
    myGoals = n(k + 8);
    cpuGoals = n(k + 9);
    toWin = n(k + 10);
    flash = _flashes[n(k + 11).clamp(0, _flashes.length - 1)];
    flashTicks = n(k + 12);
    lastEvent = n(k + 13);
    score = n(k + 14);
    if (s[k + 15] > 0.5 && !won) win();
    if (s[k + 16] > 0.5 && !dead) {
      lives = 1;
      shield = 0;
      hit();
    }
  }

  @override
  List<double> lerpNet(List<double> a, List<double> b, double f) =>
      lerpAt(a, b, f, const [1, 2, 5, 6, 7, 8, 9, 10, 11, 12]);

  @override
  void mirrorView() {
    bx = kWorldW - bx;
    by = kWorldH - by;
    vx = -vx;
    vy = -vy;
    final o = List<double>.of(off), v = List<double>.of(ov);
    final last = kRods.length - 1;
    for (var i = 0; i < kRods.length; i++) {
      off[i] = -o[last - i];
      ov[i] = -v[last - i];
    }
    final k = kick, kd = kicked;
    kick = cpuKick;
    kicked = cpuKicked;
    cpuKick = k;
    cpuKicked = kd;
    final g = myGoals;
    myGoals = cpuGoals;
    cpuGoals = g;
    if (lastEvent == 2) {
      lastEvent = 3;
    } else if (lastEvent == 3) {
      lastEvent = 2;
    }
    if (flash == 'GOAL!') {
      flash = 'GOAL ×';
    } else if (flash == 'GOAL ×') {
      flash = 'GOAL!';
    }
  }

  @override
  void onLifeLost() {
    if (matchMode) {
      _setupMatch();
    } else {
      _faceOff(0);
    }
  }

  @override
  bool useBooster() {
    // Super shot: harder kicks for ten seconds.
    if (over) return false;
    boost = 600;
    return true;
  }

  @override
  double get progress => matchMode ? (myGoals / toWin).clamp(0.0, 1.0) : 0;

  @override
  String get goalText => matchMode ? '$myGoals-$cpuGoals' : '$goalsScored';

  @override
  Map<String, int> get stats => {
        'goals_scored': goalsScored,
        'matches_won': matchesWon,
        'shots': shots,
        'best_streak': bestStreak,
      };

  @override
  int get stars {
    if (!won) return 0;
    final q = cpuGoals == 0 ? 3 : (cpuGoals <= toWin ~/ 2 ? 2 : 1);
    return math.min(lifeStars(this, 3), q);
  }
}

const _flashes = ['', 'GOAL!', 'GOAL ×'];

/// x of a straight path at height [y], with side-rail reflections.
double pathX(double x0, double y0, double ax, double y) {
  final x = x0 + ax * (y0 - y).abs();
  const w = kR - kL - 2 * kBallR;
  final u = (x - (kL + kBallR)) % (2 * w);
  return kL + kBallR + (u <= w ? u : 2 * w - u);
}

/// Best contact offset for a shot by [owner]: the path that passes furthest
/// from the opposing men and still ends inside the goal.
double shotOffset(FoosSim s, int owner) {
  var bestScore = -1e9, bestDx = 0.0;
  final opp = <(double, double)>[];
  for (var i = 0; i < kRods.length; i++) {
    final r = kRods[i];
    if (r.owner == owner) continue;
    if (owner == 0 ? r.y < s.by : r.y > s.by) opp.addAll(s.men(i));
  }
  for (var k = -8; k <= 8; k++) {
    final dx = k * 5.0;
    final ax = dx / 44 * 1.1;
    var score = 1e9;
    for (final (cx, cy) in opp) {
      score = math.min(score, (pathX(s.bx, s.by, ax, cy) - cx).abs() - (kBallR + kManR));
    }
    final gx = pathX(s.bx, s.by, ax, owner == 0 ? kT : kB);
    score = math.min(score, (kGoalHalf - kBallR) - (gx - 500).abs());
    if (score > bestScore) {
      bestScore = score;
      bestDx = dx;
    }
  }
  return bestDx;
}

/// Autopilot: lines up the man just behind the ball for the best shot and
/// taps when the ball is in front of him.
ArcadeInput foosBot(ArcadeSim sim) {
  final s = sim as FoosSim;
  var rod = 5;
  double? best;
  for (var i = 0; i < kRods.length; i++) {
    if (kRods[i].owner != 0) continue;
    final dy = kRods[i].y - s.by;
    if (dy > -10 && (best == null || dy < best)) {
      best = dy;
      rod = i;
    }
  }
  final dy = best ?? 0;
  final r = kRods[rod];
  final dx = shotOffset(s, 0);
  var off = 0.0, err = 1e9;
  for (final b in r.bases) {
    final o = clampD(s.bx - dx - b, -r.range, r.range);
    final e = (s.bx - dx - (b + o)).abs();
    if (e < err) {
      err = e;
      off = o;
    }
  }
  final tap = dy > 0 && dy < 60 && s.kick == 0 && s.ov[rod].abs() < 1;
  return ArcadeInput(down: true, x: (500 + off).roundToDouble(), y: 1500, tap: tap);
}
