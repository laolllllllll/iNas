import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import '../services/download_manager.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    // 定时刷新（下载完成后更新）
  }

  Future<void> _loadFiles() async {
    setState(() { _loading = true; });
    try {
      final files = await DownloadManager().getLocalFiles();
      if (mounted) setState(() { _files = files; });
    } catch (_) {}
    if (mounted) setState(() { _loading = false; });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() : '';
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'].contains(ext)) return Icons.image;
    if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm'].contains(ext)) return Icons.movie;
    if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].contains(ext)) return Icons.music_note;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['doc', 'docx'].contains(ext)) return Icons.description;
    if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return Icons.archive;
    if (['txt', 'md', 'json', 'xml', 'html', 'js', 'py', 'dart', 'go'].contains(ext)) return Icons.code;
    if (['apk', 'ipa', 'deb'].contains(ext)) return Icons.android;
    return Icons.insert_drive_file;
  }

  Color _getFileIconColor(String fileName) {
    final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() : '';
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) return const Color(0xFFFF3B30);
    if (['mp4', 'avi', 'mkv', 'mov'].contains(ext)) return const Color(0xFFAB47BC);
    if (['mp3', 'wav', 'flac'].contains(ext)) return const Color(0xFF34C759);
    if (['pdf', 'doc', 'docx'].contains(ext)) return const Color(0xFF42A5F5);
    if (['zip', 'rar', '7z'].contains(ext)) return const Color(0xFFFF9500);
    return const Color(0xFF007AFF);
  }

  Future<void> _shareFile(File file) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '来自 iNas 的文件: ${file.uri.pathSegments.last}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e'), backgroundColor: const Color(0xFFFF3B30)),
        );
      }
    }
  }

  Future<void> _openFile(File file) async {
    try {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开此文件类型: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteFile(File file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: Text('删除 ${file.uri.pathSegments.last}?', style: const TextStyle(color: Colors.white)),
        content: const Text('此文件将从本机永久删除', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DownloadManager().deleteLocalFile(file.path);
      _loadFiles();
    }
  }

  void _showFileOptions(File file) {
    final fileName = file.uri.pathSegments.last;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: _getFileIconColor(fileName).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: Icon(_getFileIcon(fileName), color: _getFileIconColor(fileName), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fileName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${_formatBytes(file.lengthSync())} · ${_formatDate(file.lastModifiedSync())}', style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF38383A)),
            ListTile(
              leading: const Icon(Icons.open_in_new, color: Color(0xFF007AFF)),
              title: const Text('用其他应用打开', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _openFile(file); },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share, color: Color(0xFF34C759)),
              title: const Text('分享', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _shareFile(file); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
              title: const Text('删除', style: TextStyle(color: Color(0xFFFF3B30))),
              onTap: () { Navigator.pop(ctx); _deleteFile(file); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('此终端', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('${_files.length} 个文件', style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFiles,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)))
          : _files.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadFiles,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _files.length,
                    itemBuilder: (ctx, i) {
                      final file = _files[i];
                      final fileName = file.uri.pathSegments.last;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: _getFileIconColor(fileName).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_getFileIcon(fileName), color: _getFileIconColor(fileName), size: 22),
                          ),
                          title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${_formatBytes(file.lengthSync())} · ${_formatDate(file.lastModifiedSync())}', style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.ios_share, color: Color(0xFF34C759), size: 22),
                                onPressed: () => _shareFile(file),
                                tooltip: '分享',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right, color: Color(0xFF636366), size: 20),
                            ],
                          ),
                          onTap: () => _openFile(file),
                          onLongPress: () => _showFileOptions(file),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.phone_iphone, color: Color(0xFF636366), size: 40),
          ),
          const SizedBox(height: 20),
          const Text('本机暂无文件', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('从浏览页下载文件后将显示在这里', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          const SizedBox(height: 12),
          const Text('支持 iOS 系统分享：存到文件 / 分享到其他 App', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
        ],
      ),
    );
  }
}
