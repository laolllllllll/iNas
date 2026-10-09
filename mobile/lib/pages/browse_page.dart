import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/file_item.dart';
import '../services/api_service.dart';
import '../services/download_manager.dart';
import '../widgets/connection_dialog.dart';
import 'preview_page.dart';
import 'text_editor_page.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _rootMode = 0; // 0 = iNas Root, 1 = Windows Root
  String _currentPath = '';
  List<FileItem> _files = [];
  bool _loading = false;
  String? _error;
  String? _clipboardPath; // 复制的源路径
  String _currentDirName = 'iNas Root';

  final TextEditingController _renameController = TextEditingController();
  final TextEditingController _newDirController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ApiService().isConnected) {
        _loadFiles();
      }
    });
  }

  String get _rootPrefix => _rootMode == 1 ? 'windows-root' : '';

  Future<void> _loadFiles() async {
    if (!ApiService().isConnected) return;
    setState(() { _loading = true; _error = null; });
    try {
      final path = _currentPath.isEmpty ? _rootPrefix : _currentPath;
      final data = await ApiService().listFiles(path);
      final entries = (data['entries'] as List?) ?? [];
      setState(() {
        _files = entries.map((e) => FileItem.fromJson(e)).toList();
        _currentDirName = data['name'] ?? (_rootMode == 1 ? 'Windows (C:)' : 'iNas Root');
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _switchRoot(int mode) {
    if (_rootMode == mode) return;
    setState(() {
      _rootMode = mode;
      _currentPath = '';
      _files = [];
    });
    _loadFiles();
  }

  Future<void> _onFileTap(FileItem file) async {
    if (file.isDirectory) {
      setState(() {
        _currentPath = file.path;
      });
      _loadFiles();
    } else {
      _openFile(file);
    }
  }

  Future<void> _openFile(FileItem file) async {
    if (file.isImage || file.isVideo || file.isHtml) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => PreviewPage(fileItem: file),
      ));
    } else if (file.isText) {
      final result = await Navigator.push(context, MaterialPageRoute(
        builder: (_) => TextEditorPage(filePath: file.path, fileName: file.name),
      ));
      if (result == true) _loadFiles();
    } else {
      // 其他类型提示下载
      _showDownloadConfirm(file);
    }
  }

  void _showDownloadConfirm(FileItem file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('下载 ${file.name}?', style: const TextStyle(color: Colors.white)),
        content: Text('文件大小: ${file.formattedSize}', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadFile(file);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FC3F7)),
            child: const Text('下载', style: TextStyle(color: Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFile(FileItem file) async {
    final task = await DownloadManager().startDownload(file.path, file.name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加下载: ${file.name}'), backgroundColor: const Color(0xFF4FC3F7)),
      );
    }
  }

  void _showFileMenu(FileItem file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(_getFileIcon(file), color: const Color(0xFF4FC3F7), size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(file.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('${file.formattedSize} ${file.isDirectory ? "文件夹" : ""}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A3E)),
            if (!file.isDirectory) _buildMenuItem(Icons.download, '下载到本机', () => _downloadFile(file)),
            if (!file.isDirectory && (file.isText || file.isImage || file.isVideo || file.isHtml))
              _buildMenuItem(Icons.visibility, '预览/打开', () => _openFile(file)),
            _buildMenuItem(Icons.content_copy, '复制', () { _clipboardPath = file.path; Navigator.pop(ctx); _showToast('已复制: ${file.name}'); }),
            _buildMenuItem(Icons.drive_file_rename_outline, '重命名', () { Navigator.pop(ctx); _showRenameDialog(file); }),
            _buildMenuItem(Icons.delete_outline, '删除（移入回收站）', () { Navigator.pop(ctx); _deleteFile(file); }, color: const Color(0xFFEF5350)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF4FC3F7)),
      title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 15)),
      onTap: onTap,
    );
  }

  IconData _getFileIcon(FileItem file) {
    if (file.isDirectory) return Icons.folder;
    if (file.isImage) return Icons.image;
    if (file.isVideo) return Icons.movie;
    if (file.isHtml) return Icons.language;
    if (file.isText) return Icons.description;
    return Icons.insert_drive_file;
  }

  Future<void> _showRenameDialog(FileItem file) async {
    _renameController.text = file.name;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('重命名', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _renameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            filled: true, fillColor: Color(0xFF12121A),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A3E))),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4FC3F7))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final newName = _renameController.text.trim();
              if (newName.isNotEmpty) {
                try {
                  await ApiService().renameFile(file.path, newName);
                  _loadFiles();
                } catch (e) { _showToast('重命名失败: $e'); }
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FC3F7)),
            child: const Text('确定', style: TextStyle(color: Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(FileItem file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('删除 ${file.name}?', style: const TextStyle(color: Colors.white)),
        content: const Text('文件将移入回收站，可在 Windows 端恢复', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiService().deleteFile(file.path);
        _loadFiles();
        _showToast('已删除');
      } catch (e) { _showToast('删除失败: $e'); }
    }
  }

  Future<void> _pasteHere() async {
    if (_clipboardPath == null) { _showToast('剪贴板为空'); return; }
    try {
      final dest = _currentPath.isEmpty ? _rootPrefix : _currentPath;
      await ApiService().copyFile(_clipboardPath!, dest);
      _showToast('复制任务已开始');
      _loadFiles();
    } catch (e) { _showToast('复制失败: $e'); }
  }

  Future<void> _showNewDirDialog() async {
    _newDirController.clear();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('新建文件夹', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _newDirController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            filled: true, fillColor: Color(0xFF12121A),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A3E))),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4FC3F7))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final name = _newDirController.text.trim();
              if (name.isNotEmpty) {
                try {
                  final dest = _currentPath.isEmpty ? _rootPrefix : _currentPath;
                  await ApiService().createDir(dest, name);
                  _loadFiles();
                } catch (e) { _showToast('创建失败: $e'); }
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FC3F7)),
            child: const Text('创建', style: TextStyle(color: Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<bool> _onWillPop() async {
    if (_currentPath.isNotEmpty) {
      // 返回上一级
      final parts = _currentPath.split('/');
      parts.removeLast();
      setState(() {
        _currentPath = parts.join('/');
      });
      _loadFiles();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!ApiService().isConnected) {
      return _buildNotConnected();
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            children: [
              const Text('浏览', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Text(_currentDirName, style: const TextStyle(fontSize: 11, color: Color(0xFF90A4AE))),
            ],
          ),
          actions: [
            if (_clipboardPath != null)
              IconButton(icon: const Icon(Icons.paste), onPressed: _pasteHere, tooltip: '粘贴'),
            IconButton(icon: const Icon(Icons.create_new_folder), onPressed: _showNewDirDialog, tooltip: '新建文件夹'),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles, tooltip: '刷新'),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => showDialog(context: context, builder: (_) => ConnectionDialog(onConnected: _loadFiles)),
              tooltip: '连接设置',
            ),
          ],
        ),
        body: Column(
          children: [
            // 双根目录切换栏
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildRootTab('iNas Root', Icons.storage, 0),
                  ),
                  Expanded(
                    child: _buildRootTab('Windows (C:)', Icons.desktop_windows, 1),
                  ),
                ],
              ),
            ),
            // 路径面包屑
            if (_currentPath.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () { setState(() { _currentPath = ''; }); _loadFiles(); },
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_back, size: 16, color: Color(0xFF4FC3F7)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _currentPath.replaceAll('windows-root/', 'C:\\').replaceAll('/', ' > '),
                          style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(child: _buildFileList()),
          ],
        ),
      ),
    );
  }

  Widget _buildRootTab(String label, IconData icon, int index) {
    final selected = _rootMode == index;
    return GestureDetector(
      onTap: () => _switchRoot(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4FC3F7) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? const Color(0xFF1A1A2E) : const Color(0xFF90A4AE)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              color: selected ? const Color(0xFF1A1A2E) : const Color(0xFF90A4AE),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)));
    }
    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF5350), size: 48),
          const SizedBox(height: 12),
          Text('加载失败', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadFiles, child: const Text('重试')),
        ],
      ));
    }
    if (_files.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, color: const Color(0xFF455A64), size: 64),
          const SizedBox(height: 16),
          const Text('文件夹为空', style: TextStyle(color: Color(0xFF6B7280), fontSize: 16)),
        ],
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _files.length,
      itemBuilder: (ctx, i) {
        final file = _files[i];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: file.isDirectory ? const Color(0xFFFFB74D).withOpacity(0.15) : const Color(0xFF4FC3F7).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_getFileIcon(file), color: file.isDirectory ? const Color(0xFFFFB74D) : const Color(0xFF4FC3F7), size: 22),
            ),
            title: Text(file.name, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              file.isDirectory ? '文件夹' : file.formattedSize,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
            trailing: file.isDirectory ? const Icon(Icons.chevron_right, color: Color(0xFF455A64)) : null,
            onTap: () => _onFileTap(file),
            onLongPress: () => _showFileMenu(file),
          ),
        );
      },
    );
  }

  Widget _buildNotConnected() {
    return Scaffold(
      appBar: AppBar(title: const Text('浏览')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, color: const Color(0xFF455A64), size: 72),
            const SizedBox(height: 20),
            const Text('未连接 iNas 服务端', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('请先连接同一 WiFi 下的 Windows 电脑', style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => ConnectionDialog(onConnected: _loadFiles)),
              icon: const Icon(Icons.link),
              label: const Text('连接设备'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: const Color(0xFF1A1A2E),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
