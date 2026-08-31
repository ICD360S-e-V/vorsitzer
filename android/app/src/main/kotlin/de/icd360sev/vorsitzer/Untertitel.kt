package de.icd360sev.vorsitzer

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.webrtc.AudioTrack
import org.webrtc.AudioTrackSink
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Live-Mitschrift dessen, was die GEGENSTELLE sagt.
 *
 * WOFUER
 * Der Vorsitzende hoert schlecht. Am Telefon fehlt ihm damit genau das, was in
 * einem Behoerdengespraech zaehlt: Zahlen, Daten, Namen. Hier laeuft mit, was
 * der andere sagt, waehrend er spricht.
 *
 * ⚠️ ES WIRD NICHTS AUFGEZEICHNET UND NICHTS GESPEICHERT. Kein Ton, kein Text.
 * Die Woerter stehen auf dem Schirm, solange das Gespraech laeuft, und sind
 * danach weg. Festlegung des Users, und zugleich die Linie des § 201 StGB:
 * mitlesen, um zu verstehen, ist etwas anderes als eine Aufnahme des
 * gesprochenen Wortes.
 *
 * ⚠️ ES IST KEIN GOOGLE IM SPIEL, UND ZWAR AUS NOTWENDIGKEIT, NICHT AUS HALTUNG.
 * Der naheliegende Weg waere `SpeechRecognizer.createOnDeviceSpeechRecognizer()`
 * gewesen. Der bindet aber an den Offline-Systemdienst, und den stellt auf
 * gewoehnlichen Geraeten Googles „Android System Intelligence"
 * (`com.google.android.as`) — ein Teil von Play. Ohne Play gibt es ihn nicht:
 * auf GrapheneOS liefert `isOnDeviceRecognitionAvailable()` `false`, und im
 * Fehlerverfolger des Projekts steht so ein Dienst als OFFENE Bitte
 * (GrapheneOS/os-issue-tracker#1593). Auf dem Zielgeraet — Pixel Fold mit
 * GrapheneOS — waere die Mitschrift nie angesprungen.
 *
 * Deshalb Vosk (Apache 2.0): das Modell liegt auf dem Geraet, die Erkennung
 * laeuft in unserem eigenen Prozess.
 *
 * ⚠️ NEBENBEI FAELLT EINE GANZE FEHLERKLASSE WEG. Beim Android-Erkenner musste
 * eigens geprueft werden, ob er statt der Leitung heimlich das MIKROFON
 * oeffnet — die Doku zu `EXTRA_AUDIO_SOURCE` sieht genau diesen stillen
 * Rueckfall vor. Hier gibt es im ganzen Weg kein Mikrofon: die Proben kommen
 * aus dem `AudioTrackSink` der Gegenstelle und gehen unmittelbar in den
 * Erkenner. Der Fehler kann nicht auftreten.
 *
 * WIE DER TON UEBERHAUPT ERREICHBAR IST
 * Bei einem Anruf ueber die SIM-Karte waere das unmoeglich — Android sperrt die
 * Quelle `VOICE_CALL` seit Android 10. Hier laeuft das Gespraech ueber WebRTC im
 * EIGENEN Prozess: wir empfangen das RTP und dekodieren es selbst.
 * `org.webrtc.AudioTrack.addSink()` liefert genau diese Tonspur (geprueft mit
 * `javap` gegen die ausgelieferte AAR 144.7559.09), und
 * `FlutterWebRTCPlugin.sharedSingleton.getRemoteTrack(id)` gibt sie heraus.
 */
class Untertitel(private val ctx: Context) {

    companion object {
        private const val TAG = "Untertitel"

        /** Womit das Modell gefuettert wird. Vosk-Modelle sind auf 16 kHz trainiert. */
        private const val ZIEL_RATE = 16000

        /**
         * Wie viel Ton in EINE Nachricht an den Server geht.
         *
         * 🔴 GEMESSEN, nicht geschaetzt — und die naheliegende Wahl war die
         * schlechteste. WebRTC liefert 10-ms-Rahmen; wer sie einzeln
         * weiterreicht, schickt 100 Nachrichten je Sekunde, und der Server
         * kommt nicht hinterher: der Text hing im Median 556 ms hinter dem Ton.
         *
         *   Stueck    Pakete/s   Verzug Median   p95
         *    10 ms       100         556 ms     1139 ms
         *   100 ms        10          85 ms      258 ms   ← gewaehlt
         *   250 ms         4         292 ms      726 ms
         *
         * ⚠️ Groesser ist auch nicht besser: bei 250 ms dauert die Verarbeitung
         * je Stueck laenger und der Verzug steigt wieder. 100 ms ist der Punkt
         * dazwischen — und nebenbei zehnmal weniger Pakete auf einer
         * Mobilfunkleitung, auf der wir Einbrueche unter 2 Mbit/s gemessen
         * haben.
         */
        private const val STROM_STUECK_MS = 100
        private const val STROM_PROBEN = ZIEL_RATE * STROM_STUECK_MS / 1000

        /**
         * ⚠️ Der Rueckruf kommt aus einem WebRTC-Tonthread. Wer dort blockiert,
         * laesst das GESPRAECH stocken — die Mitschrift wuerde also genau das
         * kaputtmachen, wozu sie da ist. Lieber ein Stueck Text verlieren als
         * eine Silbe Ton.
         */
        private const val PUFFER_STUECKE = 32

        /** Wo das Sprachmodell liegt, sobald es geholt wurde. */
        /**
         * Das WebRTC-Plugin DER HAUPT-ENGINE.
         *
         * 🔴 WARUM NICHT `FlutterWebRTCPlugin.sharedSingleton`. Dessen
         * Konstruktor macht `sharedSingleton = this` — JEDE neue Instanz
         * überschreibt ihn also. Und diese Anwendung hat mehr als eine
         * Flutter-Engine: neben der Oberfläche laufen die Hintergrunddienste
         * (SMS-Gateway, Anruf-Gateway, Signatur), und jede solche Engine
         * registriert über `GeneratedPluginRegistrant` ein eigenes
         * `FlutterWebRTCPlugin`. Der Kommentar im Plugin sagt es selbst:
         * „can be instantiated multiple times".
         *
         * Löst sich eine solche Engine wieder, setzt `stopListening()` ihren
         * `methodCallHandler` auf null — `sharedSingleton` zeigt aber weiter
         * auf sie. Im Betrieb sah das am 31.08.2026 so aus:
         *
         *   NullPointerException: 'MediaStreamTrack
         *   MethodCallHandlerImpl.getRemoteTrack(String)' on a null object
         *   reference at FlutterWebRTCPlugin.getRemoteTrack
         *
         * ⚠️ `?.` hilft dagegen NICHT: der Zeiger ist nicht null, sein
         * Innenleben ist es. Deshalb wird die Instanz gemerkt, solange sie
         * noch die richtige ist — beim Einrichten der Haupt-Engine.
         */
        @JvmStatic
        var webrtcPlugin: FlutterWebRTCPlugin? = null

        fun modellOrdner(ctx: Context): File = File(ctx.filesDir, "vosk-de")

        fun modellDa(ctx: Context): Boolean {
            val o = modellOrdner(ctx)
            // Ein Vosk-Modell ist ein Ordner; `am` ist der Teil, ohne den es
            // nicht laedt. Blosses Vorhandensein des Ordners genuegt nicht —
            // ein abgebrochener Download haette auch einen.
            return o.isDirectory && File(o, "am").isDirectory
        }
    }

    private var modell: Model? = null
    private var erkenner: Recognizer? = null

    /**
     * Wohin der Ton geht.
     *
     * `false` = wie bisher: das kleine Modell erkennt HIER auf dem Geraet.
     * `true`  = der Ton wird nur weitergereicht; erkannt wird auf unserem
     *           Server mit dem grossen Modell.
     *
     * ⚠️ Am Telefonband gemessen (300–3400 Hz, µ-law hin und zurueck): das
     * kleine Modell 17,6 % Wortfehler, das grosse 0,0 %. Das grosse braucht
     * 4,4 GB Arbeitsspeicher — auf diesem Geraet unmoeglich.
     *
     * ⚠️ Im Strommodus wird der Erkenner GAR NICHT angelegt: das spart dem
     * Tablet nicht nur den Speicher, sondern auch die Rechenzeit.
     */
    private var strommodus = false

    /** Sammelt die 10-ms-Rahmen, bis ein Stueck voll ist. */
    private val stromPuffer = ArrayList<Short>(STROM_PROBEN * 2)
    private var sink: AudioTrackSink? = null
    private var spur: AudioTrack? = null
    private var pumpe: Thread? = null

    private val laeuft = AtomicBoolean(false)
    private val verworfen = AtomicLong(0)
    private val warteschlange = ArrayBlockingQueue<ShortArray>(PUFFER_STUECKE)
    private val haupt = Handler(Looper.getMainLooper())

    private var senke: EventChannel.EventSink? = null

    fun senkeSetzen(s: EventChannel.EventSink?) {
        senke = s
    }

    private fun melde(art: String, daten: Map<String, Any?> = emptyMap()) {
        haupt.post { senke?.success(HashMap(daten).apply { put("art", art) }) }
    }

    fun faehig(): Map<String, Any> = mapOf(
        "modellDa" to modellDa(ctx),
        "modellPfad" to modellOrdner(ctx).absolutePath,
        // Kein Google, keine Netzabfrage, keine Play-Dienste — deshalb steht
        // hier nichts ueber Verfuegbarkeit eines Systemdienstes.
        "brauchtGoogle" to false,
    )

    fun starten(spurId: String, unused: String, strom: Boolean = false): Map<String, Any?> {
        if (laeuft.get()) return mapOf("ok" to true, "hinweis" to "laeuft schon")
        strommodus = strom
        // ⚠️ Das Modell wird nur im lokalen Betrieb gebraucht. Im Strommodus
        // danach zu fragen hiesse, die bessere Erkennung an einer Datei
        // scheitern zu lassen, die dafuer gar nicht noetig ist.
        if (!strom && !modellDa(ctx)) {
            return mapOf("ok" to false, "grund" to
                    "Das deutsche Sprachmodell ist noch nicht auf dem Geraet.",
                "modellFehlt" to true)
        }

        // ⚠️ Erst die gemerkte Instanz, dann der Singleton als Rückfall — und
        // beides in einem Fang: ein NullPointer aus dem Plugin soll eine
        // lesbare Meldung ergeben, keinen Absturzbericht auf dem Schirm.
        val ziel = try {
            (webrtcPlugin ?: FlutterWebRTCPlugin.sharedSingleton)
                ?.getRemoteTrack(spurId)
        } catch (e: Throwable) {
            Log.w(TAG, "getRemoteTrack nicht verfuegbar", e)
            null
        }
        if (ziel !is AudioTrack) {
            return mapOf("ok" to false, "grund" to "Tonspur der Gegenstelle nicht gefunden.")
        }

        return try {
            if (!strom) {
                val m = Model(modellOrdner(ctx).absolutePath)
                modell = m
                erkenner = Recognizer(m, ZIEL_RATE.toFloat())
            }

            laeuft.set(true)
            verworfen.set(0)
            warteschlange.clear()
            // ⚠️ Sonst begaenne das naechste Gespraech mit einem Rest des
            // vorigen — hoerbar als ein halbes fremdes Wort am Anfang.
            stromPuffer.clear()

            pumpeStarten()
            spurAnhaengen(ziel)
            melde("bereit")
            mapOf("ok" to true)
        } catch (e: Throwable) {
            Log.e(TAG, "Start fehlgeschlagen", e)
            stoppen()
            mapOf("ok" to false, "grund" to (e.message ?: e.toString()))
        }
    }

    private fun spurAnhaengen(ziel: AudioTrack) {
        val s = object : AudioTrackSink {
            override fun onData(
                daten: ByteBuffer, bitsProProbe: Int, rate: Int,
                kanaele: Int, rahmen: Int, zeitstempel: Long,
            ) {
                if (!laeuft.get() || bitsProProbe != 16) return
                val stueck = umrechnen(daten, rate, kanaele, rahmen) ?: return
                if (!warteschlange.offer(stueck)) verworfen.incrementAndGet()
            }
        }
        sink = s
        spur = ziel
        ziel.addSink(s)
    }

    /**
     * 48 kHz (Stereo) -> 16 kHz Mono.
     *
     * ⚠️ Ganzzahlige Dezimierung mit MITTELUNG, nicht jede n-te Probe nehmen:
     * blosses Auslassen faltet die hohen Anteile in den Sprachbereich zurueck
     * und macht die Erkennung schlechter statt besser.
     */
    private fun umrechnen(daten: ByteBuffer, rate: Int, kanaele: Int, rahmen: Int): ShortArray? {
        if (rahmen <= 0 || kanaele <= 0) return null
        val ein = daten.duplicate().order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        if (ein.limit() < rahmen * kanaele) return null

        val mono = ShortArray(rahmen)
        for (i in 0 until rahmen) {
            var summe = 0
            for (k in 0 until kanaele) summe += ein.get(i * kanaele + k).toInt()
            mono[i] = (summe / kanaele).toShort()
        }

        return when {
            rate == ZIEL_RATE -> mono
            rate % ZIEL_RATE == 0 -> {
                val f = rate / ZIEL_RATE
                ShortArray(rahmen / f) { i ->
                    var s = 0
                    for (j in 0 until f) s += mono[i * f + j].toInt()
                    (s / f).toShort()
                }
            }
            else -> {
                val n = (rahmen.toLong() * ZIEL_RATE / rate).toInt()
                ShortArray(n) { i ->
                    mono[(i.toLong() * rate / ZIEL_RATE).toInt().coerceAtMost(rahmen - 1)]
                }
            }
        }
    }

    private fun pumpeStarten() {
        val t = Thread({
            while (laeuft.get()) {
                val stueck = try {
                    warteschlange.poll(200, TimeUnit.MILLISECONDS)
                } catch (_: InterruptedException) {
                    null
                } ?: continue
                if (strommodus) {
                    // ⚠️ Sammeln, bis STROM_STUECK_MS beisammen sind. Einzeln
                    // weiterzureichen war messbar das Schlechteste (siehe dort).
                    stromPuffer.addAll(stueck.toList())
                    if (stromPuffer.size < STROM_PROBEN) continue
                    val block = ShortArray(stromPuffer.size) { stromPuffer[it] }
                    stromPuffer.clear()
                    // ⚠️ Little-Endian: der Erkenner auf dem Server erwartet
                    // 16-bit-PCM in genau dieser Reihenfolge. Andersherum
                    // haetten beide Seiten Rauschen statt Sprache — und nichts
                    // wuerde fehlschlagen, es kaeme nur nie ein Wort heraus.
                    val roh = ByteArray(block.size * 2)
                    for (i in block.indices) {
                        val v = block[i].toInt()
                        roh[i * 2] = (v and 0xFF).toByte()
                        roh[i * 2 + 1] = ((v shr 8) and 0xFF).toByte()
                    }
                    melde("ton", mapOf("pcm" to roh))
                    continue
                }
                val e = erkenner ?: break
                try {
                    // `true` = der Erkenner hat einen Satz abgeschlossen.
                    if (e.acceptWaveForm(stueck, stueck.size)) {
                        wortHeraus(e.result, "satz")
                    } else {
                        wortHeraus(e.partialResult, "teil")
                    }
                } catch (ex: Throwable) {
                    Log.w(TAG, "Erkennung fehlgeschlagen", ex)
                    break
                }
            }
        }, "untertitel-pumpe")
        t.isDaemon = true
        pumpe = t
        t.start()
    }

    /** Vosk antwortet als JSON: `{"text": "..."}` bzw. `{"partial": "..."}`. */
    private fun wortHeraus(json: String?, art: String) {
        if (json.isNullOrBlank()) return
        val w = try {
            val o = JSONObject(json)
            (if (art == "satz") o.optString("text") else o.optString("partial")).trim()
        } catch (_: Throwable) {
            return
        }
        if (w.isNotEmpty()) melde(art, mapOf("text" to w))
    }

    fun stoppen(): Map<String, Any?> {
        if (!laeuft.getAndSet(false)) return mapOf("ok" to true)
        try { spur?.let { s -> sink?.let { s.removeSink(it) } } } catch (_: Throwable) {}
        sink = null; spur = null
        pumpe?.interrupt(); pumpe = null
        warteschlange.clear()
        // ⚠️ Reihenfolge: erst der Erkenner, dann das Modell. Andersherum
        // arbeitet der Erkenner auf einem freigegebenen Modell weiter.
        try { erkenner?.close() } catch (_: Throwable) {}
        erkenner = null
        try { modell?.close() } catch (_: Throwable) {}
        modell = null
        if (verworfen.get() > 0) Log.w(TAG, "verworfene Tonstuecke: ${verworfen.get()}")
        return mapOf("ok" to true, "verworfen" to verworfen.get())
    }
}
