class AppInfo {
  final String bundleId;
  final String name;
  final String version;
  final String icon;
  final bool isSystem;

  AppInfo({
    required this.bundleId,
    required this.name,
    this.version = '1.0',
    this.icon = '',
    this.isSystem = false,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      bundleId: json['bundleId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0',
      icon: json['icon']?.toString() ?? '',
    );
  }
}
