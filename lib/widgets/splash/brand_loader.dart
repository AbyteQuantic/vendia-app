// Spec: specs/087-splash-loader-animado/spec.md
//
// Loader de marca reutilizable: cicla logos al azar dibujándose mientras la app
// espera. Úsalo en cargas in-app. VendIA + logos al azar, en bucle.

import 'dart:math';

import 'package:flutter/material.dart';

import 'logo_reveal.dart';

class BrandLoader extends StatefulWidget {
  const BrandLoader({super.key, this.size = 120, this.count = 4, this.seed});

  /// Lado del loader (cuadrado).
  final double size;

  /// Cuántos logos cicla antes de repetir el patrón.
  final int count;

  /// Semilla opcional (para tests deterministas).
  final int? seed;

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader> {
  late final List<String> _seq;

  @override
  void initState() {
    super.initState();
    final r = Random(widget.seed);
    // VendIA intercalado + otros al azar (constante de marca).
    final seq = <String>[];
    String? last;
    for (var i = 0; i < widget.count; i++) {
      if (i.isEven) {
        seq.add(SplashAssets.vendia);
      } else {
        last = SplashAssets.randomOther(r, exclude: last);
        seq.add(last);
      }
    }
    _seq = seq;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: LogoSequenceReveal(
        logos: _seq,
        loop: true,
        draw: const Duration(milliseconds: 850),
        hold: const Duration(milliseconds: 500),
        erase: const Duration(milliseconds: 550),
      ),
    );
  }
}
