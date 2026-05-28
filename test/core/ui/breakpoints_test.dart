import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';

Widget _harness({required double width, required Widget child}) {
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

void main() {
  group('Breakpoints.of', () {
    testWidgets('< 600 px is compact', (tester) async {
      late Breakpoint observed;
      await tester.pumpWidget(
        _harness(
          width: 400,
          child: Builder(
            builder: (context) {
              observed = Breakpoints.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(observed, Breakpoint.compact);
    });

    testWidgets('600–839 px is medium', (tester) async {
      late Breakpoint observed;
      await tester.pumpWidget(
        _harness(
          width: 700,
          child: Builder(
            builder: (context) {
              observed = Breakpoints.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(observed, Breakpoint.medium);
    });

    testWidgets('>= 840 px is expanded', (tester) async {
      late Breakpoint observed;
      await tester.pumpWidget(
        _harness(
          width: 1200,
          child: Builder(
            builder: (context) {
              observed = Breakpoints.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(observed, Breakpoint.expanded);
    });
  });

  group('responsiveValue', () {
    testWidgets('falls back from expanded → medium → compact', (tester) async {
      late double picked;
      await tester.pumpWidget(
        _harness(
          width: 700,
          child: Builder(
            builder: (context) {
              picked = responsiveValue<double>(
                context,
                compact: 1,
                // medium omitted on purpose — should fall back to compact.
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(picked, 1);
    });
  });
}
