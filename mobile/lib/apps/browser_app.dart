import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/app_service.dart';
import '../services/api_service.dart';

// 可识别的下载文件扩展名
const _downloadExtensions = [
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2',
  'mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg',
  'mp4', 'mkv', 'avi', 'mov', 'flv', 'wmv', 'webm',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv',
  'exe', 'msi', 'dmg', 'pkg', 'deb', 'rpm',
  'nap', 'torrent', 'apk', 'ipa',
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic',
  'txt', 'md', 'json', 'xml', 'yaml', 'yml',
  'py', 'js', 'ts', 'dart', 'go', 'rs', 'java', 'kt', 'c', 'cpp', 'h',
];

bool _isDownloadLink(String url) {
  try {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    for (final ext in _downloadExtensions) {
      if (path.endsWith('.$ext')) return true;
    }
  } catch (_) {}
  return false;
}

class BrowserApp extends StatefulWidget {
  const BrowserApp({super.key});
  @override
  State<BrowserApp> createState() => _BrowserAppState();
}

class _BrowserAppState extends State<BrowserApp> {
  late WebViewController _controller;
  final TextEditingController _urlController = TextEditingController(text: 'https://cn.bing.com');
  bool _loading = true;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) { setState(() { _loading = true; _progress = 0; }); _urlController.text = url; },
        onProgress: (p) => setState(() => _progress = p / 100),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (request) {
          if (request.url.startsWith('cor-napinstaller://')) {
            _handleNapInstall(request.url);
            return NavigationDecision.prevent;
          }
          if (_isDownloadLink(request.url)) {
            _handleDownload(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse('https://cn.bing.com'));
  }

  void _handleNapInstall(String url) {
    final uri = Uri.parse(url);
    final napUrl = uri.queryParameters['url'] ?? '';
    if (napUrl.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('正在安装 NAP 应用...'), backgroundColor: Color(0xFF4FC3F7)));
    AppService().installFromUrl(napUrl).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('应用安装成功'), backgroundColor: Color(0xFF66BB6A)));
    }).catchError((e) {
      String msg = e.toString();
      try { if (e.response?.data is Map && e.response.data['error'] != null) msg = e.response.data['error'].toString(); } catch(_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装失败: $msg'), backgroundColor: Color(0xFFEF5350)));
    });
  }

  void _handleDownload(String url) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已加入下载队列: ${Uri.parse(url).path.split('/').last}'), backgroundColor: const Color(0xFF4FC3F7)));
    ApiService().uploadFromUrl(url, '下载').catchError((e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e'), backgroundColor: const Color(0xFFEF5350)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: TextField(
          controller: _urlController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            filled: true, fillColor: Color(0xFF12121A),
            isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A3E))),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4FC3F7))),
          ),
          onSubmitted: (url) {
            if (!url.startsWith('http')) url = 'https://$url';
            _controller.loadRequest(Uri.parse(url));
          },
        ),
        actions: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => _controller.goBack()),
          IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _controller.goForward()),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller.reload()),
        ],
      ),
      body: Column(children: [
        if (_loading) LinearProgressIndicator(value: _progress, backgroundColor: Color(0xFF2A2A3E), valueColor: AlwaysStoppedAnimation(Color(0xFF4FC3F7)), minHeight: 2),
        Expanded(child: WebViewWidget(controller: _controller)),
      ]),
    );
  }
}
