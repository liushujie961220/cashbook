package com.cashbook.capture

/**
 * Privacy boundary for notification capture.
 *
 * The service layer must call [process] with a lazy content supplier.
 * Packages outside the allowlist and notifications classified as ordinary
 * messages are rejected before title/text/extras are read.
 */
class NotificationGatekeeper(
    private val parser: PaymentNotificationParser = PaymentNotificationParser(),
) {
    companion object {
        const val WECHAT_PACKAGE = "com.tencent.mm"
        const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
        const val MESSAGE_CATEGORY = "msg"

        val DEFAULT_ALLOWED_PACKAGES: Set<String> = setOf(
            WECHAT_PACKAGE,
            ALIPAY_PACKAGE,
        )
    }

    fun isAllowedPackage(packageName: String): Boolean =
        packageName in DEFAULT_ALLOWED_PACKAGES

    fun shouldReadContent(
        packageName: String,
        category: String?,
    ): Boolean {
        if (!isAllowedPackage(packageName)) return false
        if (category == MESSAGE_CATEGORY) return false
        return true
    }

    fun process(
        packageName: String,
        postedAtMillis: Long,
        category: String? = null,
        contentSupplier: () -> NotificationContent,
    ): CandidateTransaction? {
        if (!shouldReadContent(packageName, category)) {
            return null
        }

        // Sensitive content is only read after package + metadata gating.
        val content = contentSupplier()
        return parser.parse(packageName, postedAtMillis, content)
    }
}
