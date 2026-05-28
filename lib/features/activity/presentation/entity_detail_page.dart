import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/activity/presentation/cubits/activity_stream_cubit.dart';
import 'package:intellipilot/features/activity/presentation/cubits/attachments_cubit.dart';
import 'package:intellipilot/features/activity/presentation/widgets/activity_stream_view.dart';
import 'package:intellipilot/features/activity/presentation/widgets/attachments_view.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Generic entity detail page: fetches the entity header, then renders
/// description + an Activity tab + an Attachments tab. The kind comes from
/// the URL so a single route serves all four backlog entity kinds.
class EntityDetailPage extends StatelessWidget {
  const EntityDetailPage({
    required this.projectId,
    required this.kind,
    required this.entityId,
    super.key,
  });

  final String projectId;
  final EntityKind kind;
  final String entityId;

  // Client-side cap. Server default is 25 MiB; we mirror it.
  static const _maxBytes = 25 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<_Header?>(
      future: _loadHeader(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final header = snap.data;
        if (header == null) {
          return Scaffold(
            appBar: AppBar(title: Text(t.entityDetailTitle)),
            body: Center(child: Text(t.entityDetailLoadFailed)),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider<ProjectDetailCubit>(
              create: (_) => ProjectDetailCubit(
                repo: getIt<ProjectsRepository>(),
                projectId: projectId,
                currentUserId: header.userId,
              )..load(),
            ),
            BlocProvider<ActivityStreamCubit>(
              create: (_) => ActivityStreamCubit(
                repo: getIt<ActivityRepository>(),
                projectId: projectId,
                kind: kind,
                entityId: entityId,
              )..load(),
            ),
            BlocProvider<AttachmentsCubit>(
              create: (_) => AttachmentsCubit(
                repo: getIt<ActivityRepository>(),
                projectId: projectId,
                kind: kind,
                entityId: entityId,
                maxBytes: _maxBytes,
              )..load(),
            ),
          ],
          child: _DetailView(
            header: header,
            kind: kind,
            entityId: entityId,
          ),
        );
      },
    );
  }

  Future<_Header?> _loadHeader() async {
    final profileRes = await getIt<ProfileRepository>().getProfile();
    final profile = profileRes.valueOrNull;
    if (profile == null) return null;
    final repo = getIt<BacklogRepository>();
    _EntityHeader? header;
    switch (kind) {
      case EntityKind.epic:
        final v = (await repo.getEpic(projectId, entityId)).valueOrNull;
        if (v != null) {
          header = _EntityHeader(
            subject: v.subject,
            description: v.description,
            reference: v.reference,
            prefix: 'EPIC',
          );
        }
      case EntityKind.userStory:
        final v =
            (await repo.getUserStory(projectId, entityId)).valueOrNull;
        if (v != null) {
          header = _EntityHeader(
            subject: v.subject,
            description: v.description,
            reference: v.reference,
            prefix: 'US',
          );
        }
      case EntityKind.task:
        final v = (await repo.getTask(projectId, entityId)).valueOrNull;
        if (v != null) {
          header = _EntityHeader(
            subject: v.subject,
            description: v.description,
            reference: v.reference,
            prefix: 'T',
          );
        }
      case EntityKind.issue:
        final v = (await repo.getIssue(projectId, entityId)).valueOrNull;
        if (v != null) {
          header = _EntityHeader(
            subject: v.subject,
            description: v.description,
            reference: v.reference,
            prefix: 'ISSUE',
          );
        }
    }
    if (header == null) return null;
    return _Header(profile.id, header);
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({
    required this.header,
    required this.kind,
    required this.entityId,
  });

  final _Header header;
  final EntityKind kind;
  final String entityId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${header.entity.prefix}-${header.entity.reference} '
            '· ${header.entity.subject}',
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: t.entityTabActivity),
              Tab(text: t.entityTabAttachments),
            ],
          ),
        ),
        body: Column(
          children: [
            if (header.entity.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(header.entity.description),
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  ActivityStreamView(
                    draftKey: '${kind.wire}:$entityId',
                  ),
                  const AttachmentsView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntityHeader {
  const _EntityHeader({
    required this.subject,
    required this.description,
    required this.reference,
    required this.prefix,
  });
  final String subject;
  final String description;
  final int reference;
  final String prefix;
}

class _Header {
  _Header(this.userId, this.entity);
  final String userId;
  final _EntityHeader entity;
}
