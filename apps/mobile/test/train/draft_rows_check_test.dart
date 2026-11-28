import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/train/plan_editor_page.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';

ExerciseRecord _exercise(
  String uuid, {
  String mode = 'reps_load',
  int? archived,
}) => ExerciseRecord(
  uuid: uuid,
  name: 'Name of $uuid',
  muscleGroup: 'Core',
  equipment: 'None',
  movementCategory: 'Core',
  inputMode: mode,
  isBuiltIn: true,
  updatedAtMs: 1,
  archivedAtMs: archived,
);

PlanExerciseRecord _row(
  String exercise, {
  int? reps,
  int? seconds,
  int position = 0,
}) => PlanExerciseRecord(
  uuid: 'row-$exercise-$position',
  exerciseUuid: exercise,
  position: position,
  targetSets: 3,
  targetRepsMin: reps,
  targetRepsMax: reps,
  targetDurationSeconds: seconds,
);

void main() {
  final definitions = [
    _exercise('press'),
    _exercise('plank', mode: 'duration'),
    _exercise('old', archived: 5),
  ];

  test('valid reps and seconds rows pass', () {
    checkDraftRows(
      [_row('press', reps: 8), _row('plank', seconds: 30, position: 1)],
      definitions,
      previousRows: const [],
    );
  });

  test('a timed exercise with rep targets is refused', () {
    expect(
      () => checkDraftRows(
        [_row('plank', reps: 8)],
        definitions,
        previousRows: const [],
      ),
      throwsArgumentError,
    );
  });

  test('a rep exercise with a seconds target is refused', () {
    expect(
      () => checkDraftRows(
        [_row('press', seconds: 30)],
        definitions,
        previousRows: const [],
      ),
      throwsArgumentError,
    );
  });

  test('an unknown exercise is refused', () {
    expect(
      () => checkDraftRows(
        [_row('nothing', reps: 8)],
        definitions,
        previousRows: const [],
      ),
      throwsArgumentError,
    );
  });

  test(
    'a newly added archived exercise is refused with the archived error',
    () {
      expect(
        () => checkDraftRows(
          [_row('old', reps: 8)],
          definitions,
          previousRows: const [],
        ),
        throwsA(isA<ArchivedExercisePlanConflict>()),
      );
    },
  );

  test('an archived exercise already in the draft may stay', () {
    checkDraftRows(
      [_row('old', reps: 8)],
      definitions,
      previousRows: [_row('old', reps: 8)],
    );
  });
}
