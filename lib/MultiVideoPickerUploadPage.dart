import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'main.dart';

class MultiVideoPickerUploadPage extends StatefulWidget {
  final String? accessToken;
  const MultiVideoPickerUploadPage({Key? key, this.accessToken}) : super(key: key);

  @override
  _MultiVideoPickerUploadPageState createState() => _MultiVideoPickerUploadPageState();
}

class _MultiVideoPickerUploadPageState extends State<MultiVideoPickerUploadPage> {
  List<AssetEntity> _videos = [];
  Set<AssetEntity> _selectedVideos = {};
  Set<String> _uploadedVideoIds = {};
  late SharedPreferences _prefs;
  bool _loading = false;

  final Map<String, ValueNotifier<double>> _uploadProgressNotifiers = {};
  final Map<String, ValueNotifier<String>> _uploadStatusNotifiers = {};

  @override
  void initState() {
    super.initState();
    _initPrefsAndVideos();
  }

  @override
  void dispose() {
    for (var notifier in _uploadProgressNotifiers.values) {
      notifier.dispose();
    }
    for (var notifier in _uploadStatusNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  Future<void> _initPrefsAndVideos() async {
    _prefs = await SharedPreferences.getInstance();
    _uploadedVideoIds = _prefs.getStringList('uploadedVideoIds')?.toSet() ?? {};
    await _fetchVideos();
  }

  Future<void> _fetchVideos() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) return PhotoManager.openSetting();

    final albums = await PhotoManager.getAssetPathList(type: RequestType.video);
    List<AssetEntity> allVideos = [];
    for (var album in albums) {
      final videos = await album.getAssetListPaged(page: 0, size: 500);
      allVideos.addAll(videos);
    }
    final uniqueVideos = {for (var v in allVideos) v.id: v}.values.toList();
    setState(() => _videos = uniqueVideos);
  }

