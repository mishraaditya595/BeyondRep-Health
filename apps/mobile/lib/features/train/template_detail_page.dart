import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/beyondrep_theme.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/page_header.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/catalog_templates.dart';
import '../health/widgets/readiness_note.dart';
import '../watch/widgets/live_watch_auto_open.dart';
import 'active_workout_state.dart';
import 'train_library_state.dart';
import 'workout_templates_page.dart';

/// One ready-made workout: every exercise with its sets, reps or seconds and
/// rest, and a button to start it now.
class TemplateDetailPage extends ConsumerStatefulWidget {
  const TemplateDetailPage({
    required this.templateId,
    this.embedded = false,
    super.key,
  });

  final String templateId;

  /// Shown inside the workouts list's detail pane: no back button.
  final bool embedded;

  @override
  ConsumerState<TemplateDetailPage> createState() => _TemplateDetailPageState();
}

class _TemplateDetailPageState extends ConsumerState<TemplateDetailPage> {
  var _busy = false;

  Future<void> _start(
    CatalogTemplate template,
    CatalogSnapshot snapshot,
  ) async {
    if (_busy) return;
    if (openLiveWatchWorkoutInstead(context, ref)) return;
    _busy = true;
    setState(() {});
    try {
      final active = ref.read(activeWorkoutProvider);
      if (active.value != null || active.hasError) {
        _startFailed();
        return;
      }
      if (!await confirmReadinessBeforeStart(context, ref) || !mounted) {
        return;
      }
      try {
        ref
            .read(workoutActionsProvider)
            .startTemplate(
              template.name,
              templateRowInputs(template, snapshot),
              snapshot.release,
            );
        ref.invalidate(activeWorkoutProvider);
        ref.invalidate(trainLibraryProvider);
      } on Object {
        _startFailed();
        return;
      }
      await context.push<void>('/train/workout');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startFailed() {
    showNsMessage(
      context,
      'Could not start this workout. Check any unfinished workout.',
    );
    ref.invalidate(activeWorkoutProvider);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = safeCatalogState(() => ref.watch(catalogStateProvider))
        .snapshot;
    CatalogTemplate? template;
    var retired = false;
    if (snapshot != null) {
      for (final t in browsableTemplates(snapshot)) {
        if (t.id == widget.templateId) template = t;
      }
      retired = snapshot.templates.any(
        (t) => t.id == widget.templateId && t.standalone && t.retired,
      );
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.embedded ? null : const NsBackButton(),
        title: const Text('Workout'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: template == null || snapshot == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    retired
                        ? 'This workout is no longer available.'
                        : "This workout isn't available.",
                  ),
                )
              : _Detail(
                  template: template,
                  snapshot: snapshot,
                  busy: _busy,
                  onStart: () => _start(template!, snapshot),
                ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.template,
    required this.snapshot,
    required this.busy,
    required this.onStart,
  });

  final CatalogTemplate template;
  final CatalogSnapshot snapshot;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = {for (final e in snapshot.exercises) e.id: e.name};
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        28 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          template.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(template.description, style: TextStyle(color: theme.mutedColor)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NsTag(levelLabel(template.level)),
            NsTag('${template.estimatedMinutes} min'),
            for (final label in templateEquipment(template).split(', '))
              if (label.isNotEmpty) NsTag(label),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onStart,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start now'),
        ),
        const SizedBox(height: 20),
        for (final row in template.exercises)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NsListCard(
              onTap: () => context.push(
                '/train/exercises/${Uri.encodeComponent(row.exerciseId)}',
              ),
              icon: Icons.fitness_center,
              title: names[row.exerciseId] ?? row.exerciseId,
              subtitle: [
                '${prescriptionLabel(row)} · ${restLabel(row.restSeconds)}',
                if (row.note.isNotEmpty) row.note,
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}
