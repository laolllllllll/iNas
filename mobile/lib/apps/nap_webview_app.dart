import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/app_info.dart';
import '../services/app_service.dart';
import '../services/api_service.dart';

/// NAP 应用 WebView 容器，识别 cor-napinstaller:// 协议
class NapWebViewApp extends StatefulWidget {
  final AppInfo app;
  const NapWebViewApp({super.key, required this.app});

  @override
  State<NapWebViewApp> createState() => _NapWebViewAppState();
}

class _NapWebViewAppState extends State<NapWebViewApp> {
  late WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final baseUrl = ApiService().baseUrl;
    final token = ApiService().token;
    final initialUrl = '$baseUrl/api/apps/${widget.app.bundleId}/index.html';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (request) {
          if (request.url.startsWith('cor-napinstaller://')) {
            _handleNapInstall(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(initialUrl));
  }

  void _handleNapInstall(String url) {
    final uri = Uri.parse(url);
    final napUrl = uri.queryParameters['url'] ?? '';
    if (napUrl.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: const Text('安装应用', style: TextStyle(color: Colors.white)),
      content: Text('正在下载并安装 NAP 应用...\n$napUrl', style: const TextStyle(color: Colors.grey, fontSize: 12)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
    ));
    AppService().installFromUrl(napUrl).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('应用安装成功'), backgroundColor: Color(0xFF34C759)));
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装失败: $e'), backgroundColor: const Color(0xFFFF3B30)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_loading) const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF))),
      ]),
    );
  }
}
