import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_info.dart';
import 'api_service.dart';

class AppService {
  static final AppService _instance = AppService._internal();
  factory AppService() => _instance;
  AppService._internal();

  final Dio _dio = Dio();
  String? get _baseUrl => ApiService().baseUrl;
  String? get _token => ApiService().token;
  Map<String, String> get _headers => {
    if (_token != null) 'x-nas-token': _token!,
    'Content-Type': 'application/json',
  };

  // 系统应用列表
  static final List<AppInfo> systemApps = [
    AppInfo(bundleId: 'com.cor.iNas.Camera', name: '相机', isSystem: true),
    AppInfo(bundleId: 'com.cor.iNas.Photos', name: '相册', isSystem: true),
    AppInfo(bundleId: 'com.cor.iNas.Browser', name: '浏览器', isSystem: true),
    AppInfo(bundleId: 'com.cor.iNas.Files', name: '文件', isSystem: true),
    AppInfo(bundleId: 'com.cor.iNas.Music', name: '音乐', isSystem: true),
    AppInfo(bundleId: 'com.cor.iNas.Settings', name: '设置', isSystem: true),
    AppInfo(bundleId: 'com.cor.iNas.Trash', name: '废纸篓', isSystem: true),
    AppInfo(bundleId: 'com.cor.iNas.AppStore', name: 'AppStore', isSystem: true),
    AppInfo(bundleId: 'com.cor.iNas.Messages', name: '信息', isSystem: true),
  ];

  // 获取所有应用（系统 + 已安装）
  Future<List<AppInfo>> getAllApps() async {
    final apps = List<AppInfo>.from(systemApps);
    try {
      if (_baseUrl != null) {
        final response = await _dio.get('$_baseUrl/api/apps', options: Options(headers: _headers));
        final installed = (response.data['apps'] as List?) ?? [];
        for (final a in installed) {
          apps.add(AppInfo.fromJson(a));
        }
      }
    } catch (_) {}
    return apps;
  }

  // 安装 NAP 应用（从 URL）
  Future<Map<String, dynamic>> installFromUrl(String url) async {
    final response = await _dio.post('$_baseUrl/api/apps/install',
      data: {'url': url},
      options: Options(headers: _headers));
    return response.data;
  }

  // 安装 NAP 应用（从文件）
  Future<Map<String, dynamic>> installFromFile(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await _dio.post('$_baseUrl/api/apps/install',
      data: formData,
      options: Options(headers: {if (_token != null) 'x-nas-token': _token!}));
    return response.data;
  }

  // 卸载应用
  Future<void> uninstallApp(String bundleId) async {
    await _dio.delete('$_baseUrl/api/apps/$bundleId', options: Options(headers: _headers));
  }

  // 获取应用资源 URL
  String getAppResourceUrl(String bundleId, String resource) {
    return '$_baseUrl/api/apps/$bundleId/$resource';
  }

  // ============ 设备命名 ============
  Future<String?> getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('inas_device_name');
  }

  Future<void> setDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('inas_device_name', name);
    // 注册到服务器
    try {
      await _dio.post('$_baseUrl/api/connect',
        data: {'deviceName': name},
        options: Options(headers: _headers));
    } catch (_) {}
  }

  // ============ 桌面布局 ============
  Future<List<String>> getAppLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final layout = prefs.getStringList('inas_app_layout');
    if (layout != null && layout.isNotEmpty) return layout;
    // 默认布局：系统应用按顺序
    return systemApps.map((a) => a.bundleId).toList();
  }

  Future<void> saveAppLayout(List<String> bundleIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('inas_app_layout', bundleIds);
  }

  // ============ 壁纸 ============
  Future<String?> getWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('inas_wallpaper');
  }

  Future<void> setWallpaper(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('inas_wallpaper', path);
  }
}
