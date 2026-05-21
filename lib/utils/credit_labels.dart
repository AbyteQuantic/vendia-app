// Spec: specs/028-copy-fiar-credito-configurable/spec.md
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

/// Centralizes every user-visible string that depends on the tenant's
/// `credit_label_mode` setting. Two modes are supported:
///   - `'fiar'`   (default) — vocabulario de barrio colombiano.
///   - `'credit'` — vocabulario formal "venta a crédito".
///
/// Usage:
/// ```dart
/// final labels = CreditLabels.of(context);
/// Text(labels.nounPlural);            // 'fiados' o 'ventas a crédito'
/// Text(labels.cuadernoTitle);         // 'Cuaderno de fiados' o 'Cuaderno de créditos'
/// ```
///
/// The static [of] reads the mode stored in [AuthService] via Provider.
/// For tests or contexts without Provider, use the constructor directly:
/// ```dart
/// const labels = CreditLabels('fiar');
/// const labelsCredit = CreditLabels('credit');
/// ```
class CreditLabels {
  final String mode;

  const CreditLabels(this.mode);

  factory CreditLabels.fromMode(String mode) {
    final normalized = (mode == 'credit') ? 'credit' : 'fiar';
    return CreditLabels(normalized);
  }

  /// Read the tenant's mode from [AuthService] via Provider and return
  /// a [CreditLabels] instance. Falls back to `'fiar'` if the Provider
  /// is not in the tree or the stored mode is empty/unknown.
  static CreditLabels of(BuildContext context) {
    try {
      final auth = context.read<AuthService>();
      // AuthService.creditLabelMode is a synchronously-cached String
      // populated on login (alongside featureFlags / businessTypes).
      final mode = auth.creditLabelMode;
      return CreditLabels.fromMode(mode);
    } catch (_) {
      return const CreditLabels('fiar');
    }
  }

  bool get _isCredit => mode == 'credit';

  // ── Verb contexts ────────────────────────────────────────────────────────

  /// Infinitive: "fiar" / "vender a crédito"
  String get verbInfinitive => _isCredit ? 'vender a crédito' : 'fiar';

  /// Action (capitalized verb): "Fiar" / "Vender a crédito"
  String get verbAction => _isCredit ? 'Vender a crédito' : 'Fiar';

  /// Short action label: "Fiar" / "A crédito"
  String get verbActionShort => _isCredit ? 'A crédito' : 'Fiar';

  // ── Noun contexts ────────────────────────────────────────────────────────

  /// Singular noun: "fiado" / "venta a crédito"
  String get nounSingular => _isCredit ? 'venta a crédito' : 'fiado';

  /// Singular noun capitalized: "Fiado" / "Venta a crédito"
  String get nounSingularCapitalized => _isCredit ? 'Venta a crédito' : 'Fiado';

  /// Plural noun: "fiados" / "ventas a crédito"
  String get nounPlural => _isCredit ? 'ventas a crédito' : 'fiados';

  /// Plural noun capitalized: "Fiados" / "Ventas a crédito"
  String get nounPluralCapitalized => _isCredit ? 'Ventas a crédito' : 'Fiados';

  // ── Screen / section title contexts ─────────────────────────────────────

  /// Title for the cuaderno screen: "Cuaderno de fiados" / "Cuaderno de créditos"
  String get cuadernoTitle =>
      _isCredit ? 'Cuaderno de créditos' : 'Cuaderno de fiados';

  /// Short screen title: "Mis fiados" / "Mis ventas a crédito"
  String get screenTitle => _isCredit ? 'Mis ventas a crédito' : 'Mis fiados';

  /// Dashboard navigation label: "Fiados" / "Créditos"
  String get navLabel => _isCredit ? 'Créditos' : 'Fiados';

  /// Config section title: "Configuración de Fiados" / "Configuración de Créditos"
  String get configTitle =>
      _isCredit ? 'Configuración de Créditos' : 'Configuración de Fiados';

  /// Analytics label: "Cuentas por Cobrar (El Fiar)" / "Cuentas por Cobrar (Créditos)"
  String get analyticsLabel =>
      _isCredit ? 'Cuentas por Cobrar (Créditos)' : 'Cuentas por Cobrar (El Fiar)';

  // ── Customer / account contexts ──────────────────────────────────────────

  /// "tiene un fiado abierto" / "tiene una venta a crédito abierta"
  String get customerHasOpenAccount =>
      _isCredit ? 'tiene una venta a crédito abierta' : 'tiene un fiado abierto';

  /// WhatsApp reminder intro: "Te recordamos tu fiado" / "Te recordamos tu venta a crédito"
  String get whatsappReminderIntro =>
      _isCredit ? 'Te recordamos tu venta a crédito' : 'Te recordamos tu fiado';

