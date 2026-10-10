import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/app_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

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
  State<BrowserApp> createState() => BrowserAppState();
}

class BrowserAppState extends State<BrowserApp> {
  late WebViewController _controller;
  final TextEditingController _urlController = TextEditingController(text: 'https://cn.bing.com');
  bool _loading = true;
  double _progress = 0;

  /// 供 AppRuntime 返回键调用：尝试 WebView goBack
  Future<bool> tryGoBack() async {
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return true;
      }
    } catch (_) {}
    return false;
  }

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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在安装 NAP 应用...'), backgroundColor: AppTheme.accent));
    AppService().installFromUrl(napUrl).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('应用安装成功'), backgroundColor: AppTheme.success));
    }).catchError((e) {
      String msg = e.toString();
      try { if (e.response?.data is Map && e.response.data['error'] != null) msg = e.response.data['error'].toString(); } catch(_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装失败: $msg'), backgroundColor: AppTheme.danger));
    });
  }

  void _handleDownload(String url) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已加入下载队列: ${Uri.parse(url).path.split('/').last}'), backgroundColor: AppTheme.accent));
    ApiService().uploadFromUrl(url, '下载').catchError((e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e'), backgroundColor: AppTheme.danger));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        title: TextField(
          controller: _urlController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            filled: true, fillColor: AppTheme.cardAlt,
            isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.divider)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
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
        if (_loading) LinearProgressIndicator(value: _progress, backgroundColor: AppTheme.divider, valueColor: const AlwaysStoppedAnimation(AppTheme.accent), minHeight: 2),
        Expanded(child: WebViewWidget(controller: _controller)),
      ]),
    );
  }
}
