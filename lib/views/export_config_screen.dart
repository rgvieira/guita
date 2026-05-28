import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../viewmodels/score_viewmodel.dart';
import '../painters/score_painter.dart';
import '../painters/tab_painter.dart';

class ExportConfigScreen extends ConsumerStatefulWidget {
  const ExportConfigScreen({super.key});

  @override
  ConsumerState<ExportConfigScreen> createState() => _ExportConfigScreenState();
}

class _ExportConfigScreenState extends ConsumerState<ExportConfigScreen> {
  bool includeScore = true;
  bool includeTab = true;
  bool includeChords = false;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args == null) {
      return const Scaffold(
        body: Center(child: Text('Nenhum arquivo selecionado')),
      );
    }
    final filePath = args as String;

    final scoreAsync = ref.watch(scoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Exportar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                      'Conteúdo para exportar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Partitura'),
                    subtitle: const Text('Pentagrama com notas'),
                    value: includeScore,
                    onChanged: (v) => setState(() => includeScore = v!),
                    activeColor: Colors.black,
                  ),
                  CheckboxListTile(
                    title: const Text('Tablatura'),
                    subtitle: const Text('Cordas e casas'),
                    value: includeTab,
                    onChanged: (v) => setState(() => includeTab = v!),
                    activeColor: Colors.black,
                  ),
                  CheckboxListTile(
                    title: const Text('Cifras'),
                    subtitle: const Text('Nomes de acordes'),
                    value: includeChords,
                    onChanged: (v) => setState(() => includeChords = v!),
                    activeColor: Colors.black,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (scoreAsync.hasValue && scoreAsync.value != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preview: ${scoreAsync.value!.title}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${scoreAsync.value!.allNotes.length} notas | ${scoreAsync.value!.measures.length} compassos',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : () => _export(filePath),
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              label: const Text('Imprimir / Gerar PDF'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(String filePath) async {
    setState(() => _exporting = true);
    try {
      final score = ref.read(scoreProvider).valueOrNull;
      if (score == null) throw Exception('Nenhuma partitura carregada');

      if (!includeScore && !includeTab) {
        throw Exception('Selecione ao menos um elemento para exportar');
      }

      final dir = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${dir.path}/guitar2_exports');
      if (!await outputDir.exists()) await outputDir.create(recursive: true);

      final title = score.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outFile = File('${outputDir.path}/${title}_$timestamp.pdf');

      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);

      final notes = score.allNotes;
      final width = (notes.length * 40.0 + 100.0).clamp(400.0, 5000.0);
      double height = 0;

      if (includeTab) height += 130;
      if (includeScore) height += 200;

      if (includeScore) {
        final sp = ScorePainter(notes: notes);
        sp.paint(canvas, Size(width, 200));
        canvas.translate(0, 200);
      }

      if (includeTab) {
        final tp = TabPainter(notes: notes);
        tp.paint(canvas, Size(width, 130));
      }

      final picture = pictureRecorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) throw Exception('Falha ao gerar imagem');

      final uint8List = byteData.buffer.asUint8List();
      final image = pw.MemoryImage(uint8List);

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          },
        ),
      );

      final pdfBytes = await pdf.save();

      // Garantir nome válido
      final fileName = title.isEmpty ? "exportacao_guitar2" : title;

      final printSuccess = await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: fileName,
      );

      if (printSuccess) {
        // Salva cópia local apenas se abriu a impressora
        await outFile.writeAsBytes(pdfBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Documento pronto!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Impressão cancelada.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _exporting = false);
    }
  }
}
