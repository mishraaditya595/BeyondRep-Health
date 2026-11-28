import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/date_labels.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../../core/ids/uuid_factory.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/domain/catalog_templates.dart';
import '../programs/application/program_providers.dart';
import '../programs/data/objectbox_program_repository.dart';
import '../programs/domain/program_models.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import 'program_weekday_sheet.dart';
import 'workout_source_sheet.dart';

/// One workout the builder will create when the program is saved.
class _BuilderWorkout {
  const _BuilderWorkout(this.key, this.source, this.name);

  final String key;
  final ProgramWorkoutSource source;
  final String name;
}

const _limitMessage = 'A program can hold up to $maxProgramWorkouts workouts.';

/// Builds a custom program: a name, seven days and the workouts they use.
/// Nothing is written until Save, which is one idempotent transaction.
class CreateProgramPage extends ConsumerStatefulWidget {
  const CreateProgramPage({super.key});

  @override
  ConsumerState<CreateProgramPage> createState() => _CreateProgramPageState();
}

class _CreateProgramPageState extends ConsumerState<CreateProgramPage> {
  final _ids = SecureUuidFactory();
  late final String _requestUuid = _ids.newId();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _workouts = <_BuilderWorkout>[];
  final _days = List<String?>.filled(7, null);
  int? _firstWeekday;
  var _makeActive = true;
  var _saving = false;
  var _allowLeave = false;

  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _days.any((d) => d != null) ||
      _firstWeekday != null ||
      !_makeActive;

  int get _weekday => _firstWeekday ?? ref.read(localNowProvider).weekday;

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  _BuilderWorkout? _byKey(String? key) =>
      _workouts.where((w) => w.key == key).firstOrNull;

  /// Drops workouts no day uses any more: a saved program owns only used ones.
  void _prune() {
    final used = _days.whereType<String>().toSet();
    _workouts.removeWhere((w) => !used.contains(w.key));
  }

  Future<DraftWorkoutSource?> _openEditor(DraftWorkoutSource? initial) {
    return context.push<DraftWorkoutSource>(
      '/train/programs/new/workout',
      extra: initial,
    );
  }

  Future<void> _pickDay(int index) async {
    final weekday = weekdayNames[(_weekday - 1 + index) % 7];
    final currentKey = _days[index];
    final current = _byKey(currentKey);
    final choice = await showDaySheet(
      context,
      ref,
      title: 'Day ${index + 1} · $weekday',
      existing: {for (final w in _workouts) w.key: w.name},
      // Only workouts built here can be edited before Save.
      current: current?.source is DraftWorkoutSource ? currentKey : null,
      canAddWorkout: _workouts.length < maxProgramWorkouts,
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case RestChoice():
        _days[index] = null;
      case ExistingChoice(:final key):
        if (_byKey(key) != null) _days[index] = key;
      case NewWorkoutChoice():
        final draft = await _openEditor(null);
        if (draft == null || !mounted) return;
        _add(index, draft, draft.name);
      case EditChoice(:final key):
        final old = _byKey(key);
        if (old == null || old.source is! DraftWorkoutSource) return;
        final draft = await _openEditor(old.source as DraftWorkoutSource);
        if (draft == null || !mounted) return;
        final at = _workouts.indexOf(old);
        _workouts[at] = _BuilderWorkout(key, draft, draft.name);
      case TemplateChoice(:final template):
        final snapshot = safeCatalogState(() => ref.read(catalogStateProvider))
            .snapshot;
        if (snapshot == null) {
          showNsMessage(context, 'Ready-made workouts are not available now.');
          return;
        }
        try {
          _add(
            index,
            TemplateWorkoutSource(
              name: template.name,
              description: template.description,
              rows: templateRowInputs(template, snapshot),
              release: snapshot.release,
            ),
            template.name,
          );
        } on Object {
          showNsMessage(context, 'Could not add this workout. Try again.');
          return;
        }
      case SavedPlanChoice(:final planUuid):
        final name = ref
            .read(workoutLibraryRepositoryProvider)
            .getPlan(planUuid)
            ?.name;
        if (name == null) {
          showNsMessage(context, 'That workout is no longer available.');
          return;
        }
        _add(index, CopyWorkoutSource(planUuid), name);
    }
    _prune();
    _refresh();
  }

