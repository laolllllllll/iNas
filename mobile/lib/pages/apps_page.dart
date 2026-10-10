import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_info.dart';
import '../services/app_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
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
  void initState() { super.initState(); _loadApps(); }

  @override
  void didChangeDependencies() { super.didChangeDependencies(); _refreshWallpaper(); }

  Future<void> _refreshWallpaper() async {
    final wp = await AppService().getWallpaper();
    if (mounted && wp != _wallpaper) setState(() => _wallpaper = wp);
  }

  Future<void> _loadApps() async {
    final apps = await AppService().getAllApps();
    final layout = await AppService().getAppLayout();
    final wallpaper = await AppService().getWallpaper();
    final sorted = <AppInfo>[];
    for (final bundleId in layout) {
      final app = apps.firstWhere((a) => a.bundleId == bundleId, orElse: () => AppInfo(bundleId: '', name: ''));
      if (app.bundleId.isNotEmpty) sorted.add(app);
    }
    for (final app in apps) {
      if (!sorted.any((a) => a.bundleId == app.bundleId)) sorted.add(app);
    }
    if (mounted) setState(() { _apps = sorted; _layout = layout; _wallpaper = wallpaper; _loading = false; });
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
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(16), child: Row(children: [
        Icon(_getAppIcon(app), color: AppTheme.accent, size: 32),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(app.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
          Text('${app.bundleId}\nv${app.version}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ])),
      ])),
      const Divider(color: AppTheme.divider),
      ListTile(leading: const Icon(Icons.info_outline, color: AppTheme.accent), title: const Text('详情', style: TextStyle(color: AppTheme.textPrimary)),
        onTap: () { Navigator.pop(ctx); _showAppDetail(app); }),
      if (!app.isSystem)
        ListTile(leading: const Icon(Icons.delete_outline, color: AppTheme.danger), title: const Text('删除应用', style: TextStyle(color: AppTheme.danger)),
          onTap: () { Navigator.pop(ctx); _confirmDelete(app); }),
      const SizedBox(height: 8),
    ])));
  }

  void _showAppDetail(AppInfo app) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(app.name),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Bundle ID: ${app.bundleId}', style: AppTheme.secondaryStyle),
        const SizedBox(height: 4),
        Text('版本: v${app.version}', style: AppTheme.secondaryStyle),
        const SizedBox(height: 4),
        Text('类型: ${app.isSystem ? "系统应用（不可删除）" : "第三方应用"}', style: AppTheme.secondaryStyle),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
    ));
  }

  Future<void> _confirmDelete(AppInfo app) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('删除 ${app.name}?'),
      content: const Text('此应用及其数据将被永久删除。', style: AppTheme.secondaryStyle),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger), child: const Text('删除')),
      ],
    ));
    if (confirm == true) {
      try { await AppService().uninstallApp(app.bundleId); _showToast('已删除 ${app.name}'); _loadApps(); }
      catch (e) { _showToast('删除失败: $e'); }
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
      case 'com.cor.iNas.Photos': return const Color(0xFFFF3B30);
      case 'com.cor.iNas.Browser': return const Color(0xFF42A5F5);
      case 'com.cor.iNas.Files': return const Color(0xFF007AFF);
      case 'com.cor.iNas.Music': return const Color(0xFFEC407A);
      case 'com.cor.iNas.Settings': return const Color(0xFF757575);
      case 'com.cor.iNas.Trash': return const Color(0xFFFF9500);
      case 'com.cor.iNas.AppStore': return const Color(0xFF5C6BC0);
      case 'com.cor.iNas.Messages': return const Color(0xFF34C759);
      default: return AppTheme.accent;
    }
  }

  void _showToast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    return Scaffold(body: Stack(children: [
      if (_wallpaper != null && _wallpaper!.isNotEmpty && File(_wallpaper!).existsSync())
        Positioned.fill(child: Image.file(File(_wallpaper!), fit: BoxFit.cover)),
      Positioned.fill(child: Container(decoration: BoxDecoration(
        color: _wallpaper != null && _wallpaper!.isNotEmpty ? Colors.black.withOpacity(0.25) : null,
        gradient: (_wallpaper == null || _wallpaper!.isEmpty) ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF2C2C2E), AppTheme.bg]) : null,
      ))),
      Positioned.fill(child: SafeArea(child: Column(children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('APPS', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4))),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 20, crossAxisSpacing: 16, childAspectRatio: 0.75),
          itemCount: _apps.length + 1,
          itemBuilder: (ctx, i) => i == _apps.length ? _buildAddAppButton() : _buildAppIcon(_apps[i]),
        )),
        const Padding(padding: EdgeInsets.only(bottom: 20), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.circle, color: AppTheme.accent, size: 8), SizedBox(width: 6), Icon(Icons.circle, color: AppTheme.textTertiary, size: 8),
        ])),
      ]))),
    ]));
  }

  Widget _buildAppIcon(AppInfo app) {
    final color = _getAppColor(app);
    return GestureDetector(
      onTap: () => _openApp(app),
      onLongPress: () => _showAppMenu(app),
      child: Column(children: [
        Container(width: 60, height: 60, decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, color.withOpacity(0.7)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
        ), child: Icon(_getAppIcon(app), color: Colors.white, size: 30)),
        const SizedBox(height: 6),
        Text(app.name, style: const TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(color: Colors.black45, blurRadius: 2)]), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildAddAppButton() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppRuntime(child: SettingsApp(initialTab: 'add_app')))),
      child: Column(children: [
        Container(width: 60, height: 60, decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.textTertiary, width: 2)),
          child: const Icon(Icons.add, color: AppTheme.textSecondary, size: 30)),
        const SizedBox(height: 6),
        const Text('添加', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ]),
    );
  }
}
