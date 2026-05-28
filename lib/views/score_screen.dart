import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:guitar/services/audio_effects_service.dart';
import 'package:guitar/widgets/alpha_tab_view.dart';
import 'package:guitar/widgets/effects_sheet.dart';
import 'package:guitar/widgets/waveform_visualizer.dart';
import 'package:guitar/widgets/practice_panel.dart';
import 'package:guitar/services/practice_service.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  final _nativeKey = GlobalKey<AlphaTabViewState>();
  final _effectsService = AudioEffectsService();
  final _practiceService = PracticeService();
  String _filePath = '';
  int _playerState = 0;
  bool _isHorizontal = false;
  bool _effectsInited = false;
  String? _errorMessage;
  int _trackCount = 1;
  int _currentTrack = 0;
  List<String> _trackNames = [];
  bool _showPractice = false;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _practiceService.onSpeedChanged = (speed) {
      _nativeKey.currentState?.setPlaybackSpeed(speed);
    };
    _practiceService.onPlay = () {
      _nativeKey.currentState?.play();
    };
    _practiceService.onStopPlayback = () {
      _nativeKey.currentState?.stop();
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args != _filePath) {
      _filePath = args;
      _errorMessage = null;
      _isHorizontal = false;
      _playerState = 0;
      _trackCount = 1;
      _currentTrack = 0;
      _trackNames = [];
      _showPractice = false;
      _practiceService.stop();
    }
  }

  @override
  void dispose() {
    _effectsService.release();
    _practiceService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasTracks = _trackCount > 1;
    final isPlaying = _playerState == 1;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/icon/icon.png',
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.music_note, size: 28),
          ),
        ),
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
              tooltip: 'Imprimir',
              onPressed: _isPrinting ? null : _printScore,
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.tune, color: _showPractice ? Colors.blue : null),
            tooltip: 'Modo de Prática',
            onPressed: () => setState(() => _showPractice = !_showPractice),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.equalizer),
            tooltip: 'Efeitos',
            onPressed: _openEffects,
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.red.shade50,
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                Expanded(child: _buildScoreView()),
                if (isPlaying && _isHorizontal)
                  const SizedBox(
                    height: 120,
                    child: WaveformVisualizer(isPlaying: true),
                  ),
                _buildBottomBar(hasTracks, isPlaying),
              ],
            ),
          ),
          if (_showPractice)
            PracticePanel(
              service: _practiceService,
              onClose: () => setState(() => _showPractice = false),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreView() {
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
      onTrackData: () => setState(() {
        final names = _nativeKey.currentState?.trackNames;
        if (names != null) {
          _trackNames = names;
          _trackCount = names.length;
        }
      }),
    );
  }

  Widget _buildBottomBar(bool hasTracks, bool isPlaying) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1),
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
                _nativeKey.currentState?.pause();
              } else {
                _nativeKey.currentState?.play();
              }
            },
            backgroundColor: isPlaying ? Colors.red : Colors.black,
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
    final displayNames = _trackNames.isNotEmpty ? _trackNames : null;
    return SizedBox(
      width: 160,
      child: DropdownButton<int>(
        value: _currentTrack.clamp(0, _trackCount - 1),
        isExpanded: true,
        items: List.generate(_trackCount, (i) {
          String label;
          if (displayNames != null &&
              i < displayNames.length &&
              displayNames[i].isNotEmpty) {
            label = displayNames[i];
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '${_currentTrack + 1}/$_trackCount',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
      ),
    );
  }

  void _toggleLayout() {
    _nativeKey.currentState?.toggleLayout().then((h) {
      setState(() => _isHorizontal = h);
    });
  }

  void _openEffects() {
    if (!_effectsInited) {
      _effectsService.init().then((_) {
        if (mounted) setState(() => _effectsInited = true);
        _showEffectsSheet();
      });
    } else {
      _showEffectsSheet();
    }
  }

  void _showEffectsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EffectsSheet(
        service: _effectsService,
        onVolumeChanged: (vol) {
          _nativeKey.currentState?.setVolume(vol);
        },
      ),
    );
  }

  Future<void> _printScore() async {
    try {
      final nativeState = _nativeKey.currentState;
      if (nativeState == null) return;

      if (mounted) setState(() => _isPrinting = true);
      final currentTrackIndex = _currentTrack;

      // Mostrar feedback de que está "trabalhando"
      if (mounted) {
        unawaited(
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const PopScope(
              canPop: false,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Capturando páginas...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      debugPrint('Iniciando captura nativa...');

      // O erro do spinner "cair" sem mensagem geralmente é uma PlatformException
      // que não está sendo tratada corretamente no fluxo assíncrono.
      final List<dynamic> rawList = await nativeState.printScore().timeout(
        const Duration(seconds: 60),
      );

      final pngList = rawList.cast<Uint8List>();

      // Fecha o dialog apenas se ele ainda estiver lá
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (pngList.isEmpty) {
        throw 'O motor nativo retornou uma lista vazia.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Capturado: ${pngList.length} páginas. Montando PDF...',
            ),
          ),
        );
      }

      final doc = pw.Document();
      for (final pngBytes in pngList) {
        if (pngBytes.isEmpty) continue;

        final image = pw.MemoryImage(pngBytes);

        // Se a largura da imagem for maior que a altura, o alphaTab capturou em modo horizontal
        // Precisamos ajustar o PDF para Paisagem para a partitura não ficar minúscula (o "fiapo")
        final isLandscape = (image.width ?? 0) > (image.height ?? 0);
        final format = isLandscape
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4;

        doc.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.zero,
            build: (ctx) => pw.FullPage(
              ignoreMargins: true, // Remove margens extras do PDF
              child: pw.Image(
                image,
                // BoxFit.fitWidth garante que a partitura use toda a largura do papel
                fit: isLandscape ? pw.BoxFit.contain : pw.BoxFit.fitWidth,
                alignment: pw.Alignment.topCenter,
              ),
            ),
          ),
        );
      }

      final fileName = _filePath.split(RegExp(r'[\\/]')).last;
      final baseName = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;

      final trackName =
          _trackNames.isNotEmpty && currentTrackIndex < _trackNames.length
          ? _trackNames[currentTrackIndex]
          : 'faixa${currentTrackIndex + 1}';

      final safeDocName = '${baseName}_$trackName'
          .replaceAll(RegExp(r'[^\w\-]'), '_')
          .replaceAll(' ', '_');

      await Printing.sharePdf(
        bytes: await doc.save(),
        // A extensão .pdf no filename é vital para o Intent funcionar
        filename: '$safeDocName.pdf',
      );
    } on TimeoutException {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showErrorSnackBar(
        'Tempo esgotado. A partitura é muito grande ou o motor travou.',
      );
    } catch (e) {
      debugPrint('Erro na impressão: $e');
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showErrorSnackBar('Falha na captura: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade800),
    );
  }
}
