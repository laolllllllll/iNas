import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/download_manager.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Timer? _refreshTimer;
  List<dynamic> _remoteTasks = [];
  bool _loadingRemote = false;

  @override
  void initState() {
    super.initState();
    // 定时刷新队列状态
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() {}); // 触发本地下载任务 UI 更新
        _loadRemoteQueue();
      }
    });
    _loadRemoteQueue();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRemoteQueue() async {
    if (!ApiService().isConnected || _loadingRemote) return;
    setState(() { _loadingRemote = true; });
    try {
      final tasks = await ApiService().getQueue();
      if (mounted) setState(() { _remoteTasks = tasks; });
    } catch (_) {}
    if (mounted) setState(() { _loadingRemote = false; });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed': return const Color(0xFF81C784);
      case 'failed': return const Color(0xFFEF5350);
      case 'cancelled': return const Color(0xFF90A4AE);
      case 'paused': return const Color(0xFFFFB74D);
      case 'downloading':
      case 'running': return const Color(0xFF4FC3F7);
      default: return const Color(0xFF90A4AE);
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'completed': return '已完成';
      case 'failed': return '失败';
      case 'cancelled': return '已取消';
      case 'paused': return '已暂停';
      case 'downloading':
      case 'running': return '进行中';
      case 'pending': return '等待中';
      default: return status;
    }
  }

  IconData _getTaskIcon(String type) {
    switch (type) {
      case 'download': return Icons.download;
      case 'upload': return Icons.upload;
      case 'copy': return Icons.content_copy;
      case 'move': return Icons.drive_file_move;
      default: return Icons.task_alt;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final localTasks = DownloadManager().tasks;
    final hasAnyTasks = localTasks.isNotEmpty || _remoteTasks.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('队列', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () { _loadRemoteQueue(); setState(() {}); },
            tooltip: '刷新',
          ),
          if (localTasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cleaning_services),
              onPressed: () {
                DownloadManager().tasks.removeWhere((t) => t.status == 'completed' || t.status == 'failed' || t.status == 'cancelled');
                setState(() {});
              },
              tooltip: '清除已完成',
            ),
        ],
      ),
      body: !hasAnyTasks
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: () async { _loadRemoteQueue(); await Future.delayed(const Duration(milliseconds: 500)); },
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (localTasks.isNotEmpty) ...[
                    _buildSectionHeader('📱 本机任务', localTasks.length),
                    ...localTasks.map((task) => _buildLocalTaskCard(task)),
                    const SizedBox(height: 16),
                  ],
                  if (_remoteTasks.isNotEmpty) ...[
                    _buildSectionHeader('🖥️ 远程任务（Windows）', _remoteTasks.length),
                    ..._remoteTasks.map((task) => _buildRemoteTaskCard(task)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF4FC3F7).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalTaskCard(DownloadTask task) {
    final isActive = task.status == 'downloading' || task.status == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: isActive ? Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.3)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFF4FC3F7).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.download, color: Color(0xFF4FC3F7), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.fileName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: _getStatusColor(task.status).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text(_getStatusText(task.status), style: TextStyle(color: _getStatusColor(task.status), fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        if (task.totalBytes > 0)
                          Text('${_formatBytes(task.receivedBytes)} / ${_formatBytes(task.totalBytes)}', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isActive)
                IconButton(
                  icon: const Icon(Icons.cancel, color: Color(0xFFEF5350), size: 22),
                  onPressed: () => DownloadManager().cancelTask(task.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF6B7280), size: 20),
                  onPressed: () => DownloadManager().removeTask(task.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          if (task.status == 'downloading' || task.status == 'paused') ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress / 100,
                backgroundColor: const Color(0xFF12121A),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4FC3F7)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text('${task.progress.toStringAsFixed(1)}%', style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11)),
          ],
          if (task.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(task.error!, style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildRemoteTaskCard(dynamic task) {
    final status = task['status'] ?? 'unknown';
    final progress = (task['progress'] ?? 0).toDouble();
    final isActive = status == 'running' || status == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: isActive ? Border.all(color: const Color(0xFFFFB74D).withOpacity(0.3)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFFFFB74D).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(_getTaskIcon(task['type'] ?? ''), color: const Color(0xFFFFB74D), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task['name'] ?? '未知任务', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text(_getStatusText(status), style: TextStyle(color: _getStatusColor(status), fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text('类型: ${task['type'] ?? '-'}', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isActive)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status == 'running')
                      IconButton(
                        icon: const Icon(Icons.pause, color: Color(0xFFFFB74D), size: 20),
                        onPressed: () => ApiService().queueAction(task['id'], 'pause'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    if (status == 'paused')
                      IconButton(
                        icon: const Icon(Icons.play_arrow, color: Color(0xFF81C784), size: 20),
                        onPressed: () => ApiService().queueAction(task['id'], 'resume'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Color(0xFFEF5350), size: 20),
                      onPressed: () => ApiService().queueAction(task['id'], 'cancel'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
            ],
          ),
          if (isActive && progress > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: const Color(0xFF12121A),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB74D)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text('${progress.toStringAsFixed(1)}%', style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 11)),
          ],
          if (task['error'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(task['error'], style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_play_next, color: const Color(0xFF455A64), size: 72),
          const SizedBox(height: 20),
          const Text('队列为空', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('上传、下载、复制任务将显示在这里', style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14)),
        ],
      ),
    );
  }
}
