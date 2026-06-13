// Spec: specs/032-email-saliente/spec.md
//
// Canal de envío por email vía `mailto:` del dispositivo (F032).
//
// NO hay infraestructura SMTP. El botón "Email" abre el cliente de
// correo instalado (Gmail / Apple Mail / Outlook) con el mensaje
// precargado — exactamente como el botón WhatsApp usa `wa.me`. El
// usuario manda el correo desde su propia cuenta.
//
// El destinatario (`to`) puede ir vacío: en ese caso el cliente de
// email abre con el campo "Para" en blanco para que el dueño escriba
// la dirección (spec AC-07).
//
// Fallback (spec R1/R2): si el dispositivo no tiene cliente de email
// (`canLaunchUrl` retorna false), se copia el cuerpo al portapapeles y
// `open` retorna `false` para que el caller muestre un snackbar.

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper sin estado para construir y lanzar URIs `mailto:`.
class EmailLauncher {
  const EmailLauncher._();

  /// Regex RFC 5322 simplificada: una parte local sin espacios, una `@`,
  /// un dominio con al menos un punto y un TLD de 2+ letras.
  static final RegExp _emailRe = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9]'
    r'(?:[a-zA-Z0-9-]*[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)*'
    r'\.[a-zA-Z]{2,}$',
  );

  /// `true` si [value] tiene formato de email válido.
  ///
  /// Una cadena vacía o solo espacios se considera **válida** — el
  /// email es opcional en VendIA (F032 AC-07). El caller decide si un
  /// campo vacío es aceptable; este método solo valida el formato
  /// cuando hay contenido.
  static bool isValidEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return true;
    if (v.length > 254) return false;
    return _emailRe.hasMatch(v);
  }

  /// Construye la URI `mailto:` con el destinatario, asunto y cuerpo.
  ///
  /// IMPORTANTE: NO usar `Uri(queryParameters:)` — ese codifica con reglas
  /// de formulario (`application/x-www-form-urlencoded`), donde el espacio
  /// se vuelve `+`. Los clientes de correo NO decodifican `+` a espacio en
  /// `mailto:`, así que el asunto/cuerpo se veían con `+` literales
  /// ("Cotización+COT-2026-0001", "Te+comparto…"). Codificamos a mano con
  /// `Uri.encodeComponent`, que usa `%20` para el espacio y `%0A` para los
  /// saltos de línea — el formato correcto para `mailto:`.
  ///
  /// Si [to] es nulo o vacío, el `mailto:` queda sin destinatario (válido).
  static Uri buildUri({
    required String? to,
    required String subject,
    required String body,
  }) {
    final recipient = (to ?? '').trim();
    final query = 'subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}';
    return Uri.parse('mailto:$recipient?$query');
  }

  /// Abre el cliente de email del dispositivo precargado.
  ///
  /// Retorna `true` si se logró abrir un cliente de email; `false` si
  /// no hay cliente disponible — en ese caso el cuerpo se copia al
  /// portapapeles para que el usuario lo pegue manualmente. El caller
  /// debe mostrar un snackbar cuando el retorno es `false`.
  static Future<bool> open({
    String? to,
    required String subject,
    required String body,
  }) async {
    final uri = buildUri(to: to, subject: subject, body: body);

    bool canLaunch;
    try {
      canLaunch = await canLaunchUrl(uri);
    } catch (_) {
      // Algunos navegadores web lanzan en vez de retornar false.
      canLaunch = false;
    }

    if (!canLaunch) {
      await _copyToClipboard(body);
      return false;
    }

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await _copyToClipboard(body);
      }
      return ok;
    } catch (_) {
      await _copyToClipboard(body);
      return false;
    }
  }

  static Future<void> _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // El clipboard puede no estar disponible en algunos contextos
      // web; no es crítico — el caller ya informa del fallo.
    }
  }

  /// Asunto estándar para una cotización — ej.
  /// `Cotización COT-2026-0001 - Ferretería Demo`.
  static String subjectForQuote({
    required String folio,
    required String tenantName,
  }) {
    final f = folio.isNotEmpty ? folio : 'sin folio';
    return 'Cotización $f - $tenantName';
  }

  /// Asunto estándar para un recordatorio de fiado.
  static String subjectForFiado({required String tenantName}) {
    return 'Recordatorio de cuenta - $tenantName';
  }

  /// Cuerpo de texto plano para enviar una cotización por email.
  ///
  /// Saludo + descripción corta + link público al documento. Texto
  /// plano porque `mailto:` no soporta HTML (spec D2).
  static String quoteBody({
    required String tenantName,
    required String customerName,
    required String folio,
    required String publicLink,
  }) {
    final saludo = customerName.trim().isNotEmpty
        ? 'Hola ${customerName.trim()},'
        : 'Hola,';
    final folioTxt = folio.isNotEmpty ? folio : 'la cotización';
    return '$saludo\n'
        '\n'
        'Le comparto $folioTxt de $tenantName.\n'
        '\n'
        'Puede revisarla y aprobarla aquí:\n'
        '$publicLink\n'
        '\n'
        'Gracias.\n'
        '$tenantName';
  }

  /// Cuerpo de texto plano para un recordatorio de fiado / cuenta.
  ///
  /// Si [publicLink] está vacío, el cuerpo omite la línea del enlace.
  static String fiadoBody({
    required String tenantName,
    required String customerName,
    required String balanceText,
    required String publicLink,
  }) {
    final saludo = customerName.trim().isNotEmpty
        ? 'Hola ${customerName.trim()},'
        : 'Hola,';
    final linkBlock = publicLink.trim().isNotEmpty
        ? '\nPuede ver el detalle aquí:\n${publicLink.trim()}\n'
        : '';
    return '$saludo\n'
        '\n'
        'Te recuerdo que tienes un saldo pendiente de $balanceText '
        'en $tenantName.\n'
        '$linkBlock'
        '\n'
        '¡Gracias por tu preferencia!\n'
        '$tenantName';
  }
}
