import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/date_labels.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/design/hero_frame.dart';
import '../../core/design/layout.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../account/account_auth_provider.dart';
import '../health/widgets/readiness_note.dart';
import '../health/widgets/today_health_row.dart';
import '../programs/application/program_providers.dart';
import '../train/quick_workout.dart';
import '../programs/domain/program_models.dart';
import '../progress/domain/progress_overview.dart';
import '../progress/workout_history_state.dart';
import '../sync/workout_upload_coordinator.dart';
import '../sync/workout_conflict_resolution.dart';
import '../train/active_workout_state.dart';
import '../watch/widgets/watch_status_banner.dart';
import '../watch/widgets/live_watch_auto_open.dart';
import '../watch/widgets/live_watch_workout_card.dart';
import '../watch/widgets/watch_status_footer.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'backup_status_notice.dart';
import 'today_overview.dart';
import 'today_program_card.dart';

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  /// A program-day start is in flight, or its logger is still open: a second
  /// tap must not start again or show an error over the logger.
  var _starting = false;

  int _count(WorkoutSyncFlag flag) => ref
      .watch(workoutSyncFlagsProvider)
      .values
      .where((value) => value == flag)
      .length;

  /// Starts today's program workout, or the missed day [missedDate].
  Future<void> _startProgramDay(
    TrainingProgramRecord program,
    String planUuid, {
    DateTime? missedDate,
  }) async {
    if (_starting) return;
    _starting = true;
    try {
      await _startProgramDayGuarded(program, planUuid, missedDate);
    } finally {
      _starting = false;
    }
  }

  Future<void> _startProgramDayGuarded(
    TrainingProgramRecord program,
    String planUuid,
    DateTime? missedDate,
  ) async {
    if (openLiveWatchWorkoutInstead(context, ref)) return;
    if (!await confirmReadinessBeforeStart(context, ref) || !mounted) return;
    try {
      ref
          .read(workoutActionsProvider)
          .startProgramDay(
            program,
            expectedPlanUuid: planUuid,
            missedDate: missedDate,
          );
      ref.invalidate(activeWorkoutProvider);
      ref.invalidate(programWeekProvider);
      await context.push<void>('/train/workout');
    } on ProgramDayChanged {
      if (!mounted) return;
      // The day rolled over or the schedule changed since this was built.
      ref.invalidate(localNowProvider);
      ref.invalidate(programWeekProvider);
      showNsMessage(
        context,
        missedDate == null
            ? "Today's workout changed. Check it and try again."
            : 'This day changed. Check it and try again.',
      );
    } catch (_) {
      if (!mounted) return;
      showNsMessage(
        context,
        'Could not start this workout. Check the program and any unfinished '
        'workout.',
      );
      ref.invalidate(activeWorkoutProvider);
      invalidatePrograms(ref);
    }
  }

  Future<void> _confirmMissed(
    ProgramWeek week,
    DateTime date,
    String planUuid,
    String workout,
  ) async {
    if (_starting) return;
    final yes = await showNsConfirm(
      context,
      title: 'Start $workout for ${weekdayName(date)}?',
      message: 'It counts as your ${weekdayName(date)} workout.',
      confirmLabel: 'Start',
    );
    if (!yes || !mounted) return;
    await _startProgramDay(week.program, planUuid, missedDate: date);
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(localNowProvider);
    final week = ref.watch(programWeekProvider);
    final today = DateTime.utc(now.year, now.month, now.day);
    final history = ref.watch(completedWorkoutHistoryProvider);
    final active = ref.watch(activeWorkoutProvider);
    final unfinished = active.value;
    final Widget hero = unfinished != null
        ? NsHeroFrame(
            eyebrow: 'UNFINISHED WORKOUT',
            title: unfinished.session.name,
            subtitle: 'Saved on this device. Pick up where you left off.',
            actions: [
              NsHeroAction('Resume', () => context.push('/train/workout')),
            ],
          )
        // Starting would fail while an unfinished workout can't be recovered.
        : active.hasError
        ? NsHeroFrame(
            eyebrow: 'UNFINISHED WORKOUT',
            title: 'Workout recovery needs attention',
            subtitle: 'No local data has been deleted.',
            actions: [NsHeroAction('Open Train', () => context.go('/train'))],
          )
        : week != null
        ? TodayProgramHero(
            week: week,
            onStart: (planUuid) => _startProgramDay(week.program, planUuid),
            onOpenProgram: () async {
              await context.push<void>('/train/program/${week.program.uuid}');
              ref.invalidate(programWeekProvider);
            },
          )
        : ref.watch(programsLoadFailedProvider)
        ? NsHeroFrame(
            eyebrow: 'YOUR PROGRAM',
            title: 'Could not load your program',
            subtitle: 'Your local workouts were not changed.',
            actions: [NsHeroAction('Retry', () => invalidatePrograms(ref))],
          )
        : _Hero(
            onOpen: (route) => context.push<void>(route),
            onQuick: () => startQuickWorkout(context, ref),
          );
    final missed = week != null && unfinished == null && !active.hasError
        ? TodayMissedLine(
            week: week,
            onTap: (date, planUuid, workout) =>
                _confirmMissed(week, date, planUuid, workout),
          )
        : null;
    final weekCard = _WeekCard(
      today: today,
      perDay: history.hasValue ? sessionsPerDay(history.value!, today) : null,
      failed: !history.hasValue && history.hasError,
    );
    final header = PageHeader(
      title: 'Today',
      eyebrow: todayEyebrow(now),
      actions: [
        SquareButton(
          tooltip: 'Account and backup',
          onPressed: () => context.push('/today/account'),
          child: const Icon(Icons.manage_accounts_outlined, size: 20),
        ),
      ],
    );
    final backup = BackupStatusNotice(
      controller: ref.watch(accountAuthControllerProvider),
      blockedCount: ref.watch(blockedWorkoutCountProvider),
      unsyncedCount: _count(WorkoutSyncFlag.notSynced),
      reviewCount: _count(WorkoutSyncFlag.needsReview),
      restoreBlocked: ref.watch(workoutRestoreBlockedCodeProvider) != null,
      onSyncNow: ref.watch(workoutUploadKickProvider),
      onReview: () => context.push('/today/sync/review'),
    );
    final padding = EdgeInsets.fromLTRB(
      16,
      16,
      16,
      32 + MediaQuery.paddingOf(context).bottom,
    );
    if (isWideWindow(context)) {
      return ListView(
        padding: padding,
        children: [
          header,
          const SizedBox(height: 24),
          const WatchStatusBanner(),
          backup,
          const LiveWatchWorkoutCard(),
          NsSplitColumns(
            mainFlex: 1,
            sideFlex: 1,
            main: [
              hero,
              ?missed,
              const SizedBox(height: 27),
              const SectionHeading('This week'),
              weekCard,
            ],
            side: const [SectionHeading('Recent health'), TodayHealthRow()],
          ),
          const WatchStatusFooter(),
        ],
      );
    }
    return ListView(
      padding: padding,
      children: [
        header,
        const SizedBox(height: 24),
        const WatchStatusBanner(),
        backup,
        const LiveWatchWorkoutCard(),
        hero,
        ?missed,
        const SizedBox(height: 27),
        const SectionHeading('Recent health'),
        const TodayHealthRow(),
        const SizedBox(height: 27),
        const SectionHeading('This week'),
        weekCard,
        const WatchStatusFooter(),
      ],
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.today,
    required this.perDay,
    required this.failed,
  });

  final DateTime today;

  /// Finished sessions per day, Sunday first; null while loading.
  final List<int>? perDay;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<BeyondRepColors>()!;
    final counts = perDay;
    final total = counts?.fold(0, (a, b) => a + b) ?? 0;
    final days = weekDays(today);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed
                  ? 'Could not load finished workouts'
                  : counts == null
                  ? 'Loading finished workouts…'
                  : total == 0
                  ? 'No workouts finished yet this week'
                  : '$total ${total == 1 ? 'workout' : 'workouts'} finished this week',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sunday to Saturday · finished workouts on this device',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
            ),
            if (counts != null) ...[
              const SizedBox(height: 13),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < days.length; i++)
                      _Day(
                        name: weekdayName(days[i]),
                        isToday: days[i] == today,
                        trained: counts[i] > 0,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown without an active program: pick one, or start a quick workout.
class _Hero extends StatelessWidget {
  const _Hero({required this.onOpen, required this.onQuick});

  final void Function(String route) onOpen;
  final VoidCallback onQuick;

  @override
  Widget build(BuildContext context) {
    return NsHeroFrame(
      eyebrow: 'GET STARTED',
      title: 'No program yet',
      subtitle:
          'Pick a program to get a workout each day, or start a quick '
          'workout and add exercises as you go.',
      actions: [
        NsHeroAction('Pick a program', () => onOpen('/train/programs')),
        NsHeroAction('Quick workout', onQuick),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.name,
    required this.isToday,
    required this.trained,
  });

  final String name;
  final bool isToday;
  final bool trained;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Semantics(
      label: [name, if (isToday) 'today', if (trained) 'trained'].join(', '),
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: trained ? primary : null,
              border: Border.all(
                color: trained || isToday ? primary : theme.colorScheme.outline,
                width: isToday ? 2 : 1,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            name.substring(0, 3),
            style: theme.textTheme.labelSmall?.copyWith(
              color: isToday
                  ? theme.colorScheme.onSurface
                  : theme.extension<BeyondRepColors>()!.muted,
              fontWeight: isToday ? FontWeight.w800 : null,
            ),
          ),
        ],
      ),
    );
  }
}
