import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class CameraApp extends StatefulWidget {
  const CameraApp({super.key});
  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _ready = false;
  bool _uploading = false;
  bool _switching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = '未找到相机');
        return;
      }
      await _startCamera(_cameraIndex);
    } catch (e) {
      setState(() => _error = '相机初始化失败: $e');
    }
  }

  Future<void> _startCamera(int index) async {
    if (index >= _cameras.length) index = 0;
    _cameraIndex = index;
    final controller = CameraController(_cameras[index], ResolutionPreset.high);
    try {
      await controller.initialize();
      if (mounted) {
        setState(() {
          _controller = controller;
          _ready = true;
          _switching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '相机启动失败: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _switching) return;
    setState(() => _switching = true);
    final old = _controller;
    _controller = null;
    _ready = false;
    await _startCamera((_cameraIndex + 1) % _cameras.length);
    old?.dispose();
  }

  bool get _hasFrontCamera => _cameras.any((c) => c.lensDirection == CameraLensDirection.front);

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
      final now = DateTime.now();
      final ts = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}${now.second.toString().padLeft(2,'0')}';
      final newName = 'IMG_$ts.jpg';
      try {
        await ApiService().uploadFile(image.path, 'Photos', customFilename: newName);
        if (mounted) _showToast('已保存到相册', AppTheme.success);
      } catch (e) {
        if (mounted) _showToast('上传失败: $e', AppTheme.danger);
      }
    } catch (e) {
      if (mounted) _showToast('拍照失败: $e', AppTheme.danger);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showToast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
        ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
        : !_ready
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const CircularProgressIndicator(color: AppTheme.accent),
              const SizedBox(height: 12),
              Text(_switching ? '切换摄像头...' : '正在启动相机...', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ]))
          : Stack(children: [
              CameraPreview(_controller!),
              // 顶部控制栏
              Positioned(top: 0, left: 0, right: 0,
                child: SafeArea(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent])),
                  child: Row(children: [
                    const Text('相机', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_hasFrontCamera)
                      GestureDetector(onTap: _switchCamera,
                        child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                          child: const Icon(Icons.flip_camera_android, color: Colors.white, size: 22))),
                  ]),
                )),
              ),
              // 上传遮罩
              if (_uploading)
                Container(color: Colors.black54, child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const CircularProgressIndicator(color: AppTheme.accent),
                  const SizedBox(height: 12),
                  const Text('正在保存到相册...', style: TextStyle(color: Colors.white)),
                ]))),
              // 底部快门
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
