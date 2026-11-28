import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/core/date_labels.dart';
import 'package:beyondrep/features/progress/domain/progress_overview.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/today/today_overview.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';

WorkoutSessionRecord finished(
  String id,
  DateTime at, {
  String? plan,
  WorkoutStatus status = WorkoutStatus.completed,
}) => WorkoutSessionRecord(
  uuid: id,
  name: id,
  status: status,
  startedAtUtc: at.subtract(const Duration(minutes: 30)),
  completedAtUtc: status == WorkoutStatus.completed ? at : null,
  originalOffsetMinutes: 0,
  revision: 1,
  planUuid: plan,
);

void main() {
  group('date labels', () {
    test('Today eyebrow is the local calendar day, not a fixed date', () {
      expect(
        todayEyebrow(DateTime(2026, 11, 24, 23, 2)),
        'TUESDAY · 24 NOV 2026',
      );
      expect(todayEyebrow(DateTime(2027, 1, 3)), 'SUNDAY · 3 JAN 2027');
    });

    test('Train heading names the weekday and month', () {
      expect(longDayLabel(DateTime(2026, 11, 24)), 'Tuesday, 24 November');
    });
  });

  group('weekDays and sessionsPerDay', () {
    // Tuesday 24 Nov 2026. Weeks run Sunday to Saturday, like Progress.
    final today = DateTime.utc(2026, 11, 24);

    test('lists the Sunday-to-Saturday week holding today', () {
      final days = weekDays(today);
      expect(days.first, DateTime.utc(2026, 11, 22));
      expect(days.last, DateTime.utc(2026, 11, 28));
      expect(days, hasLength(7));
    });

    test('counts finished sessions on their original local day only', () {
      final counts = sessionsPerDay(
        WorkoutHistorySnapshot(
          sessions: [
            finished('a', DateTime.utc(2026, 11, 22, 9)),
            finished('b', DateTime.utc(2026, 11, 24, 7)),
            finished('c', DateTime.utc(2026, 11, 24, 18)),
            finished('last-week', DateTime.utc(2026, 11, 21, 9)),
            finished(
              'paused',
              DateTime.utc(2026, 11, 23, 9),
              status: WorkoutStatus.paused,
            ),
          ],
        ),
        today,
      );
      expect(counts, [1, 0, 2, 0, 0, 0, 0]);
    });
  });
}
