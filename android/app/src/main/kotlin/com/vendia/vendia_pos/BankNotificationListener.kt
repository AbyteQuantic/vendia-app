package com.vendia.vendia_pos

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Captures bank-app notifications and forwards a sanitized snapshot
 * to Flutter via [BankNotificationBridge].
 *
 * Per the PO mandate ("informative listener"), this listener:
 *
 *  * Filters by package — only Colombian bank / wallet apps reach
 *    the bridge. Anything outside [BANK_PACKAGES] is ignored so we
 *    never see WhatsApp, system notifications, etc.
 *  * Forwards only `bankLabel`, `title` and `text` (already
 *    visible to the user on the lock screen). No intent extras,
 *    no ticker text, no PII beyond what the bank itself surfaces.
 *  * **Never** opens, dismisses or interacts with the notification
 *    — the listener is read-only.
 *  * **Never** drives any UI gate. Flutter only flashes a green
 *    SnackBar; the cashier still has to attach the receipt photo
 *    by hand to enable the "Confirmar pago" button.
 *
 * The listener requires the user to manually grant
 * "Acceso a notificaciones" in Settings — Android does not allow
 * this permission to be requested at runtime. The Dart layer is
 * responsible for guiding the user to that screen if they want
 * the convenience banner; the cashier flow works without it.
 */
class BankNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        val bankLabel = BANK_PACKAGES[notification.packageName] ?: return

        val extras = notification.notification?.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()

        BankNotificationBridge.publish(
            bankLabel = bankLabel,
            title = title,
            text = text,
        )
    }

    /**
     * Notifications being dismissed/cleared are not interesting
     * for the cashier flow — only freshly posted ones flash the
     * SnackBar. Override is left empty on purpose.
     */
    override fun onNotificationRemoved(sbn: StatusBarNotification?) = Unit

    private companion object {
        /**
         * Package → human-readable bank label allowlist. Entries are
         * the official Play Store package names. Adding a bank here
         * is the only place the listener needs to be touched —
         * the Dart layer pivots off `bankLabel` for the SnackBar.
         */
        val BANK_PACKAGES: Map<String, String> = mapOf(
            "com.nequi.MobileApp" to "Nequi",
            "com.todo1.daviplata" to "Daviplata",
            "com.davivienda.daviplata" to "Daviplata",
            "com.bancolombia.banca.movil" to "Bancolombia",
            "com.bancolombia.app.personas" to "Bancolombia",
            "co.com.bbva.bbvanetcash" to "BBVA",
            "com.davivienda.movil" to "Davivienda",
            "co.com.colpatria.smartkey" to "Scotiabank Colpatria",
            "com.bbva.netcash" to "BBVA",
            "com.bog.bog.transac" to "Banco de Bogotá",
        )
    }
}
