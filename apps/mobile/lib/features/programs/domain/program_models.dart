import '../../workouts/domain/workout_library_models.dart';

/// One of the seven days of a program. A null [planUuid] is a rest day.
class ProgramDayRecord {
  const ProgramDayRecord({
    required this.uuid,
    required this.dayIndex,
    this.planUuid,
  });

  final String uuid;
  final int dayIndex;
  final String? planUuid;
}

/// A program the user added. Local only, never synced.
class TrainingProgramRecord {
  const TrainingProgramRecord({
    required this.uuid,
    required this.name,
    required this.description,
    required this.sourceId,
    required this.sourceRelease,
    required this.firstDayWeekday,
    required this.isActive,
    required this.updatedAtMs,
    required this.days,
    this.activatedLocalDate,
    this.archivedAtMs,
  });

  final String uuid;
  final String name;
  final String description;
  final String sourceId;
  final int sourceRelease;

  /// ISO weekday of day 1, Monday = 1.
  final int firstDayWeekday;
  final bool isActive;

  /// `yyyy-MM-dd`, set each time the program becomes active.
  final String? activatedLocalDate;
  final int updatedAtMs;
  final int? archivedAtMs;

  /// Seven days ordered by `dayIndex`.
  final List<ProgramDayRecord> days;
}

/// Most live workouts one program may own, used by a day or not.
const maxProgramWorkouts = 30;

/// The `sourceId` of a program the person built themselves.
const customProgramSourceId = 'custom';

/// Where a new program-owned workout's rows come from.
sealed class ProgramWorkoutSource {
  const ProgramWorkoutSource();
}

/// Rows built in the editor; exercise UUIDs must exist locally.
class DraftWorkoutSource extends ProgramWorkoutSource {
  const DraftWorkoutSource({
    required this.name,
    required this.description,
    required this.rows,
  });

  final String name;
  final String description;
  final List<PlanExerciseRecord> rows;
}

/// A catalogue template; exercises are materialized in the same transaction.
class TemplateWorkoutSource extends ProgramWorkoutSource {
  const TemplateWorkoutSource({
    required this.name,
    required this.description,
    required this.rows,
    required this.release,
  });

  final String name;
  final String description;
  final List<TemplateRowInput> rows;
  final int release;
}

/// A copy of an existing plan (an old saved plan or another program's
/// workout).
class CopyWorkoutSource extends ProgramWorkoutSource {
  const CopyWorkoutSource(this.planUuid);

  final String planUuid;
}

/// A program already owns [maxProgramWorkouts] workouts.
class ProgramWorkoutLimit implements Exception {
  const ProgramWorkoutLimit();

  @override
  String toString() => 'A program can hold up to $maxProgramWorkouts workouts.';
}
