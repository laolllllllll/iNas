import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'services/download_manager.dart';
import 'pages/browse_page.dart';
import 'pages/cmd_page.dart';
import 'pages/queue_page.dart';
import 'pages/terminal_page.dart';
import 'pages/apps_page.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await ApiService().loadConnection();
  await DownloadManager().init();
  runApp(const INasApp());
}

class INasApp extends StatelessWidget {
  const INasApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iNas v2',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const BrowsePage(),
    const CmdPage(),
    const QueuePage(),
    const TerminalPage(),
    const AppsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.folder_outlined, size: 22), activeIcon: Icon(Icons.folder, size: 22), label: '浏览'),
          BottomNavigationBarItem(icon: Icon(Icons.terminal_outlined, size: 22), activeIcon: Icon(Icons.terminal, size: 22), label: '管理设备'),
          BottomNavigationBarItem(icon: Icon(Icons.queue_play_next_outlined, size: 22), activeIcon: Icon(Icons.queue_play_next, size: 22), label: '队列'),
          BottomNavigationBarItem(icon: Icon(Icons.phone_iphone_outlined, size: 22), activeIcon: Icon(Icons.phone_iphone, size: 22), label: '此终端'),
          BottomNavigationBarItem(icon: Icon(Icons.apps_outlined, size: 22), activeIcon: Icon(Icons.apps, size: 22), label: 'APPS'),
        ],
      ),
    );
  }
}
