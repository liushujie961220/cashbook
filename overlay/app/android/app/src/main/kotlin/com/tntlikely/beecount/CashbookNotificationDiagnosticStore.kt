package com.tntlikely.beecount

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Local-only metadata diagnostics for real-device notification calibration.
 *
 * Never stores notification title/body/extras, amount, merchant or account data.
 */
class CashbookNotificationDiagnosticStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isEnabled(): Boolean = prefs.getBoolean(KEY_ENABLED, false)

    fun setEnabled(enabled: Boolean) {
        val editor = prefs.edit().putBoolean(KEY_ENABLED, enabled)
        if (!enabled) {
            editor.remove(KEY_EVENTS)
        }
        editor.apply()
    }

    fun record(
        packageName: String,
        category: String?,
        channelId: String?,
        outcome: String,
        occurredAtMillis: Long,
    ) {
        if (!isEnabled()) return

        val source = when (packageName) {
            CashbookNotificationGatekeeper.WECHAT_PACKAGE -> "WECHAT"
            CashbookNotificationGatekeeper.ALIPAY_PACKAGE -> "ALIPAY"
            else -> return
        }

        synchronized(lock) {
            val now = System.currentTimeMillis()
            val cutoff = now - RETENTION_MS
            val current = loadArray()
            val next = JSONArray()

            for (index in 0 until current.length()) {
                val item = current.optJSONObject(index) ?: continue
                if (item.optLong("occurredAtMillis") >= cutoff) {
                    next.put(item)
                }
            }

            next.put(JSONObject().apply {
                put("source", source)
                put("category", category ?: "")
                put("channelId", channelId ?: "")
                put("outcome", outcome)
                put("occurredAtMillis", occurredAtMillis)
            })

            val trimmed = JSONArray()
            val start = (next.length() - MAX_ITEMS).coerceAtLeast(0)
            for (index in start until next.length()) {
                trimmed.put(next.get(index))
            }

            prefs.edit().putString(KEY_EVENTS, trimmed.toString()).apply()
        }
    }

    fun events(): List<Map<String, Any?>> = synchronized(lock) {
        val cutoff = System.currentTimeMillis() - RETENTION_MS
        val array = loadArray()
        val result = ArrayList<Map<String, Any?>>(array.length())
        val retained = JSONArray()

        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val occurredAt = item.optLong("occurredAtMillis")
            if (occurredAt < cutoff) continue

            retained.put(item)
            result += mapOf(
                "source" to item.optString("source"),
                "category" to item.optString("category").takeIf { it.isNotBlank() },
                "channelId" to item.optString("channelId").takeIf { it.isNotBlank() },
                "outcome" to item.optString("outcome"),
                "occurredAtMillis" to occurredAt,
            )
        }

        prefs.edit().putString(KEY_EVENTS, retained.toString()).apply()
        result
    }

    fun clear() {
        prefs.edit().remove(KEY_EVENTS).apply()
    }

    private fun loadArray(): JSONArray = try {
        JSONArray(prefs.getString(KEY_EVENTS, "[]") ?: "[]")
    } catch (_: Exception) {
        JSONArray()
    }

    companion object {
        const val OUTCOME_BLOCKED_MESSAGE = "BLOCKED_MESSAGE_CATEGORY"
        const val OUTCOME_NO_CANDIDATE = "NO_CANDIDATE"
        const val OUTCOME_CANDIDATE_CREATED = "CANDIDATE_CREATED"

        private const val PREFS_NAME = "cashbook_notification_diagnostics"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_EVENTS = "events_v1"
        private const val MAX_ITEMS = 50
        private const val RETENTION_MS = 24 * 60 * 60 * 1000L
        private val lock = Any()
    }
}
