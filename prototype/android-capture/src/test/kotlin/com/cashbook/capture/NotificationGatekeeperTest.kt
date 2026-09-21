package com.cashbook.capture

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NotificationGatekeeperTest {
    private val gatekeeper = NotificationGatekeeper()

    @Test
    fun `non allowlisted package is dropped before content is read`() {
        var supplierCalled = false

        val result = gatekeeper.process(
            packageName = "com.example.chat",
            postedAtMillis = 1_700_000_000_000,
        ) {
            supplierCalled = true
            NotificationContent(text = "private message")
        }

        assertNull(result)
        assertFalse(supplierCalled)
    }

    @Test
    fun `wechat ordinary message category is dropped before content is read`() {
        var supplierCalled = false

        val result = gatekeeper.process(
            packageName = NotificationGatekeeper.WECHAT_PACKAGE,
            postedAtMillis = 1_700_000_000_000,
            category = NotificationGatekeeper.MESSAGE_CATEGORY,
        ) {
            supplierCalled = true
            NotificationContent(
                title = "家人",
                text = "我刚刚付款38元，你记一下",
            )
        }

        assertNull(result)
        assertFalse(supplierCalled)
    }

    @Test
    fun `wechat payment can produce an expense candidate`() {
        val result = gatekeeper.process(
            packageName = NotificationGatekeeper.WECHAT_PACKAGE,
            postedAtMillis = 1_700_000_000_000,
            category = null,
        ) {
            NotificationContent(
                title = "微信支付",
                text = "支付成功 ¥38.50",
                bigText = "向 麦当劳 付款 ¥38.50",
            )
        }

        requireNotNull(result)
        assertEquals(CaptureSource.WECHAT_NOTIFICATION, result.source)
        assertEquals(Direction.EXPENSE, result.direction)
        assertEquals(38.50, result.amount)
        assertEquals("麦当劳", result.merchant)
        assertTrue(result.confidence >= 0.80)
    }

    @Test
    fun `verification code is rejected even from an allowlisted app`() {
        val result = gatekeeper.process(
            packageName = NotificationGatekeeper.ALIPAY_PACKAGE,
            postedAtMillis = 1_700_000_000_000,
        ) {
            NotificationContent(
                title = "支付宝",
                text = "验证码 123456，请勿泄露",
            )
        }

        assertNull(result)
    }


    @Test
    fun `alipay refund is parsed as income`() {
        val result = gatekeeper.process(
            packageName = NotificationGatekeeper.ALIPAY_PACKAGE,
            postedAtMillis = 1_700_000_100_000,
        ) {
            NotificationContent(
                title = "支付宝交易提醒",
                text = "退款成功 ￥26.80",
                bigText = "商户：某某餐饮 退款26.80元",
            )
        }

        requireNotNull(result)
        assertEquals(Direction.INCOME, result.direction)
        assertEquals(26.80, result.amount)
        assertEquals("某某餐饮 退款26.80元", result.merchant)
    }

    @Test
    fun `failed payment is rejected`() {
        val result = gatekeeper.process(
            packageName = NotificationGatekeeper.ALIPAY_PACKAGE,
            postedAtMillis = 1_700_000_200_000,
        ) {
            NotificationContent(
                title = "支付宝",
                text = "付款失败 ￥88.00，请重新尝试",
            )
        }

        assertNull(result)
    }

    @Test
    fun `generic numeric notification without payment signal is rejected`() {
        val result = gatekeeper.process(
            packageName = NotificationGatekeeper.WECHAT_PACKAGE,
            postedAtMillis = 1_700_000_300_000,
        ) {
            NotificationContent(
                title = "服务通知",
                text = "余额38.50元",
            )
        }

        assertNull(result)
    }

    @Test
    fun `same transaction has stable core fingerprint across short reposts`() {
        fun at(time: Long) = gatekeeper.process(
            packageName = NotificationGatekeeper.ALIPAY_PACKAGE,
            postedAtMillis = time,
        ) {
            NotificationContent(
                title = "支付宝交易提醒",
                text = "消费人民币18.00元 商户：便利店",
            )
        }

        val first = requireNotNull(at(1_700_000_000_000))
        val second = requireNotNull(at(1_700_000_010_000))

        assertEquals(first.fingerprint, second.fingerprint)
    }
}
