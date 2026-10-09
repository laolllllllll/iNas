import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/api_service.dart';

class CameraApp extends StatefulWidget {
  const CameraApp({super.key});
  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  CameraController? _controller;
  bool _ready = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = '未找到相机');
        return;
      }
      _controller = CameraController(cameras[0], ResolutionPreset.medium);
      await _controller!.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      setState(() => _error = '相机初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _uploading) return;
    try {
      setState(() => _uploading = true);
      final image = await _controller!.takePicture();
      // 用时间戳命名
      final now = DateTime.now();
      final ts = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}${now.second.toString().padLeft(2,'0')}';
      final newName = 'IMG_$ts.jpg';
      // 上传到服务器 Photos 目录
      try {
        await ApiService().uploadFile(image.path, 'Photos', customFilename: newName);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存到相册'), backgroundColor: Color(0xFF66BB6A)));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e'), backgroundColor: const Color(0xFFEF5350)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
        ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
        : !_ready
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
          : Stack(children: [
              CameraPreview(_controller!),
              if (_uploading)
                Container(color: Colors.black54, child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircularProgressIndicator(color: Color(0xFF4FC3F7)),
                  SizedBox(height: 12),
                  Text('正在保存到相册...', style: TextStyle(color: Colors.white)),
                ]))),
              Positioned(bottom: 40, left: 0, right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GestureDetector(onTap: _takePhoto,
                    child: Container(width: 72, height: 72,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _uploading ? Colors.grey : Colors.white, width: 4)),
                      child: Padding(padding: const EdgeInsets.all(6),
                        child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: _uploading ? Colors.grey : Colors.white))),
                    ),
                  ),
                ]),
              ),
            ]),
    );
  }
}
