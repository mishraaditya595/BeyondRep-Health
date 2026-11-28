import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exact string literals that are wire keys or identifiers, not text.
const _wireLiterals = {'plan_id', 'plans', 'plans_snapshot', 'plan'};

/// The `file:line: text` hits for user-visible "plan" in [lines].
List<String> planHits(String path, List<String> lines) {
  final literal = RegExp(r'''(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''');
  final word = RegExp(r'\bplans?\b', caseSensitive: false);
  final hits = <String>[];
  for (var i = 0; i < lines.length; i++) {
    // Interpolated code is not text: `${plan.x}` is an identifier.
    final line = lines[i].replaceAll(RegExp(r'\$\{[^{}]*\}'), '');
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') ||
        trimmed.startsWith('import ') ||
        trimmed.startsWith('export ')) {
      continue;
    }
    for (final m in literal.allMatches(line)) {
      final text = m.group(1) ?? m.group(2) ?? '';
      if (!word.hasMatch(text)) continue;
      // Internal invariants and debug hook names are never shown to people.
      final context = '${i > 0 ? lines[i - 1] : ''}\n$line';
      if (RegExp(r'(?:Error|Exception)\(|toString\(\) =>|debugImportHook')
          .hasMatch(context)) {
        continue;
      }
      if (text.contains('/train/plans/')) continue;
      if (path.startsWith('lib/features/watch/') &&
          _wireLiterals.contains(text)) {
        continue;
      }
      hits.add('$path:${i + 1}: $text');
    }
  }
  return hits;
}

/// Programs replaced plans: no user-visible string in lib/ says plan.
void main() {
  test('no user-visible string in lib/ says plan', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      hits.addAll(planHits(entity.path, entity.readAsLinesSync()));
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('wire keys are exempt only in the watch files', () {
    expect(planHits('lib/features/watch/x.dart', ["'plans'"]), isEmpty);
    expect(planHits('lib/features/train/x.dart', ["'plans'"]), hasLength(1));
    expect(planHits('lib/x.dart', ["Text('Your plan')"]), hasLength(1));
    expect(planHits('lib/x.dart', ["Text('Planet')"]), isEmpty);
    expect(
      planHits('lib/x.dart', ["context.push('/train/plans/new')"]),
      isEmpty,
    );
    expect(planHits('lib/x.dart', [r"Text('${plan.name}')"]), isEmpty);
    expect(
      planHits('lib/x.dart', ["throw StateError('Unknown plan');"]),
      isEmpty,
    );
  });
}
