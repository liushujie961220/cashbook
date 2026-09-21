package com.tntlikely.beecount

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object CashbookNotificationBridge {
    private const val CHANNEL = "com.cashbook/notification_capture"

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessGranted" ->
                    result.success(isNotificationAccessGranted(context))

                "openNotificationAccessSettings" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(true)
                }

                "drainCandidates" ->
                    result.success(CashbookCandidateStore(context).drain())

                else -> result.notImplemented()
            }
        }
    }

    private fun isNotificationAccessGranted(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ).orEmpty()
        val component = ComponentName(
            context,
            CashbookNotificationCaptureService::class.java,
        )
        return enabled.split(':').any {
            it.equals(component.flattenToString(), ignoreCase = true)
        }
    }
}
