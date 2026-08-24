package com.example.tmcell_ussd

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.tmutility.app/ussd"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendUSSD" -> {
                    val ussdCode = call.argument<String>("ussdCode") ?: "*0801#"
                    val simSlot = call.argument<Int>("simSlot") ?: 0
                    executeUSSD(ussdCode, simSlot, result)
                }
                "checkPermissions" -> {
                    val granted = checkPermissionsGranted()
                    result.success(granted)
                }
                else -> result.notImplemented()
            }
        }

        SmsReceiver.onSmsReceivedListener = { sender, messageBody ->
            Handler(Looper.getMainLooper()).post {
                val data = mapOf(
                    "sender" to sender,
                    "body" to messageBody
                )
                methodChannel?.invokeMethod("onSmsReceived", data)
            }
        }
    }

    private fun checkPermissionsGranted(): Boolean {
        val smsPerm = ActivityCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
        val phonePerm = ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
        return smsPerm && phonePerm
    }

    private fun executeUSSD(ussdCode: String, simSlot: Int, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            var telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION_DENIED", "CALL_PHONE permission required", null)
                return
            }

            try {
                val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val activeSubs = subManager?.activeSubscriptionInfoList
                if (activeSubs != null && simSlot < activeSubs.size) {
                    val subId = activeSubs[simSlot].subscriptionId
                    telephonyManager = telephonyManager.createForSubscriptionId(subId)
                }
            } catch (e: Exception) {
                // Fallback to default TelephonyManager if subscription query fails
            }

            telephonyManager.sendUssdRequest(
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
                        result.error("USSD_FAILED", "USSD request failed code: $failureCode", null)
                    }
                },
                Handler(Looper.getMainLooper())
            )
        } else {
            try {
                val encodedHash = Uri.encode("#")
                val cleanCode = ussdCode.replace("#", encodedHash)
                val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$cleanCode"))
                startActivity(intent)
                result.success("USSD dial intent launched")
            } catch (e: Exception) {
                result.error("INTENT_ERROR", e.message, null)
            }
        }
    }
}
