import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraApp extends StatefulWidget {
  const CameraApp({super.key});
  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  CameraController? _controller;
  bool _ready = false;
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
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final image = await _controller!.takePicture();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('照片已保存: ${image.name}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
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
              Positioned(bottom: 40, left: 0, right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GestureDetector(onTap: _takePhoto,
                    child: Container(width: 72, height: 72,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      child: Padding(padding: const EdgeInsets.all(6),
                        child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
                    ),
                  ),
                ]),
              ),
            ]),
    );
  }
}
