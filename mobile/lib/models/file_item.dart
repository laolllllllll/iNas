import 'package:flutter/material.dart';

class FileItem {
  final String name;
  final String path;
  final int size;
  final int modified;
  final bool isDirectory;
  final bool protected;
  final String? specialType; // music, photos, download, recycle, system
  final String? originalName; // 回收站中原始文件名
  final String? displayName; // 显示名称映射（如 Photos→相册）

  FileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    required this.isDirectory,
    this.protected = false,
    this.specialType,
    this.originalName,
    this.displayName,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: (json['modified'] as num?)?.toInt() ?? 0,
      isDirectory: json['isDirectory'] == true,
      protected: json['protected'] == true,
      specialType: json['specialType']?.toString(),
      originalName: json['originalName']?.toString(),
      displayName: json['displayName']?.toString(),
    );
  }

  /// 显示用名称：优先 displayName，其次 originalName（回收站），最后 name
  String get showName => displayName ?? originalName ?? name;

  String get formattedSize {
    if (isDirectory) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  bool get isImage => ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'heic'].contains(extension);
  bool get isVideo => ['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm', 'm4v'].contains(extension);
  bool get isTorrent => extension == 'torrent';
  bool get isText => ['txt', 'md', 'json', 'xml', 'html', 'htm', 'js', 'ts', 'css', 'py', 'c', 'cpp', 'h', 'java', 'kt', 'dart', 'go', 'rs', 'sh', 'bat', 'cmd', 'ini', 'conf', 'cfg', 'yaml', 'yml', 'toml', 'log', 'csv', 'sql', 'php', 'rb', 'pl', 'swift', 'm', 'mm', 'plist', 'strings'].contains(extension);
  bool get isHtml => ['html', 'htm'].contains(extension);
}

/// 根据文件名返回扩展名对应的图标和颜色
class FileIconHelper {
  static IconData getIcon(String fileName) {
    final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() : '';
    switch (ext) {
      case 'py': return Icons.code;
      case 'html': case 'htm': return Icons.language;
      case 'mp3': case 'flac': case 'wav': case 'm4a': case 'aac': return Icons.music_note;
      case 'mp4': case 'mov': case 'avi': case 'mkv': case 'flv': return Icons.play_circle_filled;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'heic': case 'bmp': return Icons.image;
      case 'torrent': return Icons.download_for_offline;
      case 'zip': case 'rar': case '7z': case 'nap': case 'tar': case 'gz': return Icons.archive;
      case 'txt': case 'md': case 'log': return Icons.description;
      case 'exe': case 'msi': case 'bat': case 'cmd': return Icons.build;
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': case 'csv': return Icons.table_chart;
      case 'ppt': case 'pptx': return Icons.slideshow;
      case 'json': case 'xml': case 'yaml': case 'yml': case 'js': case 'ts': case 'css': return Icons.code;
      default: return Icons.insert_drive_file;
    }
  }

  static Color getColor(String fileName) {
    final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() : '';
    switch (ext) {
      case 'py': return const Color(0xFF42A5F5);
      case 'html': case 'htm': return const Color(0xFFFF9500);
      case 'mp3': case 'flac': case 'wav': case 'm4a': case 'aac': return const Color(0xFFEC407A);
      case 'mp4': case 'mov': case 'avi': case 'mkv': case 'flv': return const Color(0xFFFF3B30);
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'heic': case 'bmp': return const Color(0xFFAB47BC);
      case 'torrent': return const Color(0xFF34C759);
      case 'zip': case 'rar': case '7z': case 'nap': case 'tar': case 'gz': return const Color(0xFF8D6E63);
      case 'txt': case 'md': case 'log': return const Color(0xFF8E8E93);
      case 'exe': case 'msi': case 'bat': case 'cmd': return const Color(0xFF546E7A);
      case 'pdf': return const Color(0xFFFF3B30);
      case 'doc': case 'docx': return const Color(0xFF42A5F5);
      case 'xls': case 'xlsx': case 'csv': return const Color(0xFF34C759);
      case 'ppt': case 'pptx': return const Color(0xFFFF9500);
      case 'json': case 'xml': case 'yaml': case 'yml': case 'js': case 'ts': case 'css': return const Color(0xFF26C6DA);
      default: return const Color(0xFF8E8E93);
    }
  }

  /// 受保护目录的特色图标
  static IconData getSpecialIcon(String? specialType) {
    switch (specialType) {
      case 'music': return Icons.music_note;
      case 'photos': return Icons.photo_library;
      case 'download': return Icons.download;
      case 'recycle': return Icons.delete_sweep;
      default: return Icons.folder;
    }
  }

  static Color getSpecialColor(String? specialType) {
    switch (specialType) {
      case 'music': return const Color(0xFFEC407A);
      case 'photos': return const Color(0xFFFF3B30);
      case 'download': return const Color(0xFF007AFF);
      case 'recycle': return const Color(0xFFFF9500);
      default: return const Color(0xFF007AFF);
    }
  }
}
