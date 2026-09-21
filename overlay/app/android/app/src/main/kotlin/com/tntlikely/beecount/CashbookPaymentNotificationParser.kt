package com.tntlikely.beecount

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale

class CashbookPaymentNotificationParser {
    private val rejectPattern = Regex(
        "验证码|校验码|动态码|登录|待支付|未支付|支付失败|付款失败|扣款失败|交易关闭|已取消|自动取消",
        RegexOption.IGNORE_CASE,
    )

    private val paymentSignalPattern = Regex(
        "支付成功|付款成功|付款|消费|扣款|支出|已支付|已付款|收款|到账|收入|退款|退回|转入|转出",
        RegexOption.IGNORE_CASE,
    )

    private val incomePattern = Regex(
        "退款|退回|返还|收款|到账|收入|转入|已收钱|已收款",
        RegexOption.IGNORE_CASE,
    )

    private val expensePattern = Regex(
        "支付成功|付款成功|付款|消费|扣款|支出|已支付|已付款|转出",
        RegexOption.IGNORE_CASE,
    )

    private val amountPatterns = listOf(
        Regex("""(?:¥|￥|人民币|RMB|CNY)\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)""", RegexOption.IGNORE_CASE),
        Regex("""([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*(?:元|块|圆)""", RegexOption.IGNORE_CASE),
        Regex("""(?:金额|支付|付款|消费|扣款|支出|收入|收款|到账|退款)[^0-9¥￥]{0,10}(?:¥|￥)?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)""", RegexOption.IGNORE_CASE),
    )

    private val merchantPatterns = listOf(
        Regex("""(?:商户|商家|收款方)[：:\s]+([^|，,；;]{2,30})"""),
        Regex("""向\s*([^|，,；;]{2,30}?)\s*(?:付款|支付)"""),
        Regex("""在\s*([^|，,；;]{2,30}?)\s*(?:消费|支付)"""),
        Regex("""来自\s*([^|，,；;]{2,30})"""),
    )

    fun parse(
        packageName: String,
        postedAtMillis: Long,
        content: CashbookNotificationContent,
    ): CashbookCandidateTransaction? {
        val source = when (packageName) {
            CashbookNotificationGatekeeper.WECHAT_PACKAGE -> CashbookCaptureSource.WECHAT_NOTIFICATION
            CashbookNotificationGatekeeper.ALIPAY_PACKAGE -> CashbookCaptureSource.ALIPAY_NOTIFICATION
            else -> return null
        }

        val normalized = listOfNotNull(content.title, content.text, content.bigText)
            .joinToString(" | ")
            .replace(Regex("\\s+"), " ")
            .trim()

        if (normalized.isBlank()) return null
        if (rejectPattern.containsMatchIn(normalized)) return null
        if (!paymentSignalPattern.containsMatchIn(normalized)) return null

        val amount = extractAmount(normalized) ?: return null
        val direction = when {
            incomePattern.containsMatchIn(normalized) && !expensePattern.containsMatchIn(normalized) ->
                CashbookDirection.INCOME
            expensePattern.containsMatchIn(normalized) -> CashbookDirection.EXPENSE
            else -> return null
        }

        val merchant = extractMerchant(normalized)
        val confidence = calculateConfidence(source, normalized, merchant)

        return CashbookCandidateTransaction(
            source = source,
            amount = amount,
            direction = direction,
            merchant = merchant,
            occurredAtMillis = postedAtMillis,
            confidence = confidence,
            fingerprint = fingerprint(source, amount, direction, merchant),
        )
    }

    private fun extractAmount(text: String): Double? {
        for (pattern in amountPatterns) {
            val raw = pattern.find(text)?.groupValues?.getOrNull(1) ?: continue
            val value = raw.replace(",", "").toDoubleOrNull() ?: continue
            if (value > 0.0 && value.isFinite()) return value
        }
        return null
    }

    private fun extractMerchant(text: String): String? {
        for (pattern in merchantPatterns) {
            val raw = pattern.find(text)?.groupValues?.getOrNull(1)?.trim() ?: continue
            val cleaned = raw.replace(Regex("""\s+"""), " ")
                .trim(' ', '。', '.', '，', ',', '：', ':')
            if (cleaned.length in 2..30) return cleaned
        }
        return null
    }

    private fun calculateConfidence(
        source: CashbookCaptureSource,
        text: String,
        merchant: String?,
    ): Double {
        var score = 0.75
        if (merchant != null) score += 0.10
        val strongSignal = when (source) {
            CashbookCaptureSource.WECHAT_NOTIFICATION ->
                text.contains("微信支付") || text.contains("支付成功") || text.contains("付款成功")
            CashbookCaptureSource.ALIPAY_NOTIFICATION ->
                text.contains("支付宝") || text.contains("交易提醒") || text.contains("支付成功")
        }
        if (strongSignal) score += 0.12
        return score.coerceIn(0.0, 0.99)
    }

    private fun fingerprint(
        source: CashbookCaptureSource,
        amount: Double,
        direction: CashbookDirection,
        merchant: String?,
    ): String {
        val material = listOf(
            source.name,
            String.format(Locale.ROOT, "%.2f", amount),
            direction.name,
            merchant.orEmpty().lowercase(Locale.ROOT),
        ).joinToString("|")

        val digest = MessageDigest.getInstance("SHA-256")
            .digest(material.toByteArray(StandardCharsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }.take(24)
    }
}
