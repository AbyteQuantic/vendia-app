package com.vendia.vendia_pos

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Single point of contact between [BankNotificationListener] (a
 * background service that runs whenever a bank app posts a
 * notification) and the [io.flutter.plugin.common.MethodChannel]
 * registered by [MainActivity].
 *
 * The listener may fire before Flutter is ready (the user enabled
 * the listener permission, then never opened the app). The bridge
 * therefore keeps the *last* event so MainActivity can replay it on
 * startup, and silently drops events that arrive while the channel
 * is detached.
 *
 * Per the PO mandate the bridge is **purely informative**: the
 * payload is forwarded as-is, without any inference of "amount" or
 * "approved/rejected". The Flutter side is responsible for
 * surfacing the SnackBar — this layer must never gate any UI.
 */
internal object BankNotificationBridge {

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var channel: MethodChannel? = null

    @Volatile
    private var lastPending: Map<String, Any?>? = null

    /** Called by [MainActivity.configureFlutterEngine]. */
    fun attach(channel: MethodChannel) {
        this.channel = channel
        // If a notification arrived before Flutter mounted the
        // channel, replay it once now so the cashier still sees the
        // SnackBar on the next render.
        lastPending?.let { pending ->
            mainHandler.post { channel.invokeMethod("onBankNotification", pending) }
            lastPending = null
        }
    }

    /** Called by [MainActivity.cleanUpFlutterEngine] for symmetry. */
    fun detach() {
        channel = null
    }

    /**
     * Pushes a sanitized notification snapshot to Flutter. We
     * intentionally limit the payload to `bankLabel`, `title` and
     * `text` — the listener never forwards intent extras, ticker
     * text or any other field that could leak transaction data
     * into the Flutter logs.
     */
    fun publish(bankLabel: String, title: String?, text: String?) {
        val payload = mapOf<String, Any?>(
            "bankLabel" to bankLabel,
            "title" to title,
            "text" to text,
        )
        val active = channel
        if (active != null) {
            mainHandler.post { active.invokeMethod("onBankNotification", payload) }
        } else {
            lastPending = payload
        }
    }
}
