import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'background_service.dart';

enum JobStatus { pending, uploading, completed, failed, scheduled }

class UploadJob {
  final String id;
  final String assetId;
  String title;
  final String? filePath;
  JobStatus status;
  double progress;
  DateTime? scheduledDate;
  DateTime? completedAt;
  String? youtubeVideoId;
  String? error;
  String channelId;
  String accountEmail;

  UploadJob({
    required this.id,
    required this.assetId,
    required this.title,
    this.filePath,
    this.status = JobStatus.pending,
    this.progress = 0,
    this.scheduledDate,
    this.completedAt,
    this.youtubeVideoId,
    this.error,
    this.channelId = '',
    this.accountEmail = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'assetId': assetId,
    'title': title,
    'filePath': filePath,
    'status': status.index,
    'progress': progress,
    'scheduledDate': scheduledDate?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'youtubeVideoId': youtubeVideoId,
    'error': error,
    'channelId': channelId,
    'accountEmail': accountEmail,
  };

  factory UploadJob.fromJson(Map<String, dynamic> json) => UploadJob(
    id: json['id'] as String,
    assetId: json['assetId'] as String,
    title: json['title'] as String,
    filePath: json['filePath'] as String?,
    status: JobStatus.values[json['status'] as int],
    progress: (json['progress'] as num).toDouble(),
    scheduledDate: json['scheduledDate'] != null ? DateTime.parse(json['scheduledDate'] as String) : null,
    completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String) : null,
    youtubeVideoId: json['youtubeVideoId'] as String?,
    error: json['error'] as String?,
    channelId: json['channelId'] as String? ?? '',
    accountEmail: json['accountEmail'] as String? ?? '',
  );

  String get displayName =>
      title.isNotEmpty ? title : (filePath != null ? filePath!.split('/').last : assetId);
}

class UploadScheduler extends ChangeNotifier {
  static const int dailyLimit = 15;
  static const String _storageKey = 'upload_queue';
  static const _storage = FlutterSecureStorage();

  List<UploadJob> _jobs = [];

  List<UploadJob> get jobs => List.unmodifiable(_jobs);
  int get totalCount => _jobs.length;
  int get pendingCount => _jobs.where((j) => j.status == JobStatus.pending).length;
  int get scheduledCount => _jobs.where((j) => j.status == JobStatus.scheduled).length;
  int get uploadingCount => _jobs.where((j) => j.status == JobStatus.uploading).length;
  int get completedCount => _jobs.where((j) => j.status == JobStatus.completed).length;
  int get failedCount => _jobs.where((j) => j.status == JobStatus.failed).length;

  int get todayUploadedCount {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _jobs.where((j) =>
      j.status == JobStatus.completed &&
      j.completedAt != null &&
      j.completedAt!.toIso8601String().substring(0, 10) == today
    ).length;
  }

