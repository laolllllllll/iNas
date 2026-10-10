import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';
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
  WebViewController? _controller;
  bool _loading = true;
  bool _notConnected = false;
  String? _errorMessage;
  int? _errorCode;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 初始化：先检查连接状态，再做预检测，最后加载 WebView
  Future<void> _initialize() async {
    final baseUrl = ApiService().baseUrl;
    final token = ApiService().token;

    // 1. 未连接服务端 → 显示原生提示页，不加载 WebView
    if (baseUrl == null || baseUrl.isEmpty || token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _notConnected = true;
          _loading = false;
        });
      }
      return;
    }

    final initialUrl = '$baseUrl/api/apps/${widget.app.bundleId}/index.html';

    // 2. 预检测：用 Dio 请求目标 URL，拦截 404/500/连接失败等，避免 WebView 显示裸 HTML 错误页
    try {
      final dio = Dio();
      final response = await dio.get(
        initialUrl,
        options: Options(
          headers: {'x-nas-token': token},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      if (response.statusCode != 200) {
        if (mounted) {
          setState(() {
            _errorCode = response.statusCode;
            _errorMessage = '服务器返回错误状态码 ${response.statusCode}，应用可能不存在或已损坏';
            _loading = false;
          });
        }
        return;
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _errorCode = e.response?.statusCode ?? -1;
          _errorMessage = e.response?.data?.toString() ?? e.message ?? '无法连接到服务器，请检查网络和服务端状态';
          _loading = false;
        });
      }
      return;
    }

    // 3. 预检测通过，设置 WebViewController 并加载
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (error) {
          // WebView 运行时资源加载失败 → 显示原生错误，而非裸 HTML
          if (mounted) {
            setState(() {
              _errorCode = error.errorCode;
              _errorMessage = error.description.isNotEmpty ? error.description : '页面资源加载失败';
              _loading = false;
            });
          }
        },
        onNavigationRequest: (request) {
          if (request.url.startsWith('cor-napinstaller://')) {
            _handleNapInstall(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(initialUrl));

    if (mounted) setState(() => _controller = controller);
  }

  /// 重试：清空错误状态并重新初始化
  void _retry() {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _errorCode = null;
      _notConnected = false;
      _controller = null;
    });
    _initialize();
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_notConnected) return _buildNotConnected();
    if (_errorMessage != null) return _buildError();
    return Stack(children: [
      if (_controller != null) WebViewWidget(controller: _controller!),
      if (_loading) const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF))),
    ]);
  }

  /// 未连接服务端时的原生提示页
  Widget _buildNotConnected() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, color: Colors.grey, size: 64),
          const SizedBox(height: 16),
          const Text('未连接设备', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('请先在浏览页连接 Windows iNas 服务', style: TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('去连接'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ]),
      ),
    );
  }

  /// 加载失败时的原生错误页（含错误码 + 描述 + 重试按钮）
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.orange, size: 64),
          const SizedBox(height: 16),
          Text('加载失败 (${_errorCode ?? '?'})', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_errorMessage ?? '未知错误', style: const TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ]),
      ),
    );
  }
}
