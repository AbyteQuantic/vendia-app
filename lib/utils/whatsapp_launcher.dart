// Spec: specs/055-cuenta-mesa-whatsapp/spec.md
//
// Helper centralizado para abrir WhatsApp con un mensaje precargado.
// Antes cada pantalla (promos, cotizaciones, eventos…) repetía la misma
// normalización + launchUrl; acá queda una sola fuente de verdad.

import 'package:url_launcher/url_launcher.dart';

/// Normaliza un teléfono colombiano al formato que espera `wa.me`:
/// solo dígitos y, si son 10 dígitos que empiezan por 3 (celular CO),
/// antepone el indicativo país 57. Si ya trae indicativo u otro formato
/// se deja tal cual (solo dígitos).
String normalizeCoWhatsappNumber(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length == 10 && digits.startsWith('3')) {
    digits = '57$digits';
  }
  return digits;
}

/// Abre WhatsApp con [message] precargado, dirigido a [phone] (CO).
///
/// Usa `wa.me/<num>?text=` DIRIGIDO al número porque sin número el
/// mensaje queda vacío en iPhone (gotcha documentado en send_quote_sheet).
/// Devuelve `false` si el número quedó vacío tras normalizar o si no se
/// pudo abrir WhatsApp (sin instalar / navegador lo bloquea).
Future<bool> launchWhatsapp({
  required String phone,
  required String message,
  Future<bool> Function(Uri, {LaunchMode mode})? launcher,
}) async {
  final digits = normalizeCoWhatsappNumber(phone);
  if (digits.isEmpty) return false;
  final text = Uri.encodeComponent(message);
  final uri = Uri.parse('https://wa.me/$digits?text=$text');
  final launch = launcher ?? launchUrl;
  try {
    return await launch(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
