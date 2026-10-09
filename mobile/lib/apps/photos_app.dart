import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/file_item.dart';
import '../services/api_service.dart';

class PhotosApp extends StatefulWidget {
  const PhotosApp({super.key});
  @override
  State<PhotosApp> createState() => _PhotosAppState();
}

class _PhotosAppState extends State<PhotosApp> {
  List<FileItem> _photos = [];
  List<dynamic> _recentlyDeleted = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadPhotos(), _loadRecentlyDeleted()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPhotos() async {
    try {
      final data = await ApiService().listFiles('Photos');
      final entries = (data['entries'] as List?) ?? [];
      if (mounted) setState(() {
        _photos = entries.map((e) => FileItem.fromJson(e)).where((f) => f.isImage || f.isVideo).toList()
          ..sort((a, b) => b.name.compareTo(a.name));
      });
    } catch (_) {}
  }

  Future<void> _loadRecentlyDeleted() async {
    try {
      final list = await ApiService().getRecentlyDeleted();
      if (mounted) setState(() => _recentlyDeleted = list);
    } catch (_) {}
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: true);
      if (result == null || result.files.isEmpty) return;
      setState(() => _uploading = true);
      int success = 0;
      for (final f in result.files) {
        if (f.path == null) continue;
        try {
          await ApiService().uploadFile(f.path!, 'Photos');
          success++;
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已上传 $success/${result.files.length} 个文件'), backgroundColor: const Color(0xFF66BB6A)));
        await _loadPhotos();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择失败: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('相册'),
        automaticallyImplyLeading: false,
        actions: [
          if (_uploading) const Padding(padding: EdgeInsets.only(right: 16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7))))),
          IconButton(icon: const Icon(Icons.add), onPressed: _pickAndUpload, tooltip: '添加照片/视频'),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
        : _photos.isEmpty && _recentlyDeleted.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.photo_library, color: Color(0xFF455A64), size: 64),
              SizedBox(height: 12),
              Text('暂无照片', style: TextStyle(color: Color(0xFF6B7280))),
            ]))
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
              itemCount: _photos.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) return _buildRecentlyDeletedTile();
                final photo = _photos[i - 1];
                return _buildPhotoTile(photo);
              },
            ),
    );
  }

  Widget _buildRecentlyDeletedTile() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecentlyDeletedPage())).then((_) => _loadAll()),
      child: Container(
        color: const Color(0xFF1A1A1A),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.delete_outline, color: Color(0xFF90A4AE), size: 32),
          const SizedBox(height: 4),
          Text('最近删除 (${_recentlyDeleted.length})', style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 10), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _buildPhotoTile(FileItem photo) {
    final url = '${ApiService().baseUrl}/api/download?path=${Uri.encodeComponent(photo.path)}';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoPreviewPage(photos: _photos, initialIndex: _photos.indexOf(photo), onChanged: () => _loadAll()))),
      child: Stack(children: [
        Positioned.fill(child: photo.isImage
          ? Image.network(url, headers: {'x-nas-token': ApiService().token ?? ''}, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E1E2E), child: const Icon(Icons.image, color: Color(0xFF455A64))))
          : Container(color: const Color(0xFF1E1E2E), child: const Icon(Icons.play_circle_filled, color: Colors.white, size: 40))),
      ]),
    );
  }
}

// ============ 预览页面（左右滑动） ============
class PhotoPreviewPage extends StatefulWidget {
  final List<FileItem> photos;
  final int initialIndex;
  final VoidCallback onChanged;
  const PhotoPreviewPage({super.key, required this.photos, required this.initialIndex, required this.onChanged});

  @override
  State<PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<PhotoPreviewPage> {
  late PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveToSystemAlbum() async {
    final photo = widget.photos[_currentIndex];
    try {
      final dir = await getTemporaryDirectory();
      final tmpFile = File('${dir.path}/${photo.name}');
      await ApiService().downloadFile(photo.path, tmpFile.path);
      await Share.shareXFiles([XFile(tmpFile.path)], text: photo.name);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已调起分享，可选择存储图像/视频')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _deleteToRecentlyDeleted() async {
    final photo = widget.photos[_currentIndex];
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text('删除?', style: TextStyle(color: Colors.white)),
      content: Text('${photo.name} 将移到最近删除，30天后自动清除。', style: const TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF5350)), child: const Text('删除')),
      ],
    ));
    if (confirm != true) return;
    try {
      await ApiService().softDeletePhotos([photo.name]);
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移到最近删除'), backgroundColor: Color(0xFF66BB6A)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.photos[_currentIndex].name, style: const TextStyle(fontSize: 14)), automaticallyImplyLeading: true),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (ctx, i) {
          final photo = widget.photos[i];
          final url = '${ApiService().baseUrl}/api/download?path=${Uri.encodeComponent(photo.path)}';
          return Center(child: photo.isImage
            ? Image.network(url, headers: {'x-nas-token': ApiService().token ?? ''}, fit: BoxFit.contain)
            : Container(width: double.infinity, color: Colors.black, child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.play_circle_filled, color: Colors.white, size: 64), SizedBox(height: 8), Text('视频文件', style: TextStyle(color: Colors.grey))])));
        },
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          IconButton(icon: const Icon(Icons.save_alt, color: Color(0xFF4FC3F7)), onPressed: _saveToSystemAlbum, tooltip: '保存到系统相册'),
          IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)), onPressed: _deleteToRecentlyDeleted, tooltip: '删除'),
        ]),
      ),
    );
  }
}

