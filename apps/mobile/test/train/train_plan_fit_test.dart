import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/domain/energy.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/muscle_recovery.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import 'program_test_support.dart';
import '../support/health_overview_fixtures.dart';

class _Actions implements WorkoutActions {
  final started = <({String? expected, String? swap})>[];

  @override
  startProgramDay(
    TrainingProgramRecord program, {
    required String? expectedPlanUuid,
    DateTime? missedDate,
    String? swapPlanUuid,
  }) {
    started.add((expected: expectedPlanUuid, swap: swapPlanUuid));
    throw StateError('synthetic: stop before navigation');
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

class _Failing extends FakeHealthOverviewController {
  _Failing() : super(null);

  @override
  Future<HealthOverview?> build() async => throw StateError('read failed');
}

Section<ReadinessOverview> _ready(int value) => SectionData(
  ReadinessOverview(
    result: ReadinessReady(
      Readiness(
        value: value,
        band: readinessBandOf(value),
        parts: const [
          ReadinessPart(input: ReadinessInput.hrv, score: 40, weight: .5),
          ReadinessPart(input: ReadinessInput.sleep, score: 50, weight: .5),
        ],
      ),
    ),
    hasHrv: true,
    hasRestingHr: false,
    hasSleep: true,
    hrvVsNormal: null,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  ),
);

final _nowUtc = DateTime.utc(2026, 11, 24, 12);

CatalogDefinitionInput _def(
  String id,
  String group, {
  List<String> primary = const [],
}) => (
  id: id,
  name: 'Move $id',
  muscleGroup: group,
  equipment: 'Barbell',
  category: 'push_horizontal',
  mode: 'reps_load',
  primaryMuscles: primary,
  secondaryMuscles: const [],
);

TemplateWorkoutSource _workout(
  String name,
  List<(CatalogDefinitionInput, int)> rows,
) => TemplateWorkoutSource(
  name: name,
  description: '',
  release: 4,
  rows: [
    for (final (def, sets) in rows)
      (
        exercise: def,
        sets: sets,
        repsMin: 8,
        repsMax: 10,
        durationSeconds: null,
        restSeconds: 90,
        note: '',
      ),
  ],
);

final _bench = _def('bench', 'Chest');
final _squat = _def('squat', 'Legs');
final _plank = _def('plank', 'Core');
final _stretch = _def('stretch', 'Mobility');
final _row = _def('row', 'Back');

final _push = _workout('Push day', [(_bench, 8)]);
final _legs = _workout('Leg day', [(_squat, 12)]);
final _core = _workout('Core day', [(_plank, 4)]);
final _mobility = _workout('Mobility day', [(_stretch, 3)]);

/// A completed workout of [group] finished [hoursAgo] before [_nowUtc].
WorkoutSessionRecord _done(String group, int hoursAgo) {
  final at = _nowUtc.subtract(Duration(hours: hoursAgo));
  return WorkoutSessionRecord(
    uuid: 'done-$group',
    name: 'Done',
    status: WorkoutStatus.completed,
    startedAtUtc: at.subtract(const Duration(minutes: 40)),
    completedAtUtc: at,
    originalOffsetMinutes: 0,
    revision: 1,
    exercises: [
      WorkoutExerciseRecord(
        uuid: 'e',
        sessionUuid: 'done-$group',
        nameSnapshot: 'Move',
        muscleSnapshot: group,
        position: 0,
      ),
    ],
    sets: [
      for (var i = 0; i < 10; i++)
        WorkoutSetRecord(
          uuid: 's$i',
          exerciseUuid: 'e',
          position: i,
          kind: WorkoutSetKind.working,
          status: WorkoutSetStatus.completed,
          reps: 10,
          rpe: 8,
          completedAtUtc: at,
        ),
    ],
  );
}

late _Actions _actions;
late Directory _directory;
late Store _store;

/// Seeds an active program (first day Tuesday, so today, Tuesday 24 November,
/// is its first day) and opens Your program.
Future<void> _pump(
  WidgetTester tester, {
  required List<TemplateWorkoutSource> workouts,
  List<int?>? week,
  bool active = true,
  Object? history, // a snapshot, or an error to throw
  MuscleRecovery? recovery,
  FakeHealthOverviewController? health,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  void Function()? afterSeed,
}) async {
  _actions = _Actions();
  final created = ObjectBoxProgramRepository(_store).createProgram(
    requestUuid: 'fit-program',
    name: 'Fit program',
    description: '',
    workouts: workouts,
    week: week ?? [for (var i = 0; i < 7; i++) i < workouts.length ? i : null],
    firstDayWeekday: 2,
    makeActive: active,
    localToday: DateTime(2026, 11, 24),
  );
  afterSeed?.call();
  await pumpPrograms(
    tester,
    store: _store,
    directory: _directory,
    initial: '/train/program/${created.uuid}',
    now: DateTime(2026, 11, 24, 9),
    textScale: textScale,
    brightness: brightness,
    health: health,
    overrides: [
      progressNowProvider.overrideWithValue(_nowUtc),
      workoutActionsProvider.overrideWithValue(_actions),
      completedWorkoutHistoryProvider.overrideWith((ref) async {
        if (history is WorkoutHistorySnapshot) return history;
        throw StateError('history failed');
      }),
      activeWorkoutProvider.overrideWith(
        (ref) => const AsyncData<ActiveWorkoutView?>(null),
      ),
      if (recovery != null) muscleRecoveryProvider.overrideWithValue(recovery),
    ],
  );
  tester.view.physicalSize = Size(390, textScale > 1 ? 4000 : 2400);
  await tester.pumpAndSettle();
}

// Plan fit needs some history; the recovery itself is overridden.
WorkoutHistorySnapshot _anyHistory() =>
    WorkoutHistorySnapshot(sessions: [_done('Chest', 100)]);

WorkoutHistorySnapshot _chestDone() =>
    WorkoutHistorySnapshot(sessions: [_done('Chest', 6)]);

void main() {
  setUp(() {
    _directory = Directory.systemTemp.createTempSync('beyondrep-fit-');
    _store = Store(getObjectBoxModel(), directory: _directory.path);
  });

  tearDown(() {
    _store.close();
    _directory.deleteSync(recursive: true);
  });

  String planUuidNamed(String name) =>
      ObjectBoxProgramRepository(_store)
          .programPlans('fit-program')
          .firstWhere((p) => p.name == name)
          .uuid;

  testWidgets('a clear winner shows the card with reason and Start', (
    tester,
  ) async {
    await _pump(tester, workouts: [_push, _legs], history: _chestDone());
    expect(find.text('Better fit today'), findsOneWidget);
    expect(
      find.text('Chest still recovering · this workout rests them'),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Chest still recovering · this workout')),
      findsOneWidget,
    );
  });

  testWidgets('Start on the card swaps in the suggested workout', (
    tester,
  ) async {
    await _pump(tester, workouts: [_push, _legs], history: _chestDone());
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(_actions.started.single.swap, planUuidNamed('Leg day'));
    expect(_actions.started.single.expected, planUuidNamed('Push day'));
  });

  testWidgets('no card when the suggestion is today\'s own workout', (
    tester,
  ) async {
    await _pump(tester, workouts: [_legs, _push], history: _chestDone());
    expect(find.text('Better fit today'), findsNothing);
  });

  testWidgets('an inactive program shows no card', (tester) async {
    await _pump(
      tester,
      workouts: [_push, _legs],
      active: false,
      history: _chestDone(),
    );
    expect(find.text('Better fit today'), findsNothing);
  });

  testWidgets('saved workouts outside the program are never suggested', (
    tester,
  ) async {
    await _pump(
      tester,
      workouts: [_push, _legs],
      history: _chestDone(),
      afterSeed: () => ObjectBoxWorkoutLibraryRepository(_store).savePlan(
        uuid: 'own',
        name: 'Standalone legs',
        description: '',
        exercises: const [
          PlanExerciseRecord(
            uuid: 'own-0',
            exerciseUuid: 'squat',
            position: 0,
            targetSets: 12,
            targetRepsMin: 8,
            targetRepsMax: 10,
          ),
        ],
      ),
    );
    // An identical saved workout would tie with Leg day and hide the card.
    expect(find.text('Better fit today'), findsOneWidget);
    expect(find.text('Standalone legs'), findsNothing);
  });

  testWidgets('workouts of backfilled built-ins name specific muscles', (
    tester,
  ) async {
    final rdl = _def('rdl', 'Legs', primary: ['hamstrings', 'glutes']);
    final bench = _def('bench2', 'Chest', primary: ['chest']);
    final rdlDone = _done('Legs', 6);
    final session = WorkoutSessionRecord(
      uuid: rdlDone.uuid,
      name: rdlDone.name,
      status: rdlDone.status,
      startedAtUtc: rdlDone.startedAtUtc,
      completedAtUtc: rdlDone.completedAtUtc,
      originalOffsetMinutes: 0,
      revision: 1,
      exercises: [
        WorkoutExerciseRecord(
          uuid: 'e',
          sessionUuid: rdlDone.uuid,
          nameSnapshot: 'Romanian deadlift',
          muscleSnapshot: 'Legs',
          position: 0,
          primaryMusclesSnapshot: const ['hamstrings', 'glutes'],
        ),
      ],
      sets: rdlDone.sets,
    );
    await _pump(
      tester,
      workouts: [
        _workout('RDL day', [(rdl, 9)]),
        _workout('Push', [(bench, 8)]),
      ],
      week: const [0, 1, null, null, null, null, null],
      history: WorkoutHistorySnapshot(sessions: [session]),
    );
    expect(find.text('Better fit today'), findsOneWidget);
    expect(find.textContaining('Hamstrings'), findsWidgets);
    expect(find.textContaining('Legs still recovering'), findsNothing);
  });

  testWidgets('a low readiness day picks the lightest recovered workout', (
    tester,
  ) async {
    await _pump(
      tester,
      workouts: [_push, _legs, _core],
      history: _chestDone(),
      health: FakeHealthOverviewController(overview(readiness: _ready(48))),
    );
    expect(find.text('Better fit today'), findsOneWidget);
    expect(
      find.text(
        'Lightest workout with recovered muscles · keep effort around RPE 7',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(_actions.started.single.swap, planUuidNamed('Core day'));
  });

  testWidgets('good start drained to low energy picks the lightest workout', (
    tester,
  ) async {
    final start = _ready(80);
    await _pump(
      tester,
      workouts: [_push, _legs, _core],
      history: _chestDone(),
      health: FakeHealthOverviewController(
        overview(
          readiness: start,
          energy: energySection(
            start,
            energy: Energy(
              value: 45,
              band: readinessBandOf(45),
              start: 80,
              items: const [],
            ),
            wake: DateTime(2026, 11, 24, 6, 31),
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Lightest workout with recovered muscles · keep effort around RPE 7',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a low start without energy does not use the low rule', (
    tester,
  ) async {
    final start = _ready(40);
    await _pump(
      tester,
      workouts: [_push, _legs, _core],
      history: _chestDone(),
      health: FakeHealthOverviewController(
        overview(
          readiness: start,
          energy: SectionData(
            EnergyOverview(
              day: DateTime(2026, 11, 24),
              wake: null,
              start: (start as SectionData<ReadinessOverview>).value,
              energy: null,
              learning: const EnergyLearning(),
            ),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Lightest workout with recovered muscles'),
      findsNothing,
    );
  });

  testWidgets('day rows read Recovered and Legs recovering', (tester) async {
    await _pump(
      tester,
      workouts: [_push, _legs],
      history: WorkoutHistorySnapshot(sessions: [_done('Legs', 6)]),
    );
    expect(find.text('Day 1\nRecovered'), findsOneWidget);
    expect(find.text('Day 2\nLegs recovering'), findsOneWidget);
  });

  testWidgets('four recovering groups read "A, B, C and more"', (tester) async {
    final all = _workout('Everything', [
      (_bench, 3),
      (_squat, 3),
      (_plank, 3),
      (_row, 3),
    ]);
    await _pump(
      tester,
      workouts: [all],
      history: _anyHistory(),
      recovery: const MuscleRecovery({
        Muscle.chest: 0.5,
        Muscle.quads: 0.5,
        Muscle.abs: 0.5,
        Muscle.lats: 0.5,
      }),
    );
    expect(
      find.textContaining('Back, Chest, Core and more recovering'),
      findsOneWidget,
    );
  });

  testWidgets('a group at 0.09 reads Recovered, at 0.11 recovering', (
    tester,
  ) async {
    await _pump(
      tester,
      workouts: [_legs],
      history: _anyHistory(),
      recovery: const MuscleRecovery(
        {Muscle.quads: 0.09, Muscle.hamstrings: 0.09},
        groups: {'Legs': 0.09},
      ),
    );
    expect(find.text('Day 1\nRecovered'), findsOneWidget);
  });

  testWidgets('a group at 0.11 reads recovering', (tester) async {
    await _pump(
      tester,
      workouts: [_legs],
      history: _anyHistory(),
      recovery: const MuscleRecovery(
        {Muscle.quads: 0.11},
        groups: {'Legs': 0.11},
      ),
    );
    expect(find.text('Day 1\nLegs recovering'), findsOneWidget);
  });

  testWidgets('yesterday\'s low readiness does not pick the lightest workout', (
    tester,
  ) async {
    await _pump(
      tester,
      workouts: [_push, _legs],
      history: _chestDone(),
      health: FakeHealthOverviewController(
        overview(readiness: _ready(48), readAt: DateTime(2026, 11, 23, 20)),
      ),
    );
    expect(find.textContaining('Lightest workout'), findsNothing);
    expect(find.text('Better fit today'), findsOneWidget);
    expect(
      find.text('Chest still recovering · this workout rests them'),
      findsOneWidget,
    );
  });

  testWidgets('no completed workouts shows no card and no lines', (
    tester,
  ) async {
    await _pump(
      tester,
      workouts: [_legs],
      history: const WorkoutHistorySnapshot(sessions: []),
    );
    expect(find.text('Better fit today'), findsNothing);
    expect(find.textContaining('Recovered'), findsNothing);
    expect(find.textContaining('recovering'), findsNothing);
  });

  testWidgets('a history error shows no card and no lines', (tester) async {
    await _pump(tester, workouts: [_push, _legs], history: StateError('x'));
    expect(find.text('Better fit today'), findsNothing);
    expect(find.textContaining('Recovered'), findsNothing);
    expect(find.textContaining('recovering'), findsNothing);
    expect(find.text('Tuesday · Push day'), findsOneWidget);
  });

  testWidgets('a workout with only unmapped muscles gets no line', (
    tester,
  ) async {
    await _pump(tester, workouts: [_push, _mobility], history: _chestDone());
    expect(find.textContaining('Chest recovering'), findsOneWidget);
    final row = find.ancestor(
      of: find.text('Wednesday · Mobility day'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: row.first, matching: find.textContaining('ecover')),
      findsNothing,
    );
  });

  testWidgets('a health overview error still shows plan fit', (tester) async {
    await _pump(
      tester,
      workouts: [_push, _legs],
      history: _chestDone(),
      health: _Failing(),
    );
    expect(find.text('Better fit today'), findsOneWidget);
    expect(find.textContaining('Chest recovering'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('fits 2x text at 390 px, $brightness', (tester) async {
      await _pump(
        tester,
        workouts: [_push, _legs],
        history: _chestDone(),
        textScale: 2,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Better fit today'), findsOneWidget);
    });
  }
}
