import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class DownloadTask {
  final String id;
  final String remotePath;
  final String fileName;
  String localPath;
  int totalBytes;
  int receivedBytes;
  double progress;
  String status; // pending, downloading, completed, failed, cancelled, paused
  String? error;
  CancelToken? cancelToken;
  DateTime createdAt;

  DownloadTask({
    required this.id,
    required this.remotePath,
    required this.fileName,
    required this.localPath,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.progress = 0,
    this.status = 'pending',
    this.error,
    this.cancelToken,
    required this.createdAt,
  });
}

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => _tasks;

  late Directory _downloadDir;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final appDir = await getApplicationDocumentsDirectory();
    _downloadDir = Directory('${appDir.path}/iNasDownloads');
    if (!await _downloadDir.exists()) {
      await _downloadDir.create(recursive: true);
    }
    _initialized = true;
  }

  String get downloadPath => _downloadDir.path;

  Future<List<File>> getLocalFiles() async {
    if (!_initialized) await init();
    if (!await _downloadDir.exists()) return [];
    final entities = _downloadDir.listSync();
    final files = entities.whereType<File>().toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<DownloadTask> startDownload(String remotePath, String fileName) async {
    if (!_initialized) await init();

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final localPath = '${_downloadDir.path}/$fileName';

    // 处理重名
    String finalPath = localPath;
    int counter = 1;
    while (await File(finalPath).exists()) {
      final dotIndex = fileName.lastIndexOf('.');
      if (dotIndex > 0) {
        final name = fileName.substring(0, dotIndex);
        final ext = fileName.substring(dotIndex);
        finalPath = '${_downloadDir.path}/$name($counter)$ext';
      } else {
        finalPath = '${_downloadDir.path}/$fileName($counter)';
      }
      counter++;
    }

    final task = DownloadTask(
      id: id,
      remotePath: remotePath,
      fileName: fileName,
      localPath: finalPath,
      createdAt: DateTime.now(),
    );
    _tasks.insert(0, task);

    // 异步执行下载
    _executeDownload(task);

    return task;
  }

  Future<void> _executeDownload(DownloadTask task) async {
    task.status = 'downloading';
    task.cancelToken = CancelToken();

    try {
      await ApiService().downloadFile(
        task.remotePath,
        task.localPath,
        cancelToken: task.cancelToken,
        onProgress: (received, total) {
          task.receivedBytes = received;
          task.totalBytes = total;
          task.progress = total > 0 ? (received / total) * 100 : 0;
        },
      );
      task.status = 'completed';
      task.progress = 100;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        task.status = 'cancelled';
      } else {
        task.status = 'failed';
        task.error = e.message;
      }
      // 清理不完整文件
      try {
        final f = File(task.localPath);
        if (await f.exists() && task.status != 'completed') {
          await f.delete();
        }
      } catch (_) {}
    } catch (e) {
      task.status = 'failed';
      task.error = e.toString();
    }
  }

  void cancelTask(String id) {
    final task = _tasks.firstWhere((t) => t.id == id, orElse: () => _tasks.first);
    task.cancelToken?.cancel();
    task.status = 'cancelled';
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
  }

  Future<void> deleteLocalFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  List<DownloadTask> getActiveTasks() {
    return _tasks.where((t) =>
      t.status == 'downloading' || t.status == 'pending' || t.status == 'paused'
    ).toList();
  }
}
