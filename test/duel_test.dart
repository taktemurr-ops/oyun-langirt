import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_langirt/src/foos_engine.dart';
import 'package:oyun_langirt/src/rules.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/net_sync.dart';

/// Çevrimiçi düello: durum yazımı, ayna görünüm, karşı oyuncunun çubukları
/// ve ev sahibi → misafir eşitlemesi (devralma dahil).
void main() {
  final rules = FoosRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);
  FoosSim duel([int n = 5]) => FoosSim(rules.build(planner.spec(n)).puzzle)..enableDuel();

  ArcadeInput rivalBot(FoosSim s) {
    final m = FoosSim(s.level)
      ..applyNetState(s.netState())
      ..mirrorView();
    return foosBot(m);
  }

  test('iki kişilik oyun: çevrimiçi masa açık', () {
    expect(rules.localPlayers, 2);
  });

  test('durum yazılıp okununca aynı durum', () {
    final s = duel();
    for (var i = 0; i < 500; i++) {
      s.rivalInput = rivalBot(s);
      s.tick(foosBot(s));
    }
    final wire = encodeNums(s.netState());
    final copy = duel()..applyNetState(decodeNums(wire));
    expect(encodeNums(copy.netState()), wire);
  });

  test('ayna görünüm: çubuklar ve skorlar yer değiştirir, iki kez uygulanınca aynı', () {
    final s = duel();
    s.off[0] = 40; // oyuncunun kalecisi
    s.off[7] = -25; // rakibin kalecisi
    s.myGoals = 3;
    s.bx = 420;
    final before = encodeNums(s.netState());
    s.mirrorView();
    expect(s.off[7], -40);
    expect(s.off[0], 25);
    expect(s.cpuGoals, 3);
    expect(s.bx, kWorldW - 420);
    s.mirrorView();
    expect(encodeNums(s.netState()), before);
  });

  test('karşı oyuncunun parmağı rakip çubuklarını ters masada sürer ve şut çeker', () {
    final s = duel();
    for (var i = 0; i < 40; i++) {
      s.rivalInput = const ArcadeInput(down: true, x: 300, y: 1500);
      s.tick(const ArcadeInput(down: true, x: 500, y: 1500));
    }
    // ekranında 300 → masada 700: rakip çubukları sağa (sınırına kadar) kayar
    expect(s.off[7], 170);
    expect(s.off[4], 50);
    expect(s.off[0], 0);
    s.rivalInput = const ArcadeInput(down: true, x: 300, y: 1500, tap: true);
    s.tick(const ArcadeInput(down: true, x: 500, y: 1500));
    expect(s.cpuKick, greaterThan(0));
  });

  test('rakip maçı alınca düello biter', () {
    final s = duel();
    s.cpuGoals = s.toWin - 1;
    s.pause = 0;
    s.bx = 600;
    s.by = 1395;
    s.vx = 0;
    s.vy = 20;
    for (var i = 0; i < 20 && !s.over; i++) {
      s.rivalInput = ArcadeInput.idle;
      s.tick(ArcadeInput.idle);
    }
    expect(s.duelWinner, 1);
  });

  test('ev sahibi düşünce misafir son durumdan sürer', () {
    final host = duel(), guestSim = duel();
    final toGuest = <String>[];
    var now = 0;
    final hostSync = NetSync(mySeat: 0, seats: 2, humans: {0, 1}, send: toGuest.add);
    final gs = NetSync(mySeat: 1, seats: 2, humans: {0, 1}, send: (d) => hostSync.receive(1, d, now));
    var took = false;
    var tickAtTake = 0;
    for (var frame = 0; frame < 60 * 20; frame++) {
      now = frame * 1000 ~/ 60;
      gs.setAxes([1, 400, 1500, 0, 0]);
      gs.pump(now);
      if (frame < 60 * 2 && !host.over) {
        final a = hostSync.axesOf(1);
        host.rivalInput = a == null ? null : ArcadeInput(down: a[0] > 0.5, x: a[1], y: a[2]);
        host.tick(foosBot(host));
        hostSync.publish((host.ticks * 1000 / 60).round(), encodeNums(host.netState()), now);
      }
      for (final m in toGuest) {
        gs.receive(0, m, now);
      }
      toGuest.clear();
      if (!took && gs.checkTakeover(now)) {
        took = true;
        guestSim.applyNetState(decodeNums(gs.latest!.payload));
        tickAtTake = guestSim.ticks;
      }
      if (took && !guestSim.over) {
        guestSim.rivalInput = const ArcadeInput(down: true, x: 400, y: 1500);
        guestSim.tick(foosBot(guestSim));
      }
    }
    expect(took, isTrue);
    expect(tickAtTake, greaterThan(60));
    expect(guestSim.ticks, greaterThan(tickAtTake));
    // misafirin parmağı (ekranında 400 → masada 600) rakip çubuklarını sağa almıştı
    expect(guestSim.off[7], closeTo(100, 0.01));
  });
}
