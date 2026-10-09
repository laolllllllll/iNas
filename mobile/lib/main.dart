import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'services/download_manager.dart';
import 'pages/browse_page.dart';
import 'pages/cmd_page.dart';
import 'pages/queue_page.dart';
import 'pages/terminal_page.dart';

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
      title: 'iNas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF4FC3F7),
        scaffoldBackgroundColor: const Color(0xFF12121A),
        cardColor: const Color(0xFF1E1E2E),
        dividerColor: const Color(0xFF2A2A3E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1A1A2E),
          selectedItemColor: Color(0xFF4FC3F7),
          unselectedItemColor: Color(0xFF6B7280),
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          elevation: 8,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4FC3F7),
          secondary: Color(0xFF81C784),
          surface: Color(0xFF1E1E2E),
          error: Color(0xFFEF5350),
        ),
      ),
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_outlined, size: 24),
            activeIcon: Icon(Icons.folder, size: 24),
            label: '浏览',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.terminal_outlined, size: 24),
            activeIcon: Icon(Icons.terminal, size: 24),
            label: '管理设备',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.queue_play_next_outlined, size: 24),
            activeIcon: Icon(Icons.queue_play_next, size: 24),
            label: '队列',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.phone_iphone_outlined, size: 24),
            activeIcon: Icon(Icons.phone_iphone, size: 24),
            label: '此终端',
          ),
        ],
      ),
    );
  }
}
