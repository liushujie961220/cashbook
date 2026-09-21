package com.tntlikely.beecount

import android.app.Notification
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class CashbookNotificationCaptureService : NotificationListenerService() {
    private val gatekeeper = CashbookNotificationGatekeeper()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val event = sbn ?: return
        val packageName = event.packageName ?: return
        val notification = event.notification

        // Do not retain metadata for unrelated apps either.
        if (!gatekeeper.isAllowedPackage(packageName)) return

        val diagnostics = CashbookNotificationDiagnosticStore(applicationContext)
        val channelId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notification.channelId
        } else {
            null
        }

        // Critical privacy boundary:
        // 1) package allowlist
        // 2) metadata-only category gate
        // Both happen before Notification.extras is touched.
        if (!gatekeeper.shouldReadContent(packageName, notification.category)) {
            diagnostics.record(
                packageName = packageName,
                category = notification.category,
                channelId = channelId,
                outcome = CashbookNotificationDiagnosticStore.OUTCOME_BLOCKED_MESSAGE,
                occurredAtMillis = event.postTime,
            )
            return
        }

        val candidate = gatekeeper.process(
            packageName = packageName,
            postedAtMillis = event.postTime,
            category = notification.category,
        ) {
            val extras = notification.extras
            CashbookNotificationContent(
                title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
                text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
                bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            )
        }

        if (candidate == null) {
            diagnostics.record(
                packageName = packageName,
                category = notification.category,
                channelId = channelId,
                outcome = CashbookNotificationDiagnosticStore.OUTCOME_NO_CANDIDATE,
                occurredAtMillis = event.postTime,
            )
            return
        }

        diagnostics.record(
            packageName = packageName,
            category = notification.category,
            channelId = channelId,
            outcome = CashbookNotificationDiagnosticStore.OUTCOME_CANDIDATE_CREATED,
            occurredAtMillis = event.postTime,
        )

        // Only structured data is persisted. Raw notification content is discarded here.
        CashbookCandidateStore(applicationContext).enqueue(candidate)
    }
}
