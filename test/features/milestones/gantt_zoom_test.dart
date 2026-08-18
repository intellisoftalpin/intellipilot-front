import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/features/milestones/presentation/milestones_list_page.dart';

/// The timeline scale used to be four fixed stops (18 / 6 / 2.2 / 0.9 px per
/// day), so one click of + or − changed the chart by up to 3x with nothing in
/// between. These assert that zooming is now gradual and bounded.
void main() {
  group('GanttZoom', () {
    test('a single step is a small proportional change, not a jump', () {
      const from = GanttZoom.initial;
      final inOnce = GanttZoom.zoomIn(from);
      // Well under the old 3x jump, and large enough to be visible.
      expect(inOnce / from, closeTo(GanttZoom.step, 1e-9));
      expect(inOnce / from, lessThan(1.5));
      expect(inOnce / from, greaterThan(1.1));
    });

    test('zooming in then out returns to where it started', () {
      const from = 5.0;
      expect(GanttZoom.zoomOut(GanttZoom.zoomIn(from)), closeTo(from, 1e-9));
    });

    test('the range takes many steps to cross, so scales in between exist', () {
      var scale = GanttZoom.min;
      var steps = 0;
      while (GanttZoom.canZoomIn(scale) && steps < 100) {
        scale = GanttZoom.zoomIn(scale);
        steps++;
      }
      expect(scale, closeTo(GanttZoom.max, 1e-9));
      // The old enum crossed the whole range in three clicks.
      expect(steps, greaterThan(12));
    });

    test('clamps at both ends and disables its own buttons there', () {
      expect(GanttZoom.zoomIn(GanttZoom.max), GanttZoom.max);
      expect(GanttZoom.zoomOut(GanttZoom.min), GanttZoom.min);
      expect(GanttZoom.canZoomIn(GanttZoom.max), isFalse);
      expect(GanttZoom.canZoomOut(GanttZoom.min), isFalse);
      expect(GanttZoom.canZoomIn(GanttZoom.initial), isTrue);
      expect(GanttZoom.canZoomOut(GanttZoom.initial), isTrue);
    });

    test('every scale maps to a named tick density', () {
      expect(GanttZoom.scaleOf(GanttZoom.max), GanttScale.days);
      expect(GanttZoom.scaleOf(6), GanttScale.weeks);
      expect(GanttZoom.scaleOf(GanttZoom.initial), GanttScale.months);
      expect(GanttZoom.scaleOf(GanttZoom.min), GanttScale.quarters);
    });

    test('the named scales change over the range but not on every step', () {
      final seen = <GanttScale>{};
      var scale = GanttZoom.min;
      while (GanttZoom.canZoomIn(scale)) {
        seen.add(GanttZoom.scaleOf(scale));
        scale = GanttZoom.zoomIn(scale);
      }
      seen.add(GanttZoom.scaleOf(scale));
      // All four are reachable, so the label stays meaningful…
      expect(seen, hasLength(GanttScale.values.length));
      // …while the scale itself moves in far smaller increments than that.
      expect(GanttZoom.max / GanttZoom.min, greaterThan(50));
    });
  });
}
