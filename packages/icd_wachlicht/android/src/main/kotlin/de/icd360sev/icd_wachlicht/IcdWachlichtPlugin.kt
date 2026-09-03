package de.icd360sev.icd_wachlicht

import android.content.Context
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Ein PARTIAL_WAKE_LOCK, der nur so lange gehalten wird, wie er gebraucht wird.
 *
 * WOFÜR DAS DA IST
 * `flutter_foreground_task` nimmt mit `allowWakeLock: true` einen
 * PARTIAL_WAKE_LOCK per `acquire()` OHNE Zeitgrenze und hält ihn, solange der
 * Dienst lebt (ForegroundService.kt:428). Auf dem Vereinsgerät heisst das:
 * rund um die Uhr, jeden Tag. Googles eigene Schwelle für „excessive" liegt
 * bei zwei Stunden binnen 24 (Android vitals, „Excessive partial wake locks").
 *
 * Der naheliegende Ausweg wirkt NICHT: `updateService` läuft im Plugin über
 * den Zweig `API_UPDATE`, und der ruft weder `acquireLockMode()` noch
 * `releaseLockMode()` — nur `startForegroundService` tut das. Ein umgestelltes
 * Flag liesse den bereits genommenen Lock also gehalten, und zwar lautlos.
 * Deshalb wird der Lock des Plugins abgeschaltet und hier selbst geführt.
 *
 * ⚠️ WARUM ÜBERHAUPT EIN EIGENES PLUGIN-PAKET
 * Nur registrierte Plugins landen im `GeneratedPluginRegistrant` und damit in
 * der Engine, die der Vordergrunddienst startet. Gebraucht wird das Wachlicht
 * genau dort, im Isolate des Wachdienstes — ein Kanal aus `MainActivity`
 * existiert dort nicht. Dieselbe Begründung wie bei `icd_sms`, `icd_anruf` und
 * `icd_netinfo`.
 *
 * ⚠️ JEDER LOCK HAT EINE ZEITGRENZE, IMMER.
 * `acquire()` ohne Argument ist genau der Fehler, den dieses Paket behebt; ein
 * Absturz zwischen Nehmen und Freigeben liesse das Gerät sonst für immer wach
 * („stuck wake lock"). Die Grenze wird bei jedem Nehmen neu gesetzt, der
 * Aufrufer erneuert also einfach, solange er sie braucht.
 */
class IcdWachlichtPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var kanal: MethodChannel
    private lateinit var kontext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        kontext = binding.applicationContext
        kanal = MethodChannel(binding.binaryMessenger, "de.icd360sev/wachlicht")
        kanal.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        kanal.setMethodCallHandler(null)
        // ⚠️ Beim Abbau freigeben. Stirbt die Engine mit gehaltenem Lock, hält
        // ihn niemand mehr für uns — und niemand gibt ihn je wieder frei.
        freigeben()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "nehmen" -> {
                val ms = (call.argument<Number>("timeoutMs"))?.toLong() ?: STANDARD_GRENZE_MS
                result.success(nehmen(ms))
            }
            "freigeben" -> result.success(freigeben())
            "gehalten" -> result.success(lock?.isHeld == true)
            else -> result.notImplemented()
        }
    }

    /**
     * Nimmt den Lock oder erneuert seine Zeitgrenze.
     *
     * Gibt zurück, ob der Lock danach gehalten wird.
     */
    private fun nehmen(timeoutMs: Long): Boolean {
        val grenze = timeoutMs.coerceIn(MIN_GRENZE_MS, MAX_GRENZE_MS)
        val pm = kontext.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        val l = lock ?: pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, TAG).also {
            // Nicht zählend: „gehalten" ist ein Zustand, kein Guthaben. Mit
            // Zählung müsste jedes Nehmen sein eigenes Freigeben finden, und
            // ein verlorener Takt liesse den Lock stehen.
            it.setReferenceCounted(false)
            lock = it
        }
        // acquire(timeout) auf einem bereits gehaltenen Lock setzt die Grenze
        // neu — genau das ist hier gewollt.
        l.acquire(grenze)
        return l.isHeld
    }

    /** Gibt den Lock frei, falls er gehalten wird. Mehrfach aufrufbar. */
    private fun freigeben(): Boolean {
        val l = lock ?: return false
        if (l.isHeld) {
            l.release()
        }
        return false
    }

    companion object {
        private const val TAG = "icd360sev:Wachlicht"

        /** Ohne Angabe: gross genug für einen Durchlauf, klein genug als Netz. */
        private const val STANDARD_GRENZE_MS = 60_000L

        /** Unter einer Sekunde ergibt ein Lock keinen Sinn. */
        private const val MIN_GRENZE_MS = 1_000L

        /**
         * ⚠️ Obergrenze, absichtlich niedriger als „für immer".
         *
         * Zehn Minuten reichen für jede Aufgabe dieses Dienstes und begrenzen
         * zugleich den Schaden, wenn ein Aufrufer die Freigabe vergisst. Wer
         * länger braucht, erneuert — dann steht die Verlängerung im Code und
         * ist nachlesbar, statt aus einem `acquire()` ohne Argument zu folgen.
         */
        private const val MAX_GRENZE_MS = 600_000L

        @Volatile
        private var lock: PowerManager.WakeLock? = null
    }
}
