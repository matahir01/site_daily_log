import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

/// Compresses site photos before they're saved locally, so a full day of
/// camera captures doesn't blow up device storage or slow down PDF/Excel
/// exports that embed the images.
class ImageCompressionService {
  /// Compresses [sourcePath] and writes the result to [destinationPath].
  /// Falls back to a plain file copy if compression fails or isn't
  /// supported for the source format (e.g. an unusual camera file type),
  /// so a photo is never lost.
  static Future<File> compressAndSave({
    required String sourcePath,
    required String destinationPath,
    int quality = 70,
    int minWidth = 1280,
    int minHeight = 1280,
  }) async {
    try {
      final targetPath = _withCompressedSuffix(destinationPath);
      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        quality: quality,
        minWidth: minWidth,
        minHeight: minHeight,
        keepExif: false,
      );
      if (result != null) {
        return File(result.path);
      }
    } catch (_) {
      // Fall through to an uncompressed copy below.
    }
    return File(sourcePath).copy(destinationPath);
  }

  static String _withCompressedSuffix(String path) {
    final ext = p.extension(path);
    final base = path.substring(0, path.length - ext.length);
    // JPEG is universally supported by the compressor across platforms.
    return '$base.jpg';
  }
}
