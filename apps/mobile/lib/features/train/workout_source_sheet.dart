import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../catalog/application/templates_provider.dart';
import '../catalog/domain/catalog_models.dart';
import '../programs/domain/program_models.dart';
import 'train_library_state.dart';

/// What the user picked for one program day.
sealed class DayChoice {
  const DayChoice();
}

class RestChoice extends DayChoice {
  const RestChoice();
}

class NewWorkoutChoice extends DayChoice {
  const NewWorkoutChoice();
}

class TemplateChoice extends DayChoice {
  const TemplateChoice(this.template);
  final CatalogTemplate template;
}

class SavedPlanChoice extends DayChoice {
  const SavedPlanChoice(this.planUuid);
  final String planUuid;
}

/// A workout already in this program.
class ExistingChoice extends DayChoice {
  const ExistingChoice(this.key);
  final String key;
}

/// Edit the workout that is on this day.
class EditChoice extends DayChoice {
  const EditChoice(this.key);
  final String key;
}

const _limitText = 'A program can hold up to $maxProgramWorkouts workouts.';

/// Asks what a program day should be. [existing] maps a key (a plan UUID, or
/// a builder-local key) to a name; [current] is the key on this day, or null
/// for rest.
Future<DayChoice?> showDaySheet(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required Map<String, String> existing,
  required String? current,
  required bool canAddWorkout,
}) async {
  var savedPlans = const <({String uuid, String name})>[];
  try {
    final library = await ref.read(trainLibraryProvider.future);
    savedPlans = [for (final p in library.plans) (uuid: p.uuid, name: p.name)];
  } on Object {
    // Without the library the saved-workout option is simply not offered.
  }
  if (!context.mounted) return null;
  return showNsSheet<DayChoice>(
    context,
    heightFactor: 0.8,
    builder: (sheetContext) => _DaySheet(
      title: title,
      existing: existing,
      current: current,
      canAddWorkout: canAddWorkout,
      savedPlans: savedPlans,
    ),
  );
}

class _DaySheet extends ConsumerWidget {
  const _DaySheet({
    required this.title,
    required this.existing,
    required this.current,
    required this.canAddWorkout,
    required this.savedPlans,
  });

  final String title;
  final Map<String, String> existing;
  final String? current;
  final bool canAddWorkout;
  final List<({String uuid, String name})> savedPlans;

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool addsWorkout = false,
  }) {
    final blocked = addsWorkout && !canAddWorkout;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NsListCard(
        icon: icon,
        title: title,
        subtitle: blocked ? _limitText : subtitle,
        onTap: blocked ? null : onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        if (current != null) ...[
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, EditChoice(current!)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit workout'),
          ),
          const SizedBox(height: 14),
        ],
        _option(
          context,
          icon: Icons.hotel_outlined,
          title: 'Rest day',
          subtitle: 'No training this day',
          onTap: () => Navigator.pop(context, const RestChoice()),
        ),
        _option(
          context,
          icon: Icons.add,
          title: 'New workout',
          subtitle: 'Choose the exercises yourself',
          addsWorkout: true,
          onTap: () => Navigator.pop(context, const NewWorkoutChoice()),
        ),
        _option(
          context,
          icon: Icons.library_books_outlined,
          title: 'Copy a ready-made workout',
          subtitle: 'From the Workouts library',
          addsWorkout: true,
          onTap: () async {
            final picked = await _pick<CatalogTemplate>(
              context,
              title: 'Ready-made workouts',
              entries: [
                for (final t in ref.read(templatesProvider))
                  (
                    value: t,
                    title: t.name,
                    subtitle: '${t.estimatedMinutes} min · ${t.level}',
                  ),
              ],
              emptyText: 'No ready-made workouts are available right now.',
            );
            if (picked != null && context.mounted) {
              Navigator.pop(context, TemplateChoice(picked));
            }
          },
        ),
        if (savedPlans.isNotEmpty)
          _option(
            context,
            icon: Icons.bookmark_border,
            title: 'Copy one of my saved workouts',
            subtitle: 'From before programs',
            addsWorkout: true,
            onTap: () async {
              final picked = await _pick<String>(
                context,
                title: 'My saved workouts',
                entries: [
                  for (final p in savedPlans)
                    (value: p.uuid, title: p.name, subtitle: 'Saved workout'),
                ],
                emptyText: 'No saved workouts.',
              );
              if (picked != null && context.mounted) {
                Navigator.pop(context, SavedPlanChoice(picked));
              }
            },
          ),
        if (existing.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'In this program',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in existing.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NsListCard(
                icon: Icons.fitness_center,
                title: entry.value,
                subtitle: entry.key == current ? 'On this day' : 'Use again',
                onTap: () => Navigator.pop(context, ExistingChoice(entry.key)),
              ),
            ),
        ],
      ],
    );
  }
}

typedef _Entry<T> = ({T value, String title, String subtitle});

Future<T?> _pick<T>(
  BuildContext context, {
  required String title,
  required List<_Entry<T>> entries,
  required String emptyText,
}) {
  return showNsSheet<T>(
    context,
    builder: (_) =>
        _PickerSheet<T>(title: title, entries: entries, emptyText: emptyText),
  );
}

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.entries,
    required this.emptyText,
  });

  final String title;
  final List<_Entry<T>> entries;
  final String emptyText;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final e in widget.entries)
        if (e.title.toLowerCase().contains(_query.trim().toLowerCase())) e,
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          widget.title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        if (widget.entries.length > 8) ...[
          NsTextField(
            label: 'Search',
            prefixIcon: Icons.search,
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 14),
        ],
        if (widget.entries.isEmpty) Text(widget.emptyText),
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NsListCard(
              icon: Icons.fitness_center,
              title: e.title,
              subtitle: e.subtitle,
              onTap: () => Navigator.pop(context, e.value),
            ),
          ),
      ],
    );
  }
}
