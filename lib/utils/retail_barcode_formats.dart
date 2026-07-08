// Spec: specs/100-completar-skus-inventario/spec.md (D3)
//
// Formatos típicos de productos retail Colombia — extraído de
// `scan_screen.dart` para reutilizarlo en la sesión de ráfaga (Spec 100)
// sin duplicar la lista (Art. IX).
//
// ⚠️ EN WEB es obligatorio especificarlos — el motor wasm de
// `mobile_scanner` no detecta nada si la lista queda vacía.
//
// Lista deliberadamente corta y enfocada: muchos formatos confunden
// al ZXing WASM en web, que parsea cada frame contra cada formato
// y a veces salta al "menos probable" en condiciones de baja luz /
// baja resolución, sin emitir el match al callback. Con la lista
// mínima retail-CO el detector se enfoca y emite consistentemente.

import 'package:mobile_scanner/mobile_scanner.dart';

const List<BarcodeFormat> kRetailBarcodeFormats = <BarcodeFormat>[
  BarcodeFormat.ean13, // tiendas / minimercados — el más común
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.code128, // ferreterías / distribuidoras
  BarcodeFormat.qrCode, // SKUs propios en QR
];
