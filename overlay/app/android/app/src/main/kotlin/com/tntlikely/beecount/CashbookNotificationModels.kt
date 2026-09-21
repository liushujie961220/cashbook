package com.tntlikely.beecount

enum class CashbookCaptureSource {
    WECHAT_NOTIFICATION,
    ALIPAY_NOTIFICATION,
}

enum class CashbookDirection {
    EXPENSE,
    INCOME,
}

data class CashbookNotificationContent(
    val title: String? = null,
    val text: String? = null,
    val bigText: String? = null,
)

data class CashbookCandidateTransaction(
    val source: CashbookCaptureSource,
    val amount: Double,
    val direction: CashbookDirection,
    val merchant: String?,
    val occurredAtMillis: Long,
    val confidence: Double,
    val fingerprint: String,
)
