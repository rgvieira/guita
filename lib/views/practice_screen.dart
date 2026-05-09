import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/practice_viewmodel.dart';
import '../services/music_parser_service.dart';
import '../widgets/bpm_chart_widget.dart';

class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  @override
  Widget build(BuildContext context) {
    final filePath = ModalRoute.of(context)!.settings.arguments as String;
    final practice = ref.watch(practiceProvider);
    // final scoreAsync = ref.watch(scoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo de Prática'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Configurações',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSlider('BPM Inicial', practice.bpmStart, 20, 200,
                        (v) => ref.read(practiceProvider.notifier).updateBpmStart(v)),
                    _buildSlider('BPM Final', practice.bpmEnd, 20, 200,
                        (v) => ref.read(practiceProvider.notifier).updateBpmEnd(v)),
                    _buildSlider('Incremento', practice.bpmStep, 1, 30,
                        (v) => ref.read(practiceProvider.notifier).updateBpmStep(v)),
                    _buildSlider('Repetições', practice.repetitions, 1, 20,
                        (v) => ref.read(practiceProvider.notifier).updateRepetitions(v)),
                    SwitchListTile(
                      title: const Text('Acelerar progressivamente'),
                      subtitle: Text(
                        practice.accelerate ? 'Lento → Rápido' : 'Rápido → Lento',
                      ),
                      value: practice.accelerate,
                      onChanged: (_) => ref.read(practiceProvider.notifier).toggleAccelerate(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (practice.isRunning)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: practice.progress),
                      const SizedBox(height: 12),
                      Text(
                        'Repetição ${practice.currentRepetition + 1}/${practice.repetitions}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        'BPM atual: ${practice.currentBPM}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.brown,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => ref.read(practiceProvider.notifier).stop(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Parar'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
            if (!practice.isRunning)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _startPractice(filePath),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar Prática'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.brown,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Histórico de Prática',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: BpmChartWidget(sessions: practice.history),
            ),
          ],
        ),
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
          activeColor: Colors.brown,
          onChanged: (v) => onChanged(v.toInt()),
        ),
      ],
    );
  }

  Future<void> _startPractice(String filePath) async {
    try {
      final score = await MusicParserService.parseFile(filePath);
      final notes = score.allNotes;
      if (notes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhuma nota encontrada no arquivo')),
          );
        }
        return;
      }
      ref.read(practiceProvider.notifier).startPractice(notes, score.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }
}
