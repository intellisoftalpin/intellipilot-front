import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/app_token_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

sealed class AdminAppTokensState extends Equatable {
  const AdminAppTokensState();
  @override
  List<Object?> get props => const [];
}

final class AdminAppTokensLoading extends AdminAppTokensState {
  const AdminAppTokensLoading();
}

final class AdminAppTokensLoaded extends AdminAppTokensState {
  const AdminAppTokensLoaded({
    required this.tokens,
    required this.projects,
    this.lastError,
  });

  final List<AppTokenDto> tokens;
  final List<Project> projects;
  final AppFailure? lastError;

  String projectName(String id) =>
      projects.where((p) => p.id == id).map((p) => p.name).firstOrNull ?? id;

  @override
  List<Object?> get props => [tokens, projects, lastError];
}

final class AdminAppTokensFailed extends AdminAppTokensState {
  const AdminAppTokensFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class AdminAppTokensCubit extends Cubit<AdminAppTokensState> {
  AdminAppTokensCubit(this._admin, this._projects)
    : super(const AdminAppTokensLoading());

  final AdminRepository _admin;
  final ProjectsRepository _projects;

  Future<void> load() async {
    emit(const AdminAppTokensLoading());
    final tokensRes = await _admin.listAppTokens();
    final projectsRes = await _projects.listProjects();
    final tokens = tokensRes.valueOrNull;
    if (tokens == null) {
      emit(AdminAppTokensFailed(tokensRes.failureOrNull ?? const UnknownFailure()));
      return;
    }
    final projects = (projectsRes.valueOrNull ?? const <Project>[]).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    emit(AdminAppTokensLoaded(tokens: tokens, projects: projects));
  }

  /// Creates a token. Returns the one-time result (incl. the raw secret) on
  /// success, or null on failure (the error is surfaced via state).
  Future<CreateAppTokenResult?> create(CreateAppTokenRequest body) async {
    final res = await _admin.createAppToken(body);
    final result = res.valueOrNull;
    if (result != null) {
      await load();
      return result;
    }
    final s = state;
    if (s is AdminAppTokensLoaded) {
      emit(AdminAppTokensLoaded(
        tokens: s.tokens,
        projects: s.projects,
        lastError: res.failureOrNull,
      ));
    }
    return null;
  }

  Future<bool> update(String id, UpdateAppTokenRequest body) async {
    final res = await _admin.updateAppToken(id, body);
    if (res.isOk) {
      await load();
      return true;
    }
    final s = state;
    if (s is AdminAppTokensLoaded) {
      emit(AdminAppTokensLoaded(
        tokens: s.tokens,
        projects: s.projects,
        lastError: res.failureOrNull,
      ));
    }
    return false;
  }

  Future<void> revoke(String id) async {
    final res = await _admin.revokeAppToken(id);
    if (res.isOk) {
      await load();
    }
  }
}
