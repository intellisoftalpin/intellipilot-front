import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meeting_detail_cubit.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meeting_uploads_cubit.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_format.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/recording_player.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Resolve a server-relative signed URL against the API base.
String absoluteSignedUrl(String signedUrl) {
  final base = Uri.parse(getIt<ApiConfig>().baseUrl);
  return base.resolve(signedUrl).toString();
}

/// The meeting's recordings, each with an inline player.
class RecordingsTab extends StatelessWidget {
  const RecordingsTab({
    required this.projectId,
    required this.recordings,
    required this.canModify,
    super.key,
  });

  final String projectId;
  final List<Attachment> recordings;
  final bool canModify;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _FileTabScaffold(
      canModify: canModify,
      uploadLabel: t.meetingUploadRecording,
      uploadKind: ArtifactKind.recording,
      accept: 'audio/*,video/*',
      emptyText: t.meetingRecordingsEmpty,
      isEmpty: recordings.isEmpty,
      children: [
        for (final r in recordings)
          RecordingCard(
            key: ValueKey(r.id),
            attachment: r,
            canDelete: canModify,
          ),
      ],
    );
  }
}

/// Everything else attached to the meeting: slides, documents, images, and
/// the original transcript / summary files.
class FilesTab extends StatelessWidget {
  const FilesTab({
    required this.projectId,
    required this.files,
    required this.canModify,
    super.key,
  });

  final String projectId;
  final List<Attachment> files;
  final bool canModify;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _FileTabScaffold(
      canModify: canModify,
      uploadLabel: t.meetingUploadFile,
      uploadKind: ArtifactKind.other,
      emptyText: t.meetingFilesEmpty,
      isEmpty: files.isEmpty,
      children: [
        for (final f in files) _FileRow(attachment: f, canDelete: canModify),
      ],
    );
  }
}

class _FileTabScaffold extends StatelessWidget {
  const _FileTabScaffold({
    required this.canModify,
    required this.uploadLabel,
    required this.uploadKind,
    required this.emptyText,
    required this.isEmpty,
    required this.children,
    this.accept,
  });

  final bool canModify;
  final String uploadLabel;
  final ArtifactKind uploadKind;
  final String? accept;
  final String emptyText;
  final bool isEmpty;
  final List<Widget> children;

  Future<void> _upload(BuildContext context) async {
    final uploads = context.read<MeetingUploadsCubit>();
    final file = await uploads.pick(accept: accept);
    if (file == null) return;
    await uploads.upload(file, uploadKind);
  }

  /// Uploads shown on this tab: recordings on Recordings, the rest on Files.
  bool _isMine(MeetingUpload u) =>
      (u.kind == ArtifactKind.recording) ==
      (uploadKind == ArtifactKind.recording);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final uploads = context.watch<MeetingUploadsCubit>();
    final mine = uploads.state.where(_isMine).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (canModify)
          Align(
            alignment: Alignment.centerLeft,
            child: uploads.isSupported
                ? FilledButton.tonalIcon(
                    onPressed: () => unawaited(_upload(context)),
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(uploadLabel),
                  )
                : Text(
                    t.meetingUploadsUnsupported,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        for (final u in mine) UploadProgressRow(upload: u),
        const SizedBox(height: 8),
        if (isEmpty && mine.isEmpty)
          Text(
            emptyText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ...children,
      ],
    );
  }
}

/// A running, failed or cancelled upload.
class UploadProgressRow extends StatelessWidget {
  const UploadProgressRow({required this.upload, super.key});

  final MeetingUpload upload;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<MeetingUploadsCubit>();
    final u = upload;
    final String status;
    switch (u.status) {
      case UploadStatus.running:
        status = '${humanSize(u.sent)} / ${humanSize(u.total)}';
      case UploadStatus.cancelled:
        status = t.meetingUploadCancelled;
      case UploadStatus.failed:
        status = meetingFailureMessage(t, u.failure!);
      case UploadStatus.done:
        status = '';
    }
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  if (u.status == UploadStatus.running)
                    LinearProgressIndicator(value: u.fraction),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: u.status == UploadStatus.failed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (u.status == UploadStatus.running)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: t.meetingUploadCancel,
                onPressed: () => cubit.cancel(u.id),
              )
            else
              IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: t.meetingUploadDismiss,
                onPressed: () => cubit.dismiss(u.id),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _download(BuildContext context, Attachment att) async {
  final signed = await context.read<MeetingDetailCubit>().sign(att.id);
  if (signed == null) return;
  openExternalUrl(absoluteSignedUrl(signed.url));
}

Future<void> _confirmDelete(BuildContext context, Attachment att) async {
  final t = AppLocalizations.of(context);
  final cubit = context.read<MeetingDetailCubit>();
  final messenger = ScaffoldMessenger.of(context);
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
  if (!(ok ?? false)) return;
  final failure = await cubit.deleteArtifact(att.id);
  if (failure != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(meetingFailureMessage(t, failure))),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.attachment, required this.canDelete});

  final Attachment attachment;
  final bool canDelete;

  IconData get _icon {
    final ct = attachment.contentType;
    if (ct.startsWith('image/')) return Icons.image_outlined;
    if (ct == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (ct.startsWith('text/')) return Icons.description_outlined;
    if (ct.contains('presentation') || ct.contains('powerpoint')) {
      return Icons.slideshow_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final kind = ArtifactKind.fromWire(attachment.kind);
    final kindLabel = switch (kind) {
      ArtifactKind.transcript => t.meetingTabTranscript,
      ArtifactKind.summary => t.meetingTabSummary,
      _ => null,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon),
      title: Text(attachment.filename, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          humanSize(attachment.sizeBytes),
          ?kindLabel,
        ].join(' · '),
      ),
      onTap: () => unawaited(_download(context, attachment)),
      trailing: Wrap(
        children: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: t.attachmentsDownload,
            onPressed: () => unawaited(_download(context, attachment)),
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: t.actionDelete,
              onPressed: () => unawaited(_confirmDelete(context, attachment)),
            ),
        ],
      ),
    );
  }
}

/// A recording with its player, download and delete.
class RecordingCard extends StatelessWidget {
  const RecordingCard({
    required this.attachment,
    required this.canDelete,
    super.key,
  });

  final Attachment attachment;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isVideo = attachment.contentType.startsWith('video/');
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(isVideo ? Icons.videocam_outlined : Icons.mic_none),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    attachment.filename,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(humanSize(attachment.sizeBytes)),
                IconButton(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: t.attachmentsDownload,
                  onPressed: () => unawaited(_download(context, attachment)),
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: t.actionDelete,
                    onPressed: () =>
                        unawaited(_confirmDelete(context, attachment)),
                  ),
              ],
            ),
            RecordingPlayer(
              isVideo: isVideo,
              resolveUrl: () async {
                final signed = await context.read<MeetingDetailCubit>().sign(
                  attachment.id,
                );
                return signed == null ? null : absoluteSignedUrl(signed.url);
              },
              onDownload: () => unawaited(_download(context, attachment)),
            ),
          ],
        ),
      ),
    );
  }
}
