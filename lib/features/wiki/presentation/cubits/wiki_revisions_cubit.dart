// `_repo` field kept private for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';

sealed class WikiRevisionsState extends Equatable {
  const WikiRevisionsState();
  @override
  List<Object?> get props => [];
}

class WikiRevisionsLoading extends WikiRevisionsState {
  const WikiRevisionsLoading();
}

class WikiRevisionsFailed extends WikiRevisionsState {
  const WikiRevisionsFailed();
}

class WikiRevisionsLoaded extends WikiRevisionsState {
  const WikiRevisionsLoaded({
    required this.revisions,
    this.selectedRev,
    this.selectedBody,
    this.diff,
    this.busy = false,
  });
  final List<WikiRevision> revisions;
  final int? selectedRev;

  /// Full body of [selectedRev] loaded lazily on click.
  final String? selectedBody;
  final WikiDiff? diff;
  final bool busy;

  WikiRevisionsLoaded copyWith({
    List<WikiRevision>? revisions,
    int? selectedRev,
    String? selectedBody,
    WikiDiff? diff,
    bool? busy,
    bool clearSelection = false,
  }) => WikiRevisionsLoaded(
    revisions: revisions ?? this.revisions,
    selectedRev: clearSelection ? null : selectedRev ?? this.selectedRev,
    selectedBody: clearSelection ? null : selectedBody ?? this.selectedBody,
    diff: clearSelection ? null : diff ?? this.diff,
    busy: busy ?? this.busy,
  );

  @override
  List<Object?> get props => [
    revisions,
    selectedRev,
    selectedBody,
    diff,
    busy,
  ];
}

class WikiRevisionsCubit extends Cubit<WikiRevisionsState> {
  WikiRevisionsCubit({
    required WikiRepository repo,
    required this.projectId,
    required this.pageId,
  }) : _repo = repo,
       super(const WikiRevisionsLoading());

  final WikiRepository _repo;
  final String projectId;
  final String pageId;

  Future<void> load() async {
    if (!isClosed) emit(const WikiRevisionsLoading());
    final res = await _repo.listRevisions(projectId, pageId);
    final items = res.valueOrNull;
    if (items == null) {
      if (!isClosed) emit(const WikiRevisionsFailed());
      return;
    }
    if (!isClosed) emit(WikiRevisionsLoaded(revisions: items));
  }

  Future<void> select(int rev) async {
    final s = state;
    if (s is! WikiRevisionsLoaded) return;
    emit(s.copyWith(busy: true, selectedRev: rev, clearSelection: false));
    final detail = await _repo.getRevision(projectId, pageId, rev);
    final diffRes = await _repo.diff(projectId, pageId, rev);
    final body = detail.valueOrNull?.body;
    final diff = diffRes.valueOrNull;
    if (!isClosed) {
      emit(
        s.copyWith(
          selectedRev: rev,
          selectedBody: body,
          diff: diff,
          busy: false,
        ),
      );
    }
  }
}
