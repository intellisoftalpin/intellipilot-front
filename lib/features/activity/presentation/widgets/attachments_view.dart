import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/cubits/attachments_cubit.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class AttachmentsView extends StatelessWidget {
  const AttachmentsView({this.shrinkWrap = false, super.key});

  /// When true, the file list renders as a `Column` inline rather than an
  /// `Expanded(ListView)` — for embedding in a scrollable parent (e.g. the
  /// Jira-style entity detail page).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocConsumer<AttachmentsCubit, AttachmentsState>(
      listenWhen: (prev, next) =>
          next is AttachmentsLoaded && next.error != null,
      listener: (context, state) {
        if (state is! AttachmentsLoaded || state.error == null) return;
        final messenger = ScaffoldMessenger.of(context);
        final message = switch (state.error) {
          'too_large' => t.attachmentsTooLarge(25),
          _ => state.errorMessage ?? t.attachmentsUploadFailed,
        };
        messenger.showSnackBar(SnackBar(content: Text(message)));
      },
      builder: (context, state) {
        if (state is AttachmentsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is AttachmentsFailed) {
          return Center(child: Text(t.activityLoadFailed));
        }
        if (state is! AttachmentsLoaded) return const SizedBox.shrink();
        if (shrinkWrap) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _UploadBar(upload: state.upload),
              const Divider(height: 1),
              if (state.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(t.attachmentsEmpty)),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < state.items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _Row(att: state.items[i]),
                      ],
                    ],
                  ),
                ),
            ],
          );
        }
        return Column(
          children: [
            _UploadBar(upload: state.upload),
            const Divider(height: 1),
            Expanded(
              child: state.items.isEmpty
                  ? Center(child: Text(t.attachmentsEmpty))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: state.items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _Row(att: state.items[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _UploadBar extends StatelessWidget {
  const _UploadBar({this.upload});
  final UploadProgress? upload;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final picker = getIt<FilePicker>();
    final canCreate = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(Permission.attachmentCreate);
    });
    if (!canCreate) return const SizedBox.shrink();
    if (upload != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.cloud_upload_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(upload!.filename),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: upload!.fraction),
                ],
              ),
            ),
            IconButton(
              tooltip: t.attachmentsCancelUpload,
              icon: const Icon(Icons.close),
              onPressed: () => context.read<AttachmentsCubit>().cancelUpload(),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.upload_file),
          onPressed: () async {
            if (!picker.isSupported) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.attachmentsUploadUnsupported)),
              );
              return;
            }
            final picked = await picker.pickSingleFile();
            if (picked == null || !context.mounted) return;
            await context.read<AttachmentsCubit>().upload(
              filename: picked.name,
              bytes: picked.bytes,
              contentType: picked.contentType,
            );
          },
          label: Text(t.attachmentsUpload),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.att});
  final Attachment att;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canDelete = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(Permission.attachmentDelete);
    });
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(att.filename),
      subtitle: Text(
        '${att.contentType} · ${_humanSize(att.sizeBytes)}',
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: t.attachmentsDownload,
            onPressed: () => _download(context),
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context),
            ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    final cubit = context.read<AttachmentsCubit>();
    final signed = await cubit.sign(att.id);
    if (signed == null) return;
    // The signed URL is server-relative (`/api/v1/…`). Resolve it against the
    // API base so it opens correctly even when the SPA is hosted on a
    // different origin.
    final base = Uri.parse(getIt<ApiConfig>().baseUrl);
    final href = base.resolve(signed.url).toString();
    openExternalUrl(href);
  }

  Future<void> _delete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<AttachmentsCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.attachmentsDeleteTitle),
        content: Text(t.attachmentsDeleteConfirm(att.filename)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await cubit.delete(att.id);
    }
  }
}

String _humanSize(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB'];
  var b = bytes.toDouble();
  var i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(b < 10 && i > 0 ? 1 : 0)} ${units[i]}';
}