  /// Receipt header: "Comprobante de fiado" / "Comprobante de venta a crédito"
  String get receiptHeader =>
      _isCredit ? 'Comprobante de venta a crédito' : 'Comprobante de fiado';

  // ── POS / Checkout contexts ───────────────────────────────────────────────

  /// Chip label in checkout: "Fiar" / "A crédito"
  String get checkoutChipLabel => _isCredit ? 'A crédito' : 'Fiar';

  /// Action button CTA: "Fiar a un Cliente" / "Vender a Crédito a un Cliente"
  String get fiarClienteLabel =>
      _isCredit ? 'Vender a Crédito a un Cliente' : 'Fiar a un Cliente';

  /// Registrar dialog title: "Registrar Fiado" / "Registrar Venta a Crédito"
  String get registrarLabel =>
      _isCredit ? 'Registrar Venta a Crédito' : 'Registrar Fiado';

  /// Pending message in success screen: "cuando el cliente acepte el fiado."
  /// / "cuando el cliente acepte la venta a crédito."
  String get pendingAcceptanceMsg =>
      _isCredit
          ? 'cuando el cliente acepte la venta a crédito.'
          : 'cuando el cliente acepte el fiado.';

  /// Description for send-link: "Para un cliente que nunca le ha fiado."
  /// / "Para un cliente nuevo a crédito."
  String get newAccountDescription =>
      _isCredit
          ? 'Para un cliente nuevo. Se envía un link para que acepte la venta a crédito.'
          : 'Para un cliente que nunca le ha fiado. Se envía un link para que acepte.';

  /// "Cancelar fiado y devolver al stock" / "Cancelar crédito y devolver al stock"
  String get cancelActionLabel =>
      _isCredit
          ? '✖  Cancelar crédito y devolver al stock'
          : '✖  Cancelar fiado y devolver al stock';

  /// Toast/snack when cancelled: "Fiado cancelado." / "Crédito cancelado."
  String get cancelledMsg => _isCredit ? 'Crédito cancelado.' : 'Fiado cancelado.';

  /// "Cancelar fiado" dialog button / "Cancelar crédito"
  String get cancelDialogButton => _isCredit ? 'Cancelar crédito' : 'Cancelar fiado';

  /// Body text in cancel dialog: "El fiado de $name" / "La venta a crédito de $name"
  String cancelDialogBody(String name, String amount) =>
      _isCredit
          ? 'La venta a crédito de $name por $amount se anulará. Los productos vuelven al stock.'
          : 'El fiado de $name por $amount se anulará. Los productos vuelven al stock.';

  /// "Para agregar una venta a esta cuenta, haga una venta normal y elija «Fiado» al cobrar."
  String get addToAccountHint =>
      _isCredit
          ? 'Para agregar una venta a esta cuenta, haga una venta normal y elija "A crédito" al cobrar.'
          : 'Para agregar una venta a esta cuenta, haga una venta normal y elija "Fiado" al cobrar.';

  /// "el fiado" / "la venta a crédito" — used in inline text like "Actualizar el fiado"
  String get theAccountArticle => _isCredit ? 'la venta a crédito' : 'el fiado';

  // ── Credit detail / history contexts ─────────────────────────────────────

  /// Summary stat label: "Total fiado:" / "Total a crédito:"
  String get totalCreditLabel => _isCredit ? 'Total a crédito:' : 'Total fiado:';

  /// Section header: "Historial de ventas fiadas" / "Historial de ventas a crédito"
  String get historialLabel =>
      _isCredit ? 'Historial de ventas a crédito' : 'Historial de ventas fiadas';

  /// Empty state: "Sin registros de fiado" / "Sin registros de crédito"
  String get emptyRecordsLabel =>
      _isCredit ? 'Sin registros de crédito' : 'Sin registros de fiado';

  // ── Dashboard / financial contexts ────────────────────────────────────────

  /// Financial period label: "Fiado del período" / "Crédito del período"
  String get periodLabel => _isCredit ? 'Crédito del período' : 'Fiado del período';

  /// Financial summary: "Total cuentas por cobrar (todos los fiados abiertos)"
  /// / "Total cuentas por cobrar (todos los créditos abiertos)"
  String get totalReceivablesLabel =>
      _isCredit
          ? 'Total cuentas por cobrar (todos los créditos abiertos)'
          : 'Total cuentas por cobrar (todos los fiados abiertos)';

  /// Sales ideas nudge: "Muchos fiados hoy" / "Muchos créditos hoy"
  String get manyTodayTitle => _isCredit ? 'Muchos créditos hoy' : 'Muchos fiados hoy';

