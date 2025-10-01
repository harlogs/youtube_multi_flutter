import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'main.dart';

class MultiVideoPickerUploadPage extends StatefulWidget {
  final String? accessToken;
  final String? channelId;

  const MultiVideoPickerUploadPage({Key? key, this.accessToken, this.channelId}) : super(key: key);

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

  Future<void> _initPrefsAndVideos() async {
    _prefs = await SharedPreferences.getInstance();
    _uploadedVideoIds = _prefs.getStringList('uploadedVideoIds')?.toSet() ?? {};
    if (!kIsWeb) await _fetchVideos();
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

  /// Web file picker
  Future<List<html.File>> pickVideosWeb() async {
    final input = html.FileUploadInputElement()
      ..accept = 'video/*'
      ..multiple = true;
    input.click();
    await input.onChange.first;
    if (input.files == null) return [];
    return input.files!;
  }

  Future<Uint8List?> readVideoBytes(html.File file) async {
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    return reader.result as Uint8List?;
  }

  Future<void> _uploadSelectedVideosWeb() async {
  if (widget.accessToken == null || widget.channelId == null) return;
  setState(() => _loading = true);

  final uploader = YouTubeUploader(widget.accessToken!, selectedChannelId: widget.channelId!);

  // Open the file picker
  final files = await pickVideosWeb();
  if (files.isEmpty) {
    setState(() => _loading = false);
    return;
  }

  for (final file in files) {
    final bytes = await readVideoBytes(file);
    if (bytes == null) continue;

    final name = file.name;

    // Initialize progress and status notifiers
    _uploadProgressNotifiers.putIfAbsent(name, () => ValueNotifier<double>(0));
    _uploadStatusNotifiers.putIfAbsent(name, () => ValueNotifier<String>('Uploading...'));

    try {
      final videoId = await uploader.uploadResumable(
        videoBytes: bytes,
        title: name,
        description: 'Uploaded via Flutter web app',
        onProgress: (progress) => _uploadProgressNotifiers[name]?.value = progress,
      );

      if (videoId != null) {
        _uploadStatusNotifiers[name]?.value = 'Uploaded';
      } else {
        _uploadStatusNotifiers[name]?.value = 'Failed';
      }
    } catch (e) {
      _uploadStatusNotifiers[name]?.value = 'Failed: $e';
    }
  }

  setState(() => _loading = false);
}


  Future<void> pickVideosWebAndUpload() async {
    if (widget.accessToken == null || widget.channelId == null) return;

    final uploader = YouTubeUploader(
      widget.accessToken!,
      selectedChannelId: widget.channelId!,
    );

    final files = await pickVideosWeb();
    for (final file in files) {
      final bytes = await readVideoBytes(file);
      if (bytes == null) continue;

      final name = file.name;
      try {
        await uploader.uploadResumable(
          videoBytes: bytes,
          title: name,
          onProgress: (progress) => print('Upload progress: ${progress * 100}%'),
        );
      } catch (e) {
        print('Upload failed for $name: $e');
      }
    }
  }

    Future<void> _uploadSelectedVideos() async {
      if (widget.accessToken == null || widget.channelId == null) return;
      setState(() => _loading = true);

      final uploader = YouTubeUploader(widget.accessToken!, selectedChannelId: widget.channelId!);

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
            onProgress: (progress) => _uploadProgressNotifiers[asset.id]?.value = progress,
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
                child: const Text('Uploaded', style: TextStyle(color: Colors.white, fontSize: 10)),
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
                    builder: (_, progress, __) =>
                        progress > 0 ? LinearProgressIndicator(value: progress) : const SizedBox.shrink(),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: _uploadStatusNotifiers[video.id]!,
                    builder: (_, status, __) => status.isNotEmpty
                        ? Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.all(2),
                            child: Text(status, style: const TextStyle(color: Colors.white, fontSize: 10)),
                          )
                        : const SizedBox.shrink(),
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
                Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => MyApp()), (_) => false);
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('Pick & Upload Videos'),
        actions: [
          if (!kIsWeb) IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchVideos),
          if (!kIsWeb) IconButton(icon: const Icon(Icons.select_all), onPressed: _selectAll),
          if (!kIsWeb) IconButton(icon: const Icon(Icons.check_box), onPressed: _markSelectedAsUploaded),
          IconButton(
            icon: const Icon(Icons.cloud_upload, color: Colors.black),
            onPressed: _loading
                ? null
                : () {
                    if (kIsWeb) {
                      pickVideosWebAndUpload();
                    } else {
                      _uploadSelectedVideos();
                    }
                  },
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: kIsWeb
            ? Center(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.upload_file),
                    label: Text('Pick & Upload Videos'),
                    onPressed: _loading ? null : _uploadSelectedVideosWeb,
                  ),
                )
            : 
          _videos.isEmpty
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

/// YouTubeUploader
class YouTubeUploader {
  static const String _uploadInitiationUrl =
      'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status';
  static const int _chunkSize = 1024 * 1024 * 5; // 5 MB
  static const int _maxRetries = 5;

  final String accessToken;
  final String selectedChannelId;

  YouTubeUploader(this.accessToken, {required this.selectedChannelId});

  Future<String?> uploadResumable({
    required Uint8List videoBytes,
    required String title,
    String description = '',
    required Function(double) onProgress,
  }) async {
    final totalSize = videoBytes.length;

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
          'channelId': selectedChannelId,
        },
        'status': {'privacyStatus': 'private'},
      }),
    );

    if (initRes.statusCode != 200) throw Exception('Failed to initiate upload: ${initRes.body}');

    final uploadUrl = initRes.headers['location'];
    if (uploadUrl == null) throw Exception('Upload session URL not returned');

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
          final resBody = jsonDecode(uploadRes.body);
          return resBody['id'];
        } else if (uploadRes.statusCode == 308) {
          offset += chunkLength;
          onProgress(offset / totalSize);
          retries = 0;
        } else {
          // throw HttpException('Unexpected status code: ${uploadRes.statusCode}', uri: Uri.parse(uploadUrl));
          throw Exception('Unexpected status code: ${uploadRes.statusCode}');
        }
      } catch (e) {
        retries++;
        if (retries >= _maxRetries) rethrow;
        await Future.delayed(Duration(seconds: 2 * retries));
      }
    }

    throw Exception('Upload failed after maximum retries');
  }
}
