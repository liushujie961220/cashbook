package com.tntlikely.beecount

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs

class CashbookCandidateStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun enqueue(candidate: CashbookCandidateTransaction) {
        synchronized(lock) {
            val array = loadArray()
            for (index in 0 until array.length()) {
                val existing = array.optJSONObject(index) ?: continue
                val sameFingerprint =
                    existing.optString("fingerprint") == candidate.fingerprint
                val closeInTime = abs(
                    existing.optLong("occurredAtMillis") - candidate.occurredAtMillis
                ) <= DEDUP_WINDOW_MS

                if (sameFingerprint && closeInTime) {
                    return
                }
            }

            array.put(candidate.toJson())
            val trimmed = JSONArray()
            val start = (array.length() - MAX_ITEMS).coerceAtLeast(0)
            for (index in start until array.length()) {
                trimmed.put(array.get(index))
            }
            prefs.edit().putString(KEY_QUEUE, trimmed.toString()).apply()
        }
    }

    fun drain(): List<Map<String, Any?>> = synchronized(lock) {
        val array = loadArray()
        val result = ArrayList<Map<String, Any?>>(array.length())
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            result += mapOf(
                "source" to item.optString("source"),
                "amount" to item.optDouble("amount"),
                "direction" to item.optString("direction"),
                "merchant" to item.optString("merchant").takeIf { it.isNotBlank() },
                "occurredAtMillis" to item.optLong("occurredAtMillis"),
                "confidence" to item.optDouble("confidence"),
                "fingerprint" to item.optString("fingerprint"),
            )
        }
        prefs.edit().remove(KEY_QUEUE).apply()
        result
    }

    private fun loadArray(): JSONArray = try {
        JSONArray(prefs.getString(KEY_QUEUE, "[]") ?: "[]")
    } catch (_: Exception) {
        JSONArray()
    }

    private fun CashbookCandidateTransaction.toJson(): JSONObject = JSONObject().apply {
        put("source", source.name)
        put("amount", amount)
        put("direction", direction.name)
        put("merchant", merchant ?: "")
        put("occurredAtMillis", occurredAtMillis)
        put("confidence", confidence)
        put("fingerprint", fingerprint)
    }

    companion object {
        private const val PREFS_NAME = "cashbook_notification_capture"
        private const val KEY_QUEUE = "candidate_queue_v1"
        private const val MAX_ITEMS = 50
        private const val DEDUP_WINDOW_MS = 2 * 60 * 1000L
        private val lock = Any()
    }
}
