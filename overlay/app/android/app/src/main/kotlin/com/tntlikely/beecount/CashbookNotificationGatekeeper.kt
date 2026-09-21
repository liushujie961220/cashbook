package com.tntlikely.beecount

class CashbookNotificationGatekeeper(
    private val parser: CashbookPaymentNotificationParser = CashbookPaymentNotificationParser(),
) {
    companion object {
        const val WECHAT_PACKAGE = "com.tencent.mm"
        const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"

        // Android Notification.CATEGORY_MESSAGE == "msg".
        // We keep the literal here so this class remains easy to unit-test
        // without depending on the Android framework.
        const val MESSAGE_CATEGORY = "msg"

        private val allowedPackages = setOf(WECHAT_PACKAGE, ALIPAY_PACKAGE)
    }

    fun isAllowedPackage(packageName: String): Boolean = packageName in allowedPackages

    /**
     * Metadata-only privacy gate.
     *
     * This must run before Notification.extras is touched. Ordinary messaging
     * notifications are dropped using Android notification metadata alone, so
     * their title/body never enters Cashbook's parser.
     */
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
        contentSupplier: () -> CashbookNotificationContent,
    ): CashbookCandidateTransaction? {
        if (!shouldReadContent(packageName, category)) return null
        return parser.parse(packageName, postedAtMillis, contentSupplier())
    }
}
