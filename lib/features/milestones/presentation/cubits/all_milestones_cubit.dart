// `_repo` is intentionally kept as a private field for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

sealed class AllMilestonesState extends Equatable {
  const AllMilestonesState();
  @override
  List<Object?> get props => [];
}

class AllMilestonesLoading extends AllMilestonesState {
  const AllMilestonesLoading();
}

class AllMilestonesFailed extends AllMilestonesState {
  const AllMilestonesFailed();
}

class AllMilestonesLoaded extends AllMilestonesState {
  const AllMilestonesLoaded({
    required this.items,
    required this.completedCount,
    this.completedExpanded = false,
    this.completedLoading = false,
  });

  /// Open milestones from every visible project, plus the completed ones once
  /// their band has been expanded.
  final List<MilestoneOverview> items;
  final int completedCount;
  final bool completedExpanded;
  final bool completedLoading;

  List<MilestoneOverview> get open =>
      items.where((o) => !o.milestone.closed).toList();
  List<MilestoneOverview> get completed =>
      items.where((o) => o.milestone.closed).toList();

  AllMilestonesLoaded copyWith({
    List<MilestoneOverview>? items,
    int? completedCount,
    bool? completedExpanded,
    bool? completedLoading,
  }) => AllMilestonesLoaded(
    items: items ?? this.items,
    completedCount: completedCount ?? this.completedCount,
    completedExpanded: completedExpanded ?? this.completedExpanded,
    completedLoading: completedLoading ?? this.completedLoading,
  );

  @override
  List<Object?> get props => [
    items,
    completedCount,
    completedExpanded,
    completedLoading,
  ];
}

/// The cross-project milestones timeline: every milestone the user may see,
/// with completed ones fetched only on demand.
class AllMilestonesCubit extends Cubit<AllMilestonesState> {
  AllMilestonesCubit({required MilestonesRepository repo})
    : _repo = repo,
      super(const AllMilestonesLoading());

  final MilestonesRepository _repo;

  /// Load the open milestones — and the completed ones as well when their
  /// band is already expanded, so a reload keeps what the user sees.
  Future<void> load() async {
    final prev = state;
    final expanded = prev is AllMilestonesLoaded && prev.completedExpanded;
    if (prev is! AllMilestonesLoaded && !isClosed) {
      emit(const AllMilestonesLoading());
    }
    final res = await _repo.listAll(
      state: expanded ? MilestoneStateFilter.all : MilestoneStateFilter.open,
    );
    if (isClosed) return;
    final page = res.valueOrNull;
    if (page == null) {
      emit(const AllMilestonesFailed());
      return;
    }
    emit(
      AllMilestonesLoaded(
        items: page.items,
        completedCount: page.completedCount,
        completedExpanded: expanded,
      ),
    );
  }

  Future<void> toggleCompleted() async {
    final s = state;
    if (s is! AllMilestonesLoaded) return;
    if (s.completedExpanded) {
      emit(s.copyWith(completedExpanded: false));
      return;
    }
    if (s.completed.length >= s.completedCount) {
      emit(s.copyWith(completedExpanded: true));
      return;
    }
    emit(s.copyWith(completedExpanded: true, completedLoading: true));
    final res = await _repo.listAll(state: MilestoneStateFilter.completed);
    if (isClosed) return;
    final cur = state;
    if (cur is! AllMilestonesLoaded) return;
    final page = res.valueOrNull;
    if (page == null) {
      emit(cur.copyWith(completedExpanded: false, completedLoading: false));
      return;
    }
    emit(
      cur.copyWith(
        items: [...cur.open, ...page.items],
        completedCount: page.completedCount,
        completedLoading: false,
      ),
    );
  }
}
