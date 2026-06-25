import 'package:flutter/material.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Bulk-editable permission catalog grouped by [PermissionDomain]. The
/// surrounding form owns the [selected] state and is notified through
/// [onChanged]; this widget is purely view + interaction.
class RoleEditor extends StatelessWidget {
  const RoleEditor({
    required this.selected,
    required this.onChanged,
    this.readOnly = false,
    super.key,
  });

  final Set<Permission> selected;
  final ValueChanged<Set<Permission>> onChanged;
  final bool readOnly;

  void _toggle(Permission p, bool? on) {
    final next = Set<Permission>.from(selected);
    if (on ?? false) {
      next.add(p);
    } else {
      next.remove(p);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final byDomain = <PermissionDomain, List<Permission>>{};
    for (final p in Permission.values) {
      byDomain.putIfAbsent(p.domain, () => []).add(p);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Presets(
          readOnly: readOnly,
          onPick: onChanged,
        ),
        const SizedBox(height: 12),
        for (final entry in byDomain.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        _domainLabel(t, entry.key),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        for (final p in entry.value)
                          SizedBox(
                            width: 220,
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              title: Text(_permissionLabel(p)),
                              value: selected.contains(p),
                              onChanged:
                                  readOnly ? null : (v) => _toggle(p, v),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _domainLabel(AppLocalizations t, PermissionDomain d) =>
      switch (d) {
        PermissionDomain.project => t.permDomainProject,
        PermissionDomain.members => t.permDomainMembers,
        PermissionDomain.roles => t.permDomainRoles,
        PermissionDomain.epics => t.permDomainEpics,
        PermissionDomain.issues => t.permDomainIssues,
        PermissionDomain.milestones => t.permDomainMilestones,
        PermissionDomain.wiki => t.permDomainWiki,
        PermissionDomain.commentsAndAttachments =>
          t.permDomainCommentsAttachments,
        PermissionDomain.timeTracking => t.ttTimeTracking,
      };

  String _permissionLabel(Permission p) {
    // The wire format ("epic.create") is human-readable enough for a power-
    // user permissions screen; localizing all 40 entries adds noise without
    // value at MVP. A future audit pass can promote these to ARB if needed.
    return p.wire;
  }
}

class _Presets extends StatelessWidget {
  const _Presets({required this.readOnly, required this.onPick});
  final bool readOnly;
  final ValueChanged<Set<Permission>> onPick;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.visibility_outlined, size: 16),
          onPressed: readOnly ? null : () => onPick(RolePresets.reader()),
          label: Text(t.rolePresetReader),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined, size: 16),
          onPressed:
              readOnly ? null : () => onPick(RolePresets.contributor()),
          label: Text(t.rolePresetContributor),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.shield_outlined, size: 16),
          onPressed:
              readOnly ? null : () => onPick(RolePresets.maintainer()),
          label: Text(t.rolePresetMaintainer),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
          onPressed: readOnly ? null : () => onPick(RolePresets.admin()),
          label: Text(t.rolePresetAdmin),
        ),
      ],
    );
  }
}
