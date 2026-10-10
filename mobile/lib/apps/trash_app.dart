import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../services/api_service.dart';

class TrashApp extends StatefulWidget {
  const TrashApp({super.key});
  @override
  State<TrashApp> createState() => _TrashAppState();
}

class _TrashAppState extends State<TrashApp> {
  List<FileItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    try {
      final data = await ApiService().listFiles('回收站');
      final entries = (data['entries'] as List?) ?? [];
      setState(() {
        _items = entries.map((e) => FileItem.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('废纸篓'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(onPressed: _emptyTrash, icon: const Icon(Icons.delete_forever, size: 18), label: const Text('清空'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF3B30))),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)))
        : _items.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.delete_sweep, color: Color(0xFF636366), size: 64),
              SizedBox(height: 12),
              Text('废纸篓为空', style: TextStyle(color: Color(0xFF8E8E93))),
            ]))
          : ListView.builder(itemCount: _items.length, itemBuilder: (ctx, i) {
              final item = _items[i];
              return ListTile(
                leading: Icon(item.isDirectory ? Icons.folder : Icons.insert_drive_file, color: const Color(0xFFFF9500)),
                title: Text(item.showName, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.formattedSize, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                trailing: TextButton(onPressed: () => _restoreItem(item), child: const Text('恢复', style: TextStyle(color: Color(0xFF34C759)))),
              );
            }),
    );
  }

  Future<void> _restoreItem(FileItem item) async {
    try {
      await ApiService().restoreFromRecycle(item.path);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢复'), backgroundColor: Color(0xFF34C759)));
      _loadTrash();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败: $e')));
    }
  }

  Future<void> _emptyTrash() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: const Text('清空废纸篓?', style: TextStyle(color: Colors.white)),
      content: const Text('所有文件将被永久删除。', style: TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)), child: const Text('清空')),
      ],
    ));
    if (confirm == true) {
      try {
        await ApiService().emptyRecycle();
        _loadTrash();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e')));
      }
    }
  }
}
