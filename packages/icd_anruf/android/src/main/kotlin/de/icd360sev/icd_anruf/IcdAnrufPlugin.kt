package de.icd360sev.icd_anruf

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Wählt eine Rufnummer, die ein anderes Vorsitzer-Gerät angestoßen hat.
 *
 * WARUM DAS NICHT EINFACH `startActivity(ACTION_CALL)` IST
 * Der Auftrag kommt im Vordergrunddienst an, und für das Starten von
 * Activities zählt ein Gerät mit laufendem Vordergrunddienst laut Android
 * ausdrücklich als *im Hintergrund*. `startActivity` wird dann **stumm**
 * verworfen — kein Wurf, keine Ausnahme, nur eine Zeile im Logcat. Ein
 * Rückgabewert "gewählt" wäre also gelogen.
 *
 * Deshalb drei Wege in dieser Reihenfolge, und nach jedem eine Nachprüfung am
 * Telefoniezustand statt einer Annahme:
 *
 *   1. [TelecomManager.placeCall] — den Anruf setzt die Telefonie des Systems
 *      ab, nicht unser Prozess. Das ist der einzige Weg, der ohne zusätzliche
 *      Sonderrechte auskommen *kann*; ob er es auf einem konkreten Android
 *      tut, sagt keine Dokumentation zu, also wird es geprüft.
 *   2. `startActivity(ACTION_CALL)` — greift, wenn die App gerade sichtbar ist
 *      oder „Über anderen Apps anzeigen" erteilt wurde. Letzteres ist die
 *      offizielle Ausnahme von der Hintergrundsperre und der Grund, warum
 *      Tasker sie seit Android 10 verlangt.
 *   3. Benachrichtigung mit PendingIntent — ein Tipp wählt. Aus einem vom
 *      System gesendeten PendingIntent darf die Activity starten, das ist die
 *      zweite offizielle Ausnahme. Ist zusätzlich das Recht auf
 *      Vollbild-Benachrichtigungen erteilt, wählt Android bei ausgeschaltetem
 *      Bildschirm sogar von allein.
 *
 * Weg 3 ist keine Niederlage, sondern die Zusage, dass ein Auftrag nie
 * spurlos verschwindet. Genau das wäre die schlimmste Betriebsart: der
 * Vorsitzer klickt am Linux-Rechner, sieht „abgeschickt", und am Telefon
 * passiert nie etwas.
 */
class IcdAnrufPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    private val haupt = Handler(Looper.getMainLooper())

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
            "faehigkeiten" -> result.success(faehigkeiten())

            "waehlen" -> {
                val nummer = call.argument<String>("nummer").orEmpty()
                val bezeichnung = call.argument<String>("bezeichnung")
                waehlen(nummer, bezeichnung, result)
            }

            "overlayEinstellungOeffnen" -> result.success(oeffneOverlayEinstellung())

            "vollbildEinstellungOeffnen" -> result.success(oeffneVollbildEinstellung())

            else -> result.notImplemented()
        }
    }

    // ── Auskunft ────────────────────────────────────────────────────────────

    /**
     * Was dieses Gerät kann — ohne etwas zu versuchen.
     *
     * Die Oberfläche des sendenden Geräts zeigt daraus, warum ein Auftrag
     * gegebenenfalls nur als Benachrichtigung ankommt. Ein Gateway, das
     * behauptet bereit zu sein, während ihm „Über anderen Apps anzeigen"
     * fehlt, wäre schlimmer als gar keins.
     */
    private fun faehigkeiten(): Map<String, Any> = mapOf(
        "telefonie" to hatTelefonie(),
        "anrufrecht" to hatAnrufrecht(),
        "overlay" to darfUeberlagern(),
        "vollbild" to darfVollbild(),
        "imVordergrund" to (activity != null),
        "imGespraech" to istImGespraech()
    )

    private fun hatTelefonie(): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)

    private fun hatAnrufrecht(): Boolean =
        context.checkSelfPermission(Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED

    /** „Über anderen Apps anzeigen" — die Ausnahme von der Hintergrundsperre. */
    private fun darfUeberlagern(): Boolean = Settings.canDrawOverlays(context)

    private fun darfVollbild(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val nm = context.getSystemService(NotificationManager::class.java) ?: return false
        return nm.canUseFullScreenIntent()
    }

    /**
     * Läuft gerade ein Gespräch? Zugleich die Nachprüfung, ob ein Wählversuch
     * gegriffen hat — `isInCall()` ist ab dem Wählen wahr, nicht erst beim
     * Abheben.
     */
    private fun istImGespraech(): Boolean {
        try {
            val tm = context.getSystemService(TelecomManager::class.java)
            if (tm != null) return tm.isInCall
        } catch (_: SecurityException) {
            // READ_PHONE_STATE entzogen — unten der zweite Versuch.
        } catch (_: Exception) {
            // Telefonieprozess nicht erreichbar (WLAN-Tablet).
        }
        return try {
            val tm = context.getSystemService(TelephonyManager::class.java)
            @Suppress("DEPRECATION")
            tm != null && tm.callState != TelephonyManager.CALL_STATE_IDLE
        } catch (_: Exception) {
            false
        }
    }

    // ── Wählen ──────────────────────────────────────────────────────────────

    private fun waehlen(roh: String, bezeichnung: String?, result: MethodChannel.Result) {
        val nummer = roh.filter { it.isDigit() || it == '+' || it == '*' || it == '#' }

        if (nummer.count { it.isDigit() } < 3) {
            return antworte(result, UNGUELTIG, "Keine wählbare Rufnummer: $roh")
        }
        if (!hatTelefonie()) {
            return antworte(result, KEIN_TELEFON, "Dieses Gerät kann nicht telefonieren")
        }
        // Ein Notruf, den ein Rechner in einem anderen Raum auslöst, ist kein
        // Notruf, sondern ein Fehlalarm bei der Leitstelle. ACTION_CALL darf
        // 110/112 ohnehin nicht wählen — hier wird es aber ausdrücklich
        // abgelehnt statt still in den Dialer zu fallen, wo niemand steht.
        if (istNotruf(nummer)) {
            return antworte(result, NOTRUF, "Notrufe werden nicht ferngesteuert gewählt")
        }
        if (istImGespraech()) {
            return antworte(result, FEHLER, "Es läuft bereits ein Gespräch")
        }
        if (!hatAnrufrecht()) {
            // Ohne CALL_PHONE geht gar nichts von allein. Die Benachrichtigung
            // öffnet dann den Dialer, damit der Auftrag nicht verfällt.
            val gelegt = benachrichtigen(nummer, bezeichnung, Intent.ACTION_DIAL)
            return antworte(
                result,
                KEINE_BERECHTIGUNG,
                if (gelegt) "Anrufberechtigung fehlt — Benachrichtigung gelegt"
                else "Anrufberechtigung fehlt"
            )
        }

        // Ab hier wird gewartet und nachgeprüft: nicht auf dem Hauptthread.
        Thread {
            val (code, meldung, weg) = versucheAlleWege(nummer, bezeichnung)
            haupt.post { antworte(result, code, meldung, weg) }
        }.start()
    }

    /** @return Tripel aus Ergebniscode, Klartextmeldung und benutztem Weg. */
    private fun versucheAlleWege(
        nummer: String,
        bezeichnung: String?
    ): Triple<String, String, String> {
        val uri = Uri.fromParts("tel", nummer, null)

        // Weg 1: die Telefonie des Systems setzt den Anruf ab.
        try {
            val tm = context.getSystemService(TelecomManager::class.java)
            if (tm != null) {
                tm.placeCall(uri, null)
                if (wurdeGewaehlt()) {
                    return Triple(GEWAEHLT, "Anruf läuft", "telecom")
                }
            }
        } catch (e: SecurityException) {
            // Berechtigung zur Laufzeit entzogen — Weg 2 wird es auch nicht
            // schaffen, aber die Benachrichtigung schon.
            return Triple(KEINE_BERECHTIGUNG, "Telecom verweigert: ${e.message}", "telecom")
        } catch (_: Exception) {
            // Hersteller-ROM ohne Telecom-Weg — weiter mit Weg 2.
        }

        // Weg 2: eigener Activity-Start. Greift nur sichtbar oder mit
        // „Über anderen Apps anzeigen"; sonst verwirft Android ihn stumm,
        // weshalb danach wieder geprüft wird statt Erfolg zu melden.
        try {
            val ziel = activity ?: context
            ziel.startActivity(
                Intent(Intent.ACTION_CALL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            if (wurdeGewaehlt()) {
                return Triple(GEWAEHLT, "Anruf läuft", "activity")
            }
        } catch (_: Exception) {
            // Auch das darf scheitern; Weg 3 fängt es auf.
        }

        // Weg 3: der Auftrag bleibt sichtbar liegen.
        val gelegt = benachrichtigen(nummer, bezeichnung, Intent.ACTION_CALL)
        val grund = if (darfUeberlagern()) {
            "Android hat den Anruf aus dem Hintergrund abgewiesen"
        } else {
            // Achtung: schließendes Anführungszeichen typografisch (U+201C).
            // Ein gerades " beendet hier den Kotlin-String — genau daran ist
            // der erste Build gescheitert, und flutter analyze sieht es nicht.
            "„Über anderen Apps anzeigen“ ist für diese App aus"
        }
        return if (gelegt) {
            Triple(BESTAETIGUNG_NOETIG, "$grund — Benachrichtigung gelegt", "notification")
        } else {
            Triple(FEHLER, "$grund, und die Benachrichtigung ging auch nicht", "keiner")
        }
    }

    /**
     * Wartet kurz und sieht nach, ob wirklich ein Anruf zustande kam.
     *
     * Bis zu [PRUEF_DAUER_MS] in Schritten von [PRUEF_TAKT_MS]: die Telefonie
     * braucht einen Moment, bis der Zustand umspringt. Ein einzelner Blick
     * unmittelbar nach dem Aufruf sagt fast immer „nein" und wäre damit
     * genauso falsch wie gar nicht zu prüfen.
     */
    private fun wurdeGewaehlt(): Boolean {
        var gewartet = 0L
        while (gewartet < PRUEF_DAUER_MS) {
            if (istImGespraech()) return true
            try {
                Thread.sleep(PRUEF_TAKT_MS)
            } catch (_: InterruptedException) {
                return istImGespraech()
            }
            gewartet += PRUEF_TAKT_MS
        }
        return istImGespraech()
    }

    private fun istNotruf(nummer: String): Boolean {
        val blank = nummer.filter { it.isDigit() }
        if (blank.isEmpty()) return false
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val tm = context.getSystemService(TelephonyManager::class.java)
                if (tm != null) return tm.isEmergencyNumber(blank)
            }
        } catch (_: Exception) {
            // Telefonieprozess stumm — die Liste unten muss reichen.
        }
        return blank in setOf("110", "112", "911", "999")
    }

    // ── Weg 3: Benachrichtigung ─────────────────────────────────────────────

    /**
     * Legt eine Benachrichtigung, deren Tipp wählt.
     *
     * Der PendingIntent wird vom System gesendet — das ist die offizielle
     * Ausnahme von der Hintergrundsperre, also wählt ein Tipp wirklich, statt
     * nur die App zu öffnen. Ist zusätzlich das Vollbildrecht erteilt, startet
     * Android den Anruf bei ausgeschaltetem Bildschirm selbst.
     */
    private fun benachrichtigen(nummer: String, bezeichnung: String?, aktion: String): Boolean {
        return try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val kanal = NotificationChannel(
                    KANAL_ID,
                    "Anruf-Aufträge",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Anrufe, die von einem anderen Vereinsgerät " +
                        "angestoßen wurden und hier bestätigt werden müssen."
                    setShowBadge(true)
                }
                nm.createNotificationChannel(kanal)
            }

            val intent = Intent(aktion, Uri.fromParts("tel", nummer, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val pi = PendingIntent.getActivity(
                context,
                nummer.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val wen = if (bezeichnung.isNullOrBlank()) nummer else "$bezeichnung ($nummer)"
            val bau = NotificationCompat.Builder(context, KANAL_ID)
                .setSmallIcon(android.R.drawable.sym_action_call)
                .setContentTitle("Anrufen: $wen")
                .setContentText("Von einem anderen Vereinsgerät angestoßen — tippen zum Wählen")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .addAction(android.R.drawable.sym_action_call, "Anrufen", pi)

            // Nur wenn erlaubt: sonst verwirft Android ab 14 die ganze
            // Benachrichtigung statt sie ohne Vollbild zu zeigen.
            if (darfVollbild()) bau.setFullScreenIntent(pi, true)

            nm.notify(BENACHRICHTIGUNG_ID, bau.build())
            true
        } catch (_: Exception) {
            false
        }
    }

    // ── Einstellungsseiten ──────────────────────────────────────────────────

    /** Systemseite „Über anderen Apps anzeigen" für genau diese App. */
    private fun oeffneOverlayEinstellung(): Boolean = try {
        val ziel: Context = activity ?: context
        ziel.startActivity(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (_: Exception) {
        false
    }

    /** Systemseite „Vollbild-Benachrichtigungen" (ab Android 14). */
    private fun oeffneVollbildEinstellung(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        return try {
            val ziel: Context = activity ?: context
            ziel.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:${context.packageName}")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    // ── Antwort ─────────────────────────────────────────────────────────────

    private fun antworte(
        result: MethodChannel.Result,
        code: String,
        meldung: String,
        weg: String = "keiner"
    ) {
        result.success(mapOf("ergebnis" to code, "meldung" to meldung, "weg" to weg))
    }

    companion object {
        private const val CHANNEL = "de.icd360sev.vorsitzer/fernanruf"

        private const val KANAL_ID = "anruf_auftraege"
        private const val BENACHRICHTIGUNG_ID = 47110

        /** Wie lange auf das Umspringen des Telefoniezustands gewartet wird. */
        private const val PRUEF_DAUER_MS = 4000L
        private const val PRUEF_TAKT_MS = 250L

        // Vertrag mit `IcdAnrufErgebnis` in lib/icd_anruf.dart.
        private const val GEWAEHLT = "gewaehlt"
        private const val BESTAETIGUNG_NOETIG = "bestaetigung_noetig"
        private const val KEINE_BERECHTIGUNG = "keine_berechtigung"
        private const val KEIN_TELEFON = "kein_telefon"
        private const val NOTRUF = "notruf"
        private const val UNGUELTIG = "ungueltig"
        private const val FEHLER = "fehler"
    }
}
