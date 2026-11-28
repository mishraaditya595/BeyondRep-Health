import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/date_labels.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../../core/ui/dispose_after_dialog.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/domain/catalog_templates.dart';
import '../programs/application/program_providers.dart';
import '../programs/data/objectbox_program_repository.dart';
import '../programs/domain/program_models.dart';
import '../programs/domain/program_repository.dart';
import '../programs/domain/program_schedule.dart';
import '../programs/domain/program_status.dart';
import '../programs/presentation/start_program_day.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import 'plan_fit_widgets.dart';
import 'program_weekday_sheet.dart';
import 'train_library_state.dart';
import 'workout_source_sheet.dart';

/// A program the user added: today's workout, the weekly schedule and its
/// editing, and activation and archive.
class MyProgramPage extends ConsumerStatefulWidget {
  const MyProgramPage({required this.programUuid, super.key});

  final String programUuid;

  @override
  ConsumerState<MyProgramPage> createState() => _MyProgramPageState();
}

class _MyProgramPageState extends ConsumerState<MyProgramPage> {
  var _busy = false;

  String _planName(String planUuid) =>
      ref.read(workoutLibraryRepositoryProvider).getPlan(planUuid)?.name ??
      'Workout';

  void _failed(String message) => showNsMessage(context, message);

  Future<void> _start(
    TrainingProgramRecord program, {
    DateTime? missedDate,
    String? missedPlanUuid,
    String? swapPlanUuid,
  }) async {
    if (_busy) return;
    _busy = true;
    setState(() {});
    try {
      await startProgramDay(
        context,
        ref,
        program,
        missedDate: missedDate,
        missedPlanUuid: missedPlanUuid,
        swapPlanUuid: swapPlanUuid,
        onFailed: _failed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _write(void Function(ProgramRepository) action) {
    try {
      action(ref.read(programRepositoryProvider));
    } on ProgramWorkoutLimit {
      _failed('A program can hold up to $maxProgramWorkouts workouts.');
    } on Object {
      _failed('Could not save this change. Try again.');
    }
    invalidatePrograms(ref);
  }

  Future<void> _editDay(
    TrainingProgramRecord program,
    ({int weekday, ProgramDayRecord day}) entry,
  ) async {
    final plans = ref
        .read(programRepositoryProvider)
        .programPlans(program.uuid);
    final choice = await showDaySheet(
      context,
      ref,
      title: weekdayNames[entry.weekday - 1],
      existing: {for (final plan in plans) plan.uuid: plan.name},
      current: entry.day.planUuid,
      canAddWorkout: plans.length < maxProgramWorkouts,
    );
    if (choice == null || !mounted) return;
    void setDay(String? planUuid) => _write(
      (repo) => repo.setDayPlan(program.uuid, entry.day.dayIndex, planUuid),
    );
    // Adds the workout, then points the day at it. A failed second step only
    // leaves an unused workout in the program.
    void addAndSet(ProgramWorkoutSource source) {
      String? added;
      _write((repo) => added = repo.addWorkout(program.uuid, source));
      if (added != null) setDay(added);
    }

    switch (choice) {
      case RestChoice():
        setDay(null);
      case ExistingChoice(:final key):
        setDay(key);
      case EditChoice(:final key):
        await context.push<void>('/train/plans/$key/edit');
        if (mounted) invalidatePrograms(ref);
      case NewWorkoutChoice():
        final created = await context.push<String>(
          '/train/programs/${program.uuid}/workouts/new',
        );
        if (mounted) invalidatePrograms(ref);
        if (created != null && mounted) setDay(created);
      case TemplateChoice(:final template):
        final snapshot = safeCatalogState(() => ref.read(catalogStateProvider))
            .snapshot;
        if (snapshot == null) {
          _failed('Ready-made workouts are not available now.');
          return;
        }
        try {
          addAndSet(
            TemplateWorkoutSource(
              name: template.name,
              description: template.description,
              rows: templateRowInputs(template, snapshot),
              release: snapshot.release,
            ),
          );
        } on Object {
          _failed('Could not save this change. Try again.');
        }
      case SavedPlanChoice(:final planUuid):
        addAndSet(CopyWorkoutSource(planUuid));
    }
  }

  Future<void> _editDetails(TrainingProgramRecord program) async {
    final name = TextEditingController(text: program.name);
    final description = TextEditingController(text: program.description);
    String? error;
    try {
      await showNsDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => NsDialog(
            title: 'Edit program',
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NsTextField(
                      controller: name,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      label: 'Name',
                    ),
                    const SizedBox(height: 10),
                    NsTextField(
                      controller: description,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 3,
                      label: 'Description (optional)',
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) {
                    updateDialog(() => error = 'Give the program a name.');
                    return;
                  }
                  Navigator.pop(dialogContext);
                  _write(
                    (repo) => repo.updateDetails(
                      program.uuid,
                      name: name.text,
                      description: description.text,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      disposeAfterDialog([name, description]);
    }
  }

  Future<void> _changeStartDay(TrainingProgramRecord program) async {
    final choice = await showProgramWeekdaySheet(
      context,
      title: 'Change start day',
      confirmLabel: 'Save',
      initialWeekday: program.firstDayWeekday,
    );
    if (choice == null || !mounted) return;
    _write((repo) => repo.setFirstWeekday(program.uuid, choice.weekday));
  }

  Future<void> _archive(TrainingProgramRecord program) async {
    final yes = await showNsConfirm(
      context,
      title: 'Archive this program?',
      message:
          'Its workouts are archived with it. Workouts you already logged '
          'stay in your history.',
      confirmLabel: 'Archive',
    );
    if (!yes || !mounted) return;
    try {
      ref
          .read(programRepositoryProvider)
          .archiveProgram(
            program.uuid,
            DateTime.now().toUtc().millisecondsSinceEpoch,
          );
    } on Object {
      _failed('Could not archive this program.');
      return;
    }
    invalidatePrograms(ref);
    if (!mounted) return;
    showNsMessage(context, 'Program archived');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/train');
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = ref.watch(localProgramProvider(widget.programUuid));
    final now = ref.watch(localNowProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const NsBackButton(),
        title: const Text('Your program'),
        actions: [
          if (program != null)
            IconButton(
              onPressed: () => _editDetails(program),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit name',
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: program == null
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text("This program isn't available."),
                )
              : _body(context, program, now),
        ),
      ),
    );
  }

  Widget _dayRow(
    BuildContext context,
    TrainingProgramRecord program,
    ({int weekday, ProgramDayRecord day}) entry,
    int todayIndex,
    ProgramWeekRow? row,
  ) {
    final status =
        row?.status ??
        (entry.day.planUuid == null ? ProgramDayStatus.rest : null);
    final weekday = weekdayNames[entry.weekday - 1];
    final tag = switch (status) {
      ProgramDayStatus.rest => 'Rest',
      ProgramDayStatus.unavailable => 'Unavailable',
      ProgramDayStatus.done => 'Done',
      ProgramDayStatus.today => 'Today',
      ProgramDayStatus.missed => 'Missed',
      ProgramDayStatus.upcoming => 'Upcoming',
      null => null,
    };
    final name = entry.day.planUuid == null
        ? 'Rest'
        : _planName(entry.day.planUuid!);
    final recovery = planRecoveryLine(
      ref.watch(planFitProvider)?.byPlan[entry.day.planUuid],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NsListCard(
            onTap: () => _editDay(program, entry),
            icon: entry.day.planUuid == null
                ? Icons.hotel_outlined
                : Icons.fitness_center,
            title: '$weekday · $name',
            // The Today and Done tags already say it.
            subtitle:
                'Day ${entry.day.dayIndex + 1}'
                '${entry.day.dayIndex == todayIndex && status != ProgramDayStatus.today && status != ProgramDayStatus.done ? ' · Today' : ''}'
                '$recovery',
            trailing: tag == null
                ? null
                : NsTag(tag, warning: status == ProgramDayStatus.missed),
          ),
          if (status == ProgramDayStatus.missed)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _start(
                      program,
                      missedDate: row!.date,
                      missedPlanUuid: entry.day.planUuid,
                    ),
              child: Text('Start for $weekday'),
            ),
        ],
      ),
    );
  }

  /// The suggestion card, only for an active program with a workout still to
  /// do today when another of its workouts fits better.
  List<Widget> _betterFit(
    TrainingProgramRecord program,
    ProgramWeekRow? todayRow,
    String? todayPlan,
    bool todayAvailable,
  ) {
    final fit = ref.watch(planFitProvider);
    final suggestion = fit?.suggestion;
    if (!program.isActive ||
        suggestion == null ||
        todayPlan == null ||
        !todayAvailable ||
        todayRow?.status == ProgramDayStatus.done ||
        suggestion.plan.planUuid == todayPlan) {
      return const [];
    }
    final suggested = suggestion.plan.planUuid;
    return [
      const SizedBox(height: 16),
      BetterFitCard(
        name: _planName(suggested),
        suggestion: suggestion,
        onStart: () => _busy ? null : _start(program, swapPlanUuid: suggested),
      ),
    ];
  }

  Widget _body(
    BuildContext context,
    TrainingProgramRecord program,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final todayIndex = programDayIndex(now, program.firstDayWeekday);
    final todayPlan = dayFor(program, now).planUuid;
    final todayAvailable =
        todayPlan != null &&
        ref.read(workoutLibraryRepositoryProvider).getPlan(todayPlan) != null;
    final week = calendarWeek(program);
    final programWeek = program.isActive
        ? ref.watch(programWeekProvider)
        : null;
    // Only this program's own week: never another program's statuses.
    final rows = programWeek?.program.uuid == program.uuid
        ? programWeek?.rows
        : null;
    final todayRow = rows
        ?.where((r) => r.date == DateTime(now.year, now.month, now.day))
        .firstOrNull;
    ProgramWeekRow? rowOf(int dayIndex) =>
        rows?.where((r) => r.dayIndex == dayIndex).firstOrNull;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        28 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          program.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [NsTag(program.isActive ? 'Active' : 'Not active')],
        ),
        const SizedBox(height: 16),
        if (!program.isActive)
          Text(
            'Make this your active program to start its workouts',
            style: theme.textTheme.bodyMedium,
          )
        else if (todayRow?.status == ProgramDayStatus.done)
          Text(
            'Done for today',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          )
        else if (todayPlan == null || !todayAvailable)
          Text(
            todayPlan == null ? 'Rest day today' : 'Workout unavailable',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          )
        else
          FilledButton.icon(
            onPressed: _busy ? null : () => _start(program),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text("Start today's workout"),
          ),
        ..._betterFit(program, todayRow, todayPlan, todayAvailable),
        const SizedBox(height: 20),
        const SectionHeading('This week'),
        if (week.every((e) => e.day.planUuid == null))
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('No training days'),
          ),
        for (final entry in week)
          _dayRow(
            context,
            program,
            entry,
            todayIndex,
            rowOf(entry.day.dayIndex),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _changeStartDay(program),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: const Text('Change start day'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _write(
            (repo) => repo.setActive(program.uuid, !program.isActive, now),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: Text(
            program.isActive ? 'Stop using this program' : 'Make active',
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => _archive(program),
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: const Text('Archive program'),
        ),
      ],
    );
  }
}
