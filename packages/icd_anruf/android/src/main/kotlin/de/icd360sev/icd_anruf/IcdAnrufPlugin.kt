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
import io.flutter.plugin.common.PluginRegistry

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
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.NewIntentListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    /** Offene Antwort des Berechtigungsdialogs. */
    private var rechtErgebnis: MethodChannel.Result? = null

    /**
     * Nummer, die nach dem Erteilen der Berechtigung noch gewählt werden soll.
     *
     * Ohne sie ginge der Auftrag beim Freigeben verloren: der Nutzer tippt auf
     * die Benachrichtigung, erlaubt — und müsste am Rechner erneut klicken,
     * weil niemand mehr weiß, worum es ging.
     */
    private var wartendeNummer: String? = null

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
        binding.addRequestPermissionsResultListener(this)
        binding.addOnNewIntentListener(this)
        // Wurde die App ÜBER die Benachrichtigung gestartet, steht der Auftrag
        // schon im Start-Intent — onNewIntent kommt dann nie.
        nachtraeglichWaehlen(binding.activity.intent)
    }

    override fun onNewIntent(intent: Intent): Boolean = nachtraeglichWaehlen(intent)

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

            "anrufrechtAnfragen" -> anrufrechtAnfragen(result)

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
            // ⚠️ Hier stand `ACTION_DIAL`: die Benachrichtigung öffnete den
            // Dialer, und der Nutzer musste dort noch auf den grünen Hörer
            // tippen. Drei Handgriffe für einen Anruf, den er mit einem Klick
            // angestoßen hatte — und beim nächsten Mal wieder dieselben drei,
            // weil sich an der Ursache nichts änderte.
            //
            // Die Benachrichtigung führt jetzt dorthin, wo das Problem gelöst
            // wird: in die App, die sofort die Berechtigung erfragt und danach
            // den wartenden Auftrag selbst wählt. Einmal „Zulassen", nie wieder.
            val gelegt = berechtigungBenachrichtigung(nummer, bezeichnung)
            return antworte(
                result,
                KEINE_BERECHTIGUNG,
                if (gelegt) "Anrufberechtigung fehlt — Benachrichtigung führt zur Freigabe"
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

    // ── Anrufberechtigung ───────────────────────────────────────────────────

    /**
     * Fragt `CALL_PHONE` an.
     *
     * WARUM DAS EINEN EIGENEN WEG BRAUCHT
     * Bisher wurde die Berechtigung nur dort erfragt, wo jemand AUF DEM TELEFON
     * eine Rufnummer antippt (`MainActivity.startDirectCall`). Wer die Fernwahl
     * benutzt, tippt aber am Rechner — auf dem Telefon passiert nie etwas, das
     * den Dialog auslösen könnte. Genau daran ist der erste echte Versuch
     * gescheitert: das Pixel holte den Auftrag ab, das Plugin lief, und meldete
     * „Anrufberechtigung fehlt". Aus dem Hintergrund lässt sich kein Dialog
     * öffnen, also muss er von der Einstellungsseite kommen.
     *
     * @return "erteilt", "abgelehnt", "dauerhaft_abgelehnt", "kein_dialog"
     *         (App nicht im Vordergrund) oder "laeuft_schon".
     */
    private fun anrufrechtAnfragen(result: MethodChannel.Result) {
        if (hatAnrufrecht()) return result.success("erteilt")

        val act = activity ?: return result.success("kein_dialog")

        // Ein zweiter Aufruf bei offenem Dialog würde den ersten Result
        // verwaisen lassen; Flutter wirft dann beim zweiten reply().
        if (rechtErgebnis != null) return result.success("laeuft_schon")

        rechtErgebnis = result
        act.requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), RECHT_ANFRAGE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != RECHT_ANFRAGE) return false

        val result = rechtErgebnis
        rechtErgebnis = null

        val erteilt = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        // Kam die Freigabe über die Benachrichtigung, wartet dort ein Auftrag.
        // Ihn jetzt zu wählen ist der ganze Sinn des Weges — sonst hätte der
        // Nutzer erlaubt und müsste trotzdem von vorn anfangen.
        val nummer = wartendeNummer
        wartendeNummer = null
        if (erteilt && nummer != null) {
            Thread { versucheAlleWege(nummer, null) }.start()
        }

        if (erteilt) {
            result?.success("erteilt")
            return true
        }

        // „Nicht mehr fragen": der Dialog kommt nicht wieder, es hilft nur die
        // Systemseite. Das gehört unterschieden, sonst tippt der Nutzer ewig
        // auf einen Knopf, der nichts mehr bewirkt.
        val dauerhaft = activity?.shouldShowRequestPermissionRationale(
            Manifest.permission.CALL_PHONE
        ) == false
        result?.success(if (dauerhaft) "dauerhaft_abgelehnt" else "abgelehnt")
        return true
    }

    // ── Fehlende Berechtigung: Benachrichtigung, die sie einholt ────────────

    /**
     * Benachrichtigung für den Fall „darf nicht anrufen".
     *
     * Führt in die App statt in den Dialer. Der Tipp öffnet [MainActivity] mit
     * der wartenden Nummer im Intent; [nachtraeglichWaehlen] fragt dann die
     * Berechtigung ab und wählt bei Erfolg sofort. Der Nutzer tippt also
     * einmal auf „Zulassen" — und ab da wählt jeder weitere Auftrag von allein,
     * weil die Ursache beseitigt ist statt umgangen.
     */
    private fun berechtigungBenachrichtigung(nummer: String, bezeichnung: String?): Boolean {
        return try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return false
            kanalAnlegen(nm)

            val start = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    action = AKTION_NACHWAEHLEN
                    putExtra(EXTRA_NUMMER, nummer)
                    putExtra(EXTRA_BEZEICHNUNG, bezeichnung)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                } ?: return false

            val pi = PendingIntent.getActivity(
                context, nummer.hashCode(), start,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val wen = if (bezeichnung.isNullOrBlank()) nummer else "$bezeichnung ($nummer)"
            val bau = NotificationCompat.Builder(context, KANAL_ID)
                .setSmallIcon(android.R.drawable.sym_action_call)
                .setContentTitle("Anrufen: $wen")
                .setContentText("Einmalig freigeben — danach wählt dieses Gerät von allein")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .addAction(android.R.drawable.ic_menu_manage, "Freigeben und anrufen", pi)

            if (darfVollbild()) bau.setFullScreenIntent(pi, true)
            nm.notify(BENACHRICHTIGUNG_ID, bau.build())
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Nimmt die Nummer aus dem Intent, holt die Berechtigung und wählt.
     *
     * Wird beim Antippen der Benachrichtigung erreicht — und nur dann steht
     * die App im Vordergrund, also nur dann lässt sich überhaupt ein Dialog
     * öffnen. Genau deshalb geht dieser Weg über die App und nicht über den
     * Dialer.
     */
    private fun nachtraeglichWaehlen(intent: Intent?): Boolean {
        if (intent?.action != AKTION_NACHWAEHLEN) return false
        val nummer = intent.getStringExtra(EXTRA_NUMMER) ?: return false

        // Nur einmal: sonst wählt jedes Wiederherstellen der Activity erneut.
        intent.action = null
        intent.removeExtra(EXTRA_NUMMER)

        if (hatAnrufrecht()) {
            Thread { versucheAlleWege(nummer, intent.getStringExtra(EXTRA_BEZEICHNUNG)) }.start()
            return true
        }

        val act = activity ?: return false
        wartendeNummer = nummer
        act.requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), RECHT_ANFRAGE)
        return true
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
            kanalAnlegen(nm)

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

    private fun kanalAnlegen(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        nm.createNotificationChannel(
            NotificationChannel(KANAL_ID, "Anruf-Aufträge", NotificationManager.IMPORTANCE_HIGH)
                .apply {
                    description = "Anrufe, die von einem anderen Vereinsgerät " +
                        "angestoßen wurden und hier bestätigt werden müssen."
                    setShowBadge(true)
                }
        )
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

        /** Anfragecode des Berechtigungsdialogs. */
        private const val RECHT_ANFRAGE = 4711

        /** Intent-Aktion der Benachrichtigung „freigeben und anrufen". */
        private const val AKTION_NACHWAEHLEN = "de.icd360sev.anruf.NACHWAEHLEN"
        private const val EXTRA_NUMMER = "icd_anruf_nummer"
        private const val EXTRA_BEZEICHNUNG = "icd_anruf_bezeichnung"

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
