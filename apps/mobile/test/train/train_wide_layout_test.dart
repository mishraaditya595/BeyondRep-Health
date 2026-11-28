import 'dart:io';

import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'training_library_harness.dart';

const _wide = Size(1194, 834);

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-train-wide-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> openTrain(
    WidgetTester tester, {
    required bool program,
    Size size = _wide,
  }) async {
    if (program) seedLibraryProgram(store, 'prog.three');
    await pumpLibraryScreen(
      tester,
      store: store,
      directory: directory,
      location: '/train',
      size: size,
    );
  }

  testWidgets('wide Train puts Your program beside Start training', (
    tester,
  ) async {
    await openTrain(tester, program: true);
    final start = tester.getTopLeft(find.text('Start training'));
    final program = tester.getTopLeft(find.text('Your program'));
    expect(program.dy, start.dy);
    expect(program.dx, greaterThan(start.dx));
  });

  testWidgets('wide Train without a program keeps Start training full width', (
    tester,
  ) async {
    await openTrain(tester, program: false);
    expect(find.text('Your program'), findsNothing);
    final card = find.ancestor(
      of: find.text('Build the work.'),
      matching: find.byType(Card),
    );
    expect(
      tester.getSize(card.first).width,
      tester.getSize(find.byType(ListView).first).width - 32,
    );
  });
}
