import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Project dashboard card listing members who are out today (vacation /
/// illness / day-off / holiday).
class AvailabilityCard extends StatefulWidget {
  const AvailabilityCard({required this.projectId, super.key});
  final String projectId;

  @override
  State<AvailabilityCard> createState() => _AvailabilityCardState();
}

class _AvailabilityCardState extends State<AvailabilityCard> {
  List<Availability>? _people;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final res = await getIt<TimesheetRepository>().availability(
      widget.projectId,
    );
    if (!mounted) return;
    setState(() => _people = res.valueOrNull ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    if (people == null) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_busy_outlined),
                const SizedBox(width: 8),
                Text(
                  t.ttUnavailableToday,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (people.isEmpty)
              Text(t.ttNobodyOut, style: Theme.of(context).textTheme.bodyMedium)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in people)
                    Chip(
                      avatar: Icon(kindIcon(p.kind), size: 18),
                      label: Text('${p.displayName} · ${kindLabel(t, p.kind)}'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
