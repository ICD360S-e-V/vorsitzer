package de.icd360sev.icd_sms

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Verschickt Termin-Erinnerungen als SMS über die SIM des Geräts.
 *
 * Läuft in JEDER Engine — auch in der, die WorkManager für die automatische
 * Vortags-Erinnerung startet. Dort gibt es keine Activity: fehlt die
 * Berechtigung, wird sauber "permission_denied" gemeldet statt zu versuchen,
 * im Hintergrund einen Dialog zu öffnen. Erteilt wird sie beim ersten
 * manuellen Versand im Vordergrund.
 *
 * Der Sendestatus kommt asynchron per PendingIntent zurück; erst dann
 * antwortet [send]. Nur so kann die Warteschlange auf dem Server zwischen
 * "wirklich raus" und "Funkloch, morgen nochmal" unterscheiden.
 */
class IcdSmsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    private var pendingNumber: String? = null
    private var pendingText: String? = null
    private var pendingResult: MethodChannel.Result? = null

    private var counter = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(
                mapOf(
                    "messaging" to hasSmsCapability(),
                    "permission" to hasPermission()
                )
            )
            "send" -> {
                val number = call.argument<String>("number")
                val text = call.argument<String>("text")
                if (number.isNullOrBlank() || text.isNullOrBlank()) {
                    result.success("invalid_number")
                } else {
                    startSend(number, text, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    // =====================================================================

    private fun hasSmsCapability(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)
        }

    private fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED

    private fun startSend(number: String, text: String, result: MethodChannel.Result) {
        if (!hasSmsCapability()) {
            result.success("no_telephony")
            return
        }
        if (!hasPermission()) {
            val act = activity
            if (act == null) {
                // Hintergrundjob ohne UI — hier kann niemand zustimmen.
                result.success("permission_denied")
                return
            }
            // Einen offenen Dialog nicht verwaisen lassen, sonst wirft Flutter
            // beim zweiten reply() eine Exception.
            pendingResult?.success("cancelled")
            pendingNumber = number
            pendingText = text
            pendingResult = result
            act.requestPermissions(arrayOf(Manifest.permission.SEND_SMS), PERMISSION_REQUEST)
            return
        }
        send(number, text, result)
    }

    @Suppress("DEPRECATION")
    private fun smsManager(): SmsManager? =
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                SmsManager.getDefault()
            }
        } catch (_: Exception) {
            null
        }

    private fun send(number: String, text: String, result: MethodChannel.Result) {
        val sms = smsManager()
        if (sms == null) {
            result.success("no_telephony")
            return
        }

        val id = counter++
        val action = "${context.packageName}.SMS_SENT.$id"
        // Lange Texte zerlegt das Netz ohnehin; divideMessage setzt die
        // Segmentgrenzen richtig (GSM-7: 153 Zeichen je Teil).
        val parts = try {
            sms.divideMessage(text)
        } catch (_: Exception) {
            result.success("failed")
            return
        }
        if (parts.isEmpty()) {
            result.success("failed")
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var replied = false
        var remaining = parts.size
        var firstError: String? = null
        lateinit var receiver: BroadcastReceiver
        lateinit var timeout: Runnable

        fun finish(outcome: String) {
            if (replied) return
            replied = true
            handler.removeCallbacks(timeout)
            try {
                context.unregisterReceiver(receiver)
            } catch (_: Exception) {
                // Schon abgemeldet.
            }
            result.success(outcome)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action != action) return
                when (resultCode) {
                    Activity.RESULT_OK -> Unit
                    SmsManager.RESULT_ERROR_NO_SERVICE ->
                        firstError = firstError ?: "no_service"
                    SmsManager.RESULT_ERROR_RADIO_OFF ->
                        firstError = firstError ?: "radio_off"
                    else ->
                        firstError = firstError ?: "failed"
                }
                remaining -= 1
                if (remaining <= 0) finish(firstError ?: "sent")
            }
        }

        timeout = Runnable {
            // Manche Netze/ROMs schicken den Sent-Broadcast nie. Die SMS ist
            // dann meist trotzdem raus — als unbestätigt melden statt als
            // Fehler, sonst wiederholt die Warteschlange sie endlos.
            finish(if (remaining < parts.size) firstError ?: "sent" else "sent_unconfirmed")
        }

        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        handler.postDelayed(timeout, SEND_TIMEOUT_MS)

        val sentIntents = ArrayList<PendingIntent>(parts.size)
        for (i in parts.indices) {
            sentIntents.add(
                PendingIntent.getBroadcast(
                    context,
                    id * 100 + i,
                    Intent(action).setPackage(context.packageName),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }

        try {
            if (parts.size == 1) {
                sms.sendTextMessage(number, null, parts[0], sentIntents[0], null)
            } else {
                sms.sendMultipartTextMessage(number, null, parts, sentIntents, null)
            }
        } catch (_: SecurityException) {
            finish("permission_denied")
        } catch (_: IllegalArgumentException) {
            finish("invalid_number")
        } catch (_: Exception) {
            finish("failed")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false

        val number = pendingNumber
        val text = pendingText
        val result = pendingResult
        pendingNumber = null
        pendingText = null
        pendingResult = null
        if (number == null || text == null || result == null) return true

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            send(number, text, result)
            return true
        }

        // Bei sideloaded APKs ist SEND_SMS "hard restricted": der Dialog
        // erscheint gar nicht, solange in App-Info nicht einmalig
        // "Eingeschränkte Einstellungen zulassen" bestätigt wurde. Das sieht
        // von hier aus wie ein dauerhaftes Nein — Flutter zeigt dann die
        // Anleitung, statt bei jedem Tipp neu zu fragen.
        val act = activity
        val permanent = act == null ||
            !act.shouldShowRequestPermissionRationale(Manifest.permission.SEND_SMS)
        result.success(if (permanent) "permission_denied_permanently" else "permission_denied")
        return true
    }

    companion object {
        private const val CHANNEL = "de.icd360sev.vorsitzer/sms"
        private const val PERMISSION_REQUEST = 5418

        /** Wartezeit auf den Sendebericht, bevor die SMS als unbestätigt gilt. */
        private const val SEND_TIMEOUT_MS = 45_000L
    }
}
