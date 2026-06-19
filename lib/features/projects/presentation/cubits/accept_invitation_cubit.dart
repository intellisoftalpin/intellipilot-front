import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

sealed class AcceptInvitationState extends Equatable {
  const AcceptInvitationState();
  @override
  List<Object?> get props => const [];
}

final class AcceptInvitationRunning extends AcceptInvitationState {
  const AcceptInvitationRunning();
}

final class AcceptInvitationAccepted extends AcceptInvitationState {
  const AcceptInvitationAccepted(this.projectId);
  final String projectId;
  @override
  List<Object?> get props => [projectId];
}

final class AcceptInvitationFailed extends AcceptInvitationState {
  const AcceptInvitationFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class AcceptInvitationCubit extends Cubit<AcceptInvitationState> {
  AcceptInvitationCubit(this._repo)
    : super(const AcceptInvitationRunning());

  final ProjectsRepository _repo;

  Future<void> accept(String token) async {
    emit(const AcceptInvitationRunning());
    final res = await _repo.acceptInvitation(token);
    res.when(
      ok: (projectId) => emit(AcceptInvitationAccepted(projectId)),
      err: (f) => emit(AcceptInvitationFailed(f)),
    );
  }
}
