import 'package:flutter/material.dart';

import '../../core/design/page_header.dart';
import 'plan_fit.dart';

/// "A and B", "A, B and C"; more than three names the first three and more.
String joinMuscleGroups(Set<String> groups) {
  final sorted = groups.toList()..sort();
  if (sorted.length > 3) return '${sorted.take(3).join(', ')} and more';
  if (sorted.length < 3) return sorted.join(' and ');
  return '${sorted.take(2).join(', ')} and ${sorted.last}';
}

/// Empty when the workout has no mapped muscle group.
String planRecoveryLine(PlanRecovery? recovery) {
  if (recovery == null) return '';
  return recovery.isRecovered
      ? '\nRecovered'
      : '\n${joinMuscleGroups(recovery.recovering)} recovering';
}

/// The "Better fit today" suggestion: the tag, the workout and why, and Start.
class BetterFitCard extends StatelessWidget {
  const BetterFitCard({
    required this.name,
    required this.suggestion,
    required this.onStart,
    super.key,
  });

  final String name;
  final PlanSuggestion suggestion;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final reason = switch (suggestion) {
      SuggestRecovered(:final restedGroups) =>
        '${joinMuscleGroups(restedGroups)} still recovering · '
            'this workout rests them',
      SuggestLightest() =>
        'Lightest workout with recovered muscles · keep effort around RPE 7',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: NsTag('Better fit today'),
          ),
          NsListCard(
            icon: Icons.bolt,
            title: name,
            subtitle: reason,
            trailing: TextButton(
              onPressed: onStart,
              child: const Text('Start'),
            ),
          ),
        ],
      ),
    );
  }
}
