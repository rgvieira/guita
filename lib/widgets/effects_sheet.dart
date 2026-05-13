import 'package:flutter/material.dart';
import '../services/audio_effects_service.dart';

class EffectsSheet extends StatefulWidget {
  final AudioEffectsService service;

  const EffectsSheet({super.key, required this.service});

  @override
  State<EffectsSheet> createState() => _EffectsSheetState();
}

class _EffectsSheetState extends State<EffectsSheet> {
  final List<double> _eqValues = [];
  double _volume = 1.0;
  double _bassBoost = 0;
  double _delayMs = 0;
  double _delayFb = 0;
  double _distortion = 0;
  int _reverbIdx = 0;

  static const List<String> reverbNames = [
    'Desligado', 'Sala Pequena', 'Sala Média', 'Sala Grande', 'Hall', 'Catedral'
  ];
  static const List<int> reverbValues = [0, 1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    final svc = widget.service;
    _volume = svc.masterVolume;
    _bassBoost = svc.bassBoost.toDouble();
    _delayMs = svc.delayMs.toDouble();
    _delayFb = svc.delayFeedback;
    _distortion = svc.distortionDrive.toDouble();
    _reverbIdx = reverbValues.indexOf(svc.reverbPreset).clamp(0, reverbNames.length - 1);
    _eqValues.clear();
    for (int i = 0; i < svc.bandCount; i++) {
      _eqValues.add(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.service;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.brown.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.brown.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 16),
          const Text('Efeitos Sonoros',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),

          // Volume
          _buildSlider('Volume', Icons.volume_up, _volume, 0, 1.0, (v) {
            setState(() => _volume = v);
            svc.setVolume(v);
          }),

          const Divider(),

          // Equalizer
          if (svc.bandCount > 0) ...[
            const Text('Equalizador',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: svc.bandCount,
                itemBuilder: (ctx, i) {
                  final freqHz = svc.bandFreqs.length > i ? svc.bandFreqs[i] : 0;
                  final freqLabel = freqHz >= 1000
                      ? '${(freqHz / 1000).toStringAsFixed(1)}k' : '$freqHz';
                  return Container(
                    width: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Text('${_eqValues[i].abs().round()}dB',
                          style: const TextStyle(fontSize: 9)),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              ),
                              child: Slider(
                                value: _eqValues[i], min: -100, max: 100,
                                divisions: 200,
                                onChanged: (v) => setState(() {
                                  _eqValues[i] = v;
                                  final level = (v * (svc.maxLevel / 100)).round();
                                  svc.setEqBand(i, level);
                                }),
                              ),
                            ),
                          ),
                        ),
                        Text(freqLabel, style: const TextStyle(fontSize: 8)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
          ],

          // Reverb
          _sectionDropdown('Reverb', Icons.music_note, _reverbIdx,
              reverbNames, (i) {
            setState(() => _reverbIdx = i);
            svc.setReverbPreset(reverbValues[i]);
          }),

          // Bass Boost
          _buildSlider('Bass Boost', Icons.hearing, _bassBoost, 0, 1000, (v) {
            setState(() => _bassBoost = v);
            svc.setBassBoost(v.round());
          }),

          const Divider(),

          // Delay
          const Text('Delay / Eco',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          _buildSlider('Tempo (ms)', Icons.timer, _delayMs, 0, 500, (v) {
            setState(() => _delayMs = v);
            svc.delayMs = v.round();
          }),
          _buildSlider('Feedback', Icons.loop, _delayFb, 0, 100, (v) {
            setState(() => _delayFb = v);
            svc.delayFeedback = v / 100;
          }),

          // Distortion
          _buildSlider('Distortion', Icons.waves, _distortion, 0, 100, (v) {
            setState(() => _distortion = v);
            svc.distortionDrive = v.round();
          }),

          const SizedBox(height: 12),

          Center(
            child: TextButton.icon(
              onPressed: () async {
                setState(() {
                  _volume = 1.0;
                  _bassBoost = 0;
                  _delayMs = 0;
                  _delayFb = 0;
                  _distortion = 0;
                  _reverbIdx = 0;
                  for (int i = 0; i < _eqValues.length; i++) {
                    _eqValues[i] = 0;
                  }
                });
                await svc.setReverbPreset(0);
                await svc.setBassBoost(0);
                await svc.setVolume(1.0);
                await svc.setAllEqBands(0);
                svc.delayMs = 0;
                svc.delayFeedback = 0;
                svc.distortionDrive = 0;
              },
              icon: const Icon(Icons.restore),
              label: const Text('Resetar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, IconData icon, double value,
      double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.brown[600]),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Slider(
              value: value, min: min, max: max,
              divisions: max > 100 ? (max / 10).round() : max.round().clamp(1, 1000),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value == value.roundToDouble()
                  ? '${value.round()}'
                  : value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionDropdown(String label, IconData icon, int currentIdx,
      List<String> items, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.brown[600]),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: DropdownButton<int>(
              value: currentIdx.clamp(0, items.length - 1),
              isExpanded: true,
              underline: const SizedBox(),
              items: List.generate(items.length, (i) => DropdownMenuItem(
                value: i,
                child: Text(items[i], style: const TextStyle(fontSize: 12)),
              )),
              onChanged: (i) {
                if (i != null) onChanged(i);
              },
            ),
          ),
        ],
      ),
    );
  }
}
