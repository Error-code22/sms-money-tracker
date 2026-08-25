package com.droner.sms_money_tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsParserTest {

    private fun parse(sender: String, body: String): Txn? =
        SmsParser.parse(
            SmsMessage(id = 1L, sender = sender, body = body, date = System.currentTimeMillis())
        )

    // ---------------- M-Pesa dedicated templates ----------------

    @Test
    fun mpesaSendToPerson() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. Ksh500.00 sent to JOHN DOE 0712345678 on 12/6/25 at 7:45 PM. " +
                "New M-PESA balance is Ksh1,200.00. Transaction cost, Ksh13.00."
        )
        assertNotNull(txn)
        assertEquals(500.0, txn!!.amount, 0.001)
        assertEquals("debit", txn.type)
        assertEquals("JOHN DOE", txn.counterparty)
        assertEquals("KES", txn.currency)
        assertTrue(txn.isConfident)
    }

    @Test
    fun mpesaReceiveFromPerson() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. You have received Ksh1,000.00 from MARY ATIENO 0723456789 " +
                "on 13/6/25 at 9:15 AM. New M-PESA balance is Ksh2,200.00."
        )
        assertNotNull(txn)
        assertEquals(1000.0, txn!!.amount, 0.001)
        assertEquals("credit", txn.type)
        assertEquals("MARY ATIENO", txn.counterparty)
        assertTrue(txn.isConfident)
    }

    @Test
    fun mpesaPaybill() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. Ksh350.00 paid to KPLC PREPAID for account 1234567890 " +
                "on 13/6/25 at 10:00 AM. New M-PESA balance is Ksh1,850.00. Transaction cost, Ksh0.00."
        )
        assertNotNull(txn)
        assertEquals(350.0, txn!!.amount, 0.001)
        assertEquals("debit", txn.type)
        assertEquals("KPLC PREPAID · 1234567890", txn.counterparty)
        assertTrue(txn.isConfident)
    }

    @Test
    fun mpesaBuyGoodsTill() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. Ksh250.00 paid to NAIVAS SUPERMARKET. on 13/6/25 at 11:20 AM. " +
                "New M-PESA balance is Ksh1,600.00."
        )
        assertNotNull(txn)
        assertEquals(250.0, txn!!.amount, 0.001)
        assertEquals("debit", txn.type)
        assertEquals("NAIVAS SUPERMARKET", txn.counterparty)
        assertTrue(txn.isConfident)
    }

    @Test
    fun mpesaWithdrawAtAgent() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. Ksh2,000.00 withdrawn from M-PESA AGENT 12345 on 14/6/25 at 8:00 AM. " +
                "New M-PESA balance is Ksh3,600.00. Transaction cost, Ksh30.00."
        )
        assertNotNull(txn)
        assertEquals(2000.0, txn!!.amount, 0.001)
        assertEquals("debit", txn.type)
        assertEquals("M-PESA AGENT 12345", txn.counterparty)
        assertTrue(txn.isConfident)
    }

    @Test
    fun mpesaAirtimePurchase() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. You bought Ksh100.00 of airtime for 0712345678 on 14/6/25 at 2:30 PM. " +
                "New M-PESA balance is Ksh1,500.00."
        )
        assertNotNull(txn)
        assertEquals(100.0, txn!!.amount, 0.001)
        assertEquals("debit", txn.type)
        assertEquals("Airtime", txn.counterparty)
        assertTrue(txn.isConfident)
    }

    @Test
    fun mpesaFulizaUsage() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. Fuliza M-PESA has covered Ksh50.00 for your transaction 0712345678. " +
                "Your Fuliza M-PESA limit is Ksh2,450.00. Interest of Ksh1.50 has been charged."
        )
        assertNotNull(txn)
        assertEquals(50.0, txn!!.amount, 0.001)
        assertEquals("debit", txn.type)
        assertEquals("Fuliza", txn.category)
        assertEquals(1.5, txn.interest ?: 0.0, 0.001)
        assertTrue(txn.isConfident)
    }

    @Test
    fun mpesaReversal() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. Ksh500.00 reversal from M-PESA for failed transaction. " +
                "New M-PESA balance is Ksh1,700.00."
        )
        assertNotNull(txn)
        assertEquals(500.0, txn!!.amount, 0.001)
        assertEquals("credit", txn.type)
        assertEquals("Reversal", txn.category)
        assertTrue(txn.isConfident)
    }

    @Test
    fun mpesaPromoWithoutTransactionHeaderIsSkipped() {
        assertNull(parse("MPESA", "MPESA: Pay bills at zero cost this week! Dial *334#."))
    }

    @Test
    fun gatedButUntemplatedMpesaFallsBackToGenericAsUnconfirmed() {
        val txn = parse(
            "MPESA",
            "QGH7K3MNOP Confirmed. You have successfully deposited Ksh500.00. New M-PESA balance is Ksh2,200.00."
        )
        assertNotNull(txn)
        assertEquals(500.0, txn!!.amount, 0.001)
        assertEquals("credit", txn.type)
        assertTrue(!txn.isConfident)
    }

    // ---------------- Generic fallback (banks, Airtel) ----------------

    @Test
    fun bankDebitAlertParsedAsUnconfirmed() {
        val txn = parse(
            "GTBANK",
            "Debit Alert: Acct 1234567890 debited with NGN 5,000.00 by ATM on 14/06/26 10:00:00. " +
                "Bal: NGN 25,000.00."
        )
        assertNotNull(txn)
        assertEquals(5000.0, txn!!.amount, 0.001)
        assertEquals("debit", txn.type)
        assertEquals("NGN", txn.currency)
        assertTrue(!txn.isConfident)
    }

    @Test
    fun airtelMoneyReceiveParsedAsUnconfirmed() {
        val txn = parse(
            "AirtelMoney",
            "You have received UGX 100,000 from ALEX OKETCHO 0772123456. " +
                "Your Airtel Money balance is UGX 250,000."
        )
        assertNotNull(txn)
        assertEquals(100000.0, txn!!.amount, 0.001)
        assertEquals("credit", txn.type)
        assertEquals("UGX", txn.currency)
        assertEquals("ALEX OKETCHO", txn.counterparty)
        assertTrue(!txn.isConfident)
    }

    @Test
    fun otpMessageIsSkipped() {
        assertNull(parse("GTBANK", "123456 is your verification code for login."))
    }

    @Test
    fun balanceOnlyNoticeIsSkipped() {
        assertNull(parse("GTBANK", "Your account balance is NGN 50,000.00 as at 14/06/26."))
    }

    // ---------------- Shape learning ----------------

    @Test
    fun shapeOfNormalizesDigitsAndWhitespace() {
        assertEquals("debit ksh#.# from sender", SmsParser.shapeOf("Debit Ksh100.00 from sender"))
    }
}
