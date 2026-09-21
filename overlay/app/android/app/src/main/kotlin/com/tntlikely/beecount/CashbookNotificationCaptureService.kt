package com.tntlikely.beecount

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class CashbookNotificationCaptureService : NotificationListenerService() {
    private val gatekeeper = CashbookNotificationGatekeeper()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val event = sbn ?: return
        val packageName = event.packageName ?: return

        // Critical privacy boundary:
        // Notification.extras must never be touched before package allowlist validation.
        if (!gatekeeper.isAllowedPackage(packageName)) return

        val candidate = gatekeeper.process(
            packageName = packageName,
            postedAtMillis = event.postTime,
        ) {
            val extras = event.notification.extras
            CashbookNotificationContent(
                title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
                text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
                bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            )
        } ?: return

        // Only structured data is persisted. Raw notification content is discarded here.
        CashbookCandidateStore(applicationContext).enqueue(candidate)
    }
}
