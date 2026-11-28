import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exact string literals that are wire keys or identifiers, not text.
const _wireLiterals = {'plan_id', 'plans', 'plans_snapshot', 'plan'};

final _token = RegExp(
  r'''//[^\n]*|/\*[\s\S]*?\*/|\'\'\'[\s\S]*?\'\'\'|"""[\s\S]*?"""|'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"''',
);
final _word = RegExp(r'\bplans?\b', caseSensitive: false);

/// Statements whose strings are never shown to people: internal invariants
/// (`throw ...Error(...)`, `throw ...Exception(...)`), an exception's
/// `toString() =>` and the debug import hook.
final _internal = RegExp(
  r'^(?:(?:if\s*\([^;{}]*\)\s*)?throw\s+(?:const\s+)?[\w.]*(?:Error|Exception)\s*[(.]'
  r'|(?:@override\s+)?String\s+toString\(\)\s*=>'
  r'|debugImportHook\?\.call\()',
);

/// The `file:line: text` hits for user-visible "plan" in [source].
List<String> planHits(String path, String source) {
  // Interpolated code is not text: `${plan.x}` is an identifier.
  final code = source.replaceAllMapped(
    RegExp(r'\$\{[^{}]*\}'),
    (m) => '\n' * '\n'.allMatches(m[0]!).length,
  );
  final hits = <String>[];
  for (final m in _token.allMatches(code)) {
    final raw = m[0]!;
    if (raw.startsWith('//') || raw.startsWith('/*')) continue;
    final triple = raw.startsWith("'''") || raw.startsWith('"""');
    final text = raw
        .substring(triple ? 3 : 1, raw.length - (triple ? 3 : 1))
        .replaceAll(RegExp(r'\$\w+'), '');
    if (!_word.hasMatch(text)) continue;
    // The statement this literal belongs to: from the previous ; { or }.
    final before = code.substring(0, m.start);
    final cut = [
      before.lastIndexOf(';'),
      before.lastIndexOf('{'),
      before.lastIndexOf('}'),
    ].reduce((a, b) => a > b ? a : b);
    final statement = code.substring(cut + 1, m.start).trimLeft();
    if (statement.startsWith(RegExp(r'(?:import|export|part)\s'))) continue;
    if (_internal.hasMatch(statement)) continue;
    if (text.contains('/train/plans/')) continue;
    if (path.startsWith('lib/features/watch/') &&
        _wireLiterals.contains(text)) {
      continue;
    }
    final line = '\n'.allMatches(before).length + 1;
    hits.add('$path:$line: ${text.trim()}');
  }
  return hits;
}

/// Programs replaced plans: no user-visible string in lib/ says plan.
void main() {
  test('no user-visible string in lib/ says plan', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      hits.addAll(planHits(entity.path, entity.readAsStringSync()));
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  group('the guard itself', () {
    List<String> hits(String source, {String path = 'lib/x.dart'}) =>
        planHits(path, source);

    test('wire keys are exempt only in the watch files', () {
      expect(
        hits("final k = 'plans';", path: 'lib/features/watch/x.dart'),
        isEmpty,
      );
      expect(
        hits("final k = 'plans';", path: 'lib/features/train/x.dart'),
        hasLength(1),
      );
    });

    test('ordinary text and calls are caught', () {
      expect(hits("Text('Your plan');"), hasLength(1));
      expect(hits("showError('plan');"), hasLength(1));
      expect(hits("final e = StateError('Unknown plan');"), hasLength(1));
      expect(hits("Text('Planet');"), isEmpty);
      expect(hits("context.push('/train/plans/new');"), isEmpty);
      expect(hits(r"Text('${plan.name}');"), isEmpty);
    });

    test('throwing an error or exception is internal, also over lines', () {
      expect(hits("throw StateError('Unknown plan');"), isEmpty);
      expect(
        hits("if (x) {\n  throw ArgumentError(\n    'Invalid plan',\n  );\n}"),
        isEmpty,
      );
      expect(hits("throw const FormatException('plan');"), isEmpty);
      expect(hits("if (a == null) throw StateError('Unknown plan');"), isEmpty);
      expect(
        hits(
          "class E {\n  @override\n  String toString() => 'plan changed';\n}",
        ),
        isEmpty,
      );
    });

    test('triple-quoted strings and comments', () {
      expect(hits("final t = '''\nOpen your plan\n''';"), hasLength(1));
      expect(hits('final t = """\nOpen your plan\n""";'), hasLength(1));
      expect(hits("// a plan in a comment\nfinal x = 1;"), isEmpty);
      expect(hits("import 'package:x/plan.dart';"), isEmpty);
      expect(hits("final u = 'https://x.dev/a'; // plan"), isEmpty);
    });
  });
}
