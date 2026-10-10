import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
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
  String _currentDrive = 'C';
  List<dynamic> _drives = [];
  List<FileItem> _files = [];
  bool _loading = false;
  String? _error;
  String? _clipboardPath;
  String _currentDirName = 'iNas Root';
  bool _isRecycle = false;
  String? _highlightName;

  // 导航历史
  final List<String> _history = [];
  int _historyIndex = -1;

  final TextEditingController _renameController = TextEditingController();
  final TextEditingController _newDirController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ApiService().isConnected) {
        _loadFiles();
        _loadDrives();
      }
    });
  }

  String get _rootPrefix => _rootMode == 1 ? 'windows-root/$_currentDrive' : '';

  String get _displayPath {
    if (_rootMode == 1) {
      if (_currentPath.isEmpty) return '$_currentDrive:\\';
      return _currentPath.replaceFirst('windows-root/$_currentDrive/', '$_currentDrive:\\').replaceAll('/', '\\');
    }
    if (_currentPath.isEmpty) return 'iNas://';
    return 'iNas://${_currentPath.replaceAll("/", "/")}';
  }

  Future<void> _loadDrives() async {
    try {
      final drives = await ApiService().getDrives();
      if (mounted) setState(() => _drives = drives);
    } catch (_) {}
  }

  Future<void> _loadFiles() async {
    if (!ApiService().isConnected) return;
    setState(() { _loading = true; _error = null; _highlightName = null; });
    try {
      final path = _currentPath.isEmpty ? _rootPrefix : _currentPath;
      final data = await ApiService().listFiles(path);
      final entries = (data['entries'] as List?) ?? [];
      setState(() {
        _files = entries.map((e) => FileItem.fromJson(e)).toList();
        _currentDirName = data['name'] ?? (_rootMode == 1 ? 'Windows ($_currentDrive:)' : 'iNas Root');
        _isRecycle = data['isRecycle'] == true;
        _loading = false;
      });
      _addressController.text = _displayPath;
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _navigateTo(String newPath, {bool addHistory = true}) {
    if (addHistory) {
      // 清除当前位置之后的历史
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(_currentPath);
      _historyIndex = _history.length - 1;
    }
    setState(() => _currentPath = newPath);
    _loadFiles();
  }

  void _goBack() {
    if (_historyIndex >= 0) {
      final path = _history[_historyIndex];
      _historyIndex--;
      setState(() => _currentPath = path);
      _loadFiles();
    } else if (_currentPath.isNotEmpty) {
      final parts = _currentPath.split('/');
      parts.removeLast();
      _navigateTo(parts.join('/'));
    }
  }

  void _goForward() {
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      setState(() => _currentPath = _history[_historyIndex]);
      _loadFiles();
    }
  }

  bool get _canGoBack => _historyIndex >= 0 || _currentPath.isNotEmpty;
  bool get _canGoForward => _historyIndex < _history.length - 1;

  void _switchRoot(int mode) {
    if (_rootMode == mode) return;
    setState(() {
      _rootMode = mode;
      _currentPath = '';
      _files = [];
      _history.clear();
      _historyIndex = -1;
    });
    _loadFiles();
  }

  void _switchDrive(String letter) {
    if (_currentDrive == letter) return;
    setState(() {
      _currentDrive = letter;
      _currentPath = '';
      _files = [];
      _history.clear();
      _historyIndex = -1;
    });
    _loadFiles();
  }

  Future<void> _onFileTap(FileItem file) async {
    if (file.isDirectory) {
      _navigateTo(file.path);
    } else {
      _openFile(file);
    }
  }

  Future<void> _openFile(FileItem file) async {
    if (file.isImage || file.isVideo || file.isHtml) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileItem: file)));
    } else if (file.isText) {
      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => TextEditorPage(filePath: file.path, fileName: file.name)));
      if (result == true) _loadFiles();
    } else {
      _showDownloadConfirm(file);
    }
  }

  void _showDownloadConfirm(FileItem file) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: Text('下载 ${file.name}?', style: const TextStyle(color: Colors.white)),
      content: Text('文件大小: ${file.formattedSize}', style: const TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () { Navigator.pop(ctx); _downloadFile(file); },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)),
          child: const Text('下载', style: TextStyle(color: Color(0xFF1C1C1E)))),
      ],
    ));
  }

  Future<void> _downloadFile(FileItem file) async {
    await DownloadManager().startDownload(file.path, file.name);
    if (mounted) _showToast('已添加下载: ${file.name}');
  }

  // ============ 文件长按菜单 ============
  void _showFileMenu(FileItem file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(16), child: Row(children: [
          Icon(_getFileIcon(file), color: _getFileColor(file), size: 32),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(file.showName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${file.formattedSize} ${file.isDirectory ? "文件夹" : ""}${file.protected ? " · 受保护" : ""}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ])),
        ])),
        const Divider(color: Color(0xFF38383A)),
        // 废纸篓中的文件：显示恢复，不显示删除
        if (_isRecycle)
          _buildMenuItem(Icons.restore, '恢复到原位置', () { Navigator.pop(ctx); _restoreFile(file); }, color: const Color(0xFF34C759)),
        if (!_isRecycle && !file.isDirectory)
          _buildMenuItem(Icons.download, '下载到本机', () { Navigator.pop(ctx); _downloadFile(file); }),
        if (!_isRecycle && file.isTorrent)
          _buildMenuItem(Icons.download_for_offline, 'BT 下载', () { Navigator.pop(ctx); _startBTDownload(file); }, color: const Color(0xFF34C759)),
        if (!_isRecycle && !file.isDirectory && (file.isText || file.isImage || file.isVideo || file.isHtml))
          _buildMenuItem(Icons.visibility, '预览/打开', () { Navigator.pop(ctx); _openFile(file); }),
        // 文件夹：启用 HTTP 服务
        if (!_isRecycle && file.isDirectory && !file.protected)
          _buildMenuItem(Icons.wifi_tethering, '启用 HTTP 服务', () { Navigator.pop(ctx); _startHttpServer(file); }),
        // 文件：启用下载链接
        if (!_isRecycle && !file.isDirectory)
          _buildMenuItem(Icons.link, '启用下载链接', () { Navigator.pop(ctx); _createDownloadLink(file); }),
        // 压缩包：解压
        if (!_isRecycle && !file.isDirectory && _isArchive(file.name))
          _buildMenuItem(Icons.unarchive, '解压', () { Navigator.pop(ctx); _showExtractDialog(file); }, color: const Color(0xFF007AFF)),
        if (!_isRecycle)
          _buildMenuItem(Icons.content_copy, '复制', () { _clipboardPath = file.path; Navigator.pop(ctx); _showToast('已复制: ${file.name}'); }),
        // 受保护目录不显示重命名和删除
        if (!_isRecycle && !file.protected)
          _buildMenuItem(Icons.drive_file_rename_outline, '重命名', () { Navigator.pop(ctx); _showRenameDialog(file); }),
        if (!_isRecycle && !file.protected)
          _buildMenuItem(Icons.delete_outline, '删除（移入废纸篓）', () { Navigator.pop(ctx); _deleteFile(file); }, color: const Color(0xFFFF3B30)),
        const SizedBox(height: 8),
      ])),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF007AFF)),
      title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 15)),
      onTap: onTap,
    );
  }

  IconData _getFileIcon(FileItem file) {
    if (file.isDirectory) {
      return FileIconHelper.getSpecialIcon(file.specialType);
    }
    return FileIconHelper.getIcon(file.name);
  }

  Color _getFileColor(FileItem file) {
    if (file.isDirectory) {
      return FileIconHelper.getSpecialColor(file.specialType);
    }
    return FileIconHelper.getColor(file.name);
  }

  // ============ 废纸篓恢复 ============
  Future<void> _restoreFile(FileItem file) async {
    try {
      await ApiService().restoreFromRecycle(file.path);
      _showToast('已恢复: ${file.name}');
      _loadFiles();
    } catch (e) { _showToast('恢复失败: $e'); }
  }

  // ============ 清空废纸篓 ============
  Future<void> _emptyRecycle() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: const Text('清空废纸篓?', style: TextStyle(color: Colors.white)),
      content: const Text('废纸篓中的所有文件将被永久删除，无法恢复。', style: TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
          child: const Text('清空')),
      ],
    ));
    if (confirm == true) {
      try {
        await ApiService().emptyRecycle();
        _showToast('废纸篓已清空');
        _loadFiles();
      } catch (e) { _showToast('清空失败: $e'); }
    }
  }

  // ============ HTTP 服务 ============
  Future<void> _startHttpServer(FileItem file) async {
    try {
      final result = await ApiService().startHttpServer(file.path);
      final url = result['url'] ?? '';
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('HTTP 服务已启动', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('访问地址:', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          SelectableText(url, style: const TextStyle(color: Color(0xFF007AFF), fontSize: 14)),
          const SizedBox(height: 8),
          const Text('同一 WiFi 下的设备可通过浏览器访问此地址下载文件。可在队列中终止服务。', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ElevatedButton.icon(onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            _showToast('链接已复制');
          }, icon: const Icon(Icons.copy, size: 18), label: const Text('复制链接'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), foregroundColor: const Color(0xFF1C1C1E))),
        ],
      ));
    } catch (e) { _showToast('启动失败: $e'); }
  }

  // ============ 下载链接 ============
  Future<void> _createDownloadLink(FileItem file) async {
    try {
      final result = await ApiService().createDownloadLink(file.path);
      final url = result['url'] ?? '';
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('下载链接已生成', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('直链地址（24小时有效）:', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          SelectableText(url, style: const TextStyle(color: Color(0xFF007AFF), fontSize: 13)),
          const SizedBox(height: 8),
          const Text('任何人访问此链接即可下载该文件。可在队列中使链接失效。', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ElevatedButton.icon(onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            _showToast('链接已复制');
          }, icon: const Icon(Icons.copy, size: 18), label: const Text('复制链接'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), foregroundColor: const Color(0xFF1C1C1E))),
        ],
      ));
    } catch (e) { _showToast('生成失败: $e'); }
  }

  // ============ BT 下载 ============
  Future<void> _startBTDownload(FileItem file) async {
    try {
      final result = await ApiService().btDownload(file.path);
      _showToast('BT 下载已加入队列: ${result['taskId']}');
    } catch (e) { _showToast('BT 下载失败: $e'); }
  }

  bool _isArchive(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z');
  }

  Future<void> _showExtractDialog(FileItem file) async {
    final passwordController = TextEditingController();
    // 先尝试无密码解压
    try {
      final result = await ApiService().extractArchive(file.path);
      _showToast('解压已加入队列: ${result['destFolder']}');
      return;
    } catch (e) {
      // 如果需要密码，弹出密码输入框
      final errMsg = e.toString();
      if (!errMsg.contains('密码') && !errMsg.contains('password')) {
        _showToast('解压失败: $e');
        return;
      }
    }
    // 弹出密码对话框
    if (!mounted) return;
    final pwd = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: Text('解压 ${file.name}', style: const TextStyle(color: Colors.white)),
      content: TextField(controller: passwordController, obscureText: true, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: '压缩包密码', labelStyle: TextStyle(color: Color(0xFF8E8E93)),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF38383A))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF007AFF))))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, passwordController.text), child: const Text('解压')),
      ],
    ));
    if (pwd == null) return;
    try {
      final result = await ApiService().extractArchive(file.path, password: pwd);
      _showToast('解压已加入队列: ${result['destFolder']}');
    } catch (e) { _showToast('解压失败: $e'); }
  }

  // ============ 重命名/删除 ============
  Future<void> _showRenameDialog(FileItem file) async {
    _renameController.text = file.name;
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: const Text('重命名', style: TextStyle(color: Colors.white)),
      content: TextField(controller: _renameController, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1C1C1E),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF38383A))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF007AFF)))), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final newName = _renameController.text.trim();
          if (newName.isNotEmpty) {
            try { await ApiService().renameFile(file.path, newName); _loadFiles(); } catch (e) { _showToast('重命名失败: $e'); }
          }
          Navigator.pop(ctx);
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)),
          child: const Text('确定', style: TextStyle(color: Color(0xFF1C1C1E)))),
      ],
    ));
  }

  Future<void> _deleteFile(FileItem file) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: Text('删除 ${file.name}?', style: const TextStyle(color: Colors.white)),
      content: const Text('文件将移入废纸篓，可恢复。', style: TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)), child: const Text('删除')),
      ],
    ));
    if (confirm == true) {
      try { await ApiService().deleteFile(file.path); _loadFiles(); _showToast('已删除'); } catch (e) { _showToast('删除失败: $e'); }
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

  // ============ ➕ 菜单 ============
  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        _buildMenuItem(Icons.create_new_folder, '新建文件夹', () { Navigator.pop(ctx); _showNewDirDialog(); }),
        _buildMenuItem(Icons.note_add, '新建文件', () { Navigator.pop(ctx); _showNewFileDialog(); }),
        _buildMenuItem(Icons.upload_file, '从本地上传', () { Navigator.pop(ctx); _uploadFromLocal(); }),
        _buildMenuItem(Icons.link, '从 URL 上传', () { Navigator.pop(ctx); _showUrlUploadDialog(); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  Future<void> _uploadFromLocal() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) { _showToast('无法获取文件路径'); return; }
      final dest = _currentPath.isEmpty ? _rootPrefix : _currentPath;
      _showToast('正在上传: ${file.name}...');
      await ApiService().uploadFile(file.path!, dest);
      _showToast('上传完成: ${file.name}');
      _loadFiles();
    } catch (e) { _showToast('上传失败: $e'); }
  }

  Future<void> _showUrlUploadDialog() async {
    _urlController.clear();
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: const Text('从 URL 上传', style: TextStyle(color: Colors.white)),
      content: TextField(controller: _urlController, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(hintText: 'https://example.com/file.zip',
          hintStyle: TextStyle(color: Color(0xFF636366)),
          filled: true, fillColor: Color(0xFF1C1C1E),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF38383A))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF007AFF)))),
        autofocus: true, keyboardType: TextInputType.url),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final url = _urlController.text.trim();
          if (url.isEmpty) return;
          Navigator.pop(ctx);
          final dest = _currentPath.isEmpty ? _rootPrefix : _currentPath;
          try {
            await ApiService().uploadFromUrl(url, dest);
            _showToast('URL 下载任务已开始');
          } catch (e) { _showToast('失败: $e'); }
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)),
          child: const Text('下载', style: TextStyle(color: Color(0xFF1C1C1E)))),
      ],
    ));
  }

  Future<void> _showNewDirDialog() async {
    _newDirController.clear();
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: const Text('新建文件夹', style: TextStyle(color: Colors.white)),
      content: TextField(controller: _newDirController, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1C1C1E),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF38383A))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF007AFF)))), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final name = _newDirController.text.trim();
          if (name.isNotEmpty) {
            try {
              final dest = _currentPath.isEmpty ? _rootPrefix : _currentPath;
              await ApiService().createDir(dest, name);
              _loadFiles();
            } catch (e) { _showToast('创建失败: $e'); }
          }
          Navigator.pop(ctx);
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)),
          child: const Text('创建', style: TextStyle(color: Color(0xFF1C1C1E)))),
      ],
    ));
  }

  Future<void> _showNewFileDialog() async {
    final controller = TextEditingController();
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: const Text('新建文件', style: TextStyle(color: Colors.white)),
      content: TextField(controller: controller, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1C1C1E), hintText: '如: 新建文本文档.txt', hintStyle: TextStyle(color: Color(0xFF636366)),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF38383A))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF007AFF)))), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final filename = controller.text.trim();
          if (filename.isNotEmpty) {
            try {
              final dest = _currentPath.isEmpty ? _rootPrefix : _currentPath;
              await ApiService().createFile(dest, filename);
              _loadFiles();
            } catch (e) { _showToast('创建失败: $e'); }
          }
          Navigator.pop(ctx);
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)),
          child: const Text('创建', style: TextStyle(color: Color(0xFF1C1C1E)))),
      ],
    ));
  }

  // ============ 地址栏跳转 ============
  void _submitAddress() {
    final input = _addressController.text.trim();
    if (input.isEmpty) return;
    // Windows 路径: C:\Users\...
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(input)) {
      final drive = input[0].toUpperCase();
      final rest = input.substring(3).replaceAll('\\', '/');
      if (_rootMode != 1 || _currentDrive != drive) {
        setState(() { _rootMode = 1; _currentDrive = drive; _currentPath = ''; _history.clear(); _historyIndex = -1; });
      }
      final newPath = rest.isEmpty ? '' : 'windows-root/$drive/$rest';
      _navigateTo(newPath);
      return;
    }
    // iNas 路径: iNas://folder/
    if (input.toLowerCase().startsWith('inas://')) {
      final rest = input.substring(7);
      if (_rootMode != 0) {
        setState(() { _rootMode = 0; _currentPath = ''; _history.clear(); _historyIndex = -1; });
      }
      _navigateTo(rest.isEmpty ? '' : rest);
      return;
    }
    _showToast('路径格式不正确');
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!ApiService().isConnected) return _buildNotConnected();
    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          if (_clipboardPath != null) IconButton(icon: const Icon(Icons.paste), onPressed: _pasteHere, tooltip: '粘贴'),
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddMenu, tooltip: '新建/上传'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles, tooltip: '刷新'),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => showDialog(context: context, builder: (_) => ConnectionDialog(onConnected: () { _loadFiles(); _loadDrives(); })), tooltip: '连接设置'),
        ],
      ),
      body: Column(children: [
        // 双根目录切换
        Container(margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(child: _buildRootTab('iNas Root', Icons.storage, 0)),
            Expanded(child: _buildRootTab('Windows', Icons.desktop_windows, 1)),
          ])),
        // Windows 模式：盘符标签栏
        if (_rootMode == 1 && _drives.isNotEmpty)
          Container(height: 40, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListView.builder(scrollDirection: Axis.horizontal,
              itemCount: _drives.length,
              itemBuilder: (ctx, i) {
                final d = _drives[i];
                final letter = d['letter'] ?? d['name']?.toString().replaceAll(':', '') ?? 'C';
                final selected = _currentDrive == letter;
                return GestureDetector(onTap: () => _switchDrive(letter),
                  child: Container(margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: selected ? const Color(0xFF007AFF) : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(8), border: Border.all(color: selected ? const Color(0xFF007AFF) : const Color(0xFF38383A))),
                    child: Text('$letter:', style: TextStyle(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93), fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13))));
              })),
        // 地址栏
        Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            IconButton(icon: Icon(Icons.arrow_back, size: 20, color: _canGoBack ? const Color(0xFF007AFF) : const Color(0xFF636366)),
              onPressed: _canGoBack ? _goBack : null, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
            IconButton(icon: Icon(Icons.arrow_forward, size: 20, color: _canGoForward ? const Color(0xFF007AFF) : const Color(0xFF636366)),
              onPressed: _canGoForward ? _goForward : null, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
            Expanded(child: TextField(controller: _addressController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(filled: true, fillColor: const Color(0xFF1C1C1E),
                isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF38383A))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF007AFF))),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF007AFF)), onPressed: _submitAddress, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32))),
              onSubmitted: (_) => _submitAddress())),
          ])),
        // 废纸篓：清空按钮
        if (_isRecycle)
          Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              const Icon(Icons.delete_sweep, color: Color(0xFFFF9500), size: 18),
              const SizedBox(width: 8),
              const Text('废纸篓', style: TextStyle(color: Color(0xFFFF9500), fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              TextButton.icon(onPressed: _emptyRecycle, icon: const Icon(Icons.delete_forever, size: 16), label: const Text('清空废纸篓'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF3B30))),
            ])),
        Expanded(child: _buildFileList()),
      ]),
    );
  }

  Widget _buildRootTab(String label, IconData icon, int index) {
    final selected = _rootMode == index;
    return GestureDetector(onTap: () => _switchRoot(index),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: selected ? const Color(0xFF007AFF) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: selected ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93), fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
        ])));
  }

  Widget _buildFileList() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)));
    if (_error != null) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 48),
      const SizedBox(height: 12), const Text('加载失败', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 16), ElevatedButton(onPressed: _loadFiles, child: const Text('重试')),
    ]));
    if (_files.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(_isRecycle ? Icons.delete_sweep : Icons.folder_open, color: const Color(0xFF636366), size: 64),
      const SizedBox(height: 12),
      Text(_isRecycle ? '废纸篓为空' : '此目录为空', style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15)),
    ]));
    return ListView.builder(controller: _listScrollController,
      itemCount: _files.length,
      itemBuilder: (ctx, i) {
        final file = _files[i];
        final isHighlight = _highlightName == file.name;
        return _buildFileTile(file, isHighlight);
      });
  }

  Widget _buildFileTile(FileItem file, bool highlight) {
    return Container(
      decoration: BoxDecoration(color: highlight ? const Color(0xFF1E3A5F) : Colors.transparent),
      child: ListTile(
        leading: Icon(_getFileIcon(file), color: _getFileColor(file), size: 28),
        title: Text(file.showName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(file.isDirectory ? '文件夹${file.protected ? " · 受保护" : ""}' : file.formattedSize,
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
        trailing: file.protected ? const Icon(Icons.lock, color: Color(0xFFFF9500), size: 16) : null,
        onTap: () => _onFileTap(file),
        onLongPress: () => _showFileMenu(file),
      ),
    );
  }

  Widget _buildNotConnected() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.cloud_off, color: Color(0xFF636366), size: 72),
      const SizedBox(height: 16),
      const Text('未连接 iNas 服务端', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
      const SizedBox(height: 8),
      const Text('请确保 Windows 端已运行且在同一 WiFi', style: TextStyle(color: Color(0xFF636366), fontSize: 13)),
      const SizedBox(height: 24),
      ElevatedButton.icon(onPressed: () => showDialog(context: context, builder: (_) => ConnectionDialog(onConnected: () { _loadFiles(); _loadDrives(); })),
        icon: const Icon(Icons.link), label: const Text('连接设备'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), foregroundColor: const Color(0xFF1C1C1E), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
    ]));
  }
}