  void _toggleSelect(AssetEntity video) {
    setState(() {
      if (_selectedVideos.contains(video)) {
        _selectedVideos.remove(video);
      } else if (!_uploadedVideoIds.contains(video.id)) {
        _selectedVideos.add(video);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedVideos = _videos.where((v) => !_uploadedVideoIds.contains(v.id)).toSet();
    });
  }

  Future<void> _markSelectedAsUploaded() async {
    setState(() {
      _uploadedVideoIds.addAll(_selectedVideos.map((v) => v.id));
      _selectedVideos.clear();
    });
    await _prefs.setStringList('uploadedVideoIds', _uploadedVideoIds.toList());
  }

  void _initNotifiersForVideo(String id) {
    _uploadProgressNotifiers.putIfAbsent(id, () => ValueNotifier<double>(0));
    _uploadStatusNotifiers.putIfAbsent(id, () => ValueNotifier<String>(''));
  }

  Future<void> _uploadSelectedVideos() async {
    if (widget.accessToken == null) return;

    setState(() {
      _loading = true;
    });

    final uploader = YouTubeUploader(widget.accessToken!);

    for (final asset in _selectedVideos) {
      if (_uploadedVideoIds.contains(asset.id)) continue;

      _initNotifiersForVideo(asset.id);
      _uploadStatusNotifiers[asset.id]?.value = 'Uploading...';
      _uploadProgressNotifiers[asset.id]?.value = 0;

      final file = await asset.file;
      if (file == null) {
        _uploadStatusNotifiers[asset.id]?.value = 'Failed (No file)';
        continue;
      }

      final name = file.path.split('/').last;
      final bytes = await file.readAsBytes();

      try {
        final videoId = await uploader.uploadResumable(
          videoBytes: bytes,
          title: name,
          description: 'Uploaded via Flutter app',
          onProgress: (progress) {
            _uploadProgressNotifiers[asset.id]?.value = progress;
          },
        );

        if (videoId != null) {
          _uploadStatusNotifiers[asset.id]?.value = 'Uploaded';
          _uploadedVideoIds.add(asset.id);
          await _prefs.setStringList('uploadedVideoIds', _uploadedVideoIds.toList());
        } else {
          _uploadStatusNotifiers[asset.id]?.value = 'Failed';
        }
      } catch (e) {
        _uploadStatusNotifiers[asset.id]?.value = 'Failed: $e';

        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Upload Failed"),
              content: Text("Video '${name}' failed to upload.\nError: $e"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                )
              ],
            ),
          );
        }
      }
    }

    setState(() {
      _loading = false;
      _selectedVideos.clear();
    });
  }

  Widget _buildGridItem(AssetEntity video) {
    final isSelected = _selectedVideos.contains(video);
    final isUploaded = _uploadedVideoIds.contains(video.id);

    _initNotifiersForVideo(video.id);

    return GestureDetector(
      onTap: () => _toggleSelect(video),
      child: Stack(
        children: [
          FutureBuilder<Uint8List?>(
            future: video.thumbnailDataWithSize(ThumbnailSize(200, 200)),
            builder: (_, snap) => snap.hasData
                ? Image.memory(
                    snap.data!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  )
                : Container(color: Colors.grey[300]),
          ),
          if (isUploaded)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                color: Colors.green,
                padding: const EdgeInsets.all(2),
                child: const Text(
                  'Uploaded',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          if (isSelected && !isUploaded)
            Container(
              decoration: BoxDecoration(
                color: Colors.black38,
                border: Border.all(color: Colors.greenAccent, width: 3),
              ),
            ),
          if (!isUploaded)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _uploadProgressNotifiers[video.id]!,
                    builder: (_, progress, __) {
                      return progress > 0
                          ? LinearProgressIndicator(value: progress)
                          : const SizedBox.shrink();
                    },
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: _uploadStatusNotifiers[video.id]!,
                    builder: (_, status, __) {
                      return status.isNotEmpty
                          ? Container(
                              color: Colors.black54,
                              padding: const EdgeInsets.all(2),
                              child: Text(
                                status,
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                              ),
                            )
                          : const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.black87),
              child: Text('Menu', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('My Videos'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () {
                GoogleSignIn().signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => MyApp()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('Pick & Upload Videos'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchVideos),
          IconButton(icon: const Icon(Icons.select_all), onPressed: _selectAll),
          IconButton(icon: const Icon(Icons.check_box), onPressed: _markSelectedAsUploaded),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _selectedVideos.isEmpty || _loading ? null : _uploadSelectedVideos,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _videos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _videos.length,
              itemBuilder: (_, i) => _buildGridItem(_videos[i]),
            ),
    );
  }
}

/// YouTubeUploader class with instance method uploadResumable
class YouTubeUploader {
  static const String _uploadInitiationUrl =
      'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status';
  static const int _chunkSize = 1024 * 1024 * 5; // 5 MB chunks
  static const int _maxRetries = 5;

  final String accessToken;

  YouTubeUploader(this.accessToken);

  /// Uploads video bytes using a resumable YouTube upload session.
  /// Returns the YouTube video ID if successful, otherwise null.
  Future<String?> uploadResumable({
    required Uint8List videoBytes,
    required String title,
    String description = '',
    required Function(double) onProgress,
  }) async {
    final totalSize = videoBytes.length;

    // Step 1: Initiate the resumable upload session
    final initRes = await http.post(
      Uri.parse(_uploadInitiationUrl),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'video/*',
        'X-Upload-Content-Length': totalSize.toString(),
      },
      body: jsonEncode({
        'snippet': {
          'title': title,
          'description': description,
        },
        'status': {
          'privacyStatus': 'private',
        },
      }),
    );

    if (initRes.statusCode != 200) {
      throw Exception('Failed to initiate upload: ${initRes.body}');
    }

    final uploadUrl = initRes.headers['location'];
    if (uploadUrl == null) {
      throw Exception('Upload session URL not returned');
    }

    int offset = 0;
    int retries = 0;

    while (offset < totalSize) {
      final end = (offset + _chunkSize) > totalSize ? totalSize : (offset + _chunkSize);
      final chunk = videoBytes.sublist(offset, end);
      final chunkLength = chunk.length;
      final rangeHeader = 'bytes $offset-${offset + chunkLength - 1}/$totalSize';

      try {
        final uploadRes = await http.put(
          Uri.parse(uploadUrl),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Length': chunkLength.toString(),
            'Content-Type': 'video/*',
            'Content-Range': rangeHeader,
          },
          body: chunk,
        );

        if (uploadRes.statusCode == 200 || uploadRes.statusCode == 201) {
          // Upload complete, parse returned video ID
          final resBody = jsonDecode(uploadRes.body);
          return resBody['id'];
        } else if (uploadRes.statusCode == 308) {
          // Resume Incomplete
          offset += chunkLength;
          onProgress(offset / totalSize);
          retries = 0; // reset retries after success chunk
        } else {
          throw HttpException(
            'Unexpected status code: ${uploadRes.statusCode}',
            uri: Uri.parse(uploadUrl),
          );
        }
      } catch (e) {
        retries++;
        if (retries >= _maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * retries));
      }
    }

    throw Exception('Upload failed after maximum retries');
  }
}
