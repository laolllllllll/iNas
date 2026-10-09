import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用运行环境：顶部状态栏 + 底部导航栏，包裹所有应用页面
class AppRuntime extends StatefulWidget {
  final Widget child;
  final String? title;
  final Color? backgroundColor;
  final VoidCallback? onBack;

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
  static const MethodChannel _platform = MethodChannel('inas/battery');

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? const Color(0xFF000000),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 状态栏
            _buildStatusBar(),
            // 应用内容
            Expanded(child: widget.child),
            // 底部导航栏（安卓三大键）
            _buildNavBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_time, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          Row(
            children: [
              // 信号图标
              const Icon(Icons.signal_cellular_alt, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              // WiFi 图标
              const Icon(Icons.wifi, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              // 电池图标
              _buildBatteryIcon(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryIcon() {
    return Container(
      width: 24,
      height: 12,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.all(1.5),
            width: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      height: 50,
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 返回
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: () {
              if (widget.onBack != null) {
                widget.onBack!();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          // 主页
          IconButton(
            icon: const Icon(Icons.circle, color: Colors.white, size: 16),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          // 多任务（占位）
          IconButton(
            icon: const Icon(Icons.check_box_outline_blank, color: Colors.white, size: 18),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
