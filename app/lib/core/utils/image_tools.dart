import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Reduz a foto para no máximo [maxSide] px no maior lado e grava em JPEG.
/// Uma foto de celular de 3–5 MB vira ~40–90 KB — cabe folgado no banco gratuito.
/// Também corrige a rotação da câmera (EXIF). Retorna null se não for imagem.
Future<Uint8List?> shrinkImage(Uint8List bytes, {int maxSide = 600, int quality = 80}) =>
    compute(_shrink, (bytes, maxSide, quality));

Uint8List? _shrink((Uint8List, int, int) args) {
  final (bytes, maxSide, quality) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final big = math.max(oriented.width, oriented.height);
  final resized = big <= maxSide
      ? oriented
      : (oriented.width >= oriented.height
          ? img.copyResize(oriented, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(oriented, height: maxSide, interpolation: img.Interpolation.average));
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}
