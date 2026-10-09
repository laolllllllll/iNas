import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../widgets/connection_dialog.dart';

class CmdPage extends StatefulWidget {
  const CmdPage({super.key});

  @override
  State<CmdPage> createState() => _CmdPageState();
}

class _CmdPageState extends State<CmdPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  final List<CmdOutputLine> _output = [];
  bool _executing = false;
  String? _sessionId;
  bool _useSession = true;

  @override
  void initState() {
    super.initState();
    _addOutput('iNas Remote CMD Terminal', type: CmdLineType.system);
    _addOutput('连接到同一 WiFi 下的 Windows 电脑执行命令', type: CmdLineType.system);
    _addOutput('', type: CmdLineType.empty);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    if (_sessionId != null) {
      ApiService().closeCmdSession(_sessionId!).catchError((_) {});
    }
    super.dispose();
  }

  void _addOutput(String text, {CmdLineType type = CmdLineType.output}) {
    setState(() {
      _output.add(CmdOutputLine(text: text, type: type));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _executeCommand() async {
    if (!ApiService().isConnected) {
      _addOutput('错误: 未连接 iNas 服务端', type: CmdLineType.error);
      return;
    }

    final command = _inputController.text.trim();
    if (command.isEmpty) return;

    _inputController.clear();
    _addOutput('> $command', type: CmdLineType.command);

    // 特殊命令处理
    if (command.toLowerCase() == 'clear' || command.toLowerCase() == 'cls') {
      setState(() { _output.clear(); });
      return;
    }
    if (command.toLowerCase() == 'exit') {
      _addOutput('使用底部导航切换其他页面', type: CmdLineType.system);
      return;
    }

    setState(() { _executing = true; });

    try {
      if (_useSession) {
        await _executeWithSession(command);
      } else {
        await _executeSimple(command);
      }
    } catch (e) {
      _addOutput('执行错误: $e', type: CmdLineType.error);
    } finally {
      setState(() { _executing = false; });
    }
  }

  Future<void> _executeSimple(String command) async {
    final result = await ApiService().executeCmd(command);
    if (result['stdout'] != null && result['stdout'].toString().isNotEmpty) {
      _addOutput(result['stdout'].toString().trimRight(), type: CmdLineType.output);
    }
    if (result['stderr'] != null && result['stderr'].toString().isNotEmpty) {
      _addOutput(result['stderr'].toString().trimRight(), type: CmdLineType.error);
    }
    if (result['exitCode'] != null && result['exitCode'] != 0) {
      _addOutput('[退出码: ${result['exitCode']}]', type: CmdLineType.error);
    }
    _addOutput('', type: CmdLineType.empty);
  }

  Future<void> _executeWithSession(String command) async {
    // 确保会话存在
    if (_sessionId == null) {
      final session = await ApiService().createCmdSession();
      _sessionId = session['sessionId'];
      _addOutput('[交互式会话已创建: $_sessionId]', type: CmdLineType.system);
    }

    await ApiService().writeCmdSession(_sessionId!, command);

    // 轮询读取输出
    await Future.delayed(const Duration(milliseconds: 300));
    int attempts = 0;
    while (attempts < 20) {
      final result = await ApiService().readCmdSession(_sessionId!);
      final output = (result['output'] ?? '').toString();
      if (output.isNotEmpty) {
        // 移除命令回显（cmd 会回显输入的命令）
        var cleaned = output;
        if (cleaned.startsWith(command)) {
          cleaned = cleaned.substring(command.length).trimLeft();
        }
        if (cleaned.isNotEmpty) {
          _addOutput(cleaned.trimRight(), type: CmdLineType.output);
        }
      }
      // 检查是否还有输出（简单等待）
      await Future.delayed(const Duration(milliseconds: 200));
      final check = await ApiService().readCmdSession(_sessionId!);
      if ((check['output'] ?? '').toString().isEmpty) {
        break;
      }
      // 还有输出，继续读
      final more = (check['output'] ?? '').toString();
      if (more.isNotEmpty) _addOutput(more.trimRight(), type: CmdLineType.output);
      attempts++;
    }
    _addOutput('', type: CmdLineType.empty);
  }

  void _showQuickCommands() {
    final commands = [
      {'label': '查看系统信息', 'cmd': 'systeminfo | findstr /B /C:"OS Name" /C:"OS Version" /C:"System Type"'},
      {'label': '查看 IP 配置', 'cmd': 'ipconfig'},
      {'label': '列出当前目录', 'cmd': 'dir'},
      {'label': '查看进程', 'cmd': 'tasklist'},
      {'label': '查看磁盘空间', 'cmd': 'wmic logicaldisk get size,freespace,caption'},
      {'label': 'ping 测试', 'cmd': 'ping -n 4 www.baidu.com'},
      {'label': '查看环境变量', 'cmd': 'set'},
      {'label': '关机（1小时后）', 'cmd': 'shutdown /s /t 3600'},
      {'label': '取消关机', 'cmd': 'shutdown /a'},
      {'label': '清空屏幕', 'cmd': 'cls'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('快捷命令', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(color: Color(0xFF2A2A3E)),
            ...commands.map((c) => ListTile(
              leading: const Icon(Icons.bolt, color: Color(0xFFFFB74D), size: 20),
              title: Text(c['label']!, style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text(c['cmd']!, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(ctx);
                _inputController.text = c['cmd']!;
                _executeCommand();
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!ApiService().isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('管理设备')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.terminal, color: Color(0xFF455A64), size: 72),
              const SizedBox(height: 20),
              const Text('未连接 iNas 服务端', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('连接后可远程执行 Windows CMD 命令', style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14)),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const ConnectionDialog()),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理设备', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_useSession ? Icons.swap_horiz : Icons.swap_horiz_outlined),
            onPressed: () {
              setState(() { _useSession = !_useSession; });
              _addOutput(_useSession ? '[模式: 交互式会话]' : '[模式: 单次执行]', type: CmdLineType.system);
            },
            tooltip: _useSession ? '交互式会话' : '单次执行',
          ),
          IconButton(
            icon: const Icon(Icons.bolt),
            onPressed: _showQuickCommands,
            tooltip: '快捷命令',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => setState(() { _output.clear(); }),
            tooltip: '清空输出',
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF0A0A12),
        child: Column(
          children: [
            // 连接状态条
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1A1A2E),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF81C784), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已连接: ${ApiService().baseUrl}',
                      style: const TextStyle(color: Color(0xFF81C784), fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                  if (_executing) const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7)),
                  ),
                ],
              ),
            ),
            // 终端输出区域
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _output.length,
                itemBuilder: (ctx, i) {
                  final line = _output[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      line.text,
                      style: TextStyle(
                        color: _getLineColor(line.type),
                        fontSize: 13,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  );
                },
              ),
            ),
            // 输入区域
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A2E),
                border: Border(top: BorderSide(color: Color(0xFF2A2A3E))),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    const Text('>', style: TextStyle(color: Color(0xFF81C784), fontSize: 16, fontFamily: 'monospace')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          hintText: _executing ? '命令执行中...' : '输入 CMD 命令...',
                          hintStyle: const TextStyle(color: Color(0xFF455A64), fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF12121A),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF2A2A3E)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF4FC3F7)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        enabled: !_executing,
                        onSubmitted: (_) => _executeCommand(),
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _executing ? null : _executeCommand,
                      icon: const Icon(Icons.send),
                      color: const Color(0xFF4FC3F7),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF4FC3F7).withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getLineColor(CmdLineType type) {
    switch (type) {
      case CmdLineType.command: return const Color(0xFF4FC3F7);
      case CmdLineType.output: return const Color(0xFFE0E0E0);
      case CmdLineType.error: return const Color(0xFFEF5350);
      case CmdLineType.system: return const Color(0xFF81C784);
      case CmdLineType.empty: return Colors.transparent;
    }
  }
}

enum CmdLineType { command, output, error, system, empty }

class CmdOutputLine {
  final String text;
  final CmdLineType type;
  CmdOutputLine({required this.text, required this.type});
}
