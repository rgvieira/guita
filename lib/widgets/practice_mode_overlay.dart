import 'package:flutter/material.dart';
import '../services/practice_service.dart';

class PracticeModeOverlay extends StatefulWidget {
  final VoidCallback onPlayAtSpeed;
  final VoidCallback onStop;
  final int playerState;

  const PracticeModeOverlay({
    super.key,
    required this.onPlayAtSpeed,
    required this.onStop,
    required this.playerState,
  });

  @override
  State<PracticeModeOverlay> createState() => _PracticeModeOverlayState();
}

class _PracticeModeOverlayState extends State<PracticeModeOverlay> {
  final _service = PracticeService();
  int _bpmStart = 60;
  int _bpmEnd = 120;
  int _bpmStep = 10;
  int _repetitions = 3;
  bool _accelerate = true;
  bool _isRunning = false;
  int _currentBPM = 60;
  int _currentRepetition = 0;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _service.onStateChanged = _onPracticeStateChanged;
  }

  void _onPracticeStateChanged() {
    if (mounted) {
      setState(() {
        _isRunning = _service.isRunning;
        _currentBPM = _service.currentBPM;
        _currentRepetition = _service.currentRepetition;
        _progress = _service.progress;
      });
    }
  }

  Future<void> _startPractice() async {
    setState(() {
      _isRunning = true;
      _currentBPM = _bpmStart;
      _currentRepetition = 0;
      _progress = 0;
    });

    await _service.runPractice(
      bpmStart: _bpmStart,
      bpmEnd: _bpmEnd,
      bpmStep: _bpmStep,
      repetitions: _repetitions,
      accelerate: _accelerate,
      onSpeedChange: (bpm) {
        if (mounted) {
          setState(() => _currentBPM = bpm);
        }
      },
    );

    if (mounted) {
      setState(() {
        _isRunning = false;
        _currentBPM = _bpmStart;
        _progress = 0;
      });
    }
  }

  void _stopPractice() {
    _service.stop();
    widget.onStop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Modo de Prática',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildSlider('BPM Inicial', _bpmStart, 20, 200,
                      (v) => setState(() => _bpmStart = v)),
                  _buildSlider('BPM Final', _bpmEnd, 20, 200,
                      (v) => setState(() => _bpmEnd = v)),
                  _buildSlider('Incremento', _bpmStep, 1, 30,
                      (v) => setState(() => _bpmStep = v)),
                  _buildSlider('Repetições', _repetitions, 1, 20,
                      (v) => setState(() => _repetitions = v)),
                  SwitchListTile(
                    title: const Text('Acelerar progressivamente'),
                    subtitle: Text(
                      _accelerate ? 'Lento → Rápido' : 'Rápido → Lento',
                    ),
                    value: _accelerate,
                    onChanged: (_) => setState(() => _accelerate = !_accelerate),
                  ),
                ],
              ),
            ),
          ),
          if (_isRunning)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 12),
                  Text(
                    'Repetição ${_currentRepetition + 1}/$_repetitions',
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    'BPM atual: $_currentBPM',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _stopPractice,
                    icon: const Icon(Icons.stop),
                    label: const Text('Parar'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startPractice,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar Prática'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value'),
        Slider(
          min: min.toDouble(),
          max: max.toDouble(),
          value: value.toDouble(),
          divisions: max - min,
          onChanged: (v) => onChanged(v.toInt()),
        ),
      ],
    );
  }
}
