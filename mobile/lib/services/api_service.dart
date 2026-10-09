import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/file_item.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
  ));

  String? _baseUrl;
  String? _token;
  bool _connected = false;

  bool get isConnected => _connected && _baseUrl != null && _token != null;
  String? get baseUrl => _baseUrl;
  String? get token => _token;

  Future<void> loadConnection() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('inas_base_url');
    _token = prefs.getString('inas_token');
    if (_baseUrl != null && _token != null) {
      _connected = true;
    }
  }

  Future<void> saveConnection(String ip, int port, String token) async {
    _baseUrl = 'http://$ip:$port';
    _token = token;
    _connected = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('inas_base_url', _baseUrl!);
    await prefs.setString('inas_token', token);
    await prefs.setString('inas_ip', ip);
    await prefs.setInt('inas_port', port);
  }

  Future<void> clearConnection() async {
    _baseUrl = null;
    _token = null;
    _connected = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('inas_base_url');
    await prefs.remove('inas_token');
    await prefs.remove('inas_ip');
    await prefs.remove('inas_port');
  }

  Map<String, String> get _headers => {
    if (_token != null) 'x-nas-token': _token!,
    'Content-Type': 'application/json',
  };

  // ============ 文件列表 ============
  Future<Map<String, dynamic>> listFiles(String path) async {
    final response = await _dio.get(
      '$_baseUrl/api/files',
      queryParameters: {'path': path},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 下载文件 ============
  Future<void> downloadFile(String path, String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await _dio.download(
      '$_baseUrl/api/download',
      savePath,
      queryParameters: {'path': path},
      options: Options(
        headers: _headers,
        responseType: ResponseType.bytes,
      ),
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  // ============ 上传文件 ============
  Future<Response> uploadFile(String filePath, String targetPath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'path': targetPath,
      'file': await MultipartFile.fromFile(filePath),
    });
    return await _dio.post(
      '$_baseUrl/api/upload',
      data: formData,
      options: Options(headers: {
        if (_token != null) 'x-nas-token': _token!,
      }),
      onSendProgress: onProgress,
    );
  }

  // ============ 删除文件 ============
  Future<Map<String, dynamic>> deleteFile(String path) async {
    final response = await _dio.post(
      '$_baseUrl/api/delete',
      data: {'path': path},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 重命名 ============
  Future<Map<String, dynamic>> renameFile(String path, String newName) async {
    final response = await _dio.post(
      '$_baseUrl/api/rename',
      data: {'path': path, 'newName': newName},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 复制 ============
  Future<Map<String, dynamic>> copyFile(String source, String destination) async {
    final response = await _dio.post(
      '$_baseUrl/api/copy',
      data: {'source': source, 'destination': destination},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 移动 ============
  Future<Map<String, dynamic>> moveFile(String source, String destination) async {
    final response = await _dio.post(
      '$_baseUrl/api/move',
      data: {'source': source, 'destination': destination},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 创建目录 ============
  Future<Map<String, dynamic>> createDir(String path, String name) async {
    final response = await _dio.post(
      '$_baseUrl/api/mkdir',
      data: {'path': path, 'name': name},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 读取文本 ============
  Future<Map<String, dynamic>> readText(String path) async {
    final response = await _dio.get(
      '$_baseUrl/api/read-text',
      queryParameters: {'path': path},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 写入文本 ============
  Future<Map<String, dynamic>> writeText(String path, String content) async {
    final response = await _dio.post(
      '$_baseUrl/api/write-text',
      data: {'path': path, 'content': content},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 队列状态 ============
  Future<List<dynamic>> getQueue() async {
    final response = await _dio.get(
      '$_baseUrl/api/queue',
      options: Options(headers: _headers),
    );
    return response.data['tasks'] ?? [];
  }

  // ============ 队列操作 ============
  Future<Map<String, dynamic>> queueAction(String id, String action) async {
    final response = await _dio.post(
      '$_baseUrl/api/queue/$id/$action',
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ CMD 执行（简单模式） ============
  Future<Map<String, dynamic>> executeCmd(String command, {String? sessionId}) async {
    final response = await _dio.post(
      '$_baseUrl/api/cmd',
      data: {'command': command, if (sessionId != null) 'sessionId': sessionId},
      options: Options(
        headers: _headers,
        receiveTimeout: const Duration(seconds: 65),
      ),
    );
    return response.data;
  }

  // ============ CMD 会话 ============
  Future<Map<String, dynamic>> createCmdSession({String? cwd}) async {
    final response = await _dio.post(
      '$_baseUrl/api/cmd/session',
      data: {if (cwd != null) 'cwd': cwd},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  Future<Map<String, dynamic>> writeCmdSession(String id, String input) async {
    final response = await _dio.post(
      '$_baseUrl/api/cmd/session/$id/write',
      data: {'input': input},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  Future<Map<String, dynamic>> readCmdSession(String id) async {
    final response = await _dio.get(
      '$_baseUrl/api/cmd/session/$id/read',
      options: Options(headers: _headers),
    );
    return response.data;
  }

  Future<Map<String, dynamic>> closeCmdSession(String id) async {
    final response = await _dio.post(
      '$_baseUrl/api/cmd/session/$id/close',
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 可用盘符列表 ============
  Future<List<dynamic>> getDrives() async {
    final response = await _dio.get('$_baseUrl/api/drives', options: Options(headers: _headers));
    return response.data['drives'] ?? [];
  }

  // ============ 从 URL 上传 ============
  Future<Map<String, dynamic>> uploadFromUrl(String url, String targetPath) async {
    final response = await _dio.post('$_baseUrl/api/upload-url',
      data: {'url': url, 'path': targetPath},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 回收站 - 恢复文件 ============
  Future<Map<String, dynamic>> restoreFromRecycle(String path) async {
    final response = await _dio.post('$_baseUrl/api/recycle/restore',
      data: {'path': path},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 回收站 - 清空 ============
  Future<Map<String, dynamic>> emptyRecycle() async {
    final response = await _dio.post('$_baseUrl/api/recycle/empty',
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 启用 HTTP 静态服务 ============
  Future<Map<String, dynamic>> startHttpServer(String path) async {
    final response = await _dio.post('$_baseUrl/api/http-server/start',
      data: {'path': path},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 停止 HTTP 服务 ============
  Future<Map<String, dynamic>> stopHttpServer(String taskId) async {
    final response = await _dio.post('$_baseUrl/api/http-server/stop',
      data: {'taskId': taskId},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 生成下载链接 ============
  Future<Map<String, dynamic>> createDownloadLink(String path) async {
    final response = await _dio.post('$_baseUrl/api/download-link',
      data: {'path': path},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ 使下载链接失效 ============
  Future<Map<String, dynamic>> revokeDownloadLink(String taskId) async {
    final response = await _dio.post('$_baseUrl/api/download-link/revoke',
      data: {'taskId': taskId},
      options: Options(headers: _headers),
    );
    return response.data;
  }

  // ============ v2: 设备连接 ============
  Future<Map<String, dynamic>> connectDevice(String deviceName) async {
    final response = await _dio.post('$_baseUrl/api/connect',
      data: {'deviceName': deviceName}, options: Options(headers: _headers));
    return response.data;
  }

  // ============ v2: 设备管理 ============
  Future<List<dynamic>> getDevices() async {
    final response = await _dio.get('$_baseUrl/api/devices', options: Options(headers: _headers));
    return response.data['devices'] ?? [];
  }
  Future<void> deleteDevice(String id) async {
    await _dio.delete('$_baseUrl/api/devices/$id', options: Options(headers: _headers));
  }

  // ============ v2: 电源控制 ============
  Future<void> shutdown() async {
    await _dio.post('$_baseUrl/api/power/shutdown', options: Options(headers: _headers));
  }
  Future<void> restart() async {
    await _dio.post('$_baseUrl/api/power/restart', options: Options(headers: _headers));
  }

  // ============ v2: 服务器信息 ============
  Future<Map<String, dynamic>> getServerInfo() async {
    final response = await _dio.get('$_baseUrl/api/server-info', options: Options(headers: _headers));
    return response.data;
  }
  Future<String> getServerName() async {
    final response = await _dio.get('$_baseUrl/api/settings/server-name', options: Options(headers: _headers));
    return response.data['name'] ?? '';
  }
  Future<void> setServerName(String name) async {
    await _dio.post('$_baseUrl/api/settings/server-name',
      data: {'name': name}, options: Options(headers: _headers));
  }

  // ============ v2: 服务管理 ============
  Future<void> stopService() async {
    await _dio.post('$_baseUrl/api/service/stop', options: Options(headers: _headers));
  }
  Future<void> restartService() async {
    await _dio.post('$_baseUrl/api/service/restart', options: Options(headers: _headers));
  }

  // ============ v2: 消息 ============
  Future<List<dynamic>> getMessages() async {
    final response = await _dio.get('$_baseUrl/api/messages', options: Options(headers: _headers));
    return response.data['messages'] ?? [];
  }
  Future<Map<String, dynamic>> sendMessage(String deviceName, String content) async {
    final response = await _dio.post('$_baseUrl/api/messages',
      data: {'deviceName': deviceName, 'content': content}, options: Options(headers: _headers));
    return response.data;
  }

  // ============ 测试连接 ============
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/status',
        options: Options(headers: _headers, receiveTimeout: const Duration(seconds: 5)),
      );
      return response.data['ok'] == true;
    } catch (e) {
      return false;
    }
  }
}
