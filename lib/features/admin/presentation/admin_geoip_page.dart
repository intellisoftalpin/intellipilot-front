import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/datetime/relative_time.dart';
import 'package:intellipilot/features/admin/data/dtos/security_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Superadmin control for local IP geolocation.
///
/// Deliberately opt-in: resolution never leaves the server, but the location
/// it derives from an address is personal data, so an operator has to switch
/// it on and can erase what was collected.
class AdminGeoipPage extends StatefulWidget {
  const AdminGeoipPage({super.key});

  @override
  State<AdminGeoipPage> createState() => _AdminGeoipPageState();
}

class _AdminGeoipPageState extends State<AdminGeoipPage> {
  late final AdminRepository _repo = getIt<AdminRepository>();

  GeoipStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final res = await _repo.getGeoipStatus();
    if (!mounted) return;
    res.when(
      ok: (s) => setState(() {
        _status = s;
        _loading = false;
        _loadError = null;
      }),
      err: (f) => setState(() {
        _loading = false;
        _loadError = f.debugLabel;
      }),
    );
  }

  Future<void> _patch({
    bool? enabled,
    String? variant,
    bool? autoUpdate,
  }) async {
    setState(() => _busy = true);
    final res = await _repo.updateGeoipSettings(
      enabled: enabled,
      variant: variant,
      autoUpdate: autoUpdate,
    );
    if (!mounted) return;
    res.when(
      ok: (s) => setState(() {
        _status = s;
        _busy = false;
      }),
      err: (_) => setState(() => _busy = false),
    );
  }

  Future<void> _updateNow() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final res = await _repo.updateGeoipDatabase();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    res.when(
      ok: (r) {
        setState(() {
          _status = r.status;
          _busy = false;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              r.installed
                  ? l10n.adminGeoipUpdated(r.buildMonth ?? '')
                  : l10n.adminGeoipAlreadyCurrent,
            ),
          ),
        );
      },
      err: (f) {
        setState(() => _busy = false);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.adminGeoipUpdateFailed(f.debugLabel))),
        );
      },
    );
  }

  Future<void> _purge() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final res = await _repo.purgeGeoipData();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = false);
    res.when(
      ok: (n) => messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminGeoipPurgeDone(n))),
      ),
      err: (_) => messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminGeoipUpdateFailed(''))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminGeoipTitle)),
      body: Builder(
        builder: (context) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = _status;
          if (s == null) {
            return Center(
              child: Text(l10n.adminSettingsFailed(_loadError ?? '')),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.adminGeoipSubtitle, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(l10n.adminGeoipEnable),
                subtitle: Text(l10n.adminGeoipPrivacyNote),
                value: s.enabled,
                onChanged: _busy ? null : (v) => _patch(enabled: v),
              ),
              const Divider(),
              ListTile(
                title: Text(l10n.adminGeoipVariant),
                subtitle: Text(
                  s.variant == 'country'
                      ? l10n.adminGeoipVariantCountry
                      : l10n.adminGeoipVariantCity,
                ),
                trailing: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'country',
                      label: Text(l10n.adminGeoipVariantCountry),
                    ),
                    ButtonSegment(
                      value: 'city',
                      label: Text(l10n.adminGeoipVariantCity),
                    ),
                  ],
                  selected: {s.variant},
                  onSelectionChanged: _busy
                      ? null
                      : (sel) => _patch(variant: sel.first),
                ),
              ),
              SwitchListTile(
                title: Text(l10n.adminGeoipAutoUpdate),
                value: s.autoUpdate,
                onChanged: _busy ? null : (v) => _patch(autoUpdate: v),
              ),
              const Divider(),
              _DatabaseCard(status: s),
              if (s.lastError != null && s.lastError!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.adminGeoipLastError(s.lastError!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _updateNow,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(
                      _busy
                          ? l10n.adminGeoipUpdating
                          : l10n.adminGeoipUpdateNow,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _busy ? null : _purge,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(l10n.adminGeoipPurge),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Required by the database licence (CC BY 4.0).
              Text(
                l10n.adminGeoipAttribution(s.attribution),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DatabaseCard extends StatelessWidget {
  const _DatabaseCard({required this.status});

  final GeoipStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (!status.hasDatabase) {
      return ListTile(
        leading: const Icon(Icons.storage_outlined),
        title: Text(l10n.adminGeoipNotInstalled),
      );
    }

    final sizeMb = status.fileSize == null
        ? null
        : (status.fileSize! / (1024 * 1024)).toStringAsFixed(1);

    return ListTile(
      leading: Icon(
        status.databaseLoaded ? Icons.storage : Icons.storage_outlined,
        color: status.databaseLoaded ? theme.colorScheme.primary : null,
      ),
      title: Text(
        l10n.adminGeoipInstalled(
          status.installedVariant ?? status.variant,
          status.buildMonth ?? '',
        ),
      ),
      subtitle: Text(
        [
          if (sizeMb != null) '$sizeMb MB',
          if (status.checkedAt != null) relativeTime(l10n, status.checkedAt),
        ].join(' · '),
      ),
    );
  }
}
