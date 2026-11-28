import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/inputs.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: BeyondRepTheme.build(brightness),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('shows the label and subtitle and toggles on tap', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, set) => NsSwitchRow(
            label: 'Make this my active program',
            subtitle: 'Replaces the current one.',
            value: value,
            onChanged: (v) => set(() => value = v),
          ),
        ),
      ),
    );
    expect(find.text('Make this my active program'), findsOneWidget);
    expect(find.text('Replaces the current one.'), findsOneWidget);
    await tester.tap(find.text('Make this my active program'));
    await tester.pump();
    expect(value, isTrue);
  });

  testWidgets('the row is at least 48 dp tall and exposes switch semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(NsSwitchRow(label: 'Quiet', value: true, onChanged: (_) {})),
    );
    expect(
      tester.getSize(find.byType(NsSwitchRow)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSemantics(find.byType(NsSwitchRow)),
      isSemantics(
        label: 'Quiet',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a null onChanged disables the row', (tester) async {
    await tester.pumpWidget(
      _host(const NsSwitchRow(label: 'Off', value: false, onChanged: null)),
    );
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNull);
  });

  testWidgets('renders in dark and at 2x text without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BeyondRepTheme.build(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: NsSwitchRow(
              label: 'Make this my active program',
              subtitle: 'Replaces the current one.',
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
