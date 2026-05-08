package com.vendia.vendia_pos

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BANK_NOTIFICATIONS_CHANNEL,
        )
        BankNotificationBridge.attach(channel)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Lets the Flutter side check whether the user has
                // already granted the "Notification access" permission
                // before deciding to show the educational dialog.
                "isListenerEnabled" -> {
                    val flat = Settings.Secure.getString(
                        contentResolver,
                        "enabled_notification_listeners",
                    ) ?: ""
                    val enabled = flat.split(":").any { component ->
                        component.startsWith("$packageName/")
                    }
                    result.success(enabled)
                }
                // Routes the cashier to the system screen where they
                // can flip the toggle. Required because Android does
                // not surface this permission via the runtime
                // permission API.
                "openListenerSettings" -> {
                    val intent =
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        BankNotificationBridge.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        const val BANK_NOTIFICATIONS_CHANNEL = "vendia.com/notifications"
    }
}
