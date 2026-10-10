import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/file_item.dart';
import '../services/api_service.dart';

class PreviewPage extends StatefulWidget {
  final FileItem fileItem;
  const PreviewPage({super.key, required this.fileItem});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  String? _localPath;
  bool _loading = true;
  String? _error;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  WebViewController? _webController;

  @override
  void initState() {
    super.initState();
    _loadAndPreview();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _loadAndPreview() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/inas_preview_${DateTime.now().millisecondsSinceEpoch}_${widget.fileItem.name}');

      await ApiService().downloadFile(widget.fileItem.path, tempFile.path);

      setState(() {
        _localPath = tempFile.path;
        _loading = false;
      });

      if (widget.fileItem.isVideo) {
        _initVideo(tempFile.path);
      } else if (widget.fileItem.isHtml) {
        _initWebView(tempFile);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _initVideo(String path) async {
    _videoController = VideoPlayerController.file(File(path));
    await _videoController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowPlaybackSpeedChanging: true,
      placeholder: const Center(child: CircularProgressIndicator()),
    );
    if (mounted) setState(() {});
  }

  void _initWebView(File file) {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1C1C1E))
      ..loadFile(file.path);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.fileItem.name, style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => Navigator.pop(context),
            tooltip: '返回',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF007AFF)),
          SizedBox(height: 16),
          Text('加载中...', style: TextStyle(color: Colors.grey)),
        ],
      ));
    }

    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 48),
          const SizedBox(height: 12),
          const Text('预览失败', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
        ],
      ));
    }

    if (widget.fileItem.isImage && _localPath != null) {
      return InteractiveViewer(
        child: Center(child: Image.file(File(_localPath!), fit: BoxFit.contain)),
      );
    }

    if (widget.fileItem.isVideo && _chewieController != null) {
      return Center(child: Chewie(controller: _chewieController!));
    }

    if (widget.fileItem.isVideo && _chewieController == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)));
    }

    if (widget.fileItem.isHtml && _webController != null) {
      return WebViewWidget(controller: _webController!);
    }

    return const Center(child: Text('不支持的预览类型', style: TextStyle(color: Colors.grey)));
  }
}
