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

        // Known TM CELL shortcodes
        private val TARGET_SENDERS = listOf("0801", "100", "0800", "0805", "TMCELL", "TM CELL")
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val pdus = intent.extras?.get("pdus") as? Array<*> ?: return
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)

            for (message in messages) {
                val sender = message.displayOriginatingAddress ?: message.originatingAddress ?: ""
                val body = message.messageBody ?: ""

                Log.d(TAG, "Incoming SMS from [$sender]: $body")

                val isTMCell = TARGET_SENDERS.any { target ->
                    sender.contains(target, ignoreCase = true)
                } || body.contains("pakedyn gutarmagyna", ignoreCase = true) 
                  || body.contains("balansynyz", ignoreCase = true)

                if (isTMCell) {
                    Log.d(TAG, "Intercepting TM CELL SMS silently. Aborting broadcast.")
                    
                    // Abort notification and sound display on Android
                    abortBroadcast()

                    // Dispatch to Flutter MethodChannel listener
                    onSmsReceivedListener?.invoke(sender, body)
                }
            }
        }
    }
}
