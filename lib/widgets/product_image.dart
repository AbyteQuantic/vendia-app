// Spec: specs/090-lazyload-imagenes/spec.md
//
// Imagen de producto con CACHÉ EN DISCO (móvil) + placeholder + manejo de error.
// Reemplaza Image.network para no re-descargar las fotos en cada apertura — ahorra
// los datos prepago del tendero. En web usa la caché del navegador (las grillas ya
// son .builder, así que solo se piden las visibles).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/supabase_image.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.url,
    this.height,
    this.width = double.infinity,
    this.fit = BoxFit.contain,
    this.placeholder,
  });

  final String? url;
  final double? height;
  final double? width;
  final BoxFit fit;

  /// Placeholder/errorWidget opcional (para reusar el de cada pantalla).
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? _defaultPlaceholder();
    if (url == null || url!.isEmpty) return ph;
    // Spec 090: si la foto vive en NUESTRO Supabase Storage, pide una
    // miniatura redimensionada (≈10× menos bytes) en vez del PNG original.
    // Fotos externas / R2 / ya-transformadas se dejan intactas.
    final resolvedUrl = optimizedProductImageUrl(
      url,
      width: width,
      height: height,
    );
    return CachedNetworkImage(
      imageUrl: resolvedUrl,
      height: height,
      width: width,
      fit: fit,
      // Decodifica al tamaño de la tile (×3 cubre el DPR) — menos CPU/memoria.
      memCacheHeight: height != null ? (height! * 3).round() : null,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => ph,
      errorWidget: (_, __, ___) => ph,
    );
  }

  Widget _defaultPlaceholder() => Container(
        height: height,
        width: width,
        color: const Color(0xFFF0F4FF),
        child: const Center(
          child: Icon(Icons.inventory_2_rounded,
              color: AppTheme.primary, size: 32),
        ),
      );
}
