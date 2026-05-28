// `_repo` is intentionally kept as a private field for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

sealed class MilestonesListState extends Equatable {
  const MilestonesListState();
  @override
  List<Object?> get props => [];
}

class MilestonesListLoading extends MilestonesListState {
  const MilestonesListLoading();
}

class MilestonesListFailed extends MilestonesListState {
  const MilestonesListFailed();
}

class MilestonesListLoaded extends MilestonesListState {
  const MilestonesListLoaded({required this.milestones, this.busy = false});
  final List<Milestone> milestones;
  final bool busy;

  MilestonesListLoaded copyWith({
    List<Milestone>? milestones,
    bool? busy,
  }) => MilestonesListLoaded(
    milestones: milestones ?? this.milestones,
    busy: busy ?? this.busy,
  );

  /// Open milestones come first, ordered by `order`. Closed milestones
  /// trail at the bottom in newest-first order.
  List<Milestone> get sorted {
    final open = milestones.where((m) => !m.closed).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final closed = milestones.where((m) => m.closed).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...open, ...closed];
  }

  @override
  List<Object?> get props => [milestones, busy];
}

class MilestonesListCubit extends Cubit<MilestonesListState> {
  MilestonesListCubit({
    required MilestonesRepository repo,
    required this.projectId,
  }) : _repo = repo,
       super(const MilestonesListLoading());

  final MilestonesRepository _repo;
  final String projectId;

  Future<void> load() async {
    if (!isClosed) emit(const MilestonesListLoading());
    final res = await _repo.list(projectId);
    final items = res.valueOrNull;
    if (items == null) {
      if (!isClosed) emit(const MilestonesListFailed());
      return;
    }
    if (!isClosed) emit(MilestonesListLoaded(milestones: items));
  }

  Future<bool> create(CreateMilestoneRequest body) async {
    final s = state;
    if (s is! MilestonesListLoaded) return false;
    emit(s.copyWith(busy: true));
    final res = await _repo.create(projectId, body);
    final m = res.valueOrNull;
    if (m == null) {
      if (!isClosed) emit(s.copyWith(busy: false));
      return false;
    }
    if (!isClosed) {
      emit(s.copyWith(milestones: [...s.milestones, m], busy: false));
    }
    return true;
  }

  Future<bool> update(String id, UpdateMilestoneRequest body) async {
    final s = state;
    if (s is! MilestonesListLoaded) return false;
    final res = await _repo.update(projectId, id, body: body);
    final m = res.valueOrNull;
    if (m == null) return false;
    if (!isClosed) {
      emit(
        s.copyWith(
          milestones:
              s.milestones.map((x) => x.id == id ? m : x).toList(),
        ),
      );
    }
    return true;
  }

  Future<bool> delete(String id) async {
    final s = state;
    if (s is! MilestonesListLoaded) return false;
    final res = await _repo.delete(projectId, id);
    if (res.valueOrNull == null) return false;
    if (!isClosed) {
      emit(
        s.copyWith(
          milestones: s.milestones.where((x) => x.id != id).toList(),
        ),
      );
    }
    return true;
  }
}