  /// Sales ideas body: "Envie recordatorios por WhatsApp desde el modulo de Fiados."
  String get manyTodayBody =>
      _isCredit
          ? 'Envie recordatorios por WhatsApp desde el modulo de Créditos.'
          : 'Envie recordatorios por WhatsApp desde el modulo de Fiados.';

  /// Payment quick setup hint about client seeing fiado data
  String get paymentSetupHint =>
      _isCredit
          ? 'Configure sus datos de pago. Sus clientes verán estos datos en su cuenta del crédito para pagarle sin errores.'
          : 'Configure sus datos de pago. Sus clientes verán estos datos en su cuenta del fiado para pagarle sin errores.';

  // ── PIN / Security context ─────────────────────────────────────────────────

  /// PIN explanation text fragment: "fiar a un cliente nuevo"
  /// / "vender a crédito a un cliente nuevo"
  String get pinActionDescription =>
      _isCredit
          ? 'vender a crédito a un cliente nuevo'
          : 'fiar a un cliente nuevo';

  /// Checkout gate PIN text: "Para abrir un fiado nuevo, pida al propietario..."
  String get openNewAccountPinHint =>
      _isCredit
          ? 'Para abrir una venta a crédito nueva, pida al propietario que ingrese su PIN de 4 dígitos.'
          : 'Para abrir un fiado nuevo, pida al propietario que ingrese su PIN de 4 dígitos.';

  // ── Employee context ───────────────────────────────────────────────────────

  /// Employee role description: "Solo puede vender y fiar"
  /// / "Solo puede vender y dar crédito"
  String get employeeRoleDescription =>
      _isCredit ? 'Solo puede vender y dar crédito' : 'Solo puede vender y fiar';

  // ── WhatsApp share body context ───────────────────────────────────────────

  /// Body for WhatsApp share: "Hemos registrado un fiado a tu nombre."
  /// / "Hemos registrado una venta a crédito a tu nombre."
  String registeredAccountMsg(String tenantName) =>
      _isCredit
          ? 'Somos de $tenantName. Hemos registrado una venta a crédito a tu nombre. '
          : 'Somos de $tenantName. Hemos registrado un fiado a tu nombre. ';

  // ── Status sending context ────────────────────────────────────────────────

  /// "Preparando solicitud de fiado..." / "Preparando solicitud de crédito..."
  String get sendingStatusMsg =>
      _isCredit ? 'Preparando solicitud de crédito...' : 'Preparando solicitud de fiado...';

  /// Waiting text: "$name esta revisando los terminos del fiado"
  /// / "$name esta revisando los terminos del crédito"
  String reviewingTermsMsg(String name) =>
      _isCredit
          ? '$name esta revisando los terminos del crédito'
          : '$name esta revisando los terminos del fiado';

  // ── Error context ─────────────────────────────────────────────────────────

  /// Generic error: "Error al crear fiado" / "Error al crear crédito"
  String get createErrorMsg => _isCredit ? 'Error al crear crédito' : 'Error al crear fiado';

  // ── Cart label context ────────────────────────────────────────────────────

  /// Cart row label: "Fiado" / "Crédito"  (when no customer name)
  String get cartLabel => _isCredit ? 'Crédito' : 'Fiado';

  /// Cart row label with customer: "Fiado: $name" / "Crédito: $name"
  String cartLabelWithName(String name) =>
      _isCredit ? 'Crédito: $name' : 'Fiado: $name';

  // ── Notification/badge context ────────────────────────────────────────────

  /// POS notification: "Fiado aceptado por el cliente. Slot liberado."
  /// / "Crédito aceptado por el cliente. Slot liberado."
  String get acceptedNotificationMsg =>
      _isCredit
          ? 'Crédito aceptado por el cliente. Slot liberado.'
          : 'Fiado aceptado por el cliente. Slot liberado.';

  // ── Dashboard nav description ─────────────────────────────────────────────

  /// Dashboard hub tile text: "Mesas, Fiados, Empleados y Perfil"
  /// / "Mesas, Créditos, Empleados y Perfil"
  String get hubNavDescription =>
      _isCredit
          ? 'Mesas, Créditos, Empleados y Perfil'
          : 'Mesas, Fiados, Empleados y Perfil';

  // ── Vocabulary selector (F028 toggle) ────────────────────────────────────

  /// Label for 'fiar' option in the segmented control
  static const String optionFiarLabel = 'Fiar';

  /// Label for 'credit' option in the segmented control
  static const String optionCreditLabel = 'Venta a crédito';
}
