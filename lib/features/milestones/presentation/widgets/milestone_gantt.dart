import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/progress_ring.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// palette, zoom, schedule helpers
// ---------------------------------------------------------------------------

/// Colours the timeline uses for everything that is not the bar itself.
/// Fixed hues rather than theme roles: they carry meaning (commercial /
/// late / early / overdue) that must not shift with the seed colour. Late and
/// early are always drawn *striped*, because bars take their project's colour
/// and the project palette itself contains a red and an orange.
abstract final class MilestonePalette {
  /// The commercial release tail. Blue — it is a shipping date, not a
  /// problem.
  static const business = Color(0xFF2F6FED);

  /// Time lost: a start or an end later than planned.
  static const overrun = Color(0xFFE8833A);

  /// Time saved: a start or an end earlier than planned.
  static const saved = Color(0xFF2E9E5B);

  /// Outline of a milestone past its planned end and still open.
  static const overdue = Color(0xFFD32F2F);
}

/// Parse a project colour (`#rrggbb`), or null when unset or malformed.
Color? parseProjectColor(String hex) {
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// The timeline scale, in pixels per day.
///
/// Continuous rather than four fixed stops: each click multiplies by [step],
/// which is a small enough ratio to feel like zooming and keeps every
/// intermediate scale reachable.
abstract final class GanttZoom {
  /// A whole year fits comfortably at the far end.
  static const double min = 0.3;

  /// Individual days are clearly separated at the near end.
  static const double max = 26;

  /// One click. ~26% per step gives roughly 19 stops across the range.
  static const double step = 1.26;

  /// Opening scale: a few months in view.
  static const double initial = 2.2;

  static double zoomIn(double v) => (v * step).clamp(min, max);
  static double zoomOut(double v) => (v / step).clamp(min, max);

  // Tolerances keep the buttons from staying enabled at a bound that
  // floating-point drift left a hair short of it.
  static bool canZoomIn(double v) => v < max * 0.999;
  static bool canZoomOut(double v) => v > min * 1.001;

  /// Which of the four named scales this pixel budget reads as, for the label
  /// between the buttons and for choosing tick spacing.
  static GanttScale scaleOf(double pxPerDay) {
    if (pxPerDay >= 10) return GanttScale.days;
    if (pxPerDay >= 4) return GanttScale.weeks;
    if (pxPerDay >= 1.4) return GanttScale.months;
    return GanttScale.quarters;
  }

  static String label(AppLocalizations t, double z) => switch (scaleOf(z)) {
    GanttScale.days => t.milestoneZoomDays,
    GanttScale.weeks => t.milestoneZoomWeeks,
    GanttScale.months => t.milestoneZoomMonths,
    GanttScale.quarters => t.milestoneZoomQuarters,
  };
}

/// The named scale a pixel budget falls into. Drives tick density and the
/// label shown between the zoom buttons.
enum GanttScale { days, weeks, months, quarters }

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// A milestone still in progress whose planned technical release has passed.
bool isAtRisk(Milestone m) {
  if (m.closed) return false;
  final end = m.endDate;
  if (end == null) return false;
  return end.isBefore(_today());
}

/// Effective schedule of a milestone for display: the start and end that
/// really happened when recorded, otherwise the plan. A missing start
/// defaults to today, a missing end to start + 7 days; [estimated] marks
/// defaulted values so views can render them as tentative.
({DateTime start, DateTime end, bool estimated}) effectiveRange(Milestone m) {
  final start = m.effectiveStartDate ?? _today();
  final end = m.effectiveEndDate ?? start.add(const Duration(days: 7));
  return (
    start: start,
    end: end.isBefore(start) ? start : end,
    estimated: m.effectiveStartDate == null || m.effectiveEndDate == null,
  );
}

/// Nearest deadline first, keyed on the end that really happened, so a
/// slipped milestone sits where its bar sits.
List<GanttEntry> sortByEnd(Iterable<GanttEntry> items) => items.toList()
  ..sort(
    (a, b) => effectiveRange(
      a.milestone,
    ).end.compareTo(effectiveRange(b.milestone).end),
  );

// ---------------------------------------------------------------------------
// public model
// ---------------------------------------------------------------------------

/// One milestone as the timeline draws it.
class GanttEntry {
  const GanttEntry({
    required this.milestone,
    required this.color,
    this.taskTotal = 0,
    this.taskClosed = 0,
    this.epicCount = 0,
    this.project,
  });

  final Milestone milestone;

  /// The bar colour — its project's colour.
  final Color color;
  final int taskTotal;
  final int taskClosed;
  final int epicCount;

  /// Set on the cross-project page, where rows need a project chip.
  final MilestoneProjectRef? project;

  double? get progress => taskTotal <= 0 ? null : taskClosed / taskTotal;
}

/// How the cross-project timeline orders its rows.
enum GanttGrouping { chronological, byProject }

/// Lets the page's toolbar scroll the chart back to today.
class MilestoneGanttController extends ChangeNotifier {
  void centerToday() => notifyListeners();
}

// ---------------------------------------------------------------------------
// the chart
// ---------------------------------------------------------------------------

const double _kLabelWidth = 340;
const double _kHeaderHeight = 40;
const double _kEntryHeight = 80;
const double _kGroupHeight = 40;
const double _kBandHeight = 48;
const double _kLoadingHeight = 48;
const double _kBarHeight = 22;

sealed class _Row {
  const _Row();
  double get height;
}

class _EntryRow extends _Row {
  const _EntryRow(this.entry);
  final GanttEntry entry;
  @override
  double get height => _kEntryHeight;
}

class _GroupRow extends _Row {
  const _GroupRow(this.project, this.color);
  final MilestoneProjectRef project;
  final Color color;
  @override
  double get height => _kGroupHeight;
}

class _BandRow extends _Row {
  const _BandRow();
  @override
  double get height => _kBandHeight;
}

class _LoadingRow extends _Row {
  const _LoadingRow();
  @override
  double get height => _kLoadingHeight;
}

/// Timeline of milestones as horizontal bars over a shared date axis.
///
/// Open milestones sit on top. Completed ones live in a band underneath that
/// starts collapsed — only its count is known until the user expands it and
/// the page fetches them. The date header stays put while rows scroll, the
/// chart opens centred on today, and zooming keeps the centre date fixed.
class MilestoneGantt extends StatefulWidget {
  const MilestoneGantt({
    required this.open,
    required this.completed,
    required this.completedCount,
    required this.completedExpanded,
    required this.completedLoading,
    required this.onToggleCompleted,
    required this.zoom,
    required this.showBusinessRelease,
    required this.onOpen,
    this.grouping = GanttGrouping.chronological,
    this.controller,
    super.key,
  });

  final List<GanttEntry> open;

  /// Completed entries loaded so far; ignored while collapsed.
  final List<GanttEntry> completed;
  final int completedCount;
  final bool completedExpanded;
  final bool completedLoading;
  final VoidCallback onToggleCompleted;

  /// Pixels per day.
  final double zoom;

  /// Whether the business release tail may be drawn — only the per-project
  /// page knows this as one flag; the cross-project API already strips the
  /// date where the viewer may not see it.
  final bool showBusinessRelease;
  final GanttGrouping grouping;
  final void Function(GanttEntry entry) onOpen;
  final MilestoneGanttController? controller;

  @override
  State<MilestoneGantt> createState() => _MilestoneGanttState();
}

class _MilestoneGanttState extends State<MilestoneGantt> {
  final _body = ScrollController();
  final _header = ScrollController();

  // What the last frame was drawn with, so a change of scale or window can
  // keep the date in the middle of the viewport where it was.
  DateTime? _lastMin;
  double? _lastZoom;
  double _viewport = 0;
  bool _centred = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(_syncHeader);
    widget.controller?.addListener(_animateToToday);
  }

  @override
  void didUpdateWidget(covariant MilestoneGantt old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_animateToToday);
      widget.controller?.addListener(_animateToToday);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_animateToToday);
    _body
      ..removeListener(_syncHeader)
      ..dispose();
    _header.dispose();
    super.dispose();
  }

  void _syncHeader() {
    if (!_header.hasClients || !_body.hasClients) return;
    final max = _header.position.maxScrollExtent;
    _header.jumpTo(_body.offset.clamp(0.0, max));
  }

  double _offsetForToday(DateTime min, double zoom) =>
      _today().difference(min).inDays * zoom - _viewport / 2 + zoom / 2;

  void _animateToToday() {
    final min = _lastMin;
    final zoom = _lastZoom;
    if (min == null || zoom == null || !_body.hasClients) return;
    final target = _offsetForToday(
      min,
      zoom,
    ).clamp(0.0, _body.position.maxScrollExtent);
    _body.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  /// After a layout change, put the scroll position where it must be: centred
  /// on today the first time, and on the previous centre date afterwards.
  void _scheduleScroll(DateTime min, double zoom) {
    final lastMin = _lastMin;
    final lastZoom = _lastZoom;
    final firstTime = !_centred;
    final changed =
        lastMin != null &&
        lastZoom != null &&
        (lastMin != min || lastZoom != zoom);
    if (!firstTime && !changed) return;
    final double? target;
    if (firstTime) {
      target = _offsetForToday(min, zoom);
      _centred = true;
    } else if (_body.hasClients) {
      final centreDays = (_body.offset + _viewport / 2) / lastZoom!;
      final shift = lastMin!.difference(min).inDays;
      target = (centreDays + shift) * zoom - _viewport / 2;
    } else {
      target = null;
    }
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_body.hasClients) return;
      _body.jumpTo(target!.clamp(0.0, _body.position.maxScrollExtent));
      _syncHeader();
    });
  }

  List<_Row> _rows() {
    final rows = <_Row>[];
    void addAll(List<GanttEntry> entries) {
      if (widget.grouping == GanttGrouping.chronological) {
        rows.addAll(sortByEnd(entries).map(_EntryRow.new));
        return;
      }
      // By project: groups in order of each project's nearest deadline, so
      // the group that needs attention first still comes first.
      final groups = <String, List<GanttEntry>>{};
      for (final e in sortByEnd(entries)) {
        groups.putIfAbsent(e.project?.id ?? '', () => []).add(e);
      }
      for (final g in groups.values) {
        final p = g.first.project;
        if (p != null) rows.add(_GroupRow(p, g.first.color));
        rows.addAll(g.map(_EntryRow.new));
      }
    }

    addAll(widget.open);
    if (widget.completedCount > 0) {
      rows.add(const _BandRow());
      if (widget.completedExpanded) {
        if (widget.completedLoading) {
          rows.add(const _LoadingRow());
        } else {
          addAll(widget.completed);
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows();
    final drawn = [
      ...widget.open,
      if (widget.completedExpanded) ...widget.completed,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = math.max(0, constraints.maxWidth - _kLabelWidth - 16);
        final zoom = widget.zoom;

        // Window: every bar, every planned date, the business tails, and
        // enough room either side of today that it can sit mid-screen.
        final today = _today();
        final halfView = Duration(days: (_viewport / 2 / zoom).ceil() + 1);
        var min = today.subtract(halfView);
        var max = today.add(halfView);
        void widen(DateTime? d) {
          if (d == null) return;
          if (d.isBefore(min)) min = d;
          if (d.isAfter(max)) max = d;
        }

        for (final e in drawn) {
          final m = e.milestone;
          final r = effectiveRange(m);
          widen(r.start);
          widen(r.end);
          widen(m.startDate);
          widen(m.endDate);
          if (widget.showBusinessRelease) widen(m.businessReleaseDate);
        }
        min = min.subtract(const Duration(days: 14));
        max = max.add(const Duration(days: 30));
        // Snap to the first of the month so the window — and with it the
        // scroll position — does not creep as "today" moves.
        min = DateTime(min.year, min.month);
        final totalDays = max.difference(min).inDays.clamp(1, 7300);
        final chartWidth = totalDays * zoom;
        double x(DateTime d) => d.difference(min).inDays * zoom;

        _scheduleScroll(min, zoom);
        _lastMin = min;
        _lastZoom = zoom;

        final chartHeight = rows.fold<double>(0, (h, r) => h + r.height);

        return Column(
          children: [
            // Sticky date header: scrolls sideways with the chart, never down.
            SizedBox(
              height: _kHeaderHeight,
              child: Row(
                children: [
                  const SizedBox(width: _kLabelWidth + 16),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _header,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: chartWidth,
                        height: _kHeaderHeight,
                        child: _Header(min: min, max: max, zoom: zoom, x: x),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(left: 16, bottom: 96),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _kLabelWidth,
                      child: Column(
                        children: [
                          for (final r in rows)
                            SizedBox(
                              height: r.height,
                              child: _label(context, r),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _body,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: chartWidth,
                          height: chartHeight,
                          child: _chart(
                            context,
                            rows: rows,
                            min: min,
                            max: max,
                            zoom: zoom,
                            x: x,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _label(BuildContext context, _Row r) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return switch (r) {
      _EntryRow(:final entry) => _GanttLabel(
        entry: entry,
        onTap: () => widget.onOpen(entry),
      ),
      _GroupRow(:final project, :final color) => Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                project.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
      _BandRow() => Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: widget.completedExpanded
              ? t.milestoneHideCompleted
              : t.milestoneShowCompleted,
          child: TextButton.icon(
            onPressed: widget.onToggleCompleted,
            icon: Icon(
              widget.completedExpanded
                  ? Icons.expand_more
                  : Icons.chevron_right,
            ),
            label: Text(t.milestoneCompletedBand(widget.completedCount)),
          ),
        ),
      ),
      _LoadingRow() => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(left: 16),
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    };
  }

  Widget _chart(
    BuildContext context, {
    required List<_Row> rows,
    required DateTime min,
    required DateTime max,
    required double zoom,
    required double Function(DateTime) x,
  }) {
    final theme = Theme.of(context);
    final children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: _GridPainter(
            min: min,
            max: max,
            zoom: zoom,
            line: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    ];
    var top = 0.0;
    for (final r in rows) {
      switch (r) {
        case _GroupRow(:final color):
          children.add(
            Positioned(
              left: 0,
              right: 0,
              top: top + 4,
              height: r.height - 8,
              child: ColoredBox(color: color.withValues(alpha: 0.06)),
            ),
          );
        case _BandRow():
          children.add(
            Positioned(
              left: 0,
              right: 0,
              top: top + r.height / 2,
              child: Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
          );
        case _EntryRow(:final entry):
          children.add(
            _bar(context, entry, top: top, height: r.height, zoom: zoom, x: x),
          );
        case _LoadingRow():
          break;
      }
      top += r.height;
    }
    children.add(
      Positioned(
        left: x(_today()) + zoom / 2 - 1,
        top: 0,
        bottom: 0,
        child: IgnorePointer(
          child: Container(
            width: 2,
            color: MilestonePalette.overdue.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
    return Stack(children: children);
  }

  Widget _bar(
    BuildContext context,
    GanttEntry e, {
    required double top,
    required double height,
    required double zoom,
    required double Function(DateTime) x,
  }) {
    final m = e.milestone;
    final r = effectiveRange(m);
    final business = widget.showBusinessRelease ? m.businessReleaseDate : null;
    // The painted span: the bar plus any late-start / early-end gap and the
    // business tail, so one gesture area covers everything the row draws.
    var from = r.start;
    var to = r.end;
    for (final d in [m.startDate, m.endDate, business]) {
      if (d == null) continue;
      if (d.isBefore(from)) from = d;
      if (d.isAfter(to)) to = d;
    }
    final left = x(from);
    final width = (to.difference(from).inDays + 1) * zoom;
    return Positioned(
      left: left,
      top: top,
      width: math.max(width, 6),
      height: height,
      child: Tooltip(
        message: _tooltip(context, e),
        waitDuration: const Duration(milliseconds: 300),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => widget.onOpen(e),
            child: CustomPaint(
              painter: _BarPainter(
                origin: from,
                zoom: zoom,
                milestone: m,
                range: r,
                business: business,
                progress: e.progress,
                color: e.color,
                muted: Theme.of(context).colorScheme.outline,
                overdue: isAtRisk(m),
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _tooltip(BuildContext context, GanttEntry e) {
    final t = AppLocalizations.of(context);
    final m = e.milestone;
    String d(DateTime? v) => v == null ? '—' : isoDate(v);
    final r = effectiveRange(m);
    final actual =
        '${t.milestoneActualShort}: '
        '${d(m.actualStartDate)} → ${d(m.actualEndDate)}';
    return [
      m.name,
      if (e.project != null) e.project!.name,
      '${t.milestonePlannedShort}: ${d(m.startDate)} → ${d(m.endDate)}',
      if (m.actualStartDate != null || m.actualEndDate != null) actual,
      if (widget.showBusinessRelease && m.businessReleaseDate != null)
        '${t.milestoneFieldBusinessRelease}: ${d(m.businessReleaseDate)}',
      if (e.taskTotal > 0) t.milestoneTooltipTasks(e.taskClosed, e.taskTotal),
      t.milestoneEpicCount(e.epicCount),
      if (r.estimated) t.milestonesDatesEstimated,
    ].join('\n');
  }
}

// ---------------------------------------------------------------------------
// header, grid, bar
// ---------------------------------------------------------------------------

/// Month (or quarter) labels plus the "Today" pill over the red line.
class _Header extends StatelessWidget {
  const _Header({
    required this.min,
    required this.max,
    required this.zoom,
    required this.x,
  });
  final DateTime min;
  final DateTime max;
  final double zoom;
  final double Function(DateTime) x;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fmt = DateFormat.yMMM(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final today = _today();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final month in _ticks(min, max, zoom))
          Positioned(
            left: x(month) + 4,
            bottom: 6,
            child: Text(
              fmt.format(month),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        Positioned(
          left: x(today) + zoom / 2 - 28,
          top: 2,
          width: 56,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: MilestonePalette.overdue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                t.milestonesToday,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// First-of-month ticks across the window; quarters only at the coarsest
/// zooms so the header does not turn into a smear.
List<DateTime> _ticks(DateTime min, DateTime max, double zoom) {
  final every = GanttZoom.scaleOf(zoom) == GanttScale.quarters ? 3 : 1;
  final out = <DateTime>[];
  var tick = DateTime(min.year, min.month);
  while (!tick.isAfter(max)) {
    if (!tick.isBefore(min) && (tick.month - 1) % every == 0) out.add(tick);
    tick = DateTime(tick.year, tick.month + 1);
  }
  return out;
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.min,
    required this.max,
    required this.zoom,
    required this.line,
  });
  final DateTime min;
  final DateTime max;
  final double zoom;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final tick in _ticks(min, max, zoom)) {
      final dx = tick.difference(min).inDays * zoom;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.min != min || old.max != max || old.zoom != zoom || old.line != line;
}

/// One row's bar.
///
/// * The bar runs from the start that really happened to the end that really
///   happened, in the project colour: a light track with the done fraction
///   filled in solid.
/// * Deviations from the plan are striped — orange when late, green when
///   early — at the start and at the end. A late start leaves a striped gap
///   before the bar; an early end leaves one after it; an early start or a
///   late end stripes the bar itself.
/// * The business release is a thin blue tail ending in a diamond.
/// * Estimated dates get a dashed outline, an overdue milestone a red one.
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.origin,
    required this.zoom,
    required this.milestone,
    required this.range,
    required this.business,
    required this.progress,
    required this.color,
    required this.muted,
    required this.overdue,
    required this.dark,
  });

  final DateTime origin;
  final double zoom;
  final Milestone milestone;
  final ({DateTime start, DateTime end, bool estimated}) range;
  final DateTime? business;
  final double? progress;
  final Color color;
  final Color muted;
  final bool overdue;

  /// Dark surfaces need a stronger track for an empty bar to stay visible.
  final bool dark;

  static const _radius = Radius.circular(6);

  double _x(DateTime d) => d.difference(origin).inDays * zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final m = milestone;
    final top = (size.height - _kBarHeight) / 2;
    final completed = m.closed;
    final base = completed ? Color.lerp(color, muted, 0.55)! : color;

    Rect span(DateTime from, DateTime toExclusive, {double inset = 0}) =>
        Rect.fromLTRB(
          _x(from),
          top + inset,
          math.max(_x(toExclusive), _x(from) + 3),
          top + _kBarHeight - inset,
        );
    DateTime next(DateTime d) => d.add(const Duration(days: 1));

    final barRect = span(range.start, next(range.end));
    final bar = RRect.fromRectAndRadius(barRect, _radius);

    // Business release tail, behind the bar.
    final biz = business;
    final techEnd = m.effectiveEndDate;
    if (biz != null && techEnd != null && biz.isAfter(techEnd)) {
      final tail = span(next(techEnd), next(biz), inset: 7);
      canvas.drawRRect(
        RRect.fromRectAndRadius(tail, const Radius.circular(3)),
        Paint()..color = MilestonePalette.business.withValues(alpha: 0.75),
      );
      final c = Offset(tail.right, tail.center.dy);
      final diamond = Path()
        ..moveTo(c.dx, c.dy - 7)
        ..lineTo(c.dx + 7, c.dy)
        ..lineTo(c.dx, c.dy + 7)
        ..lineTo(c.dx - 7, c.dy)
        ..close();
      canvas.drawPath(diamond, Paint()..color = MilestonePalette.business);
    }

    // Track and done fraction.
    canvas.drawRRect(
      bar,
      Paint()
        ..color = base.withValues(
          alpha: (completed ? 0.45 : 0.28) + (dark ? 0.2 : 0),
        ),
    );
    final p = progress;
    if (p != null && p > 0) {
      canvas
        ..save()
        ..clipRRect(bar)
        ..drawRect(
          Rect.fromLTWH(
            barRect.left,
            barRect.top,
            barRect.width * p.clamp(0.0, 1.0),
            barRect.height,
          ),
          Paint()..color = base.withValues(alpha: 0.9),
        )
        ..restore();
    }

    // Start deviation.
    final ps = m.startDate;
    final as = m.actualStartDate;
    if (ps != null && as != null && ps != as) {
      final late = as.isAfter(ps);
      _stripes(
        canvas,
        late ? span(ps, as) : span(as, ps),
        late ? MilestonePalette.overrun : MilestonePalette.saved,
        roundLeft: true,
      );
    }
    // End deviation.
    final pe = m.endDate;
    final ae = m.actualEndDate;
    if (pe != null && ae != null && pe != ae) {
      final late = ae.isAfter(pe);
      _stripes(
        canvas,
        late ? span(next(pe), next(ae)) : span(next(ae), next(pe)),
        late ? MilestonePalette.overrun : MilestonePalette.saved,
        roundRight: true,
      );
    }

    if (range.estimated) {
      _dashed(canvas, bar, base);
    }
    if (overdue) {
      canvas.drawRRect(
        bar.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = MilestonePalette.overdue,
      );
    }
  }

  void _stripes(
    Canvas canvas,
    Rect r,
    Color c, {
    bool roundLeft = false,
    bool roundRight = false,
  }) {
    final shape = RRect.fromRectAndCorners(
      r,
      topLeft: roundLeft ? _radius : Radius.zero,
      bottomLeft: roundLeft ? _radius : Radius.zero,
      topRight: roundRight ? _radius : Radius.zero,
      bottomRight: roundRight ? _radius : Radius.zero,
    );
    canvas
      ..save()
      ..clipRRect(shape)
      ..drawRect(r, Paint()..color = c.withValues(alpha: 0.3));
    final line = Paint()
      ..color = c
      ..strokeWidth = 2.5;
    for (var dx = r.left - r.height; dx < r.right; dx += 7) {
      canvas.drawLine(
        Offset(dx, r.bottom),
        Offset(dx + r.height, r.top),
        line,
      );
    }
    canvas.restore();
  }

  void _dashed(Canvas canvas, RRect shape, Color c) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = c;
    for (final metric in (Path()..addRRect(shape)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.origin != origin ||
      old.zoom != zoom ||
      old.milestone != milestone ||
      old.business != business ||
      old.progress != progress ||
      old.color != color ||
      old.muted != muted ||
      old.overdue != overdue ||
      old.dark != dark;
}

// ---------------------------------------------------------------------------
// row labels
// ---------------------------------------------------------------------------

class _GanttLabel extends StatelessWidget {
  const _GanttLabel({required this.entry, required this.onTap});
  final GanttEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final m = entry.milestone;
    final completed = m.closed;
    final project = entry.project;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          children: [
            ProgressRing(value: entry.progress, size: 40, completed: completed),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (project != null) ...[
                        _ProjectChip(project: project, color: entry.color),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          m.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: completed
                                ? theme.colorScheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                      ),
                      if (isAtRisk(m))
                        Tooltip(
                          message: t.milestoneOverdue,
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: MilestonePalette.overdue,
                          ),
                        ),
                    ],
                  ),
                  RowDates(milestone: m),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectChip extends StatelessWidget {
  const _ProjectChip({required this.project, required this.color});
  final MilestoneProjectRef project;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Tooltip(
      message: project.name,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          project.prefix.isEmpty ? project.name : project.prefix,
          style: theme.textTheme.labelSmall?.copyWith(
            color: onColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The planned range under each row, plus the actual one once anything of it
/// is recorded — each actual date coloured by whether it came late or early,
/// so the row says the same thing as its bar without reading the chart.
class RowDates extends StatelessWidget {
  const RowDates({required this.milestone, super.key});
  final Milestone milestone;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final m = milestone;
    final small = theme.textTheme.labelSmall;
    final quiet = small?.copyWith(color: theme.colorScheme.outline);
    String d(DateTime? v) => v == null ? '—' : isoDate(v);

    TextSpan actual(DateTime? date, int? slip) {
      if (date == null) return TextSpan(text: '—', style: quiet);
      final colour = slip == null
          ? theme.colorScheme.onSurfaceVariant
          : (slip > 0 ? MilestonePalette.overrun : MilestonePalette.saved);
      return TextSpan(
        text:
            '${isoDate(date)}'
            '${slip == null ? '' : ' (${slip > 0 ? '+' : ''}$slip)'}',
        style: small?.copyWith(color: colour, fontWeight: FontWeight.w600),
      );
    }

    final hasPlan = m.startDate != null || m.endDate != null;
    final hasActual = m.actualStartDate != null || m.actualEndDate != null;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPlan)
            Text(
              '${t.milestonePlannedShort} ${d(m.startDate)} → ${d(m.endDate)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: quiet,
            ),
          if (hasActual)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${t.milestoneActualShort} ', style: quiet),
                  actual(m.actualStartDate, m.startSlipDays),
                  TextSpan(text: ' → ', style: quiet),
                  actual(m.actualEndDate, m.slipDays),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// legend
// ---------------------------------------------------------------------------

/// A one-line key to the bar's encodings.
class MilestoneGanttLegend extends StatelessWidget {
  const MilestoneGanttLegend({
    required this.showBusinessRelease,
    this.color,
    super.key,
  });

  final bool showBusinessRelease;

  /// The bar colour on a single-project page; a neutral one otherwise.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final base = color ?? theme.colorScheme.primary;
    Widget item(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    Widget swatch(CustomPainter p) =>
        SizedBox(width: 22, height: 12, child: CustomPaint(painter: p));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          item(swatch(_SwatchPainter.done(base)), t.milestoneLegendDone),
          item(
            swatch(_SwatchPainter.striped(MilestonePalette.overrun)),
            t.milestoneLegendLate,
          ),
          item(
            swatch(_SwatchPainter.striped(MilestonePalette.saved)),
            t.milestoneLegendEarly,
          ),
          if (showBusinessRelease)
            item(
              swatch(
                _SwatchPainter.solid(MilestonePalette.business, thin: true),
              ),
              t.milestoneFieldBusinessRelease,
            ),
          item(
            swatch(_SwatchPainter.outlined(MilestonePalette.overdue)),
            t.milestoneLegendOverdue,
          ),
        ],
      ),
    );
  }
}

@immutable
class _SwatchPainter extends CustomPainter {
  const _SwatchPainter._(this.kind, this.color, {this.thin = false});
  factory _SwatchPainter.done(Color c) => _SwatchPainter._(0, c);
  factory _SwatchPainter.striped(Color c) => _SwatchPainter._(1, c);
  factory _SwatchPainter.solid(Color c, {bool thin = false}) =>
      _SwatchPainter._(2, c, thin: thin);
  factory _SwatchPainter.outlined(Color c) => _SwatchPainter._(3, c);

  final int kind;
  final Color color;
  final bool thin;

  @override
  void paint(Canvas canvas, Size size) {
    final r = thin
        ? Rect.fromLTWH(0, size.height / 2 - 2, size.width, 4)
        : Offset.zero & size;
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
    switch (kind) {
      case 0:
        canvas
          ..drawRRect(rr, Paint()..color = color.withValues(alpha: 0.28))
          ..save()
          ..clipRRect(rr)
          ..drawRect(
            Rect.fromLTWH(0, 0, size.width * 0.6, size.height),
            Paint()..color = color.withValues(alpha: 0.9),
          )
          ..restore();
      case 1:
        canvas
          ..save()
          ..clipRRect(rr)
          ..drawRect(r, Paint()..color = color.withValues(alpha: 0.3));
        final line = Paint()
          ..color = color
          ..strokeWidth = 2;
        for (var dx = -size.height; dx < size.width; dx += 6) {
          canvas.drawLine(
            Offset(dx, size.height),
            Offset(dx + size.height, 0),
            line,
          );
        }
        canvas.restore();
      case 2:
        canvas.drawRRect(rr, Paint()..color = color);
      default:
        canvas.drawRRect(
          rr.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color,
        );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.kind != kind || old.color != color || old.thin != thin;
}
