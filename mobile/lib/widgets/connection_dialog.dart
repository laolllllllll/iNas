import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';

class ConnectionDialog extends StatefulWidget {
  final VoidCallback? onConnected;
  const ConnectionDialog({super.key, this.onConnected});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '18080');
  final _tokenController = TextEditingController();
  bool _scanning = false;
  bool _connecting = false;
  String? _error;

  // mobile_scanner 控制器，管理相机生命周期
  MobileScannerController? _scannerController;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() { _connecting = true; _error = null; });
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 18080;
    final token = _tokenController.text.trim();

    if (ip.isEmpty || token.isEmpty) {
      setState(() {
        _error = '请填写 IP 地址和 Token';
        _connecting = false;
      });
      return;
    }

    await ApiService().saveConnection(ip, port, token);
    final ok = await ApiService().testConnection();

    if (ok) {
      if (mounted) {
        Navigator.of(context).pop();
        widget.onConnected?.call();
      }
    } else {
      await ApiService().clearConnection();
      setState(() {
        _error = '连接失败，请检查 IP、端口和 Token 是否正确，确保同一 WiFi';
        _connecting = false;
      });
    }
  }

  // 打开扫码页面（mobile_scanner 内部处理相机权限请求）
  void _openScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    setState(() { _scanning = true; });
  }

  void _closeScanner() {
    _scannerController?.dispose();
    _scannerController = null;
    if (mounted) setState(() { _scanning = false; });
  }

  void _onQRDetect(BarcodeCapture capture) {
    // 空值保护：barcodes 可能为空
    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    try {
      final data = jsonDecode(rawValue);
      if (data is! Map) return;

      final ip = data['ip']?.toString() ?? '';
      final port = data['port']?.toString() ?? '18080';
      final token = data['token']?.toString() ?? '';

      if (ip.isEmpty || token.isEmpty) return;

      // 停止扫描防止重复触发
      _scannerController?.stop();

      setState(() {
        _ipController.text = ip;
        _portController.text = port;
        _tokenController.text = token;
        _scanning = false;
      });

      // 延迟关闭控制器后再连接
      Future.delayed(const Duration(milliseconds: 300), () {
        _scannerController?.dispose();
        _scannerController = null;
        _connect();
      });
    } catch (e) {
      // 不是有效的 JSON 二维码，忽略继续扫描
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return _buildScannerView();
    }
    return _buildConnectionForm();
  }

  Widget _buildScannerView() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _closeScanner,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerController?.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerController?.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 扫码区域，mobile_scanner 内部处理权限请求
          MobileScanner(
            controller: _scannerController,
            onDetect: _onQRDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 56),
                      const SizedBox(height: 16),
                      const Text(
                        '无法访问相机',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请在系统设置 > iNas > 相机中开启权限后重试\n\n错误: $error',
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _closeScanner,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('返回手动输入'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          foregroundColor: const Color(0xFF1C1C1E),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // 扫描框
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF007AFF), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // 底部提示
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '将二维码放入框内，自动扫描',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionForm() {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '连接 iNas 服务端',
        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _buildTextField(
              controller: _ipController,
              label: 'IP 地址',
              icon: Icons.wifi,
              hint: '如 192.168.1.100',
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _portController,
              label: '端口',
              icon: Icons.settings_ethernet,
              hint: '默认 18080',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _tokenController,
              label: '认证 Token',
              icon: Icons.vpn_key,
              hint: '从 Windows 端获取',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openScanner,
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: const Text('扫码'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF007AFF),
                      side: const BorderSide(color: Color(0xFF007AFF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _connecting ? null : _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: const Color(0xFF1C1C1E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _connecting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('连接', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF636366)),
        prefixIcon: Icon(icon, color: const Color(0xFF007AFF), size: 20),
        filled: true,
        fillColor: const Color(0xFF1C1C1E),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF38383A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF007AFF)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
