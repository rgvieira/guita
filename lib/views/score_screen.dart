import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:guitarra/widgets/alpha_tab_view.dart';
import 'package:guitarra/widgets/midi_score_view.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  final _nativeKey = GlobalKey<AlphaTabViewState>();
  final _midiKey = GlobalKey<MidiScoreViewState>();
  String _filePath = '';
  int _playerState = 0;
  bool _isHorizontal = false;
  bool _isMidiOrKar = false;
  String? _errorMessage;
  List<int> _channels = [];
  int _currentChannel = 0;
  int _trackCount = 1;
  int _currentTrack = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args != _filePath) {
      _filePath = args;
      _errorMessage = null;
      _channels = [];
      _currentChannel = 0;
      _isHorizontal = false;
      _playerState = 0;
      _trackCount = 1;
      _currentTrack = 0;
      final ext = _filePath.split('.').last.toLowerCase();
      _isMidiOrKar = ext == 'mid' || ext == 'midi' || ext == 'kar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTracks = _trackCount > 1 || _channels.length > 1;
    final isPlaying = _playerState == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filePath.split('\\').last.split('/').last,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: Icon(_isHorizontal ? Icons.view_agenda : Icons.view_day),
            tooltip: _isHorizontal ? 'Layout Vertical' : 'Layout Horizontal',
            onPressed: _toggleLayout,
          ),
          const SizedBox(width: 4),
          if (_filePath.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Imprimir / PDF',
              onPressed: _printScore,
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () =>
                Navigator.pushNamed(context, '/practice', arguments: _filePath),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade100,
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          Expanded(child: _buildScoreView()),
          _buildBottomBar(hasTracks, isPlaying),
        ],
      ),
    );
  }

  Widget _buildScoreView() {
    if (_isMidiOrKar) {
      return MidiScoreView(
        key: _midiKey,
        filePath: _filePath,
        onChannelsLoaded: (channels) => setState(() {
          _channels = channels;
          _trackCount = channels.length;
          if (channels.isNotEmpty) _currentChannel = channels.first;
        }),
        onError: (msg) => setState(() => _errorMessage = msg),
        onPlayerStateChanged: (s) => setState(() => _playerState = s),
      );
    }
    return AlphaTabView(
      key: _nativeKey,
      filePath: _filePath,
      isHorizontal: _isHorizontal,
      onPlayerStateChanged: (s) => setState(() => _playerState = s),
      onError: (msg) => setState(() => _errorMessage = msg),
      onTrackChanged: (info) {
        if (info == null) return;
        final parts = info.split('/');
        if (parts.length == 2) {
          setState(() {
            _currentTrack = int.tryParse(parts[0]) ?? 0;
            _trackCount = int.tryParse(parts[1]) ?? 1;
          });
        }
      },
      onTrackData: () => setState(() {}),
    );
  }

  Widget _buildBottomBar(bool hasTracks, bool isPlaying) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasTracks) _buildTrackSelector() else const SizedBox(width: 8),
          const SizedBox(width: 8),
          FloatingActionButton(
            mini: true,
            onPressed: () {
              if (isPlaying) {
                if (_isMidiOrKar) {
                  _midiKey.currentState?.pause();
                } else {
                  _nativeKey.currentState?.pause();
                }
              } else {
                if (_isMidiOrKar) {
                  _midiKey.currentState?.play();
                } else {
                  _nativeKey.currentState?.play();
                }
              }
            },
            backgroundColor: isPlaying ? Colors.red : Colors.brown,
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
          ),
          if (hasTracks)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _buildTrackInfo(),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackSelector() {
    if (_isMidiOrKar) {
      return SizedBox(
        width: 160,
        child: DropdownButton<int>(
          value: _channels.contains(_currentChannel)
              ? _currentChannel
              : _channels.firstOrNull ?? 0,
          isExpanded: true,
          items: _channels.map((ch) {
            final name = _midiKey.currentState?.channelNames[ch];
            return DropdownMenuItem<int>(
              value: ch,
              child: Text(
                name ?? 'Canal $ch',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (ch) {
            if (ch == null) return;
            _midiKey.currentState?.setChannel(ch);
            setState(() => _currentChannel = ch);
          },
        ),
      );
    }
    return SizedBox(
      width: 160,
      child: DropdownButton<int>(
        value: _currentTrack.clamp(0, _trackCount - 1),
        isExpanded: true,
        items: List.generate(_trackCount, (i) {
          final names = _nativeKey.currentState?.trackNames;
          String label;
          if (names != null && i < names.length && names[i].isNotEmpty) {
            label = names[i];
          } else {
            label = 'Faixa ${i + 1}';
          }
          return DropdownMenuItem<int>(
            value: i,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (track) {
          if (track == null) return;
          _nativeKey.currentState?.setTrack(track);
          setState(() => _currentTrack = track);
        },
      ),
    );
  }

  Widget _buildTrackInfo() {
    if (_trackCount <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.brown.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.brown.shade200),
      ),
      child: Text(
        '${_currentTrack + 1}/$_trackCount',
        style: TextStyle(fontSize: 11, color: Colors.brown[700]),
      ),
    );
  }

  void _toggleLayout() {
    if (_isMidiOrKar) {
      _midiKey.currentState?.toggleLayout();
      setState(() => _isHorizontal = !_isHorizontal);
    } else {
      _nativeKey.currentState?.toggleLayout().then((h) {
        setState(() => _isHorizontal = h);
      });
    }
  }

  Future<void> _printScore() async {
    try {
      Uint8List pdfBytes;
      if (_isMidiOrKar) {
        final midiState = _midiKey.currentState;
        if (midiState == null) return;
        pdfBytes = await midiState.printScore();
      } else {
        final nativeState = _nativeKey.currentState;
        if (nativeState == null) return;
        final pngList = await nativeState.printScore();
        if (pngList.isEmpty) return;
        final doc = pw.Document();
        for (final pngBytes in pngList) {
          final img = pw.MemoryImage(pngBytes);
          doc.addPage(pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (ctx) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
          ));
        }
        pdfBytes = await doc.save();
      }
      if (pdfBytes.isEmpty) return;
      final baseName = _filePath.split('\\').last.split('/').last.split('.').first;
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '$baseName.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir: $e')),
        );
      }
    }
  }
}
