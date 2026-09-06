package com.example.tmcell_ussd

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TmUtility"

        /** Flutter/MethodChannel-a habar ibermek üçin callback */
        var onSmsReceivedListener: ((sender: String, messageBody: String) -> Unit)? = null

        /** TM CELL gysga sanlary */
        private val TARGET_SENDERS = listOf(
            "0800", "0801", "0805",
            "100",  "101",
            "TMCELL", "TM CELL", "TmCell"
        )

        /** Mazmuny boýunça TM CELL habarlary tanaýan açar sözler */
        private val CONTENT_KEYWORDS = listOf(
            "pakedyn gutarmagyna",
            "balansynyz",
            "MSISDN",
            "TMT",
            "sowgat",
            "Sowgat"
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        for (message in messages) {
            val sender = message.displayOriginatingAddress
                ?: message.originatingAddress
                ?: ""
            val body = message.messageBody ?: ""

            Log.d(TAG, "SMS geldi [$sender]: ${body.take(80)}")

            val isTMCellBySender  = TARGET_SENDERS.any  { sender.contains(it, ignoreCase = true) }
            val isTMCellByContent = CONTENT_KEYWORDS.any { body.contains(it, ignoreCase = true) }

            if (isTMCellBySender || isTMCellByContent) {
                Log.d(TAG, "TM CELL SMS anyklady — Flutter-a iberilýär")

                // Ordered broadcast-da SMS_RECEIVED-y saklamagy synanyş.
                // Android 10+ (Q+) üçin bu işlemeýär, ýöne synanyşmak zyýan etmeýär.
                try { abortBroadcast() } catch (_: Exception) {}

                onSmsReceivedListener?.invoke(sender, body)
            }
        }
    }
}
