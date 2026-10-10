import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用运行环境：顶部状态栏 + 底部导航栏，包裹所有应用页面
class AppRuntime extends StatefulWidget {
  final Widget child;
  final String? title;
  final Color? backgroundColor;
  /// 返回键回调：返回 true 表示已处理（如 WebView goBack），不退出
  final Future<bool> Function()? onBack;
  const AppRuntime({
    super.key,
    required this.child,
    this.title,
    this.backgroundColor,
    this.onBack,
  });
  @override
  State<AppRuntime> createState() => _AppRuntimeState();
}

class _AppRuntimeState extends State<AppRuntime> {
  String _time = '';
  Timer? _timer;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() => _time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
  }

  /// 返回键逻辑：先尝试 onBack（WebView goBack），再双击退出
  Future<void> _onBack() async {
    // 1. 先尝试 WebView goBack 等自定义返回
    if (widget.onBack != null) {
      try {
        final handled = await widget.onBack!();
        if (handled) return;
      } catch (_) {}
    }
    // 2. 双击退出
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('再按一次退出'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
      );
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// 主页键：直接退出 App 回桌面
  void _onHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? Colors.black,
      body: SafeArea(
        top: false, bottom: false,
        child: Column(children: [
          _buildStatusBar(),
          Expanded(child: widget.child),
          _buildNavBar(),
        ]),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 44, padding: const EdgeInsets.symmetric(horizontal: 20), color: Colors.black87,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_time, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        Row(children: const [
          Icon(Icons.signal_cellular_alt, color: Colors.white, size: 16),
          SizedBox(width: 4),
          Icon(Icons.wifi, color: Colors.white, size: 16),
          SizedBox(width: 6),
          Icon(Icons.battery_full, color: Colors.white, size: 18),
        ]),
      ]),
    );
  }

  Widget _buildNavBar() {
    return Container(
      height: 50, color: Colors.black87,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        // 返回键
        IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: _onBack,
        ),
        // 主页键
        IconButton(
          icon: const Icon(Icons.circle, color: Colors.white, size: 16),
          onPressed: _onHome,
        ),
        // 多任务键（占位）
        IconButton(
          icon: const Icon(Icons.check_box_outline_blank, color: Colors.white54, size: 18),
          onPressed: () {},
        ),
      ]),
    );
  }
}
