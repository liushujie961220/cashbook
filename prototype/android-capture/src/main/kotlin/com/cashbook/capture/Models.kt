package com.cashbook.capture

enum class CaptureSource {
    WECHAT_NOTIFICATION,
    ALIPAY_NOTIFICATION
}

enum class Direction {
    EXPENSE,
    INCOME
}

data class NotificationContent(
    val title: String? = null,
    val text: String? = null,
    val bigText: String? = null,
)

data class CandidateTransaction(
    val source: CaptureSource,
    val amount: Double,
    val direction: Direction,
    val merchant: String?,
    val occurredAtMillis: Long,
    val confidence: Double,
    val fingerprint: String,
)
