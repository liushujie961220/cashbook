package com.tntlikely.beecount

class CashbookNotificationGatekeeper(
    private val parser: CashbookPaymentNotificationParser = CashbookPaymentNotificationParser(),
) {
    companion object {
        const val WECHAT_PACKAGE = "com.tencent.mm"
        const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"

        private val allowedPackages = setOf(WECHAT_PACKAGE, ALIPAY_PACKAGE)
    }

    fun isAllowedPackage(packageName: String): Boolean = packageName in allowedPackages

    fun process(
        packageName: String,
        postedAtMillis: Long,
        contentSupplier: () -> CashbookNotificationContent,
    ): CashbookCandidateTransaction? {
        if (!isAllowedPackage(packageName)) return null
        return parser.parse(packageName, postedAtMillis, contentSupplier())
    }
}
