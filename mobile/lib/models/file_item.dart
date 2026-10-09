class FileItem {
  final String name;
  final String path;
  final int size;
  final int modified;
  final bool isDirectory;

  FileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    required this.isDirectory,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      size: json['size'] ?? 0,
      modified: json['modified'] ?? 0,
      isDirectory: json['isDirectory'] ?? false,
    );
  }

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

  bool get isImage => ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico'].contains(extension);
  bool get isVideo => ['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm', 'm4v'].contains(extension);
  bool get isText => ['txt', 'md', 'json', 'xml', 'html', 'htm', 'js', 'ts', 'css', 'py', 'c', 'cpp', 'h', 'java', 'kt', 'dart', 'go', 'rs', 'sh', 'bat', 'cmd', 'ini', 'conf', 'cfg', 'yaml', 'yml', 'toml', 'log', 'csv', 'sql', 'php', 'rb', 'pl', 'swift', 'm', 'mm', 'plist', 'strings'].contains(extension);
  bool get isHtml => ['html', 'htm'].contains(extension);
}
