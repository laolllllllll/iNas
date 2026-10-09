import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/file_item.dart';
import '../services/api_service.dart';

class FilesApp extends StatefulWidget {
  const FilesApp({super.key});
  @override
  State<FilesApp> createState() => _FilesAppState();
}

class _FilesAppState extends State<FilesApp> {
  int _tab = 0; // 0=下载, 1=音乐
  List<FileItem> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final folder = _tab == 0 ? '下载' : '音乐';
      final data = await ApiService().listFiles(folder);
      final entries = (data['entries'] as List?) ?? [];
      setState(() {
        _files = entries.map((e) => FileItem.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(_tab == 0 ? '下载' : '音乐'),
        automaticallyImplyLeading: false,
        actions: [
          if (_tab == 1)
            IconButton(icon: const Icon(Icons.add), tooltip: '添加音乐',
              onPressed: _addMusic),
        ],
      ),
      body: Column(children: [
        Container(color: const Color(0xFF1A1A2E), child: Row(children: [
          _buildTab('下载', Icons.download, 0),
          _buildTab('音乐', Icons.music_note, 1),
        ])),
        Expanded(child: _buildFileList()),
      ]),
    );
  }

  Widget _buildTab(String label, IconData icon, int index) {
    final selected = _tab == index;
    return Expanded(child: GestureDetector(onTap: () { setState(() => _tab = index); _loadFiles(); },
      child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? const Color(0xFF4FC3F7) : Colors.transparent, width: 2))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: selected ? const Color(0xFF4FC3F7) : const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: selected ? const Color(0xFF4FC3F7) : const Color(0xFF6B7280), fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ]))));
  }

  Widget _buildFileList() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)));
    if (_files.isEmpty) return Center(child: Text(_tab == 0 ? '下载目录为空' : '音乐目录为空', style: const TextStyle(color: Color(0xFF6B7280))));
    return ListView.builder(itemCount: _files.length, itemBuilder: (ctx, i) {
      final file = _files[i];
      return ListTile(
        leading: Icon(file.isDirectory ? Icons.folder : Icons.insert_drive_file, color: const Color(0xFF4FC3F7)),
        title: Text(file.name, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(file.formattedSize, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
        onLongPress: () => _showFileMenu(file),
      );
    });
  }

  void _showFileMenu(FileItem file) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)), title: const Text('删除', style: TextStyle(color: Color(0xFFEF5350))),
          onTap: () async { Navigator.pop(ctx); await ApiService().deleteFile(file.path); _loadFiles(); }),
        ListTile(leading: const Icon(Icons.drive_file_rename_outline, color: Color(0xFF4FC3F7)), title: const Text('重命名', style: TextStyle(color: Colors.white)),
          onPressed: () => Navigator.pop(ctx)),
        ListTile(leading: const Icon(Icons.link, color: Color(0xFF4FC3F7)), title: const Text('开启直链', style: TextStyle(color: Colors.white)),
          onPressed: () async { Navigator.pop(ctx); await ApiService().createDownloadLink(file.path); }),
      ])));
  }

  Future<void> _addMusic() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.audio);
    if (result == null) return;
    for (final f in result.files) {
      if (f.path != null) {
        await ApiService().uploadFile(f.path!, '音乐');
      }
    }
    _loadFiles();
  }
}
