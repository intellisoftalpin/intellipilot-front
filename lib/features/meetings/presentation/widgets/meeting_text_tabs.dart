import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/ui/markdown_editor.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meeting_detail_cubit.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_format.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/transcript_view.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The meeting summary: rendered markdown, editable in place, or replaced by
/// an imported `.md` / `.txt` file.
class SummaryTab extends StatelessWidget {
  const SummaryTab({required this.meeting, required this.canModify, super.key});

  final Meeting meeting;
  final bool canModify;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _EditableText(
      text: meeting.summary,
      canModify: canModify,
      emptyText: t.meetingSummaryEmpty,
      importTarget: MeetingTextTarget.summary,
      importHint: t.meetingImportSummaryHint,
      viewer: (text) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: MarkdownText(text),
      ),
      editor: (controller) =>
          MarkdownEditor(controller: controller, minLines: 12),
      save: (cubit, text) => cubit.saveSummary(text),
    );
  }
}

/// The meeting transcript: searchable plain text, editable (paste) in place,
/// or replaced by an imported `.txt` / `.vtt` / `.srt` / `.md` file.
class TranscriptTab extends StatelessWidget {
  const TranscriptTab({
    required this.meeting,
    required this.canModify,
    super.key,
  });

  final Meeting meeting;
  final bool canModify;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _EditableText(
      text: meeting.transcript,
      canModify: canModify,
      emptyText: t.meetingTranscriptEmpty,
      importTarget: MeetingTextTarget.transcript,
      importHint: t.meetingImportTranscriptHint,
      viewer: (text) => TranscriptView(text: text),
      editor: (controller) => TextField(
        key: const Key('transcript-editor'),
        controller: controller,
        maxLines: null,
        minLines: 16,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(hintText: t.meetingTranscriptPasteHint),
      ),
      save: (cubit, text) => cubit.saveTranscript(text),
    );
  }
}

class _EditableText extends StatefulWidget {
  const _EditableText({
    required this.text,
    required this.canModify,
    required this.emptyText,
    required this.importTarget,
    required this.importHint,
    required this.viewer,
    required this.editor,
    required this.save,
  });

  final String text;
  final bool canModify;
  final String emptyText;
  final MeetingTextTarget importTarget;
  final String importHint;
  final Widget Function(String text) viewer;
  final Widget Function(TextEditingController controller) editor;
  final Future<AppFailure?> Function(MeetingDetailCubit cubit, String text)
  save;

  @override
  State<_EditableText> createState() => _EditableTextState();
}

class _EditableTextState extends State<_EditableText> {
  TextEditingController? _editing;
  bool _busy = false;

  @override
  void dispose() {
    _editing?.dispose();
    super.dispose();
  }

  void _startEdit() =>
      setState(() => _editing = TextEditingController(text: widget.text));

  void _stopEdit() {
    final c = _editing;
    setState(() => _editing = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => c?.dispose());
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<MeetingDetailCubit>();
    setState(() => _busy = true);
    final failure = await widget.save(cubit, _editing!.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure == null) {
      _stopEdit();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(meetingFailureMessage(t, failure))),
      );
    }
  }

  Future<void> _import() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<MeetingDetailCubit>();
    final file = await getIt<FilePicker>().pickSingleFile();
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    final failure = await cubit.importText(widget.importTarget, file);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(meetingFailureMessage(t, failure))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final editing = _editing;
    final canImport =
        widget.canModify &&
        getIt.isRegistered<FilePicker>() &&
        getIt<FilePicker>().isSupported;

    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: editing != null
            ? [
                FilledButton(
                  onPressed: _busy ? null : () => unawaited(_save()),
                  child: Text(t.actionSave),
                ),
                TextButton(
                  onPressed: _busy ? null : _stopEdit,
                  child: Text(t.actionCancel),
                ),
              ]
            : [
                if (widget.canModify)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _startEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(t.actionEdit),
                  ),
                if (canImport)
                  Tooltip(
                    message: widget.importHint,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => unawaited(_import()),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(t.meetingImportFile),
                    ),
                  ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
      ),
    );

    final Widget body;
    if (editing != null) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: widget.editor(editing),
      );
    } else if (widget.text.trim().isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.emptyText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      body = widget.viewer(widget.text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canModify) toolbar,
        Expanded(child: body),
      ],
    );
  }
}
