package com.example.tmcell_ussd

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsReceiver"

        // Callback listener to notify MainActivity / MethodChannel
        var onSmsReceivedListener: ((sender: String, messageBody: String) -> Unit)? = null

        // Known TM CELL shortcodes and keywords that identify operator messages
        private val TARGET_SENDERS = listOf(
            "0800", "0801", "0805",
            "100", "101",
            "TMCELL", "TM CELL", "TmCell"
        )

        // Content keywords that reliably identify TM CELL messages regardless of sender
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

            Log.d(TAG, "Incoming SMS from [$sender]: $body")

            val isTMCellBySender = TARGET_SENDERS.any { target ->
                sender.contains(target, ignoreCase = true)
            }

            val isTMCellByContent = CONTENT_KEYWORDS.any { keyword ->
                body.contains(keyword, ignoreCase = true)
            }

            if (isTMCellBySender || isTMCellByContent) {
                Log.d(TAG, "TM CELL SMS anyklady — arka planda sessiz ýuwulýar.")

                // ── Ses we bildiriş ýok: broadcast serpilýär ──────────────────
                // abortBroadcast() diňe sms_received üçin ordered broadcast-da işleýär.
                // priority=2147483647 Manifest-da kesgitlenenden işleýär.
                try {
                    abortBroadcast()
                } catch (e: Exception) {
                    Log.w(TAG, "abortBroadcast çäklendirilen (Android 10+): ${e.message}")
                }

                // ── Flutter MethodChannel arkaly ugrat ────────────────────────
                onSmsReceivedListener?.invoke(sender, body)
            }
        }
    }
}
