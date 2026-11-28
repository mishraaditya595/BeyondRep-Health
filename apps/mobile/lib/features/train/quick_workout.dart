import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../health/widgets/readiness_note.dart';
import '../watch/widgets/live_watch_auto_open.dart';
import 'active_workout_state.dart';

/// Asks for a name, then starts an empty workout and opens the logger. Shared
/// by Train and Today so both ask the same way.
Future<void> startQuickWorkout(BuildContext context, WidgetRef ref) async {
  if (openLiveWatchWorkoutInstead(context, ref)) return;
  var proposed = 'Quick workout';
  final chosen = await showNsDialog<String>(
    context: context,
    builder: (dialogContext) => NsDialog(
      title: 'Start an empty workout',
      content: NsTextField(
        autofocus: true,
        initialValue: proposed,
        onChanged: (value) => proposed = value,
        maxLength: 160,
        label: 'Workout name',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, proposed.trim()),
          child: const Text('Start workout'),
        ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return;
  if (chosen.isEmpty) {
    showNsMessage(context, 'Enter a workout name first.');
    return;
  }
  await _startWorkout(
    context,
    ref,
    () => ref.read(workoutActionsProvider).startQuick(chosen),
  );
}

Future<void> _startWorkout(
  BuildContext context,
  WidgetRef ref,
  void Function() action,
) async {
  if (openLiveWatchWorkoutInstead(context, ref)) return;
  // The start would fail while a workout is unfinished or unrecoverable:
  // say so before the readiness note, which only shows once a day.
  final active = ref.read(activeWorkoutProvider);
  if (active.value != null || active.hasError) {
    _showStartFailed(context, ref);
    return;
  }
  if (!await confirmReadinessBeforeStart(context, ref) || !context.mounted) {
    return;
  }
  try {
    action();
    ref.invalidate(activeWorkoutProvider);
    context.push('/train/workout');
  } catch (_) {
    _showStartFailed(context, ref);
  }
}

void _showStartFailed(BuildContext context, WidgetRef ref) {
  showNsMessage(
    context,
    'Could not start this workout. Check any unfinished workout.',
  );
  ref.invalidate(activeWorkoutProvider);
}
