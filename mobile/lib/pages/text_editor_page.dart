import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TextEditorPage extends StatefulWidget {
  final String filePath;
  final String fileName;
  const TextEditorPage({super.key, required this.filePath, required this.fileName});

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final result = await ApiService().readText(widget.filePath);
      if (mounted) {
        setState(() {
          _controller.text = result['content'] ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveFile() async {
    setState(() { _saving = true; });
    try {
      await ApiService().writeText(widget.filePath, _controller.text);
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存'), backgroundColor: Color(0xFF81C784), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() { _saving = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: const Color(0xFFEF5350)),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (_dirty) {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('未保存的更改', style: TextStyle(color: Colors.white)),
          content: const Text('文件已修改但未保存，是否保存？', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('不保存')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      );
      if (result == true) {
        await _saveFile();
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF12121A),
        appBar: AppBar(
          title: Text(widget.fileName, style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (_dirty)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Center(child: Text('●', style: TextStyle(color: Color(0xFFFFB74D), fontSize: 10))),
              ),
            IconButton(
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7)))
                  : const Icon(Icons.save),
              onPressed: _saving ? null : _saveFile,
              tooltip: '保存',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
            : _error != null
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFEF5350), size: 48),
                      const SizedBox(height: 12),
                      const Text('加载失败', style: TextStyle(color: Colors.white)),
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ))
                : Container(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _controller,
                      onChanged: (_) => setState(() { _dirty = true; }),
                      style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13, fontFamily: 'monospace', height: 1.5),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
      ),
    );
  }
}
