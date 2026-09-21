package com.cashbook.capture

/**
 * Privacy boundary for notification capture.
 *
 * The service layer must call [process] with a lazy content supplier.
 * For packages outside the allowlist, the supplier is never invoked, so
 * notification title/text/extras are not read by Cashbook at all.
 */
class NotificationGatekeeper(
    private val parser: PaymentNotificationParser = PaymentNotificationParser(),
) {
    companion object {
        const val WECHAT_PACKAGE = "com.tencent.mm"
        const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"

        val DEFAULT_ALLOWED_PACKAGES: Set<String> = setOf(
            WECHAT_PACKAGE,
            ALIPAY_PACKAGE,
        )
    }

    fun isAllowedPackage(packageName: String): Boolean =
        packageName in DEFAULT_ALLOWED_PACKAGES

    fun process(
        packageName: String,
        postedAtMillis: Long,
        contentSupplier: () -> NotificationContent,
    ): CandidateTransaction? {
        if (!isAllowedPackage(packageName)) {
            return null
        }

        // Sensitive content is only read after package allowlist validation.
        val content = contentSupplier()
        return parser.parse(packageName, postedAtMillis, content)
    }
}
