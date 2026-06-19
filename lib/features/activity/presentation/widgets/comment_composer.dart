import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/activity/presentation/cubits/activity_stream_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Composer that autosaves the in-progress comment to the [HiveBoxes.drafts]
/// box every 3s and restores it on mount. The draft is cleared on successful
/// post.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    required this.draftKey,
    required this.busy,
    super.key,
  });
  final String draftKey;
  final bool busy;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  static const _flushEvery = Duration(seconds: 3);

  late final TextEditingController _ctrl;
  late final KeyValueStorage _store;
  Timer? _flushTimer;
  bool _restoredNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _store = getIt<KeyValueStorage>(instanceName: HiveBoxes.drafts);
    final saved = _store.get<String>(widget.draftKey);
    _ctrl = TextEditingController(text: saved ?? '');
    if (saved != null && saved.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _restoredNoticeShown) return;
        _restoredNoticeShown = true;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commentDraftRestored),
            duration: const Duration(seconds: 2),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    // Best-effort flush on dispose so the user doesn't lose the last edit.
    _flush();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushEvery, _flush);
  }

  void _flush() {
    final body = _ctrl.text;
    if (body.trim().isEmpty) {
      unawaited(_store.remove(widget.draftKey));
    } else {
      unawaited(_store.set<String>(widget.draftKey, body));
    }
  }

  Future<void> _submit() async {
    final cubit = context.read<ActivityStreamCubit>();
    final body = _ctrl.text;
    if (body.trim().isEmpty) return;
    final ok = await cubit.postComment(body);
    if (ok) {
      _ctrl.clear();
      _flushTimer?.cancel();
      await _store.remove(widget.draftKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              enabled: !widget.busy,
              decoration: InputDecoration(
                hintText: t.commentComposerHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _scheduleFlush(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: widget.busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            onPressed: widget.busy ? null : _submit,
            label: Text(t.commentPostAction),
          ),
        ],
      ),
    );
  }
}
