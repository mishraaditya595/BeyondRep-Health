import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/features/train/train_page.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_health_overview.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double textScale,
  required Brightness brightness,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const TrainPage())],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthOverview(FakeHealthOverviewController(null)),
        localNowProvider.overrideWithValue(DateTime(2026, 11, 24, 9)),
        trainLibraryProvider.overrideWith(
          (ref) async => const WorkoutLibrarySnapshot(exercises: [], plans: []),
        ),
        activeWorkoutProvider.overrideWith(
          (ref) => const AsyncData<ActiveWorkoutView?>(null),
        ),
      ],
      child: MaterialApp.router(
        theme: BeyondRepTheme.build(brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 1.3, 1.5, 2.0, 3.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('Train header fits ${scale}x text at 390 px, $brightness', (
        tester,
      ) async {
        await _pump(tester, textScale: scale, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('Your training week'), findsOneWidget);
        expect(find.text('Create training plan'), findsNothing);
        final title = tester.getRect(find.text('Your training week'));
        expect(title.right, lessThanOrEqualTo(390 - 16));
      });
    }
  }
}
