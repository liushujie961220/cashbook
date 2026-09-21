package com.cashbook.capture

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import kotlin.math.absoluteValue

/**
 * Deterministic local parser. No network and no persistence.
 *
 * It intentionally prefers false negatives over false positives.
 */
class PaymentNotificationParser {
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

    private val currencyAmountPatterns = listOf(
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
        content: NotificationContent,
    ): CandidateTransaction? {
        val source = when (packageName) {
            NotificationGatekeeper.WECHAT_PACKAGE -> CaptureSource.WECHAT_NOTIFICATION
            NotificationGatekeeper.ALIPAY_PACKAGE -> CaptureSource.ALIPAY_NOTIFICATION
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
        if (amount <= 0.0 || !amount.isFinite()) return null

        val direction = when {
            incomePattern.containsMatchIn(normalized) && !expensePattern.containsMatchIn(normalized) ->
                Direction.INCOME
            expensePattern.containsMatchIn(normalized) ->
                Direction.EXPENSE
            else -> return null
        }

        val merchant = extractMerchant(normalized)
        val confidence = calculateConfidence(
            source = source,
            text = normalized,
            merchant = merchant,
            amount = amount,
        )

        return CandidateTransaction(
            source = source,
            amount = amount.absoluteValue,
            direction = direction,
            merchant = merchant,
            occurredAtMillis = postedAtMillis,
            confidence = confidence,
            fingerprint = fingerprint(source, amount, direction, merchant, postedAtMillis),
        )
    }

    private fun extractAmount(text: String): Double? {
        for (pattern in currencyAmountPatterns) {
            val raw = pattern.find(text)?.groupValues?.getOrNull(1) ?: continue
            val value = raw.replace(",", "").toDoubleOrNull() ?: continue
            if (value > 0.0) return value
        }
        return null
    }

    private fun extractMerchant(text: String): String? {
        for (pattern in merchantPatterns) {
            val raw = pattern.find(text)?.groupValues?.getOrNull(1)?.trim() ?: continue
            val cleaned = raw
                .replace(Regex("""\s+"""), " ")
                .trim(' ', '。', '.', '，', ',', '：', ':')
            if (cleaned.length in 2..30) return cleaned
        }
        return null
    }

    private fun calculateConfidence(
        source: CaptureSource,
        text: String,
        merchant: String?,
        amount: Double,
    ): Double {
        var score = 0.55

        if (amount > 0.0) score += 0.20
        if (merchant != null) score += 0.10

        val strongSignal = when (source) {
            CaptureSource.WECHAT_NOTIFICATION ->
                text.contains("微信支付") || text.contains("支付成功") || text.contains("付款成功")
            CaptureSource.ALIPAY_NOTIFICATION ->
                text.contains("支付宝") || text.contains("交易提醒") || text.contains("支付成功")
        }
        if (strongSignal) score += 0.12

        // Very generic text should not auto-confirm.
        if (text.length < 8) score -= 0.10

        return score.coerceIn(0.0, 0.99)
    }

    /**
     * Fingerprint deliberately excludes raw notification text.
     * Time is bucketed to 30 seconds so Android reposts can deduplicate.
     */
    private fun fingerprint(
        source: CaptureSource,
        amount: Double,
        direction: Direction,
        merchant: String?,
        occurredAtMillis: Long,
    ): String {
        val timeBucket = occurredAtMillis / 30_000L
        val material = listOf(
            source.name,
            String.format(Locale.ROOT, "%.2f", amount),
            direction.name,
            merchant.orEmpty().lowercase(Locale.ROOT),
            timeBucket.toString(),
        ).joinToString("|")

        val digest = MessageDigest.getInstance("SHA-256")
            .digest(material.toByteArray(StandardCharsets.UTF_8))

        return digest.joinToString("") { "%02x".format(it) }.take(24)
    }
}
