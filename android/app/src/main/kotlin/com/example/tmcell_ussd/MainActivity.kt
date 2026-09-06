package com.example.tmcell_ussd

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.tmutility.app/ussd"
    private val TAG = "TmUtility"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendUSSD" -> {
                    val ussdCode = call.argument<String>("ussdCode") ?: "*0800#"
                    val simSlot  = call.argument<Int>("simSlot")    ?: 0
                    executeUSSD(ussdCode, simSlot, result)
                }
                "getSignalStrength" -> {
                    val simSlot = call.argument<Int>("simSlot") ?: 0
                    getSignalLevel(simSlot, result)
                }
                "checkPermissions" -> {
                    result.success(checkPermissionsGranted())
                }
                "deleteSms" -> {
                    // Flutter TM CELL SMS'ini sessiz öçürmek üçin çagyrýar
                    val sender = call.argument<String>("sender") ?: ""
                    val body   = call.argument<String>("body")   ?: ""
                    val deleted = deleteTmCellSms(sender, body)
                    result.success(deleted)
                }
                else -> result.notImplemented()
            }
        }

        // SmsReceiver → Flutter köprüsi
        SmsReceiver.onSmsReceivedListener = { sender, messageBody ->
            Handler(Looper.getMainLooper()).post {
                val data = mapOf(
                    "sender" to sender,
                    "body"   to messageBody
                )
                methodChannel?.invokeMethod("onSmsReceived", data)
            }
        }
    }

    // ── SMS'i ContentProvider arkaly sessiz öçür ──────────────────────────────
    private fun deleteTmCellSms(sender: String, body: String): Boolean {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_SMS)
            != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "READ_SMS rugsady ýok – SMS öçürilmedi")
            return false
        }

        return try {
            // Inbox-dan sender + ilkinji 60 simwol bilen tap
            val shortBody = if (body.length > 60) body.substring(0, 60) else body
            val cursor: Cursor? = contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                arrayOf("_id"),
                "address LIKE ? AND body LIKE ?",
                arrayOf("%$sender%", "%$shortBody%"),
                "date DESC LIMIT 3"
            )
            var deleted = 0
            cursor?.use {
                while (it.moveToNext()) {
                    val id = it.getLong(it.getColumnIndexOrThrow("_id"))
                    val deleteUri = ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id)
                    deleted += contentResolver.delete(deleteUri, null, null)
                }
            }
            Log.d(TAG, "TM CELL SMS: $deleted sany öçürildi (sender=$sender)")
            deleted > 0
        } catch (e: Exception) {
            Log.e(TAG, "SMS öçürmek säwligi: ${e.message}")
            false
        }
    }

    private fun checkPermissionsGranted(): Boolean {
        val call    = ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
        val phone   = ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
        val sms     = ActivityCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS)
        return call == PackageManager.PERMISSION_GRANTED &&
               phone == PackageManager.PERMISSION_GRANTED &&
               sms == PackageManager.PERMISSION_GRANTED
    }

    private fun executeUSSD(ussdCode: String, simSlot: Int, result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "CALL_PHONE izni talap edilýär", null)
            return
        }

        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        var targetTelephonyManager = telephonyManager
        var targetSubId: Int? = null

        try {
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
                == PackageManager.PERMISSION_GRANTED) {
                val activeSubs = subManager?.activeSubscriptionInfoList
                if (activeSubs != null && simSlot < activeSubs.size) {
                    targetSubId = activeSubs[simSlot].subscriptionId
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        targetTelephonyManager =
                            telephonyManager.createForSubscriptionId(targetSubId)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                targetTelephonyManager.sendUssdRequest(
                    ussdCode,
                    object : TelephonyManager.UssdResponseCallback() {
                        override fun onReceiveUssdResponse(
                            tm: TelephonyManager?,
                            request: String?,
                            response: CharSequence?
                        ) {
                            result.success(response?.toString() ?: "")
                        }

                        override fun onReceiveUssdResponseFailed(
                            tm: TelephonyManager?,
                            request: String?,
                            failureCode: Int
                        ) {
                            // UssdResponseCallback başa barmady – klassik arama usulyna geç
                            dialUSSDFallback(ussdCode, simSlot, targetSubId, result)
                        }
                    },
                    Handler(Looper.getMainLooper())
                )
            } catch (e: Exception) {
                dialUSSDFallback(ussdCode, simSlot, targetSubId, result)
            }
        } else {
            dialUSSDFallback(ussdCode, simSlot, targetSubId, result)
        }
    }

    private fun dialUSSDFallback(
        ussdCode: String,
        simSlot: Int,
        subId: Int?,
        result: MethodChannel.Result
    ) {
        try {
            val encodedCode = Uri.encode(ussdCode)
            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$encodedCode")).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra("com.android.phone.force.slot", true)
                putExtra("Cdma_SubId", simSlot)
                putExtra("simSlot", simSlot)
                putExtra("com.android.phone.extra.slot", simSlot)
                subId?.let {
                    putExtra("subscription", it)
                    putExtra("subscription_id", it)
                }
            }
            startActivity(intent)
            // Jogap SMS arkaly geler – Flutter SMS-i SmsReceiver arkaly alarys
            result.success("")
        } catch (e: Exception) {
            result.error("INTENT_ERROR", e.message ?: "Arama säwligi", null)
        }
    }

    private fun getSignalLevel(simSlot: Int, result: MethodChannel.Result) {
        var signalLevel = 4
        try {
            val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            var targetManager = telephonyManager

            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
                == PackageManager.PERMISSION_GRANTED) {
                val subManager =
                    getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val activeSubs = subManager?.activeSubscriptionInfoList
                if (activeSubs != null && simSlot < activeSubs.size) {
                    val subId = activeSubs[simSlot].subscriptionId
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        targetManager = telephonyManager.createForSubscriptionId(subId)
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                signalLevel = targetManager.signalStrength?.level ?: 4
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        result.success(signalLevel)
    }
}
