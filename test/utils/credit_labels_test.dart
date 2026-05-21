// Spec: specs/028-copy-fiar-credito-configurable/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/credit_labels.dart';

void main() {
  group('CreditLabels — modo fiar (default)', () {
    const labels = CreditLabels('fiar');

    test('verbInfinitive', () => expect(labels.verbInfinitive, 'fiar'));
    test('verbAction', () => expect(labels.verbAction, 'Fiar'));
    test('verbActionShort', () => expect(labels.verbActionShort, 'Fiar'));
    test('nounSingular', () => expect(labels.nounSingular, 'fiado'));
    test('nounSingularCapitalized',
        () => expect(labels.nounSingularCapitalized, 'Fiado'));
    test('nounPlural', () => expect(labels.nounPlural, 'fiados'));
    test('nounPluralCapitalized',
        () => expect(labels.nounPluralCapitalized, 'Fiados'));
    test('cuadernoTitle',
        () => expect(labels.cuadernoTitle, 'Cuaderno de fiados'));
    test('screenTitle', () => expect(labels.screenTitle, 'Mis fiados'));
    test('navLabel', () => expect(labels.navLabel, 'Fiados'));
    test('configTitle',
        () => expect(labels.configTitle, 'Configuración de Fiados'));
    test('analyticsLabel',
        () => expect(labels.analyticsLabel, 'Cuentas por Cobrar (El Fiar)'));
    test('customerHasOpenAccount',
        () => expect(labels.customerHasOpenAccount, 'tiene un fiado abierto'));
    test('whatsappReminderIntro',
        () => expect(labels.whatsappReminderIntro, 'Te recordamos tu fiado'));
    test('receiptHeader',
        () => expect(labels.receiptHeader, 'Comprobante de fiado'));
    test('checkoutChipLabel', () => expect(labels.checkoutChipLabel, 'Fiar'));
    test('fiarClienteLabel',
        () => expect(labels.fiarClienteLabel, 'Fiar a un Cliente'));
    test('registrarLabel',
        () => expect(labels.registrarLabel, 'Registrar Fiado'));
    test('pendingAcceptanceMsg',
        () => expect(labels.pendingAcceptanceMsg,
            'cuando el cliente acepte el fiado.'));
    test('newAccountDescription',
        () => expect(labels.newAccountDescription,
            'Para un cliente que nunca le ha fiado. Se envía un link para que acepte.'));
    test('cancelActionLabel',
        () => expect(labels.cancelActionLabel,
            '✖  Cancelar fiado y devolver al stock'));
    test('cancelledMsg', () => expect(labels.cancelledMsg, 'Fiado cancelado.'));
    test('cancelDialogButton',
        () => expect(labels.cancelDialogButton, 'Cancelar fiado'));
    test('cancelDialogBody',
        () => expect(labels.cancelDialogBody('María', '\$5.000'),
            'El fiado de María por \$5.000 se anulará. Los productos vuelven al stock.'));
    test('addToAccountHint',
        () => expect(labels.addToAccountHint, contains('"Fiado"')));
    test('theAccountArticle',
        () => expect(labels.theAccountArticle, 'el fiado'));
    test('totalCreditLabel',
        () => expect(labels.totalCreditLabel, 'Total fiado:'));
    test('historialLabel',
        () => expect(labels.historialLabel, 'Historial de ventas fiadas'));
    test('emptyRecordsLabel',
        () => expect(labels.emptyRecordsLabel, 'Sin registros de fiado'));
    test('periodLabel', () => expect(labels.periodLabel, 'Fiado del período'));
    test('totalReceivablesLabel',
        () => expect(labels.totalReceivablesLabel,
            'Total cuentas por cobrar (todos los fiados abiertos)'));
    test('manyTodayTitle',
        () => expect(labels.manyTodayTitle, 'Muchos fiados hoy'));
    test('manyTodayBody', () => expect(labels.manyTodayBody, contains('Fiados')));
    test('paymentSetupHint',
        () => expect(labels.paymentSetupHint, contains('fiado')));
    test('pinActionDescription',
        () => expect(labels.pinActionDescription, 'fiar a un cliente nuevo'));
    test('openNewAccountPinHint',
        () => expect(labels.openNewAccountPinHint, contains('fiado nuevo')));
    test('employeeRoleDescription',
        () => expect(labels.employeeRoleDescription, 'Solo puede vender y fiar'));
    test('registeredAccountMsg',
        () => expect(labels.registeredAccountMsg('Tienda X'), contains('un fiado')));
    test('sendingStatusMsg',
        () => expect(labels.sendingStatusMsg,
            'Preparando solicitud de fiado...'));
    test('reviewingTermsMsg',
        () => expect(labels.reviewingTermsMsg('Ana'),
            'Ana esta revisando los terminos del fiado'));
    test('createErrorMsg',
        () => expect(labels.createErrorMsg, 'Error al crear fiado'));
    test('cartLabel', () => expect(labels.cartLabel, 'Fiado'));
    test('cartLabelWithName',
        () => expect(labels.cartLabelWithName('Juan'), 'Fiado: Juan'));
    test('acceptedNotificationMsg',
        () => expect(labels.acceptedNotificationMsg,
            'Fiado aceptado por el cliente. Slot liberado.'));
    test('hubNavDescription',
        () => expect(labels.hubNavDescription, contains('Fiados')));
  });

  group('CreditLabels — modo credit', () {
    const labels = CreditLabels('credit');

    test('verbInfinitive',
        () => expect(labels.verbInfinitive, 'vender a crédito'));
    test('verbAction',
        () => expect(labels.verbAction, 'Vender a crédito'));
    test('verbActionShort', () => expect(labels.verbActionShort, 'A crédito'));
    test('nounSingular', () => expect(labels.nounSingular, 'venta a crédito'));
    test('nounSingularCapitalized',
        () => expect(labels.nounSingularCapitalized, 'Venta a crédito'));
    test('nounPlural',
        () => expect(labels.nounPlural, 'ventas a crédito'));
    test('nounPluralCapitalized',
        () => expect(labels.nounPluralCapitalized, 'Ventas a crédito'));
    test('cuadernoTitle',
        () => expect(labels.cuadernoTitle, 'Cuaderno de créditos'));
    test('screenTitle',
        () => expect(labels.screenTitle, 'Mis ventas a crédito'));
    test('navLabel', () => expect(labels.navLabel, 'Créditos'));
    test('configTitle',
        () => expect(labels.configTitle, 'Configuración de Créditos'));
    test('analyticsLabel',
        () => expect(labels.analyticsLabel,
            'Cuentas por Cobrar (Créditos)'));
    test('customerHasOpenAccount',
        () => expect(labels.customerHasOpenAccount,
            'tiene una venta a crédito abierta'));
    test('whatsappReminderIntro',
        () => expect(labels.whatsappReminderIntro,
            'Te recordamos tu venta a crédito'));
    test('receiptHeader',
        () => expect(labels.receiptHeader,
            'Comprobante de venta a crédito'));
    test('checkoutChipLabel',
        () => expect(labels.checkoutChipLabel, 'A crédito'));
    test('fiarClienteLabel',
        () => expect(labels.fiarClienteLabel,
            'Vender a Crédito a un Cliente'));
    test('registrarLabel',
        () => expect(labels.registrarLabel, 'Registrar Venta a Crédito'));
    test('pendingAcceptanceMsg',
        () => expect(labels.pendingAcceptanceMsg,
            'cuando el cliente acepte la venta a crédito.'));
    test('newAccountDescription',
        () => expect(labels.newAccountDescription,
            contains('venta a crédito')));
    test('cancelActionLabel',
        () => expect(labels.cancelActionLabel,
            '✖  Cancelar crédito y devolver al stock'));
    test('cancelledMsg',
        () => expect(labels.cancelledMsg, 'Crédito cancelado.'));
    test('cancelDialogButton',
        () => expect(labels.cancelDialogButton, 'Cancelar crédito'));
    test('cancelDialogBody',
        () => expect(labels.cancelDialogBody('María', '\$5.000'),
            'La venta a crédito de María por \$5.000 se anulará. Los productos vuelven al stock.'));
    test('addToAccountHint',
        () => expect(labels.addToAccountHint, contains('"A crédito"')));
    test('theAccountArticle',
        () => expect(labels.theAccountArticle, 'la venta a crédito'));
    test('totalCreditLabel',
        () => expect(labels.totalCreditLabel, 'Total a crédito:'));
    test('historialLabel',
        () => expect(labels.historialLabel,
            'Historial de ventas a crédito'));
    test('emptyRecordsLabel',
        () => expect(labels.emptyRecordsLabel, 'Sin registros de crédito'));
    test('periodLabel',
        () => expect(labels.periodLabel, 'Crédito del período'));
    test('totalReceivablesLabel',
        () => expect(labels.totalReceivablesLabel,
            'Total cuentas por cobrar (todos los créditos abiertos)'));
    test('manyTodayTitle',
        () => expect(labels.manyTodayTitle, 'Muchos créditos hoy'));
    test('manyTodayBody',
        () => expect(labels.manyTodayBody, contains('Créditos')));
    test('paymentSetupHint',
        () => expect(labels.paymentSetupHint, contains('crédito')));
    test('pinActionDescription',
        () => expect(labels.pinActionDescription,
            'vender a crédito a un cliente nuevo'));
    test('openNewAccountPinHint',
        () => expect(labels.openNewAccountPinHint, contains('crédito nueva')));
    test('employeeRoleDescription',
        () => expect(labels.employeeRoleDescription,
            'Solo puede vender y dar crédito'));
    test('registeredAccountMsg',
        () => expect(labels.registeredAccountMsg('Tienda X'),
            contains('una venta a crédito')));
    test('sendingStatusMsg',
        () => expect(labels.sendingStatusMsg,
            'Preparando solicitud de crédito...'));
    test('reviewingTermsMsg',
        () => expect(labels.reviewingTermsMsg('Ana'),
            'Ana esta revisando los terminos del crédito'));
    test('createErrorMsg',
        () => expect(labels.createErrorMsg, 'Error al crear crédito'));
    test('cartLabel', () => expect(labels.cartLabel, 'Crédito'));
    test('cartLabelWithName',
        () => expect(labels.cartLabelWithName('Juan'), 'Crédito: Juan'));
    test('acceptedNotificationMsg',
        () => expect(labels.acceptedNotificationMsg,
            'Crédito aceptado por el cliente. Slot liberado.'));
    test('hubNavDescription',
        () => expect(labels.hubNavDescription, contains('Créditos')));
  });

  group('CreditLabels.fromMode — fallback a fiar', () {
    test('modo vacío → fiar',
        () => expect(CreditLabels.fromMode('').nounSingular, 'fiado'));
    test('modo desconocido → fiar',
        () => expect(CreditLabels.fromMode('unknown').nounSingular, 'fiado'));
    test('modo null-string → fiar',
        () => expect(CreditLabels.fromMode('null').nounSingular, 'fiado'));
    test('modo credit → credit',
        () => expect(CreditLabels.fromMode('credit').nounSingular, 'venta a crédito'));
    test('modo fiar → fiar',
        () => expect(CreditLabels.fromMode('fiar').nounSingular, 'fiado'));
  });

  group('CreditLabels — constantes estáticas', () {
    test('optionFiarLabel', () => expect(CreditLabels.optionFiarLabel, 'Fiar'));
    test('optionCreditLabel',
        () => expect(CreditLabels.optionCreditLabel, 'Venta a crédito'));
  });
}
