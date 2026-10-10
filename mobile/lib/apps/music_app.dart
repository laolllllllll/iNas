import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class MusicApp extends StatefulWidget {
  const MusicApp({super.key});
  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  final AudioPlayer _player = AudioPlayer();
  List<dynamic> _songs = [];
  int _currentIndex = -1;
  bool _playing = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _loading = true;
  int _playMode = 0; // 0=顺序, 1=随机, 2=单曲循环
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _artistController = TextEditingController();
  String? _pendingMp3Path;
  String? _pendingCoverPath;

  @override
  void initState() {
    super.initState();
    _loadSongs();
    // 进度更新
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    // 时长更新
    _player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
    // 播放状态 + 自动下一首
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed) {
        _onPlayComplete();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await ApiService().getMusicList();
      if (mounted) setState(() { _songs = songs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPlayComplete() {
    if (_playMode == 2) {
      // 单曲循环
      _player.seek(Duration.zero);
      _player.play();
    } else if (_playMode == 1) {
      // 随机
      if (_songs.length > 1) {
        int next;
        do { next = DateTime.now().microsecond % _songs.length; } while (next == _currentIndex);
        _playSong(next);
      }
    } else {
      // 顺序
      if (_currentIndex < _songs.length - 1) {
        _playSong(_currentIndex + 1);
      } else {
        _player.pause();
        _player.seek(Duration.zero);
      }
    }
  }

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    final songPath = song['path'] ?? '';
    final url = '${ApiService().baseUrl}/api/download?path=${Uri.encodeComponent(songPath)}';
    try {
      await _player.setUrl(url, headers: {'x-nas-token': ApiService().token ?? ''});
      _player.play();
      if (mounted) setState(() => _currentIndex = index);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e'), backgroundColor: AppTheme.danger));
    }
  }

  void _togglePlay() {
    if (_currentIndex < 0) {
      if (_songs.isNotEmpty) _playSong(0);
      return;
    }
    if (_playing) { _player.pause(); } else { _player.play(); }
  }

  void _nextSong() {
    if (_songs.isEmpty) return;
    _playSong((_currentIndex + 1) % _songs.length);
  }

  void _prevSong() {
    if (_songs.isEmpty) return;
    if (_position.inSeconds > 3) {
      _player.seek(Duration.zero);
    } else {
      _playSong((_currentIndex - 1 + _songs.length) % _songs.length);
    }
  }

  void _cyclePlayMode() {
    setState(() => _playMode = (_playMode + 1) % 3);
    final modes = ['顺序播放', '随机播放', '单曲循环'];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(modes[_playMode]), duration: const Duration(seconds: 1)));
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  IconData get _playModeIcon {
    switch (_playMode) {
      case 1: return Icons.shuffle;
      case 2: return Icons.repeat_one;
      default: return Icons.repeat;
    }
  }

  // ============ 添加音乐 ============
  void _showAddMusicMenu() {
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.folder, color: AppTheme.accent), title: const Text('从 NAS 音乐目录选择', style: TextStyle(color: AppTheme.textPrimary)),
        onTap: () { Navigator.pop(ctx); _pickNasMp3(); }),
      ListTile(leading: const Icon(Icons.upload_file, color: AppTheme.accent), title: const Text('从本地上传 MP3', style: TextStyle(color: AppTheme.textPrimary)),
        onTap: () { Navigator.pop(ctx); _pickLocalMp3(); }),
      const SizedBox(height: 8),
    ])));
  }

  Future<void> _pickLocalMp3() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'flac', 'wav', 'm4a', 'aac']);
    if (result == null || result.files.isEmpty) return;
    _pendingMp3Path = result.files.first.path;
    _titleController.text = result.files.first.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    _artistController.text = '';
    _pendingCoverPath = null;
    _showMusicInfoDialog();
  }

  Future<void> _pickNasMp3() async {
    // 简单起见，直接让用户输入文件名，或浏览音乐目录
    // 这里用输入框让用户输入 NAS 上已有的 MP3 文件名
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('输入 MP3 文件名'),
      content: TextField(controller: controller, decoration: const InputDecoration(hintText: '如 song.mp3（音乐目录下的文件）')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('确定')),
      ],
    ));
    if (name == null || name.isEmpty) return;
    _pendingMp3Path = null;
    _titleController.text = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    _artistController.text = '';
    _pendingCoverPath = null;
    _showMusicInfoDialog(mp3Path: '音乐/$name');
  }

  void _showMusicInfoDialog({String? mp3Path}) {
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('歌曲信息'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _titleController, decoration: const InputDecoration(labelText: '歌曲名 *')),
          const SizedBox(height: 8),
          TextField(controller: _artistController, decoration: const InputDecoration(labelText: '艺术家（选填）')),
          const SizedBox(height: 12),
          Row(children: [
            const Text('专辑封面：', style: AppTheme.secondaryStyle),
            TextButton(onPressed: () async {
              final picker = ImagePicker();
              final img = await picker.pickImage(source: ImageSource.gallery);
              if (img != null) { _pendingCoverPath = img.path; setDialogState(() {}); }
            }, child: const Text('选择图片')),
            if (_pendingCoverPath != null) const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () async {
            Navigator.pop(ctx);
            await _submitMusic(mp3Path: mp3Path);
          }, child: const Text('保存')),
        ],
      ),
    ));
  }

  Future<void> _submitMusic({String? mp3Path}) async {
    try {
      await ApiService().addMusic(
        filePath: _pendingMp3Path,
        mp3Path: mp3Path,
        title: _titleController.text.trim(),
        artist: _artistController.text.trim().isEmpty ? null : _artistController.text.trim(),
        coverPath: _pendingCoverPath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('添加成功'), backgroundColor: AppTheme.success));
        _loadSongs();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败: $e'), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        title: const Text('音乐'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddMusicMenu, tooltip: '添加音乐'),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
        : Column(children: [
            // 正在播放区域
            if (_currentIndex >= 0) _buildNowPlaying(),
            // 歌曲列表
            Expanded(child: _songs.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.music_note, color: AppTheme.textTertiary, size: 48),
                  const SizedBox(height: 12),
                  const Text('音乐目录为空', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _showAddMusicMenu, child: const Text('添加音乐')),
                ]))
              : ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (ctx, i) => _buildSongItem(_songs[i], i),
                )),
          ]),
    );
  }

  Widget _buildNowPlaying() {
    final song = _songs[_currentIndex];
    final title = song['title'] ?? '未知歌曲';
    final artist = song['artist'] ?? '未知艺术家';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A2A2C), AppTheme.bg]),
      ),
      child: Column(children: [
        Row(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: const Color(0xFFEC407A), borderRadius: BorderRadius.circular(8), boxShadow: AppTheme.cardShadow),
            child: const Icon(Icons.music_note, color: Colors.white, size: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 8),
        Slider(
          value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble()),
          max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1,
          onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
          activeColor: const Color(0xFFEC407A), inactiveColor: AppTheme.divider,
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_fmt(_position), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          Text(_fmt(_duration), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: Icon(_playModeIcon, color: AppTheme.textSecondary, size: 22), onPressed: _cyclePlayMode),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white, size: 28), onPressed: _prevSong),
          const SizedBox(width: 16),
          IconButton(icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: const Color(0xFFEC407A), size: 52), onPressed: _togglePlay),
          const SizedBox(width: 16),
          IconButton(icon: const Icon(Icons.skip_next, color: Colors.white, size: 28), onPressed: _nextSong),
          const SizedBox(width: 8),
          const SizedBox(width: 44),
        ]),
      ]),
    );
  }

  Widget _buildSongItem(dynamic song, int index) {
    final title = song['title'] ?? '未知歌曲';
    final artist = song['artist'] ?? '未知艺术家';
    final duration = song['duration'] ?? 0;
    final isCurrent = index == _currentIndex;
    return ListTile(
      leading: Icon(isCurrent ? Icons.play_arrow : Icons.music_note, color: isCurrent ? const Color(0xFFEC407A) : AppTheme.textSecondary, size: 24),
      title: Text(title, style: TextStyle(color: isCurrent ? const Color(0xFFEC407A) : AppTheme.textPrimary, fontSize: 14, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$artist · ${_fmtDuration(duration)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      trailing: isCurrent && _playing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEC407A))) : null,
      onTap: () => _playSong(index),
    );
  }
}
