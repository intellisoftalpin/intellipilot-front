// Dashboard response DTOs. Mirror the backend `intellipilot_core::dashboard`
// types. Pure data — no Flutter imports.

class StatusBucket {
  const StatusBucket({
    required this.name,
    required this.color,
    required this.isClosed,
    required this.count,
  });

  factory StatusBucket.fromJson(Map<String, dynamic> json) => StatusBucket(
    name: json['name'] as String? ?? '',
    color: json['color'] as String? ?? '',
    isClosed: json['is_closed'] as bool? ?? false,
    count: (json['count'] as num?)?.toInt() ?? 0,
  );

  final String name;
  final String color;
  final bool isClosed;
  final int count;
}

class NamedCount {
  const NamedCount({
    required this.name,
    required this.color,
    required this.count,
  });

  factory NamedCount.fromJson(Map<String, dynamic> json) => NamedCount(
    name: json['name'] as String? ?? '',
    color: json['color'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
  );

  final String name;
  final String color;
  final int count;
}

class ProjectBucket {
  const ProjectBucket({
    required this.projectId,
    required this.slug,
    required this.name,
    required this.openCount,
  });

  factory ProjectBucket.fromJson(Map<String, dynamic> json) => ProjectBucket(
    projectId: json['project_id'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    name: json['name'] as String? ?? '',
    openCount: (json['open_count'] as num?)?.toInt() ?? 0,
  );

  final String projectId;
  final String slug;
  final String name;
  final int openCount;
}

class AttentionItem {
  const AttentionItem({
    required this.projectId,
    required this.projectSlug,
    required this.reference,
    required this.subject,
    required this.statusName,
    required this.overdue,
    this.dueDate,
  });

  factory AttentionItem.fromJson(Map<String, dynamic> json) => AttentionItem(
    projectId: json['project_id'] as String? ?? '',
    projectSlug: json['project_slug'] as String? ?? '',
    reference: (json['reference'] as num?)?.toInt() ?? 0,
    subject: json['subject'] as String? ?? '',
    statusName: json['status_name'] as String? ?? '',
    overdue: json['overdue'] as bool? ?? false,
    dueDate: json['due_date'] as String?,
  );

  final String projectId;
  final String projectSlug;
  final int reference;
  final String subject;
  final String statusName;
  final bool overdue;
  final String? dueDate;
}

class HomeDashboard {
  const HomeDashboard({
    required this.assignedTotal,
    required this.overdue,
    required this.dueSoon,
    required this.vacationDaysLeft,
    required this.byStatus,
    required this.byProject,
    required this.attention,
  });

  factory HomeDashboard.fromJson(Map<String, dynamic> json) => HomeDashboard(
    assignedTotal: (json['assigned_total'] as num?)?.toInt() ?? 0,
    overdue: (json['overdue'] as num?)?.toInt() ?? 0,
    dueSoon: (json['due_soon'] as num?)?.toInt() ?? 0,
    vacationDaysLeft: (json['vacation_days_left'] as num?)?.toDouble() ?? 0,
    byStatus: _list(json['by_status'], StatusBucket.fromJson),
    byProject: _list(json['by_project'], ProjectBucket.fromJson),
    attention: _list(json['attention'], AttentionItem.fromJson),
  );

  final int assignedTotal;
  final int overdue;
  final int dueSoon;
  final double vacationDaysLeft;
  final List<StatusBucket> byStatus;
  final List<ProjectBucket> byProject;
  final List<AttentionItem> attention;
}

class EpicReadiness {
  const EpicReadiness({
    required this.epicId,
    required this.reference,
    required this.subject,
    required this.color,
    required this.total,
    required this.done,
    required this.percent,
  });

  factory EpicReadiness.fromJson(Map<String, dynamic> json) => EpicReadiness(
    epicId: json['epic_id'] as String? ?? '',
    reference: (json['reference'] as num?)?.toInt() ?? 0,
    subject: json['subject'] as String? ?? '',
    color: json['color'] as String? ?? '',
    total: (json['total'] as num?)?.toInt() ?? 0,
    done: (json['done'] as num?)?.toInt() ?? 0,
    percent: (json['percent'] as num?)?.toInt() ?? 0,
  );

  final String epicId;
  final int reference;
  final String subject;
  final String color;
  final int total;
  final int done;
  final int percent;
}

class WeekCount {
  const WeekCount({required this.weekStart, required this.closed});

  factory WeekCount.fromJson(Map<String, dynamic> json) => WeekCount(
    weekStart: json['week_start'] as String? ?? '',
    closed: (json['closed'] as num?)?.toInt() ?? 0,
  );

  final String weekStart;
  final int closed;
}

class ProjectDashboard {
  const ProjectDashboard({
    required this.total,
    required this.open,
    required this.overdue,
    required this.unassigned,
    required this.bugsOpen,
    required this.myAssigned,
    required this.myOverdue,
    required this.byStatus,
    required this.myByStatus,
    required this.byType,
    required this.byPriority,
    required this.epics,
    required this.throughput,
  });

  factory ProjectDashboard.fromJson(Map<String, dynamic> json) =>
      ProjectDashboard(
        total: (json['total'] as num?)?.toInt() ?? 0,
        open: (json['open'] as num?)?.toInt() ?? 0,
        overdue: (json['overdue'] as num?)?.toInt() ?? 0,
        unassigned: (json['unassigned'] as num?)?.toInt() ?? 0,
        bugsOpen: (json['bugs_open'] as num?)?.toInt() ?? 0,
        myAssigned: (json['my_assigned'] as num?)?.toInt() ?? 0,
        myOverdue: (json['my_overdue'] as num?)?.toInt() ?? 0,
        byStatus: _list(json['by_status'], StatusBucket.fromJson),
        myByStatus: _list(json['my_by_status'], StatusBucket.fromJson),
        byType: _list(json['by_type'], NamedCount.fromJson),
        byPriority: _list(json['by_priority'], NamedCount.fromJson),
        epics: _list(json['epics'], EpicReadiness.fromJson),
        throughput: _list(json['throughput'], WeekCount.fromJson),
      );

  final int total;
  final int open;
  final int overdue;
  final int unassigned;
  final int bugsOpen;
  final int myAssigned;
  final int myOverdue;
  final List<StatusBucket> byStatus;
  final List<StatusBucket> myByStatus;
  final List<NamedCount> byType;
  final List<NamedCount> byPriority;
  final List<EpicReadiness> epics;
  final List<WeekCount> throughput;
}

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) from) =>
    (raw as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic e) => from(e as Map<String, dynamic>))
        .toList();
