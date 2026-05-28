import 'package:flutter/material.dart';
import '../services/practice_service.dart';

class PracticePanel extends StatefulWidget {
  final PracticeService service;
  final VoidCallback onClose;

  const PracticePanel({
    super.key,
    required this.service,
    required this.onClose,
  });

  @override
  State<PracticePanel> createState() => _PracticePanelState();
}

class _PracticePanelState extends State<PracticePanel> {
  int _bpmStart = 60;
  int _bpmEnd = 120;
  int _bpmStep = 10;
  int _repetitions = 3;
  bool _accelerate = true;

  @override
  void initState() {
    super.initState();
    widget.service.onStateChanged = _onState;
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.onStateChanged = null;
    super.dispose();
  }

  Future<void> _start() async {
    widget.service.stop();
    await widget.service.runPractice(
      bpmStart: _bpmStart,
      bpmEnd: _bpmEnd,
      bpmStep: _bpmStep,
      repetitions: _repetitions,
      accelerate: _accelerate,
      onSpeedChange: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.service;
    return Container(
      width: 280,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('Prática',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _slider('BPM Inicial', _bpmStart, 20, 200,
                      (v) => setState(() => _bpmStart = v)),
                  _slider('BPM Final', _bpmEnd, 20, 200,
                      (v) => setState(() => _bpmEnd = v)),
                  _slider('Incremento', _bpmStep, 1, 30,
                      (v) => setState(() => _bpmStep = v)),
                  _slider('Repetições', _repetitions, 1, 20,
                      (v) => setState(() => _repetitions = v)),
                  SwitchListTile(
                    title: const Text('Acelerar', style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      _accelerate ? 'Lento → Rápido' : 'Rápido → Lento',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: _accelerate,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (_) => setState(() => _accelerate = !_accelerate),
                  ),
                  const SizedBox(height: 12),
                  if (svc.isRunning) ...[
                    LinearProgressIndicator(value: svc.progress),
                    const SizedBox(height: 8),
                    Text('Rep ${svc.currentRepetition + 1}/${_repetitions}',
                        style: const TextStyle(fontSize: 13)),
                    Text('BPM: ${svc.currentBPM}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => widget.service.stop(),
                        icon: const Icon(Icons.stop, size: 18),
                        label: const Text('Parar'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Iniciar'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, int value, int min, int max,
      ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value', style: const TextStyle(fontSize: 12)),
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
