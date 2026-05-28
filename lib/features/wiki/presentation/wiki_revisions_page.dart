import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';
import 'package:intellipilot/features/wiki/presentation/cubits/wiki_page_cubit.dart';
import 'package:intellipilot/features/wiki/presentation/cubits/wiki_revisions_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class WikiRevisionsPage extends StatelessWidget {
  const WikiRevisionsPage({
    required this.projectId,
    required this.pageId,
    super.key,
  });
  final String projectId;
  final String pageId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<WikiPageCubit>(
          create: (_) => WikiPageCubit(
            repo: getIt<WikiRepository>(),
            projectId: projectId,
            pageId: pageId,
          )..load(),
        ),
        BlocProvider<WikiRevisionsCubit>(
          create: (_) => WikiRevisionsCubit(
            repo: getIt<WikiRepository>(),
            projectId: projectId,
            pageId: pageId,
          )..load(),
        ),
      ],
      child: const _View(),
    );
  }
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.wikiRevisionsTitle)),
      body: BlocBuilder<WikiRevisionsCubit, WikiRevisionsState>(
        builder: (context, state) {
          if (state is WikiRevisionsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is WikiRevisionsFailed) {
            return Center(child: Text(t.wikiRevisionsLoadFailed));
          }
          if (state is! WikiRevisionsLoaded) return const SizedBox.shrink();
          return Row(
            children: [
              SizedBox(
                width: 260,
                child: ListView.builder(
                  itemCount: state.revisions.length,
                  itemBuilder: (context, i) {
                    final rev = state.revisions[i];
                    final selected = state.selectedRev == rev.rev;
                    return ListTile(
                      selected: selected,
                      dense: true,
                      title: Text('r${rev.rev} · ${rev.title}'),
                      subtitle: Text(_timestamp(rev.createdAt)),
                      onTap: () =>
                          context.read<WikiRevisionsCubit>().select(rev.rev),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _Detail(state: state)),
            ],
          );
        },
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.state});
  final WikiRevisionsLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (state.busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.selectedRev == null) {
      return Center(child: Text(t.wikiRevisionsPickHint));
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TabBar(
                  tabs: [
                    Tab(text: t.wikiRevisionTabSnapshot),
                    Tab(text: t.wikiRevisionTabDiff),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.restore),
                onPressed: () => _restore(context),
                label: Text(t.wikiRevisionRestore),
              ),
              const SizedBox(width: 16),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    state.selectedBody ?? '',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                _DiffView(diff: state.diff),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final pageCubit = context.read<WikiPageCubit>();
    final rev = state.selectedRev;
    if (rev == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.wikiRestoreTitle),
        content: Text(t.wikiRestoreConfirm(rev)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.wikiRevisionRestore),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    await pageCubit.restoreRevision(rev);
  }
}

class _DiffView extends StatelessWidget {
  const _DiffView({this.diff});
  final WikiDiff? diff;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (diff == null) {
      return Center(child: Text(t.wikiDiffEmpty));
    }
    final lines = diff!.diff.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        Color? bg;
        if (line.startsWith('+') && !line.startsWith('+++')) {
          bg = Colors.green.withValues(alpha: 0.15);
        } else if (line.startsWith('-') && !line.startsWith('---')) {
          bg = Colors.red.withValues(alpha: 0.15);
        } else if (line.startsWith('@@')) {
          bg = Theme.of(context).colorScheme.surfaceContainerHighest;
        }
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SelectableText(
            line,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        );
      },
    );
  }
}

String _timestamp(DateTime dt) {
  final local = dt.toLocal();
  final yy = local.year.toString().padLeft(4, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$yy-$mm-$dd $h:$m';
}
