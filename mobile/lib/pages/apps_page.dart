import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_info.dart';
import '../services/app_service.dart';
import '../services/api_service.dart';
import 'app_runtime.dart';
import '../apps/camera_app.dart';
import '../apps/photos_app.dart';
import '../apps/browser_app.dart';
import '../apps/files_app.dart';
import '../apps/music_app.dart';
import '../apps/settings_app.dart';
import '../apps/trash_app.dart';
import '../apps/appstore_app.dart';
import '../apps/messages_app.dart';
import '../apps/nap_webview_app.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  List<AppInfo> _apps = [];
  List<String> _layout = [];
  String? _wallpaper;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 返回桌面时刷新壁纸
    _refreshWallpaper();
  }

  Future<void> _refreshWallpaper() async {
    final wp = await AppService().getWallpaper();
    if (mounted && wp != _wallpaper) setState(() => _wallpaper = wp);
  }

  Future<void> _loadApps() async {
    final apps = await AppService().getAllApps();
    final layout = await AppService().getAppLayout();
    final wallpaper = await AppService().getWallpaper();
    // 按布局排序
    final sorted = <AppInfo>[];
    for (final bundleId in layout) {
      final app = apps.firstWhere((a) => a.bundleId == bundleId, orElse: () => AppInfo(bundleId: '', name: ''));
      if (app.bundleId.isNotEmpty) sorted.add(app);
    }
    // 添加不在布局中的新应用
    for (final app in apps) {
      if (!sorted.any((a) => a.bundleId == app.bundleId)) sorted.add(app);
    }
    if (mounted) setState(() {
      _apps = sorted;
      _layout = layout;
      _wallpaper = wallpaper;
      _loading = false;
    });
  }

  void _openApp(AppInfo app) {
    Widget page;
    switch (app.bundleId) {
      case 'com.cor.iNas.Camera': page = const CameraApp(); break;
      case 'com.cor.iNas.Photos': page = const PhotosApp(); break;
      case 'com.cor.iNas.Browser': page = const BrowserApp(); break;
      case 'com.cor.iNas.Files': page = const FilesApp(); break;
      case 'com.cor.iNas.Music': page = const MusicApp(); break;
      case 'com.cor.iNas.Settings': page = const SettingsApp(); break;
      case 'com.cor.iNas.Trash': page = const TrashApp(); break;
      case 'com.cor.iNas.AppStore': page = const AppStoreApp(); break;
      case 'com.cor.iNas.Messages': page = const MessagesApp(); break;
      default: page = NapWebViewApp(app: app);
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => AppRuntime(child: page, title: app.name)));
  }

  void _showAppMenu(AppInfo app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(_getAppIcon(app), color: const Color(0xFF4FC3F7), size: 32),
          title: Text(app.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          subtitle: Text('${app.bundleId}\nv${app.version}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        const Divider(color: Color(0xFF2A2A3E)),
        ListTile(
          leading: const Icon(Icons.info_outline, color: Color(0xFF4FC3F7)),
          title: const Text('详情', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(ctx); _showAppDetail(app); },
        ),
        if (!app.isSystem)
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)),
            title: const Text('删除应用', style: TextStyle(color: Color(0xFFEF5350))),
            onTap: () { Navigator.pop(ctx); _confirmDelete(app); },
          ),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _showAppDetail(AppInfo app) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: Text(app.name, style: const TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Bundle ID: ${app.bundleId}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 4),
        Text('版本: v${app.version}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 4),
        Text('类型: ${app.isSystem ? "系统应用（不可删除）" : "第三方应用"}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
    ));
  }

  Future<void> _confirmDelete(AppInfo app) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: Text('删除 ${app.name}?', style: const TextStyle(color: Colors.white)),
      content: const Text('此应用及其数据将被永久删除。', style: TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF5350)), child: const Text('删除')),
      ],
    ));
    if (confirm == true) {
      try {
        await AppService().uninstallApp(app.bundleId);
        _showToast('已删除 ${app.name}');
        _loadApps();
      } catch (e) { _showToast('删除失败: $e'); }
    }
  }

  IconData _getAppIcon(AppInfo app) {
    switch (app.bundleId) {
      case 'com.cor.iNas.Camera': return Icons.camera_alt;
      case 'com.cor.iNas.Photos': return Icons.photo_library;
      case 'com.cor.iNas.Browser': return Icons.public;
      case 'com.cor.iNas.Files': return Icons.folder;
      case 'com.cor.iNas.Music': return Icons.music_note;
      case 'com.cor.iNas.Settings': return Icons.settings;
      case 'com.cor.iNas.Trash': return Icons.delete_sweep;
      case 'com.cor.iNas.AppStore': return Icons.store;
      case 'com.cor.iNas.Messages': return Icons.message;
      default: return Icons.apps;
    }
  }

  Color _getAppColor(AppInfo app) {
    switch (app.bundleId) {
      case 'com.cor.iNas.Camera': return const Color(0xFF607D8B);
      case 'com.cor.iNas.Photos': return const Color(0xFFEF5350);
      case 'com.cor.iNas.Browser': return const Color(0xFF42A5F5);
      case 'com.cor.iNas.Files': return const Color(0xFF4FC3F7);
      case 'com.cor.iNas.Music': return const Color(0xFFEC407A);
      case 'com.cor.iNas.Settings': return const Color(0xFF757575);
      case 'com.cor.iNas.Trash': return const Color(0xFFFFA726);
      case 'com.cor.iNas.AppStore': return const Color(0xFF5C6BC0);
      case 'com.cor.iNas.Messages': return const Color(0xFF66BB6A);
      default: return const Color(0xFF4FC3F7);
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)));
    return Scaffold(
      body: Stack(children: [
        // 壁纸背景
        if (_wallpaper != null && _wallpaper!.isNotEmpty && File(_wallpaper!).existsSync())
          Positioned.fill(child: Image.file(File(_wallpaper!), fit: BoxFit.cover)),
        // 暗色遮罩 + 默认渐变
        Positioned.fill(child: Container(
          decoration: BoxDecoration(
            color: _wallpaper != null && _wallpaper!.isNotEmpty ? Colors.black.withOpacity(0.35) : null,
            gradient: (_wallpaper == null || _wallpaper!.isEmpty) ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFF1A1A2E), const Color(0xFF0D0D1A)],
            ) : null,
          ),
        )),
        // 内容
        Positioned.fill(child: SafeArea(
          child: Column(
            children: [
              // 顶部标题
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('APPS', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4)),
              ),
              // 应用网格
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _apps.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == _apps.length) return _buildAddAppButton();
                    return _buildAppIcon(_apps[i]);
                  },
                ),
              ),
              // 底部指示
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.circle, color: Color(0xFF4FC3F7), size: 8),
                  SizedBox(width: 6),
                  Icon(Icons.circle, color: Color(0xFF455A64), size: 8),
                ]),
              ),
            ],
          ),
        )),
      ]),
    );
  }

  Widget _buildAppIcon(AppInfo app) {
    return GestureDetector(
      onTap: () => _openApp(app),
      onLongPress: () => _showAppMenu(app),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _getAppColor(app),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: _getAppColor(app).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: Icon(_getAppIcon(app), color: Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          Text(app.name, style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildAddAppButton() {
    return GestureDetector(
      onTap: () {
        // 跳转到设置→添加应用
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AppRuntime(child: SettingsApp(initialTab: 'add_app'))));
      },
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF455A64), style: BorderStyle.solid, width: 2),
            ),
            child: const Icon(Icons.add, color: Color(0xFF90A4AE), size: 28),
          ),
          const SizedBox(height: 6),
          const Text('添加', style: TextStyle(color: Color(0xFF90A4AE), fontSize: 11)),
        ],
      ),
    );
  }
}
