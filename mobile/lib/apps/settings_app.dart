import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/app_service.dart';
import '../models/file_item.dart';

class SettingsApp extends StatefulWidget {
  final String? initialTab;
  const SettingsApp({super.key, this.initialTab});
  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  String _deviceName = '';
  String _serverName = '';
  Map<String, dynamic> _serverInfo = {};
  List<dynamic> _devices = [];
  bool _loading = true;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _napUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _deviceName = await AppService().getDeviceName() ?? '';
    try {
      _serverInfo = await ApiService().getServerInfo();
      _serverName = _serverInfo['serverName'] ?? '';
      _devices = await ApiService().getDevices();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: Color(0xFF12121A), body: Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7))));
    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(backgroundColor: const Color(0xFF1A1A2E), title: const Text('设置'), automaticallyImplyLeading: false),
      body: ListView(children: [
        _section('设备管理', [
          ListTile(leading: const Icon(Icons.devices, color: Color(0xFF4FC3F7)), title: const Text('已绑定设备', style: TextStyle(color: Colors.white)),
            subtitle: Text('${_devices.length}/10 台', style: const TextStyle(color: Color(0xFF6B7280))),
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF455A64)), onTap: _showDevices),
          ListTile(leading: const Icon(Icons.power_settings_new, color: Color(0xFFEF5350)), title: const Text('关机', style: TextStyle(color: Color(0xFFEF5350))), onTap: () => _confirmAction('关机', ApiService().shutdown)),
          ListTile(leading: const Icon(Icons.restart_alt, color: Color(0xFFFFA726)), title: const Text('重启', style: TextStyle(color: Color(0xFFFFA726))), onTap: () => _confirmAction('重启', ApiService().restart)),
        ]),
        _section('添加应用', [
          ListTile(leading: const Icon(Icons.add_circle_outline, color: Color(0xFF66BB6A)), title: const Text('从 URL 安装 NAP', style: TextStyle(color: Colors.white)), onTap: _showNapUrlDialog),
          ListTile(leading: const Icon(Icons.file_upload_outlined, color: Color(0xFF4FC3F7)), title: const Text('从本地文件安装', style: TextStyle(color: Colors.white)), onTap: _installFromFile),
        ]),
        _section('壁纸', [
          ListTile(leading: const Icon(Icons.wallpaper, color: Color(0xFFEC407A)), title: const Text('从本机选择', style: TextStyle(color: Colors.white)), onTap: _pickLocalWallpaper),
          ListTile(leading: const Icon(Icons.photo_library, color: Color(0xFFEF5350)), title: const Text('从 NAS 相册选择', style: TextStyle(color: Colors.white)), onTap: _pickNasWallpaper),
          ListTile(leading: const Icon(Icons.refresh, color: Color(0xFF90A4AE)), title: const Text('恢复默认', style: TextStyle(color: Colors.white)), onTap: _resetWallpaper),
        ]),
        _section('本机', [
          ListTile(leading: const Icon(Icons.phone_iphone, color: Color(0xFF4FC3F7)), title: const Text('本机名字', style: TextStyle(color: Colors.white)), subtitle: Text(_deviceName, style: const TextStyle(color: Color(0xFF6B7280))), trailing: const Icon(Icons.edit, color: Color(0xFF455A64), size: 18), onTap: _editDeviceName),
        ]),
        _section('服务器', [
          ListTile(leading: const Icon(Icons.dns, color: Color(0xFF4FC3F7)), title: const Text('服务器名字', style: TextStyle(color: Colors.white)), subtitle: Text(_serverName, style: const TextStyle(color: Color(0xFF6B7280))), trailing: const Icon(Icons.edit, color: Color(0xFF455A64), size: 18), onTap: _editServerName),
          ListTile(leading: const Icon(Icons.info_outline, color: Color(0xFF90A4AE)), title: const Text('Windows 版本', style: TextStyle(color: Colors.white)), subtitle: Text(_serverInfo['windowsVersion']?.toString() ?? '未知', style: const TextStyle(color: Color(0xFF6B7280)))),
          ListTile(leading: const Icon(Icons.tag, color: Color(0xFF90A4AE)), title: const Text('iNAS 版本', style: TextStyle(color: Colors.white)), subtitle: Text('v${_serverInfo['version'] ?? '2.2026.1010'}', style: const TextStyle(color: Color(0xFF6B7280)))),
          ListTile(leading: const Icon(Icons.storage, color: Color(0xFF90A4AE)), title: const Text('磁盘空间', style: TextStyle(color: Colors.white)), subtitle: Text('${_formatBytes(_serverInfo['freeSpace'])} 可用 / ${_formatBytes(_serverInfo['totalSpace'])} 总计', style: const TextStyle(color: Color(0xFF6B7280)))),
        ]),
        _section('服务管理', [
          ListTile(leading: const Icon(Icons.stop_circle_outlined, color: Color(0xFFEF5350)), title: const Text('关闭 iNAS 服务', style: TextStyle(color: Color(0xFFEF5350))), onTap: () => _confirmAction('关闭服务', ApiService().stopService)),
          ListTile(leading: const Icon(Icons.refresh, color: Color(0xFFFFA726)), title: const Text('重启 iNAS 服务', style: TextStyle(color: Color(0xFFFFA726))), onTap: () => _confirmAction('重启服务', ApiService().restartService)),
        ]),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(title, style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(12)), child: Column(children: tiles)),
    ]);
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null) return '未知';
    final b = bytes is num ? bytes : num.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '${b}B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)}KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)}MB';
    return '${(b / 1073741824).toStringAsFixed(1)}GB';
  }

  // ============ 壁纸 ============
  Future<void> _pickLocalWallpaper() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/wallpaper.jpg');
      await File(image.path).copy(dest.path);
      await AppService().setWallpaper(dest.path);
      _showToast('壁纸已设置');
    } catch (e) { _showToast('选择失败: $e'); }
  }

  Future<void> _pickNasWallpaper() async {
    try {
      final data = await ApiService().listFiles('Photos');
      final entries = (data['entries'] as List?) ?? [];
      final photos = entries.map((e) => FileItem.fromJson(e)).where((f) => f.isImage).toList();
      if (!mounted) return;
      if (photos.isEmpty) { _showToast('相册中没有图片'); return; }
      final selected = await showModalBottomSheet<FileItem>(
        context: context,
        backgroundColor: const Color(0xFF1E1E2E),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false, initialChildSize: 0.6, maxChildSize: 0.9,
          builder: (ctx, scrollCtrl) => GridView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
            itemCount: photos.length,
            itemBuilder: (ctx, i) {
              final photo = photos[i];
              final url = '${ApiService().baseUrl}/api/download?path=${Uri.encodeComponent(photo.path)}';
              return GestureDetector(
                onTap: () => Navigator.pop(ctx, photo),
                child: Image.network(url, headers: {'x-nas-token': ApiService().token ?? ''}, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF12121A), child: const Icon(Icons.image, color: Color(0xFF455A64)))),
              );
            },
          ),
        ),
      );
      if (selected != null) {
        final dir = await getApplicationDocumentsDirectory();
        final dest = File('${dir.path}/wallpaper.jpg');
        await ApiService().downloadFile(selected.path, dest.path);
        await AppService().setWallpaper(dest.path);
        _showToast('壁纸已设置');
      }
    } catch (e) { _showToast('选择失败: $e'); }
  }

  Future<void> _resetWallpaper() async {
    await AppService().setWallpaper('');
    _showToast('已恢复默认壁纸');
  }

  // ============ 设备管理 ============
  void _showDevices() {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E2E), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(expand: false, initialChildSize: 0.6, maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Column(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('已绑定设备', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
          Expanded(child: _devices.isEmpty ? const Center(child: Text('暂无设备', style: TextStyle(color: Color(0xFF6B7280))))
            : ListView.builder(controller: scrollCtrl, itemCount: _devices.length, itemBuilder: (ctx, i) {
                final d = _devices[i];
                return ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFF4FC3F7), child: Icon(Icons.phone_iphone, color: Colors.white, size: 18)),
                  title: Text(d['name']?.toString() ?? '未知', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(d['connectedAt']?.toString() ?? '', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)), onPressed: () async {
                    await ApiService().deleteDevice(d['id']?.toString() ?? d['name']?.toString() ?? '');
                    Navigator.pop(ctx); _loadData();
                  }));
              })),
        ])));
  }

  // ============ 添加应用 ============
  void _showNapUrlDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E), title: const Text('从 URL 安装 NAP', style: TextStyle(color: Colors.white)),
      content: TextField(controller: _napUrlController, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(hintText: 'https://example.com/app.nap', hintStyle: TextStyle(color: Color(0xFF455A64)),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A3E))), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4FC3F7))))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          final url = _napUrlController.text.trim();
          if (url.isEmpty) return;
          try { await AppService().installFromUrl(url); _showToast('安装成功'); } catch (e) { _showToast('安装失败: ${_extractError(e)}'); }
        }, child: const Text('安装')),
      ],
    ));
  }

  Future<void> _installFromFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['nap', 'zip']);
    if (result == null || result.files.isEmpty) return;
    try {
      await AppService().installFromFile(result.files.first.path!);
      _showToast('安装成功');
    } catch (e) { _showToast('安装失败: ${_extractError(e)}'); }
  }

  // ============ 本机/服务器 ============
  void _editDeviceName() {
    _nameController.text = _deviceName;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E), title: const Text('修改本机名字', style: TextStyle(color: Colors.white)),
      content: TextField(controller: _nameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: '输入名字（不可重复）', hintStyle: TextStyle(color: Color(0xFF455A64)))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final name = _nameController.text.trim();
          if (name.isEmpty) return;
          await AppService().setDeviceName(name);
          setState(() => _deviceName = name);
          Navigator.pop(ctx); _showToast('已保存');
        }, child: const Text('保存'))],
    ));
  }

  void _editServerName() {
    _nameController.text = _serverName;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E), title: const Text('修改服务器名字', style: TextStyle(color: Colors.white)),
      content: TextField(controller: _nameController, style: const TextStyle(color: Colors.white)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final name = _nameController.text.trim();
          if (name.isEmpty) return;
          await ApiService().setServerName(name);
          setState(() => _serverName = name);
          Navigator.pop(ctx); _showToast('已保存');
        }, child: const Text('保存'))],
    ));
  }

  Future<void> _confirmAction(String label, Future<void> Function() action) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E), title: Text('确认$label?', style: const TextStyle(color: Colors.white)),
      content: Text('此操作将$label。', style: const TextStyle(color: Colors.grey)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF5350)), child: Text(label))],
    ));
    if (confirm == true) {
      try { await action(); _showToast('已执行$label'); } catch (e) { _showToast('失败: $e'); }
    }
  }

  void _showToast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  String _extractError(dynamic e) {
    if (e is DioException && e.response?.data != null) {
      final data = e.response!.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
      if (data is Map && data['message'] != null) return data['message'].toString();
    }
    return e.toString();
  }
}
