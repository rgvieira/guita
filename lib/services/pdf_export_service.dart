import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PdfExportService {
  static Future<String> exportToPdf({
    required String title,
    required ui.Image scoreImage,
    required ui.Image? tabImage,
    required List<String> chords,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final outputDir = Directory('${dir.path}/exports');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${outputDir.path}/$title-$timestamp.png';

    final byteData = await scoreImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to render image');

    final file = File(filePath);
    await file.writeAsBytes(byteData.buffer.asUint8List());

    return filePath;
  }
}
