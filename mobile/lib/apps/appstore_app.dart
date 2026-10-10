import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/app_service.dart';

class AppStoreApp extends StatefulWidget {
  const AppStoreApp({super.key});
  @override
  State<AppStoreApp> createState() => _AppStoreAppState();
}

class _AppStoreAppState extends State<AppStoreApp> {
  late WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (request) {
          if (request.url.startsWith('cor-napinstaller://')) {
            final uri = Uri.parse(request.url);
            final napUrl = uri.queryParameters['url'] ?? '';
            if (napUrl.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在安装应用...'), backgroundColor: Color(0xFF007AFF)));
              AppService().installFromUrl(napUrl).then((_) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('安装成功'), backgroundColor: Color(0xFF34C759)));
              }).catchError((e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装失败: $e'), backgroundColor: Color(0xFFFF3B30)));
              });
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse('https://apps.inas.corw.top/cor-app/index.html'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_loading) const Center(child: CircularProgressIndicator(color: Color(0xFF5C6BC0))),
      ]),
    );
  }
}
