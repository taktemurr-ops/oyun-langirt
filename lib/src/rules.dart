import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import 'foos_engine.dart';

class FoosRules extends ArcadeRules<FoosLevel> {
  @override
  String get gameId => 'oyun-langirt';

  @override
  List<String> get optionalMechanics => const [];

  /// İki kişilik: "Bilgisayara karşı" ve "Çevrimiçi masa" (gerçek zamanlı düello).
  @override
  int get localPlayers => 2;

  @override
  List<GameStat> get gameStats => const [
        GameStat('goals_scored', 'Atılan gol', 'Goals scored', scale: 500),
        GameStat('matches_won', 'Kazanılan maç', 'Matches won', scale: 40),
        GameStat('shots', 'Şut', 'Shots', scale: 1000),
        GameStat('best_streak', 'Üst üste gol', 'Goal streak', scale: 20),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('goals_scored', 'goals_scored', [40, 80, 160]),
        MissionTemplate('matches_won', 'matches_won', [5, 10, 20], coinReward: 80),
      ];

  @override
  int maxTicks(FoosLevel level) => 60 * 60 * 10;

  @override
  FoosLevel generate(LevelSpec spec) => generateFoos(spec);

  @override
  ArcadeMeta metaOf(FoosLevel l) => l.meta;

  @override
  ArcadeSim createSim(FoosLevel l) => FoosSim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => foosBot(sim);
}

ArcadeRules createRules() => FoosRules();
