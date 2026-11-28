import '../progress/domain/progress_overview.dart';
import '../progress/domain/workout_history_models.dart';
import '../workouts/domain/workout_models.dart';

/// Finished sessions on each day of [weekDays] for [today], counted on each
/// session's original local day like Progress.
List<int> sessionsPerDay(WorkoutHistorySnapshot snapshot, DateTime today) {
  final days = weekDays(today);
  final counts = List.filled(days.length, 0);
  for (final s in snapshot.sessions) {
    if (s.status != WorkoutStatus.completed || s.completedAtUtc == null) {
      continue;
    }
    final index = days.indexOf(originalLocalDay(s));
    if (index >= 0) counts[index]++;
  }
  return counts;
}
