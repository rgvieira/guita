import 'package:flutter/material.dart';
import 'package:guitarra/widgets/alpha_tab_view.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  final _alphaTabKey = GlobalKey<AlphaTabViewState>();
  String _filePath = '';
  bool _initialised = false;
  int _playerState = 0;
  bool _sfLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final path = ModalRoute.of(context)!.settings.arguments as String;
    if (path != _filePath) {
      _filePath = path;
      _initialised = false;
    }
    if (!_initialised && _filePath.isNotEmpty) {
      _initialised = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filePath.split('\\').last.split('/').last,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () =>
                Navigator.pushNamed(context, '/practice', arguments: _filePath),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AlphaTabView(
              key: _alphaTabKey,
              filePath: _filePath,
              onPlayerStateChanged: (state) =>
                  setState(() => _playerState = state),
              onSoundFontLoaded: () => setState(() => _sfLoaded = true),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _sfLoaded ? () {} : null,
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  mini: true,
                  onPressed: _sfLoaded
                      ? (isPlaying
                          ? () => _alphaTabKey.currentState?.pause()
                          : () => _alphaTabKey.currentState?.play())
                      : null,
                  backgroundColor: isPlaying ? Colors.red : Colors.brown,
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _sfLoaded ? () {} : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
