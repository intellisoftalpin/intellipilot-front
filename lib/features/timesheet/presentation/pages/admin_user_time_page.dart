import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/widgets/app_scaffold.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Superadmin page: a user's yearly vacation allowances (with carryover) and
/// their daily work target.
class AdminUserTimePage extends StatefulWidget {
  const AdminUserTimePage({required this.userId, super.key});
  final String userId;

  @override
  State<AdminUserTimePage> createState() => _AdminUserTimePageState();
}

class _AdminUserTimePageState extends State<AdminUserTimePage> {
  List<VacationAllowance> _allowances = const [];
  bool _loading = true;

  late final _year = TextEditingController(text: '${DateTime.now().year}');
  final _allowance = TextEditingController();
  final _carry = TextEditingController();
  final _workMinutes = TextEditingController(text: '480');

  TimesheetRepository get _repo => getIt<TimesheetRepository>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _year.dispose();
    _allowance.dispose();
    _carry.dispose();
    _workMinutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _repo.listAllowances(widget.userId);
    if (!mounted) return;
    setState(() {
      _allowances = res.valueOrNull ?? const [];
      _loading = false;
    });
  }

  Future<void> _saveAllowance() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final year = int.tryParse(_year.text);
    final days = double.tryParse(_allowance.text.replaceAll(',', '.'));
    final carry = double.tryParse(_carry.text.replaceAll(',', '.')) ?? 0;
    if (year == null || days == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.ttActionFailed)));
      return;
    }
    final res = await _repo.setAllowance(
      widget.userId,
      year: year,
      allowanceDays: days,
      carriedOverDays: carry,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(res.isOk ? t.ttSaved : t.ttActionFailed)),
    );
    if (res.isOk) await _load();
  }

  Future<void> _saveWork() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final minutes = int.tryParse(_workMinutes.text);
    if (minutes == null || minutes < 1) {
      messenger.showSnackBar(SnackBar(content: Text(t.ttActionFailed)));
      return;
    }
    final res = await _repo.setWorkSettings(
      widget.userId,
      workMinutesPerDay: minutes,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(res.isOk ? t.ttSaved : t.ttActionFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppScaffold(
      title: Text(t.ttAdminTimeTitle),
      body: _loading
          ? const LoadingIndicator()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  t.ttSetAllowance,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _num(_year, t.ttYear)),
                    const SizedBox(width: 8),
                    Expanded(child: _num(_allowance, t.ttAllowance)),
                    const SizedBox(width: 8),
                    Expanded(child: _num(_carry, t.ttCarriedOver)),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _saveAllowance,
                    child: Text(t.ttSave),
                  ),
                ),
                const Divider(height: 32),
                Text(
                  t.ttWorkMinutesPerDay,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _num(_workMinutes, t.ttWorkMinutesPerDay)),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _saveWork, child: Text(t.ttSave)),
                  ],
                ),
                const Divider(height: 32),
                Text(
                  t.ttAllowancesHistory,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final a in _allowances)
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: Text('${a.year}'),
                    subtitle: Text(
                      '${t.ttAllowance}: ${a.allowanceDays} · ${t.ttCarriedOver}: ${a.carriedOverDays}',
                    ),
                  ),
                if (_allowances.isEmpty) Text(t.ttNoEntries),
              ],
            ),
    );
  }

  Widget _num(TextEditingController c, String label) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
  );
}
