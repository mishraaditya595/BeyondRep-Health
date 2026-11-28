import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/train/create_program_page.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';
import 'template_test_support.dart';

/// Stands in for the workout editor: returns a fixed draft.
class _StubEditor extends StatelessWidget {
  const _StubEditor({required this.seen, required this.name});

  final List<DraftWorkoutSource?> seen;
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => context.pop(
          DraftWorkoutSource(
            name: name,
            description: '',
            rows: const [
              PlanExerciseRecord(
                uuid: 'row',
                exerciseUuid: 'builtin.v1.synthetic-move-1',
                position: 0,
                targetSets: 3,
                targetRepsMin: 8,
                targetRepsMax: 10,
                restSeconds: 90,
              ),
            ],
          ),
        ),
        child: const Text('Return draft'),
      ),
    ),
  );
}

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-create-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    final e = templatesSnapshot().exercises.first;
    ObjectBoxWorkoutLibraryRepository(store).materializeCatalogExercise(
      id: e.id,
      name: e.name,
      muscleGroup: e.muscleGroup,
      equipment: 'Barbell',
      category: e.category,
      mode: e.mode,
      release: 3,
      primaryMuscles: e.primaryMuscles,
      secondaryMuscles: e.secondaryMuscles,
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<List<DraftWorkoutSource?>> pump(
    WidgetTester tester, {
    String editorName = 'Push day',
  }) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seen = <DraftWorkoutSource?>[];
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/train/programs/new'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/train/programs/new',
          builder: (_, _) => const CreateProgramPage(),
        ),
        GoRoute(
          path: '/train/programs/new/workout',
          builder: (_, state) {
            seen.add(state.extra as DraftWorkoutSource?);
            return _StubEditor(seen: seen, name: editorName);
          },
        ),
        GoRoute(
          path: '/train/program/:uuid',
          builder: (_, state) =>
              Text('PROGRAM ${state.pathParameters['uuid']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          localNowProvider.overrideWithValue(DateTime(2026, 11, 25, 10)),
          catalogRepositoryProvider.overrideWithValue(
            StubCatalogRepository(readyTemplates(), directory),
          ),
        ],
        child: MaterialApp.router(
          theme: BeyondRepTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return seen;
  }

  Future<void> newWorkoutOn(WidgetTester tester, String day) async {
    await tester.tap(find.text(day));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return draft'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save program'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save program'));
    await tester.pumpAndSettle();
  }

  TrainingProgramEntity onlyProgram() =>
      store.box<TrainingProgramEntity>().getAll().single;

  testWidgets('builds a program from a new workout and a ready-made copy', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'My split');
    await newWorkoutOn(tester, 'Day 1');
    expect(find.text('Push day · Wednesday'), findsOneWidget);
    await tester.tap(find.text('Day 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy a ready-made workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic pull'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic pull · Friday'), findsOneWidget);
    await save(tester);

    final program = onlyProgram();
    expect(program.name, 'My split');
    expect(program.sourceId, customProgramSourceId);
    expect(program.isActive, isTrue);
    expect(program.firstDayWeekday, 3);
    final repo = ObjectBoxProgramRepository(store);
    final record = repo.getProgram(program.uuid)!;
    final plans = {for (final p in repo.programPlans(program.uuid)) p.uuid: p};
    expect(plans, hasLength(2));
    expect(plans[record.days[0].planUuid]!.name, 'Push day');
    expect(plans[record.days[2].planUuid]!.name, 'Synthetic pull');
    expect([
      for (final i in [1, 3, 4, 5, 6]) record.days[i].planUuid,
    ], everyElement(isNull));
    expect(find.text('PROGRAM ${program.uuid}'), findsOneWidget);
  });

  testWidgets('a workout can be used on several days', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Repeat');
    await newWorkoutOn(tester, 'Day 1');
    await tester.tap(find.text('Day 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In this program'));
    await tester.tap(find.widgetWithText(Card, 'Push day'));
    await tester.pumpAndSettle();
    await save(tester);
    final repo = ObjectBoxProgramRepository(store);
    final record = repo.getProgram(onlyProgram().uuid)!;
    expect(record.days[0].planUuid, record.days[1].planUuid);
    expect(repo.programPlans(record.uuid), hasLength(1));
  });

  testWidgets('a workout that loses its last day is not saved', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Pruned');
    await newWorkoutOn(tester, 'Day 1');
    await newWorkoutOn(tester, 'Day 2');
    await tester.tap(find.text('Day 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rest day'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(store.box<WorkoutPlanEntity>().count(), 1);
  });

  testWidgets('a new workout on a day can be edited again', (tester) async {
    final seen = await pump(tester);
    await newWorkoutOn(tester, 'Day 1');
    expect(seen, [null]);
    await tester.tap(find.text('Day 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit workout'));
    await tester.pumpAndSettle();
    expect(seen.last?.name, 'Push day');
  });

  testWidgets('saving without a name says so', (tester) async {
    await pump(tester);
    await newWorkoutOn(tester, 'Day 1');
    await save(tester);
    expect(find.text('Give the program a name.'), findsOneWidget);
    expect(store.box<TrainingProgramEntity>().count(), 0);
  });

  testWidgets('saving with only rest days says so', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Empty');
    await save(tester);
    expect(find.text('Add at least one workout day.'), findsOneWidget);
    expect(store.box<TrainingProgramEntity>().count(), 0);
  });

  testWidgets('back with changes asks before discarding', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Draft');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard this program?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Create program'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('changing Starts on counts as a change', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Starts on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday'));
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard this program?'), findsOneWidget);
  });

  testWidgets('turning the active switch off counts as a change', (
    tester,
  ) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Make this my active program'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make this my active program'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard this program?'), findsOneWidget);
  });

  testWidgets('back without changes leaves at once', (tester) async {
    await pump(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a double tap on Save makes one program', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Once');
    await newWorkoutOn(tester, 'Day 1');
    await tester.ensureVisible(find.text('Save program'));
    await tester.pumpAndSettle();
    final button = tester.getCenter(find.text('Save program'));
    await tester.tapAt(button);
    await tester.tapAt(button);
    await tester.pumpAndSettle();
    expect(store.box<TrainingProgramEntity>().count(), 1);
  });

  testWidgets('the start day defaults to today and can change', (tester) async {
    await pump(tester);
    expect(find.text('Rest · Wednesday'), findsWidgets);
    await tester.tap(find.text('Starts on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday'));
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Rest · Monday'), findsWidgets);
  });
}
