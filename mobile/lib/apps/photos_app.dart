import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../services/api_service.dart';

class PhotosApp extends StatefulWidget {
  const PhotosApp({super.key});
  @override
  State<PhotosApp> createState() => _PhotosAppState();
}

class _PhotosAppState extends State<PhotosApp> {
  List<FileItem> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final data = await ApiService().listFiles('Photos');
      final entries = (data['entries'] as List?) ?? [];
      setState(() {
        _photos = entries.map((e) => FileItem.fromJson(e)).where((f) => f.isImage || f.isVideo).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('相册'), automaticallyImplyLeading: false),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
        : _photos.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.photo_library, color: Color(0xFF455A64), size: 64),
              SizedBox(height: 12),
              Text('暂无照片', style: TextStyle(color: Color(0xFF6B7280))),
            ]))
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
              itemCount: _photos.length,
              itemBuilder: (ctx, i) {
                final photo = _photos[i];
                final url = '${ApiService().baseUrl}/api/download?path=${Uri.encodeComponent(photo.path)}';
                return GestureDetector(
                  onLongPress: () => _showPhotoMenu(photo),
                  child: photo.isImage
                    ? Image.network(url, headers: {'x-nas-token': ApiService().token ?? ''}, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E1E2E), child: const Icon(Icons.image, color: Color(0xFF455A64))))
                    : Container(color: const Color(0xFF1E1E2E), child: const Icon(Icons.play_circle_filled, color: Colors.white, size: 40)),
                );
              },
            ),
    );
  }

  void _showPhotoMenu(FileItem photo) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)), title: const Text('删除（移入废纸篓）', style: TextStyle(color: Color(0xFFEF5350))),
          onTap: () async { Navigator.pop(ctx); await ApiService().deleteFile(photo.path); _loadPhotos(); }),
        ListTile(leading: const Icon(Icons.share, color: Color(0xFF4FC3F7)), title: const Text('分享', style: TextStyle(color: Colors.white)),
          onTap: () => Navigator.pop(ctx)),
      ])));
  }
}
