import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/train/workout_source_sheet.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_fixtures.dart';
import 'template_test_support.dart';

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-day-sheet-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  /// Opens the day sheet from a button and records what it returns.
  Future<List<DayChoice?>> pumpSheet(
    WidgetTester tester, {
    Map<String, String> existing = const {},
    String? current,
    bool canAddWorkout = true,
    bool withSavedPlan = false,
    CatalogState? catalog,
  }) async {
    if (withSavedPlan) {
      ObjectBoxWorkoutLibraryRepository(store).savePlan(
        uuid: 'old-1',
        name: 'Old routine',
        description: '',
        exercises: const [],
      );
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <DayChoice?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          catalogRepositoryProvider.overrideWithValue(
            StubCatalogRepository(catalog ?? readyTemplates(), directory),
          ),
        ],
        child: MaterialApp(
          theme: BeyondRepTheme.build(Brightness.light),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => results.add(
                    await showDaySheet(
                      context,
                      ref,
                      title: 'Day 3',
                      existing: existing,
                      current: current,
                      canAddWorkout: canAddWorkout,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('offers the add options, hiding saved workouts when none exist', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(find.text('Day 3'), findsOneWidget);
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('New workout'), findsOneWidget);
    expect(find.text('Copy a ready-made workout'), findsOneWidget);
    expect(find.text('Copy one of my saved workouts'), findsNothing);
    expect(find.text('Edit workout'), findsNothing);
    expect(find.text('In this program'), findsNothing);
  });

  testWidgets('shows saved workouts only when old saved plans exist', (
    tester,
  ) async {
    await pumpSheet(tester, withSavedPlan: true);
    expect(find.text('Copy one of my saved workouts'), findsOneWidget);
  });

  testWidgets('canAddWorkout false disables the add options', (tester) async {
    final results = await pumpSheet(
      tester,
      canAddWorkout: false,
      withSavedPlan: true,
      existing: {'a': 'Push'},
    );
    expect(
      find.text('A program can hold up to 30 workouts.'),
      findsNWidgets(3),
    );
    await tester.tap(find.text('New workout'));
    await tester.pumpAndSettle();
    expect(results, isEmpty);
    expect(find.text('Day 3'), findsOneWidget);
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(results.single, isA<ExistingChoice>());
  });

  testWidgets('Rest day and New workout return their choices', (tester) async {
    final results = await pumpSheet(tester);
    await tester.tap(find.text('Rest day'));
    await tester.pumpAndSettle();
    expect(results.single, isA<RestChoice>());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New workout'));
    await tester.pumpAndSettle();
    expect(results.last, isA<NewWorkoutChoice>());
  });

  testWidgets('Edit workout shows with a current workout and returns its key', (
    tester,
  ) async {
    final results = await pumpSheet(
      tester,
      current: 'a',
      existing: {'a': 'Push'},
    );
    await tester.tap(find.text('Edit workout'));
    await tester.pumpAndSettle();
    expect((results.single as EditChoice).key, 'a');
  });

  testWidgets('tapping a template returns TemplateChoice', (tester) async {
    final results = await pumpSheet(tester);
    await tester.tap(find.text('Copy a ready-made workout'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic hidden'), findsNothing);
    await tester.tap(find.text('Synthetic pull'));
    await tester.pumpAndSettle();
    final choice = results.single as TemplateChoice;
    expect(choice.template.id, 'tpl.pull');
  });

  testWidgets('more than eight templates adds a search field', (tester) async {
    final base = templatesSnapshot();
    final many = [
      for (var i = 0; i < 9; i++)
        CatalogTemplate(
          id: 'tpl.n$i',
          name: 'Synthetic number $i',
          description: 'x',
          goals: const ['general'],
          level: 'beginner',
          equipment: const ['barbell'],
          estimatedMinutes: 30,
          exercises: base.templates.first.exercises,
        ),
    ];
    final snapshot = CatalogSnapshot(
      release: base.release,
      schemaVersion: base.schemaVersion,
      minAppCatalogSchema: 1,
      publishedAt: base.publishedAt,
      sha256: base.sha256,
      exercises: base.exercises,
      templates: many,
      programs: const [],
    );
    final results = await pumpSheet(
      tester,
      catalog: CatalogState(snapshot: snapshot, status: CatalogStatus.ready),
    );
    await tester.tap(find.text('Copy a ready-made workout'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'number 7');
    await tester.pumpAndSettle();
    expect(find.text('Synthetic number 3'), findsNothing);
    await tester.tap(find.text('Synthetic number 7'));
    await tester.pumpAndSettle();
    expect((results.single as TemplateChoice).template.id, 'tpl.n7');
  });

  testWidgets('tapping a saved plan returns SavedPlanChoice', (tester) async {
    final results = await pumpSheet(tester, withSavedPlan: true);
    await tester.tap(find.text('Copy one of my saved workouts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old routine'));
    await tester.pumpAndSettle();
    expect((results.single as SavedPlanChoice).planUuid, 'old-1');
  });

  testWidgets('tapping a program workout returns ExistingChoice', (
    tester,
  ) async {
    final results = await pumpSheet(
      tester,
      existing: {'a': 'Push', 'b': 'Pull'},
      current: 'a',
    );
    expect(find.text('In this program'), findsOneWidget);
    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    expect((results.single as ExistingChoice).key, 'b');
  });
}