  void _add(int index, ProgramWorkoutSource source, String name) {
    final key = _ids.newId();
    _workouts.add(_BuilderWorkout(key, source, name));
    _days[index] = key;
  }

  Future<void> _pickStart() async {
    final choice = await showProgramWeekdaySheet(
      context,
      title: 'Starts on',
      confirmLabel: 'Save',
      initialWeekday: _weekday,
    );
    if (choice == null || !mounted) return;
    setState(() => _firstWeekday = choice.weekday);
  }

  void _save() {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      showNsMessage(context, 'Give the program a name.');
      return;
    }
    if (_days.every((d) => d == null)) {
      showNsMessage(context, 'Add at least one workout day.');
      return;
    }
    _saving = true;
    setState(() {});
    try {
      final created = ref
          .read(programRepositoryProvider)
          .createProgram(
            requestUuid: _requestUuid,
            name: _name.text,
            description: _description.text,
            workouts: [for (final w in _workouts) w.source],
            week: [
              for (final key in _days)
                key == null ? null : _workouts.indexWhere((w) => w.key == key),
            ],
            firstDayWeekday: _weekday,
            makeActive: _makeActive,
            localToday: ref.read(localNowProvider),
          );
      invalidatePrograms(ref);
      if (!mounted) return;
      _allowLeave = true;
      context.pushReplacement('/train/program/${created.uuid}');
      return;
    } on ProgramWorkoutLimit {
      showNsMessage(context, _limitMessage);
    } on Object {
      if (mounted) {
        showNsMessage(
          context,
          'Could not save this program. Nothing was saved.',
        );
      }
    }
    _saving = false;
    if (mounted) setState(() {});
  }

  Future<void> _requestExit() async {
    if (!_dirty || _allowLeave) {
      context.pop();
      return;
    }
    final discard = await showNsConfirm(
      context,
      title: 'Discard this program?',
      message: 'What you added has not been saved.',
      cancelLabel: 'Keep editing',
      confirmLabel: 'Discard',
    );
    if (discard && mounted) {
      setState(() => _allowLeave = true);
      context.pop();
    }
  }

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (!didPop && mounted) await _requestExit();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).extension<BeyondRepColors>()!.muted;
    return PopScope(
      canPop: !_dirty || _allowLeave,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          leading: NsBackButton(onPressed: _requestExit),
          title: const Text('Create program'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                NsTextField(
                  controller: _name,
                  onChanged: (_) => _refresh(),
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  label: 'Name',
                  hint: 'e.g. Push Pull Legs',
                ),
                const SizedBox(height: 12),
                NsTextField(
                  controller: _description,
                  onChanged: (_) => _refresh(),
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 2,
                  label: 'Description (optional)',
                ),
                const SizedBox(height: 14),
                NsListCard(
                  onTap: _pickStart,
                  icon: Icons.today_outlined,
                  title: 'Starts on',
                  subtitle: weekdayNames[_weekday - 1],
                ),
                const SizedBox(height: 18),
                const SectionHeading('Days'),
                Text(
                  'Tap a day to choose a workout or a rest day.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: NsListCard(
                      onTap: () => _pickDay(i),
                      icon: _days[i] == null
                          ? Icons.hotel_outlined
                          : Icons.fitness_center,
                      title: 'Day ${i + 1}',
                      subtitle:
                          '${_byKey(_days[i])?.name ?? 'Rest'} · '
                          '${weekdayNames[(_weekday - 1 + i) % 7]}',
                    ),
                  ),
                const SizedBox(height: 6),
                NsSwitchRow(
                  label: 'Make this my active program',
                  value: _makeActive,
                  onChanged: (value) => setState(() => _makeActive = value),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                  ),
                  child: const Text('Save program'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