// ============ 最近删除页面 ============
class RecentlyDeletedPage extends StatefulWidget {
  const RecentlyDeletedPage({super.key});
  @override
  State<RecentlyDeletedPage> createState() => _RecentlyDeletedPageState();
}

class _RecentlyDeletedPageState extends State<RecentlyDeletedPage> {
  List<dynamic> _items = [];
  bool _loading = true;
  final Set<String> _selected = {};
  bool _selectMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiService().getRecentlyDeleted();
      if (mounted) setState(() { _items = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _daysAgo(int ts) {
    final days = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)).inDays;
    return '${days}Day';
  }

  Future<void> _recoverSelected() async {
    if (_selected.isEmpty) return;
    try {
      await ApiService().recoverPhotos(_selected.toList());
      _selected.clear();
      _selectMode = false;
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢复'), backgroundColor: Color(0xFF66BB6A)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败: $e')));
    }
  }

  Future<void> _purgeSelected() async {
    if (_selected.isEmpty) return;
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text('彻底删除?', style: TextStyle(color: Colors.white)),
      content: Text('将永久删除 ${_selected.length} 个文件，无法恢复。', style: const TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF5350)), child: const Text('删除')),
      ],
    ));
    if (confirm != true) return;
    try {
      await ApiService().purgePhotos(_selected.toList());
      _selected.clear();
      _selectMode = false;
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已彻底删除'), backgroundColor: Color(0xFFEF5350)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_selectMode ? '已选 ${_selected.length} 项' : '最近删除'),
        automaticallyImplyLeading: true,
        actions: [
          if (_selectMode) TextButton(onPressed: () { setState(() { _selected.clear(); _selectMode = false; }); }, child: const Text('取消', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
        : _items.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.delete_sweep, color: Color(0xFF455A64), size: 64),
              SizedBox(height: 12),
              Text('最近删除为空', style: TextStyle(color: Color(0xFF6B7280))),
              SizedBox(height: 4),
              Text('删除的照片将在这里保留30天', style: TextStyle(color: Color(0xFF455A64), fontSize: 12)),
            ]))
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
              itemCount: _items.length,
              itemBuilder: (ctx, i) {
                final item = _items[i];
                final name = item['name']?.toString() ?? '';
                final deletedAt = item['deletedAt'] as int? ?? 0;
                final isImage = name.toLowerCase().endsWith('.jpg') || name.toLowerCase().endsWith('.jpeg') || name.toLowerCase().endsWith('.png') || name.toLowerCase().endsWith('.gif') || name.toLowerCase().endsWith('.webp');
                final url = '${ApiService().baseUrl}/api/download?path=${Uri.encodeComponent('Photos/最近删除/$name')}';
                final isSel = _selected.contains(name);
                return GestureDetector(
                  onLongPress: () => setState(() { _selectMode = true; _selected.add(name); }),
                  onTap: () {
                    if (_selectMode) {
                      setState(() { isSel ? _selected.remove(name) : _selected.add(name); });
                    }
                  },
                  child: Stack(children: [
                    Positioned.fill(child: isImage
                      ? Image.network(url, headers: {'x-nas-token': ApiService().token ?? ''}, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E1E2E), child: const Icon(Icons.image, color: Color(0xFF455A64))))
                      : Container(color: const Color(0xFF1E1E2E), child: const Icon(Icons.play_circle_filled, color: Colors.white, size: 32))),
                    if (isSel) Positioned.fill(child: Container(color: Colors.blue.withOpacity(0.4), child: const Icon(Icons.check_circle, color: Colors.white, size: 28))),
                    Positioned(top: 4, right: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text(_daysAgo(deletedAt), style: const TextStyle(color: Colors.white, fontSize: 9)))),
                  ]),
                );
              },
            ),
      bottomNavigationBar: _selectMode ? BottomAppBar(
        color: const Color(0xFF1A1A1A),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          TextButton.icon(onPressed: _recoverSelected, icon: const Icon(Icons.restore, color: Color(0xFF66BB6A)), label: const Text('恢复', style: TextStyle(color: Color(0xFF66BB6A)))),
          TextButton.icon(onPressed: _purgeSelected, icon: const Icon(Icons.delete_forever, color: Color(0xFFEF5350)), label: const Text('彻底删除', style: TextStyle(color: Color(0xFFEF5350)))),
        ]),
      ) : null,
    );
  }
}
