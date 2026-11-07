import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

import '../../../core/errors/app_exception.dart';

Future<Uint8List> prepareItemPhoto(Uint8List bytes) =>
    compute(normalizeItemPhoto, bytes);

/// Rebuild pixels in a new image so EXIF, GPS and camera metadata are discarded.
Uint8List normalizeItemPhoto(Uint8List bytes) {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const AppException('PHOTO_TOO_LARGE', 'Pilih foto di bawah 20 MB.');
  }
  try {
    final decoder = image.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width * info.height > 40000000) {
      throw const FormatException();
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) throw const FormatException();
    var pixels = image.bakeOrientation(decoded);
    if (pixels.width > 1600 || pixels.height > 1600) {
      pixels = image.copyResize(
        pixels,
        width: pixels.width >= pixels.height ? 1600 : null,
        height: pixels.height > pixels.width ? 1600 : null,
        interpolation: image.Interpolation.average,
      );
    }
    final clean = image.Image(
      width: pixels.width,
      height: pixels.height,
      numChannels: 3,
    );
    image.fill(clean, color: image.ColorRgb8(255, 255, 255));
    image.compositeImage(clean, pixels);
    return Uint8List.fromList(image.encodeJpg(clean, quality: 85));
  } catch (_) {
    throw const AppException(
      'INVALID_PHOTO',
      'Foto belum dapat dibaca. Pilih JPEG, PNG, atau WebP yang valid.',
    );
  }
}
