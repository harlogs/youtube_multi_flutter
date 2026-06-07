import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

class ReelPlayerPage extends StatefulWidget {
  final List<AssetEntity> videos;
  final int initialIndex;

  const ReelPlayerPage({
    Key? key,
    required this.videos,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<ReelPlayerPage> createState() => _ReelPlayerPageState();
}

class _ReelPlayerPageState extends State<ReelPlayerPage> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.videos.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => _ReelVideoTile(
              key: ValueKey(widget.videos[i].id),
              entity: widget.videos[i],
              isActive: i == _currentIndex,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.videos.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelVideoTile extends StatefulWidget {
  final AssetEntity entity;
  final bool isActive;

  const _ReelVideoTile({Key? key, required this.entity, required this.isActive})
      : super(key: key);

  @override
  State<_ReelVideoTile> createState() => _ReelVideoTileState();
}

class _ReelVideoTileState extends State<_ReelVideoTile> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _controlsVisible = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _initVideo();
  }

  @override
  void didUpdateWidget(_ReelVideoTile old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _initVideo();
    } else if (!widget.isActive && old.isActive) {
      _disposeVideo();
    }
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final file = await widget.entity.file;
    if (file == null || !mounted) return;
    _controller = VideoPlayerController.file(file);
    await _controller!.initialize();
    if (!mounted) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    _controller!.play();
    _controller!.setLooping(true);
    if (mounted) setState(() => _initialized = true);
  }

  void _disposeVideo() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    _initialized = false;
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() => _controlsVisible = !_controlsVisible);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_initialized && _controller != null)
            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (_controlsVisible) ...[
            Container(color: Colors.black26),
            Center(
              child: Icon(
                _controller?.value.isPlaying == true
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: Colors.white,
                size: 64,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
