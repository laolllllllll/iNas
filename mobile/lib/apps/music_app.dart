import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/file_item.dart';
import '../services/api_service.dart';

class MusicApp extends StatefulWidget {
  const MusicApp({super.key});
  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  final AudioPlayer _player = AudioPlayer();
  List<FileItem> _songs = [];
  int _currentIndex = -1;
  bool _playing = false;
  double _progress = 0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadSongs();
    _player.positionStream.listen((p) => setState(() => _position = p));
    _player.durationStream.listen((d) => setState(() => _duration = d ?? Duration.zero));
    _player.playerStateStream.listen((state) {
      setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed && _currentIndex < _songs.length - 1) {
        _playSong(_currentIndex + 1);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    try {
      final data = await ApiService().listFiles('音乐');
      final entries = (data['entries'] as List?) ?? [];
      setState(() => _songs = entries.map((e) => FileItem.fromJson(e)).where((f) => !f.isDirectory).toList());
    } catch (_) {}
  }

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    final url = '${ApiService().baseUrl}/api/download?path=${Uri.encodeComponent(song.path)}';
    try {
      await _player.setUrl(url, headers: {'x-nas-token': ApiService().token ?? ''});
      _player.play();
      setState(() => _currentIndex = index);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e')));
    }
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(backgroundColor: const Color(0xFF1A1A2E), title: const Text('音乐'), automaticallyImplyLeading: false),
      body: Column(children: [
        // 正在播放
        if (_currentIndex >= 0) Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF0D0D1A),
          child: Column(children: [
            Row(children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(color: const Color(0xFFEC407A), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.music_note, color: Colors.white, size: 28)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_songs[_currentIndex].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                const Text('iNas Music', style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 8),
            Slider(value: _position.inSeconds.toDouble(), max: _duration.inSeconds.toDouble(), onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
              activeColor: const Color(0xFFEC407A), inactiveColor: const Color(0xFF2A2A3E)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_fmt(_position), style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11)),
              Text(_fmt(_duration), style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: () => _playSong(_currentIndex - 1)),
              const SizedBox(width: 16),
              IconButton(icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: const Color(0xFFEC407A), size: 48),
                onPressed: () => _playing ? _player.pause() : _player.play()),
              const SizedBox(width: 16),
              IconButton(icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: () => _playSong(_currentIndex + 1)),
            ]),
          ]),
        ),
        // 歌曲列表
        Expanded(child: _songs.isEmpty
          ? const Center(child: Text('音乐目录为空', style: TextStyle(color: Color(0xFF6B7280))))
          : ListView.builder(itemCount: _songs.length, itemBuilder: (ctx, i) {
              final song = _songs[i];
              final isCurrent = i == _currentIndex;
              return ListTile(
                leading: Icon(isCurrent ? Icons.play_arrow : Icons.music_note, color: isCurrent ? const Color(0xFFEC407A) : const Color(0xFF90A4AE)),
                title: Text(song.name, style: TextStyle(color: isCurrent ? const Color(0xFFEC407A) : Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(song.formattedSize, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                onTap: () => _playSong(i),
              );
            })),
      ]),
    );
  }
}