  int todayUploadedCountForChannel(String channelId) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _jobs.where((j) =>
      j.channelId == channelId &&
      j.status == JobStatus.completed &&
      j.completedAt != null &&
      j.completedAt!.toIso8601String().substring(0, 10) == today
    ).length;
  }

  List<UploadJob> get pendingAndActive =>
      _jobs.where((j) => j.status == JobStatus.pending || j.status == JobStatus.uploading).toList();

  List<UploadJob> get scheduledJobs =>
      _jobs.where((j) => j.status == JobStatus.scheduled).toList();

  List<UploadJob> get completedJobs =>
      _jobs.where((j) => j.status == JobStatus.completed).toList()
        ..sort((a, b) => (b.completedAt ?? DateTime(0)).compareTo(a.completedAt ?? DateTime(0)));

  List<UploadJob> get failedJobs =>
      _jobs.where((j) => j.status == JobStatus.failed).toList();

  Future<void> init() async {
    await load();
  }

  Future<void> load() async {
    final data = await _storage.read(key: _storageKey);
    if (data == null) return;
    final list = jsonDecode(data) as List;
    _jobs = list.map((e) => UploadJob.fromJson(e as Map<String, dynamic>)).toList();
    _rescheduleAfterRestart();
    notifyListeners();
  }

  Future<void> _save() async {
    final data = jsonEncode(_jobs.map((j) => j.toJson()).toList());
    await _storage.write(key: _storageKey, value: data);
    unawaited(updateBadgeCount(pendingCount + uploadingCount));
  }

  void _rescheduleAfterRestart() {
    final now = DateTime.now();
    for (final job in _jobs) {
      if (job.status == JobStatus.uploading) {
        job.status = JobStatus.pending;
        job.progress = 0;
      }
      // Convert scheduled jobs whose date has arrived to pending
      if (job.status == JobStatus.scheduled &&
          job.scheduledDate != null &&
          !job.scheduledDate!.isAfter(now)) {
        job.status = JobStatus.pending;
        job.scheduledDate = null;
      }
    }
  }

  Future<void> addJobs(List<Map<String, String>> videos, String channelId, String accountEmail) async {
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);

    // Count jobs already assigned to each date for this channel
    final dateCounts = <String, int>{};
    for (final j in _jobs.where((j) => j.channelId == channelId)) {
      String dateKey;
      if (j.status == JobStatus.completed && j.completedAt != null) {
        dateKey = j.completedAt!.toIso8601String().substring(0, 10);
      } else if (j.status == JobStatus.scheduled && j.scheduledDate != null) {
        dateKey = j.scheduledDate!.toIso8601String().substring(0, 10);
      } else if (j.status == JobStatus.pending && j.scheduledDate == null) {
        dateKey = todayStr;
      } else {
        continue;
      }
      dateCounts[dateKey] = (dateCounts[dateKey] ?? 0) + 1;
    }

    int dayOffset = 0;
    for (final video in videos) {
      while (true) {
        final dateKey = today.add(Duration(days: dayOffset)).toIso8601String().substring(0, 10);
        final count = dateCounts[dateKey] ?? 0;
        if (count < dailyLimit) {
          dateCounts[dateKey] = count + 1;
          break;
        }
        dayOffset++;
      }

      final job = UploadJob(
        id: '${video['assetId']}_${DateTime.now().millisecondsSinceEpoch}_${_jobs.length}',
        assetId: video['assetId']!,
        title: video['title']!,
        filePath: video['filePath'],
        channelId: channelId,
        accountEmail: accountEmail,
      );

      if (dayOffset > 0) {
        job.status = JobStatus.scheduled;
        job.scheduledDate = today.add(Duration(days: dayOffset));
      }

      _jobs.add(job);
    }
    await _save();
    notifyListeners();
  }

  UploadJob? claimNext() {
    // Get the first pending job that is scheduled for today or earlier
    final now = DateTime.now();
    final idx = _jobs.indexWhere((j) =>
      j.status == JobStatus.pending &&
      (j.scheduledDate == null || j.scheduledDate!.isBefore(now) || j.scheduledDate!.day == now.day)
    );
    if (idx == -1) return null;
    _jobs[idx].status = JobStatus.uploading;
    _jobs[idx].progress = 0;
    notifyListeners();
    return _jobs[idx];
  }

  Future<void> markProgress(String id, double progress) async {
    final idx = _jobs.indexWhere((j) => j.id == id);
    if (idx == -1) return;
    _jobs[idx].progress = progress;
    notifyListeners();
  }

  Future<void> markCompleted(String id, String youtubeVideoId) async {
    final idx = _jobs.indexWhere((j) => j.id == id);
    if (idx == -1) return;
    _jobs[idx].status = JobStatus.completed;
    _jobs[idx].progress = 1.0;
    _jobs[idx].youtubeVideoId = youtubeVideoId;
    _jobs[idx].completedAt = DateTime.now();
    await _save();
    notifyListeners();
  }

  Future<void> markFailed(String id, String error) async {
    final idx = _jobs.indexWhere((j) => j.id == id);
    if (idx == -1) return;
    _jobs[idx].status = JobStatus.failed;
    _jobs[idx].error = error;
    await _save();
    notifyListeners();
  }

  Future<void> retry(String id) async {
    final idx = _jobs.indexWhere((j) => j.id == id);
    if (idx == -1) return;
    _jobs[idx].status = JobStatus.pending;
    _jobs[idx].progress = 0;
    _jobs[idx].error = null;
    await _save();
    notifyListeners();
  }

  Future<void> retryAllFailed() async {
    for (final job in _jobs) {
      if (job.status == JobStatus.failed) {
        job.status = JobStatus.pending;
        job.progress = 0;
        job.error = null;
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _jobs.removeWhere((j) => j.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> clearCompleted() async {
    _jobs.removeWhere((j) => j.status == JobStatus.completed);
    await _save();
    notifyListeners();
  }

  int dailyCountForChannel(String channelId) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _jobs.where((j) =>
      j.channelId == channelId &&
      j.status == JobStatus.completed &&
      j.completedAt != null &&
      j.completedAt!.toIso8601String().substring(0, 10) == today
    ).length;
  }

  /// All jobs sorted by most recent activity (completedAt / scheduledDate / added)
  List<UploadJob> get recentJobs {
    final all = List<UploadJob>.from(_jobs);
    all.sort((a, b) {
      final aDate = a.completedAt ?? a.scheduledDate ?? DateTime(0);
      final bDate = b.completedAt ?? b.scheduledDate ?? DateTime(0);
      return bDate.compareTo(aDate);
    });
    return all;
  }

  /// Scheduled jobs grouped by date key (yyyy-MM-dd) for a specific channel.
  /// If channelId is null, returns all channels.
  Map<String, List<UploadJob>> scheduledByDateForChannel(String? channelId) {
    final map = <String, List<UploadJob>>{};
    final filtered = channelId != null
        ? _jobs.where((j) => j.status == JobStatus.scheduled && j.channelId == channelId)
        : _jobs.where((j) => j.status == JobStatus.scheduled);
    for (final j in filtered) {
      final key = j.scheduledDate?.toIso8601String().substring(0, 10) ?? 'unknown';
      map.putIfAbsent(key, () => []).add(j);
    }
    final sorted = <String, List<UploadJob>>{};
    final keys = map.keys.toList()..sort();
    for (final k in keys) {
      sorted[k] = map[k]!;
    }
    return sorted;
  }

  /// All scheduled jobs (for backward compatibility)
  Map<String, List<UploadJob>> get scheduledByDate => scheduledByDateForChannel(null);
}
