import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/features/board/presentation/cubits/board_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Right-edge drawer with the search + assignee filter controls. Persistence
/// of the in-memory filter is handled at the cubit level; saving the filter
/// as a "view" is a separate explicit action.
class BoardFiltersDrawer extends StatelessWidget {
  const BoardFiltersDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: BlocBuilder<BoardCubit, BoardState>(
          builder: (context, state) {
            if (state is! BoardLoaded) return const SizedBox.shrink();
            return _Body(state: state);
          },
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.state});
  final BoardLoaded state;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.state.filter.search);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final assignees = widget.state.knownAssignees;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.boardFiltersTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: t.backlogSearchHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => context.read<BoardCubit>().setFilter(
              widget.state.filter.copyWith(search: v),
            ),
          ),
          const SizedBox(height: 16),
          Text(t.boardFilterAssignee,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          DropdownButtonFormField<String?>(
            initialValue: widget.state.filter.assignee,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(t.issuesFilterClear),
              ),
              for (final a in assignees)
                DropdownMenuItem<String?>(value: a, child: Text(a)),
            ],
            onChanged: (v) => context.read<BoardCubit>().setFilter(
              widget.state.filter.copyWith(assignee: v),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _search.clear();
              context.read<BoardCubit>().setFilter(const BoardFilter());
            },
            label: Text(t.boardFiltersReset),
          ),
        ],
      ),
    );
  }
}
