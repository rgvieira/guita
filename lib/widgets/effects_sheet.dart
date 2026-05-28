import 'package:flutter/material.dart';
import '../services/audio_effects_service.dart';

class EffectsSheet extends StatefulWidget {
  final AudioEffectsService service;
  final void Function(double volume) onVolumeChanged;

  const EffectsSheet({super.key, required this.service, required this.onVolumeChanged});

  @override
  State<EffectsSheet> createState() => _EffectsSheetState();
}

class _EffectsSheetState extends State<EffectsSheet> {
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _volume = widget.service.masterVolume;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 16),
          const Text('Efeitos Sonoros',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),

          _buildSlider('Volume', Icons.volume_up, _volume, 0, 1.0, (v) {
            setState(() => _volume = v);
            widget.service.setVolume(v);
            widget.onVolumeChanged(v);
          }),

          const Divider(),

          const Text(
            'Equalizador, Reverb, BassBoost e outros efeitos\n'
            'não são compatíveis com o motor de áudio alphaTab.\n'
            'Apenas controle de volume está disponível.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),

          const SizedBox(height: 16),

          Center(
            child: TextButton.icon(
              onPressed: () {
                setState(() => _volume = 1.0);
                widget.service.setVolume(1.0);
              },
              icon: const Icon(Icons.restore),
              label: const Text('Volume Máximo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, IconData icon, double value,
      double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black),
          const SizedBox(width: 8),
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Slider(
              value: value, min: min, max: max,
              divisions: 20,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
