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

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _tokenController.dispose();
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

  void _onQRDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.first;
    if (barcode.rawValue != null) {
      try {
        final data = jsonDecode(barcode.rawValue!);
        setState(() {
          _ipController.text = data['ip'] ?? '';
          _portController.text = data['port']?.toString() ?? '18080';
          _tokenController.text = data['token'] ?? '';
          _scanning = false;
        });
        _connect();
      } catch (e) {
        // 不是 JSON 格式，忽略
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('扫描二维码'),
          backgroundColor: Colors.black,
        ),
        body: Stack(
          children: [
            MobileScanner(
              onDetect: _onQRDetect,
            ),
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
                    '扫描 Windows 端 iNas 窗口中的二维码',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
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
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFEF5350), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _scanning = true),
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: const Text('扫码'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4FC3F7),
                      side: const BorderSide(color: Color(0xFF4FC3F7)),
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
                      backgroundColor: const Color(0xFF4FC3F7),
                      foregroundColor: const Color(0xFF1A1A2E),
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
        labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF455A64)),
        prefixIcon: Icon(icon, color: const Color(0xFF4FC3F7), size: 20),
        filled: true,
        fillColor: const Color(0xFF12121A),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A2A3E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
