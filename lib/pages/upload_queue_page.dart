import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:intl/intl.dart';

import '../youtube_uploader.dart';
import '../services/upload_scheduler.dart';
import '../services/account_manager.dart';
import 'reel_player_page.dart';

class UploadQueuePage extends StatefulWidget {
  final UploadScheduler scheduler;
  final AccountManager accountManager;
  final String? accessToken;

  const UploadQueuePage({
    Key? key,
    required this.scheduler,
    required this.accountManager,
    this.accessToken,
  }) : super(key: key);

  @override
  State<UploadQueuePage> createState() => _UploadQueuePageState();
}

class _UploadQueuePageState extends State<UploadQueuePage> {
  bool _isUploading = false;
  List<AssetEntity> _galleryVideos = [];
  Set<AssetEntity> _selectedForQueue = {};
  bool _showPicker = true;

  @override
  void initState() {
    super.initState();
    widget.scheduler.addListener(_onSchedulerChanged);
    _loadGallery();
  }

  @override
  void dispose() {
    widget.scheduler.removeListener(_onSchedulerChanged);
    super.dispose();
  }

  void _onSchedulerChanged() {
    if (mounted) setState(() {});
    _processNextIfNeeded();
  }

  Future<void> _loadGallery() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) return;
    final albums = await PhotoManager.getAssetPathList(type: RequestType.video);
    List<AssetEntity> all = [];
    for (final album in albums) {
      all.addAll(await album.getAssetListPaged(page: 0, size: 500));
    }
    if (mounted) {
      setState(() => _galleryVideos = {for (final v in all) v.id: v}.values.toList());
    }
  }

  Future<void> _addSelectedToQueue() async {
    if (_selectedForQueue.isEmpty) return;

    final channelId = widget.accountManager.selectedChannelId;
    final email = widget.accountManager.currentAccount?.email ?? '';
    final now = DateTime.now();
    final titleFmt = DateFormat('dd MMMM yyyy HH:mm');
    final items = _selectedForQueue.toList();

    final entries = <Map<String, String>>[];
    for (int i = 0; i < items.length; i++) {
      final v = items[i];
      final file = await v.file;
      final ts = now.add(Duration(minutes: i));
      entries.add({
        'assetId': v.id,
        'title': titleFmt.format(ts),
        if (file != null) 'filePath': file.path,
      });
    }

    await widget.scheduler.addJobs(entries, channelId, email);

    setState(() => _selectedForQueue.clear());
  }

  Future<void> _deleteSelected() async {
    if (_selectedForQueue.isEmpty) return;
    final count = _selectedForQueue.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete videos?',
            style: TextStyle(color: Colors.white)),
        content: Text('Permanently delete $count video$count from your device?',
            style: TextStyle(color: Colors.grey[400])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red[300])),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ids = _selectedForQueue.map((v) => v.id).toList();
    await PhotoManager.editor.deleteWithIds(ids);
    setState(() {
      _galleryVideos.removeWhere((v) => _selectedForQueue.contains(v));
      _selectedForQueue.clear();
    });
  }

  Future<void> _processNextIfNeeded() async {
    if (_isUploading) return;
    final job = widget.scheduler.claimNext();
    if (job == null) return;
    _isUploading = true;

    try {
      final asset = _findAsset(job.assetId);
      if (asset == null) {
        await widget.scheduler.markFailed(job.id, 'Video not found locally');
        _isUploading = false;
        _processNextIfNeeded();
        return;
      }

      final file = await asset.file;
      if (file == null) {
        await widget.scheduler.markFailed(job.id, 'File not accessible');
        _isUploading = false;
        _processNextIfNeeded();
        return;
      }

      final token = widget.accessToken;
      if (token == null) {
        await widget.scheduler.markFailed(job.id, 'Not signed in');
        _isUploading = false;
        _processNextIfNeeded();
        return;
      }

      final uploader = YouTubeUploader(token, selectedChannelId: job.channelId);
      final bytes = await file.readAsBytes();

      await uploader.uploadResumable(
        videoBytes: bytes,
        title: job.title,
        description: 'Uploaded via Flutter app',
        onProgress: (p) => widget.scheduler.markProgress(job.id, p),
      );

      await widget.scheduler.markCompleted(job.id, '');
    } catch (e) {
      await widget.scheduler.markFailed(job.id, e.toString());
    }

    _isUploading = false;
    _processNextIfNeeded();
  }

  AssetEntity? _findAsset(String assetId) {
    for (final v in _galleryVideos) {
      if (v.id == assetId) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_showPicker) return _buildPickerView();
    return _buildQueueView();
  }

  Widget _buildPickerView() {
    final alreadyInQueue = <String>{};
    final alreadyUploaded = <String>{};
    for (final j in widget.scheduler.jobs) {
      if (j.status != JobStatus.completed) {
        alreadyInQueue.add(j.assetId);
      } else {
        alreadyUploaded.add(j.assetId);
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Select Videos'),
        actions: [
          if (_selectedForQueue.isNotEmpty)
            TextButton(
              onPressed: () async {
                await _addSelectedToQueue();
                setState(() => _showPicker = false);
              },
              child: Text('Add ${_selectedForQueue.length} to Queue'),
            ),
          if (_selectedForQueue.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red[300]),
              onPressed: () => _deleteSelected(),
            ),
          IconButton(
            icon: const Icon(Icons.queue_rounded),
            onPressed: () => setState(() => _showPicker = false),
          ),
        ],
      ),
      body: _galleryVideos.isEmpty
          ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6,
                    childAspectRatio: 0.7),
                  itemCount: _galleryVideos.length,
                  itemBuilder: (_, i) {
                    final v = _galleryVideos[i];
                    final selected = _selectedForQueue.contains(v);
                    final inQueue = alreadyInQueue.contains(v.id);
                    return GestureDetector(
                      onTap: () {
                        if (inQueue || alreadyUploaded.contains(v.id)) return;
                        setState(() {
                          if (selected) {
                            _selectedForQueue.remove(v);
                          } else {
                            _selectedForQueue.add(v);
                          }
                        });
                      },
                      onDoubleTap: () {
                        if (inQueue || alreadyUploaded.contains(v.id)) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReelPlayerPage(
                              videos: _galleryVideos,
                              initialIndex: i,
                            ),
                          ),
                        );
                      },
                  child: Stack(
                    children: [
                      FutureBuilder<Uint8List?>(
                        future: v.thumbnailDataWithSize(const ThumbnailSize(300, 420)),
                        builder: (_, snap) => snap.hasData
                            ? Image.memory(snap.data!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                            : Container(color: Colors.grey[800]),
                      ),
                      if (inQueue)
                        Positioned(
                          top: 4, left: 4,
                          child: Container(
                            color: Colors.blueGrey,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: const Text('In Queue', style: TextStyle(color: Colors.white, fontSize: 8)),
                          ),
                        ),
                      if (alreadyUploaded.contains(v.id))
                        Positioned(
                          top: 4, left: 4,
                          child: Container(
                            color: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: const Text('Uploaded', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      if (selected && !inQueue && !alreadyUploaded.contains(v.id))
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            border: Border.all(color: Colors.greenAccent, width: 3),
                          ),
                          child: Center(
                            child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 30),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _statusLabel(JobStatus s) {
    switch (s) {
      case JobStatus.pending: return 'Pending';
      case JobStatus.uploading: return 'Uploading';
      case JobStatus.completed: return 'Completed';
      case JobStatus.failed: return 'Failed';
      case JobStatus.scheduled: return 'Scheduled';
    }
  }

  Color _statusColor(JobStatus s) {
    switch (s) {
      case JobStatus.pending: return Colors.orange;
      case JobStatus.uploading: return Colors.blue;
      case JobStatus.completed: return Colors.green;
      case JobStatus.failed: return Colors.red;
      case JobStatus.scheduled: return Colors.blueGrey;
    }
  }

  IconData _statusIcon(JobStatus s) {
    switch (s) {
      case JobStatus.pending: return Icons.hourglass_empty;
      case JobStatus.uploading: return Icons.cloud_upload;
      case JobStatus.completed: return Icons.check_circle;
      case JobStatus.failed: return Icons.error;
      case JobStatus.scheduled: return Icons.schedule;
    }
  }

  Widget _buildQueueView() {
    final todayUsed = widget.scheduler.todayUploadedCount;
    final all = widget.scheduler.jobs;
    final active = all.where((j) => j.status == JobStatus.pending || j.status == JobStatus.uploading).toList();
    final scheduled = widget.scheduler.scheduledJobs;
    final completed = widget.scheduler.completedJobs;
    final failed = widget.scheduler.failedJobs;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Upload Queue'),
        actions: [
          if (failed.isNotEmpty)
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => widget.scheduler.retryAllFailed()),
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: () {
              _loadGallery();
              setState(() => _showPicker = true);
            },
          ),
        ],
      ),
      body: all.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text('Queue is empty', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('Tap + to select videos', style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Select Videos'),
                    onPressed: () {
                      _loadGallery();
                      setState(() => _showPicker = true);
                    },
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Daily limit indicator
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.today, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Today\'s Uploads',
                                style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                            const SizedBox(height: 4),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: todayUsed / UploadScheduler.dailyLimit),
                              duration: const Duration(milliseconds: 500),
                              builder: (_, v, __) => ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: v,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey[800],
                                  color: todayUsed >= UploadScheduler.dailyLimit ? Colors.red : Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$todayUsed/${UploadScheduler.dailyLimit}',
                          style: TextStyle(color: Colors.grey[300], fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Active uploads
                if (active.isNotEmpty) ...[
                  Text('Active', style: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...active.map((job) => _buildJobTile(job)),
                  const SizedBox(height: 16),
                ],

                // Scheduled
                if (scheduled.isNotEmpty) ...[
                  Text('Scheduled', style: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...scheduled.map((job) => _buildJobTile(job)),
                  const SizedBox(height: 16),
                ],

                // Failed
                if (failed.isNotEmpty) ...[
                  Text('Failed', style: TextStyle(color: Colors.red[400], fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...failed.map((job) => _buildJobTile(job)),
                  const SizedBox(height: 16),
                ],

                // Completed
                if (completed.isNotEmpty) ...[
                  Text('Completed', style: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...completed.take(20).map((job) => _buildJobTile(job)),
                ],
              ],
            ),
    );
  }

  String _channelName(String channelId) {
    final c = widget.accountManager.channels.where((ch) => ch.id == channelId).firstOrNull;
    return c?.title ?? channelId;
  }

  Widget _buildJobTile(UploadJob job) {
    final dateFmt = DateFormat('MMM d, HH:mm');
    return Dismissible(
      key: Key(job.id),
      direction: job.status == JobStatus.completed || job.status == JobStatus.failed
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) => widget.scheduler.remove(job.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(_statusIcon(job.status), color: _statusColor(job.status), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.channelId.isNotEmpty ? _channelName(job.channelId) : job.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  if (job.status == JobStatus.uploading && job.progress > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(value: job.progress, minHeight: 3,
                          backgroundColor: Colors.grey[800], color: Colors.blue),
                    ),
                  if (job.status == JobStatus.scheduled && job.scheduledDate != null)
                    Text('Scheduled: ${job.displayName}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  if (job.status == JobStatus.completed && job.completedAt != null)
                    Text(job.displayName,
                        style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  if (job.status == JobStatus.failed && job.error != null)
                    Text('${job.displayName} - ${job.error}',
                        style: TextStyle(color: Colors.red[300], fontSize: 10),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (job.status == JobStatus.pending)
                    Text(job.displayName,
                        style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (job.status == JobStatus.completed && job.completedAt != null)
              Text(dateFmt.format(job.completedAt!),
                  style: TextStyle(color: Colors.grey[500], fontSize: 11))
            else
              Text(_statusLabel(job.status),
                  style: TextStyle(color: _statusColor(job.status), fontSize: 11, fontWeight: FontWeight.w500)),
            if (job.status == JobStatus.failed)
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => widget.scheduler.retry(job.id),
              ),
          ],
        ),
      ),
    );
  }
}
