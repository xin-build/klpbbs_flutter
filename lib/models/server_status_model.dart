import 'package:flutter/material.dart';

/// 服务器运行状态（status.klpz.net）
enum ServerHealthStatus {
  operational('全部正常', Color(0xFF10B981), Icons.check_circle_rounded),
  degraded('部分降级', Color(0xFFF59E0B), Icons.warning_amber_rounded),
  down('服务中断', Color(0xFFEF4444), Icons.error_outline_rounded),
  unknown('未知状态', Colors.grey, Icons.help_outline_rounded);

  final String label;
  final Color color;
  final IconData icon;

  const ServerHealthStatus(this.label, this.color, this.icon);

  static ServerHealthStatus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'operational':
        return ServerHealthStatus.operational;
      case 'degraded':
        return ServerHealthStatus.degraded;
      case 'down':
        return ServerHealthStatus.down;
      default:
        return ServerHealthStatus.unknown;
    }
  }
}

/// 服务分组模型
class ServerStatusGroup {
  final int id;
  final String name;
  final String description;
  final int sortOrder;
  final int isPublic;
  final int columnsPerRow;
  final int includeInStatus;

  const ServerStatusGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.sortOrder = 0,
    this.isPublic = 1,
    this.columnsPerRow = 2,
    this.includeInStatus = 1,
  });

  factory ServerStatusGroup.fromJson(Map<String, dynamic> json) {
    return ServerStatusGroup(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isPublic: (json['is_public'] as num?)?.toInt() ?? 1,
      columnsPerRow: (json['columns_per_row'] as num?)?.toInt() ?? 2,
      includeInStatus: (json['include_in_status'] as num?)?.toInt() ?? 1,
    );
  }
}

/// 单个服务监控指标
class ServerStatusService {
  final int id;
  final int groupId;
  final String name;
  final String description;
  final String currentStatusRaw;
  final String lastCheckedAt;
  final int lastLatencyMs;
  final int sortOrder;
  final int includeInStatus;

  const ServerStatusService({
    required this.id,
    required this.groupId,
    required this.name,
    this.description = '',
    required this.currentStatusRaw,
    this.lastCheckedAt = '',
    this.lastLatencyMs = 0,
    this.sortOrder = 0,
    this.includeInStatus = 1,
  });

  ServerHealthStatus get status => ServerHealthStatus.fromString(currentStatusRaw);

  /// 延迟等级色彩
  Color get latencyColor {
    if (status == ServerHealthStatus.down) return const Color(0xFFEF4444);
    if (lastLatencyMs <= 100) return const Color(0xFF10B981);
    if (lastLatencyMs <= 300) return const Color(0xFF3B82F6);
    if (lastLatencyMs <= 800) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  factory ServerStatusService.fromJson(Map<String, dynamic> json) {
    return ServerStatusService(
      id: (json['id'] as num?)?.toInt() ?? 0,
      groupId: (json['group_id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      currentStatusRaw: json['current_status'] as String? ?? 'operational',
      lastCheckedAt: json['last_checked_at'] as String? ?? '',
      lastLatencyMs: (json['last_latency_ms'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      includeInStatus: (json['include_in_status'] as num?)?.toInt() ?? 1,
    );
  }
}

/// 故障时间线更新
class IncidentUpdate {
  final int id;
  final int incidentId;
  final String status;
  final String message;
  final String createdAt;

  const IncidentUpdate({
    required this.id,
    required this.incidentId,
    required this.status,
    required this.message,
    required this.createdAt,
  });

  factory IncidentUpdate.fromJson(Map<String, dynamic> json) {
    return IncidentUpdate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      incidentId: (json['incident_id'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? '',
      message: json['message'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// 故障事件记录
class ServerStatusIncident {
  final int id;
  final int serviceId;
  final String serviceName;
  final String title;
  final String type;
  final String status;
  final String impact;
  final String message;
  final String startedAt;
  final String? resolvedAt;
  final List<IncidentUpdate> updates;

  const ServerStatusIncident({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.title,
    this.type = 'incident',
    required this.status,
    this.impact = 'major',
    required this.message,
    required this.startedAt,
    this.resolvedAt,
    this.updates = const [],
  });

  bool get isResolved => status == 'resolved' || resolvedAt != null;

  factory ServerStatusIncident.fromJson(Map<String, dynamic> json) {
    final updatesRaw = json['updates'] as List<dynamic>? ?? [];
    return ServerStatusIncident(
      id: (json['id'] as num?)?.toInt() ?? 0,
      serviceId: (json['service_id'] as num?)?.toInt() ?? 0,
      serviceName: json['service_name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? 'incident',
      status: json['status'] as String? ?? '',
      impact: json['impact'] as String? ?? 'major',
      message: json['message'] as String? ?? '',
      startedAt: json['started_at'] as String? ?? '',
      resolvedAt: json['resolved_at'] as String?,
      updates: updatesRaw
          .whereType<Map>()
          .map((u) => IncidentUpdate.fromJson(Map<String, dynamic>.from(u)))
          .toList(),
    );
  }
}

/// 状态数据聚合包裹模型
class ServerStatusData {
  final String siteName;
  final String overallRaw;
  final List<ServerStatusGroup> groups;
  final List<ServerStatusService> services;
  final List<ServerStatusIncident> incidents;
  final DateTime updatedAt;

  const ServerStatusData({
    required this.siteName,
    required this.overallRaw,
    this.groups = const [],
    this.services = const [],
    this.incidents = const [],
    required this.updatedAt,
  });

  ServerHealthStatus get overallStatus => ServerHealthStatus.fromString(overallRaw);

  /// 快捷获取核心服务
  List<ServerStatusService> get coreServices =>
      services.where((s) => s.groupId == 1).toList();

  /// 快捷获取存储服务
  List<ServerStatusService> get storageServices =>
      services.where((s) => s.groupId == 2).toList();

  /// 快捷获取边缘节点服务
  List<ServerStatusService> get edgeNodes =>
      services.where((s) => s.groupId == 4).toList();

  factory ServerStatusData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : json;
    final groupsRaw = data['groups'] as List<dynamic>? ?? [];
    final servicesRaw = data['services'] as List<dynamic>? ?? [];
    final incidentsRaw = data['incidents'] as List<dynamic>? ?? [];

    return ServerStatusData(
      siteName: data['site_name'] as String? ?? '服务状态面板',
      overallRaw: data['overall'] as String? ?? 'operational',
      groups: groupsRaw
          .whereType<Map>()
          .map((g) => ServerStatusGroup.fromJson(Map<String, dynamic>.from(g)))
          .toList(),
      services: servicesRaw
          .whereType<Map>()
          .map((s) => ServerStatusService.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
      incidents: incidentsRaw
          .whereType<Map>()
          .map((i) => ServerStatusIncident.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
      updatedAt: DateTime.now(),
    );
  }
}
