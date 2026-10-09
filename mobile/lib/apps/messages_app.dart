import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/app_service.dart';

class MessagesApp extends StatefulWidget {
  const MessagesApp({super.key});
  @override
  State<MessagesApp> createState() => _MessagesAppState();
}

class _MessagesAppState extends State<MessagesApp> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _messages = [];
  String? _deviceName;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _deviceName = await AppService().getDeviceName();
    _loadMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await ApiService().getMessages();
      if (mounted) {
        setState(() => _messages = msgs);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        });
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final content = _msgController.text.trim();
    if (content.isEmpty || _deviceName == null) return;
    _msgController.clear();
    try {
      await ApiService().sendMessage(_deviceName!, content);
      _loadMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(backgroundColor: const Color(0xFF1A1A2E), title: const Text('信息'), automaticallyImplyLeading: false),
      body: Column(children: [
        Expanded(child: _messages.isEmpty
          ? const Center(child: Text('暂无消息', style: TextStyle(color: Color(0xFF6B7280))))
          : ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(12), itemCount: _messages.length, itemBuilder: (ctx, i) {
              final msg = _messages[i];
              final isMe = msg['deviceName'] == _deviceName;
              return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(
                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe) ...[
                    CircleAvatar(radius: 16, backgroundColor: const Color(0xFF66BB6A), child: Text(msg['deviceName']?.toString().substring(0, 1).toUpperCase() ?? '?', style: const TextStyle(color: Colors.white, fontSize: 12))),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                    if (!isMe) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(msg['deviceName']?.toString() ?? '', style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11))),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: isMe ? const Color(0xFF4FC3F7) : const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(16)),
                      child: Text(msg['content']?.toString() ?? '', style: TextStyle(color: isMe ? const Color(0xFF1A1A2E) : Colors.white, fontSize: 14))),
                  ])),
                  if (isMe) ...[
                    const SizedBox(width: 8),
                    CircleAvatar(radius: 16, backgroundColor: const Color(0xFF4FC3F7), child: Text(_deviceName?.substring(0, 1).toUpperCase() ?? '?', style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 12))),
                  ],
                ],
              ));
            })),
        // 输入框
        Container(padding: const EdgeInsets.all(12), color: const Color(0xFF1A1A2E), child: Row(children: [
          Expanded(child: TextField(controller: _msgController, style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF12121A), hintText: '输入消息...', hintStyle: TextStyle(color: Color(0xFF455A64)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A3E)), borderRadius: BorderRadius.all(Radius.circular(20))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4FC3F7)), borderRadius: BorderRadius.all(Radius.circular(20))), contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            onSubmitted: (_) => _sendMessage())),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.send, color: Color(0xFF4FC3F7)), onPressed: _sendMessage),
        ])),
      ]),
    );
  }
}
