package de.icd360sev.icd_netinfo

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.ScanResult
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.net.TrafficStats
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.telephony.CellInfo
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyDisplayInfo
import android.telephony.TelephonyManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Momentaufnahme des Netzes für den Speedtest.
 *
 * Beantwortet die Frage, die eine reine Durchsatzmessung offenlässt: die
 * Leitung war langsam — aber warum? Lag 5G an oder war das Gerät auf LTE
 * zurückgefallen, wie stark war das Signal, und was hat das Netz selbst
 * behauptet liefern zu können?
 *
 * WARUM DIE 5G-ERKENNUNG NICHT ÜBER getDataNetworkType() LÄUFT
 * Telekoms 5G ist überwiegend NSA (Non-Standalone): der Datenanker bleibt
 * LTE, NR kommt als zusätzlicher Träger dazu. getDataNetworkType() meldet in
 * genau diesem Fall brav NETWORK_TYPE_LTE. Eine Messreihe, die daraufhin
 * jahrelang „LTE" protokolliert, obwohl 5G anlag, wäre als Beweismittel
 * wertlos — und zwar in die für uns ungünstige Richtung. Den echten Zustand
 * kennt nur TelephonyDisplayInfo.getOverrideNetworkType(), und den gibt es
 * ausschließlich über einen laufenden Listener, nicht als Abfrage. Deshalb
 * hängt hier ein Listener dauerhaft und legt den letzten Wert beiseite.
 *
 * Läuft in JEDER Engine — auch in der, die WorkManager für die automatische
 * 30-Minuten-Messung startet. Dort gibt es keine Activity: fehlt eine
 * Berechtigung, bleibt das jeweilige Feld null. Es wird nie ein Dialog aus dem
 * Hintergrund versucht, und es wird nie geworfen — eine fehlende Netzangabe
 * darf keine Messung verhindern.
 */
class IcdNetinfoPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    private var pendingPermissionResult: MethodChannel.Result? = null

    /** Letzter bekannter Anzeige-Netztyp; nur von einem Listener befüllbar. */
    @Volatile private var letzterOverride: Int? = null
    private var listenerAktiv = false

    private var telephonyCallback: Any? = null
    private var phoneStateListener: PhoneStateListener? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        anzeigeListenerStarten()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        anzeigeListenerStoppen()
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> result.success(momentaufnahme())
            "deviceProfile" -> result.success(geraeteprofil())
            "trafficCounters" -> result.success(verkehrszaehler())
            "hasPhonePermission" -> result.success(hatTelefonRecht())
            "requestPhonePermission" -> telefonRechtAnfragen(result)
            else -> result.notImplemented()
        }
    }

    // ── Verkehrszähler ──────────────────────────────────────────────────────

    /**
     * Byte-Zähler des Geräts, roh und zustandslos.
     *
     * WOZU: Der billigste Einwand der Gegenseite lautet „Ihre 40 Mbit/s sind
     * das, was von 200 uebrig blieb, weil parallel etwas anderes lief". Bisher
     * war das unwiderlegbar — die Felder `alleine` und `koordiniert` decken nur
     * die drei eigenen angemeldeten Geraete ab, nicht ein Play-Store-Update
     * oder ein laufendes Videogespraech DERSELBEN App.
     *
     * Zustandslos mit Absicht: der Aufrufer liest zweimal und bildet die
     * Differenz. Ein Start/Ende-Paar im Plugin haette Zustand im Isolat, und
     * der WorkManager-Lauf hat keinen.
     *
     * ⚠️ TrafficStats liefert UNSUPPORTED (-1), wenn der Zaehler fehlt. Das
     * MUSS als null durchschlagen: die Differenz zweier -1 ergibt sauber 0, und
     * das Geraet spraeche sich still selbst frei.
     */
    private fun verkehrszaehler(): Map<String, Any?> {
        fun wert(v: Long): Long? = if (v == TrafficStats.UNSUPPORTED.toLong() || v < 0) null else v

        val d = HashMap<String, Any?>()
        try {
            d["gesamt_rx"] = wert(TrafficStats.getTotalRxBytes())
            d["gesamt_tx"] = wert(TrafficStats.getTotalTxBytes())
            d["mobil_rx"] = wert(TrafficStats.getMobileRxBytes())
            d["mobil_tx"] = wert(TrafficStats.getMobileTxBytes())
            // Nur unsere eigene App — die Differenz zum Gesamtwert sind andere
            // Apps und das System.
            d["eigen_rx"] = wert(TrafficStats.getUidRxBytes(Process.myUid()))
            d["eigen_tx"] = wert(TrafficStats.getUidTxBytes(Process.myUid()))
        } catch (_: Throwable) {
        }
        d["zeit_ms"] = System.currentTimeMillis()
        return d
    }

    /**
     * Zustaende, die eine schlechte Messung ERKLAEREN — und damit verhindern,
     * dass sie faelschlich der Leitung angelastet wird.
     */
    private fun geraetezustand(d: HashMap<String, Any?>) {
        try {
            val pm = context.getSystemService(PowerManager::class.java)
            if (pm != null) {
                d["energiesparmodus"] = pm.isPowerSaveMode
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    d["thermisch"] = thermalName(pm.currentThermalStatus)
                }
                // isDeviceIdleMode() waere hier wertlos: ein WorkManager-Job
                // laeuft nie im Doze, sondern im Wartungsfenster. Was die
                // LUECKEN in der Reihe erklaert, ist die Freistellung von der
                // Akku-Optimierung.
                d["akku_optimierung_aus"] =
                    pm.isIgnoringBatteryOptimizations(context.packageName)
            }
        } catch (_: Throwable) {
        }
        try {
            val am = context.getSystemService(ActivityManager::class.java)
            if (am != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                d["hintergrund_eingeschraenkt"] = am.isBackgroundRestricted
            }
        } catch (_: Throwable) {
        }
        try {
            val cm = context.getSystemService(ConnectivityManager::class.java)
            if (cm != null) {
                d["datensparmodus"] = when (cm.restrictBackgroundStatus) {
                    ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED -> "aus"
                    ConnectivityManager.RESTRICT_BACKGROUND_STATUS_WHITELISTED -> "freigestellt"
                    ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED -> "an"
                    else -> null
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun thermalName(s: Int): String = when (s) {
        PowerManager.THERMAL_STATUS_NONE -> "none"
        PowerManager.THERMAL_STATUS_LIGHT -> "light"
        PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
        PowerManager.THERMAL_STATUS_SEVERE -> "severe"
        PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
        PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
        PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
        else -> "status_$s"
    }

    // ── Geräteprofil ────────────────────────────────────────────────────────

    /**
     * Bauform und Betriebssystem-Variante des Geräts.
     *
     * Warum das in die Messreihe gehört: der Verein misst gleichzeitig von drei
     * Geräten aus. Eine Reihe, in der nicht steht, ob der Punkt vom Tablet an
     * der Telekom-SIM oder vom Laptop am WLAN stammt, beantwortet die Frage
     * nach der Mobilfunkleitung überhaupt nicht.
     *
     * ZUR OS-VARIANTE: Es gibt keinen verlässlichen Weg, GrapheneOS oder
     * CalyxOS zu erkennen — sämtliche Build-Felder lassen sich setzen, genau
     * dafür existieren Play-Integrity-Umgehungen. Hier werden deshalb die
     * Rohfelder mitgegeben und nur nach bekannten Markern durchsucht. Findet
     * sich keiner, heißt das Ergebnis "unbestimmt" und NICHT "Stock-Android":
     * eine falsche Gewissheit wäre schlechter als gar keine Angabe.
     */
    private fun geraeteprofil(): Map<String, Any?> {
        val d = HashMap<String, Any?>()

        d["hersteller"] = Build.MANUFACTURER
        d["marke"] = Build.BRAND
        d["modell"] = Build.MODEL
        d["geraet"] = Build.DEVICE
        d["produkt"] = Build.PRODUCT
        d["android"] = Build.VERSION.RELEASE
        d["sdk"] = Build.VERSION.SDK_INT
        d["sicherheitspatch"] = Build.VERSION.SECURITY_PATCH
        d["fingerprint"] = Build.FINGERPRINT
        d["build_id"] = Build.ID
        d["build_display"] = Build.DISPLAY
        d["build_tags"] = Build.TAGS
        d["build_host"] = Build.HOST

        // Bauform über die kleinste Bildschirmkante, nicht über den Modellnamen:
        // eine Liste wie „sm-x, tablet, mediapad" trifft jedes Modell nicht, das
        // noch nicht auf ihr steht. 600 dp ist Androids eigene Grenze für
        // Tablet-Layouts.
        d["bauform"] = try {
            val kleinsteKante = context.resources.configuration.smallestScreenWidthDp
            d["kleinste_kante_dp"] = kleinsteKante
            if (kleinsteKante >= 600) "tablet" else "handy"
        } catch (_: Throwable) {
            "unbekannt"
        }

        // Nur benennen, was sich tatsächlich in den Build-Feldern zeigt.
        val heuhaufen = listOf(
            Build.FINGERPRINT, Build.DISPLAY, Build.ID, Build.HOST,
            Build.PRODUCT, Build.TAGS, Build.VERSION.INCREMENTAL,
        ).joinToString(" ").lowercase()

        val marker = mapOf(
            "graphene" to "GrapheneOS",
            "calyx" to "CalyxOS",
            "lineage" to "LineageOS",
            "divest" to "DivestOS",
            "e-os" to "/e/OS",
            "iode" to "iodéOS",
        )
        d["os_variante"] = marker.entries.firstOrNull { heuhaufen.contains(it.key) }?.value
            ?: "unbestimmt"
        // Ehrlich mitgeben, wie sicher das ist — nachgeschlagen 2026-08-04:
        // Build-Felder sind setzbar, eine Erkennung kann also nur ein Indiz sein.
        d["os_variante_sicher"] = false

        return d
    }

    // ── Berechtigungen ──────────────────────────────────────────────────────

    private fun hatRecht(recht: String) =
        context.checkSelfPermission(recht) == PackageManager.PERMISSION_GRANTED

    private fun hatTelefonRecht() = hatRecht(Manifest.permission.READ_PHONE_STATE)

    private fun hatOrtRecht() = hatRecht(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun telefonRechtAnfragen(result: MethodChannel.Result) {
        if (hatTelefonRecht()) { result.success(true); return }
        val act = activity
        if (act == null) {
            // Hintergrund-Isolat: kein Dialog möglich. Sauber melden statt
            // einen Aufruf ins Leere laufen zu lassen.
            result.success(false)
            return
        }
        // Ein zweiter Aufruf während ein Dialog offen ist würde den ersten
        // Result verwaisen lassen — Flutter wirft dann beim zweiten reply().
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        act.requestPermissions(arrayOf(Manifest.permission.READ_PHONE_STATE), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val erteilt = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(erteilt)
        pendingPermissionResult = null
        // Der Anzeige-Listener scheitert ohne die Berechtigung still. Jetzt,
        // wo sie da ist, nachziehen — sonst bliebe die 5G-Erkennung bis zum
        // nächsten App-Start tot.
        if (erteilt) anzeigeListenerStarten()
        return true
    }

    // ── Anzeige-Netztyp (die eigentliche 5G-Erkennung) ──────────────────────

    private fun anzeigeListenerStarten() {
        if (listenerAktiv || !hatTelefonRecht()) return
        val tm = context.getSystemService(TelephonyManager::class.java) ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val cb = object : TelephonyCallback(), TelephonyCallback.DisplayInfoListener {
                    override fun onDisplayInfoChanged(info: TelephonyDisplayInfo) {
                        letzterOverride = info.overrideNetworkType
                    }
                }
                tm.registerTelephonyCallback(context.mainExecutor, cb)
                telephonyCallback = cb
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val l = object : PhoneStateListener() {
                    @Deprecated("Ab API 31 ersetzt durch TelephonyCallback")
                    override fun onDisplayInfoChanged(info: TelephonyDisplayInfo) {
                        letzterOverride = info.overrideNetworkType
                    }
                }
                @Suppress("DEPRECATION")
                tm.listen(l, PhoneStateListener.LISTEN_DISPLAY_INFO_CHANGED)
                phoneStateListener = l
            } else {
                // Vor Android 11 gibt es TelephonyDisplayInfo nicht. Dann bleibt
                // nur getDataNetworkType(), und NSA-5G ist dort nicht von LTE zu
                // unterscheiden — das wird im Datensatz auch so ausgewiesen.
                return
            }
            listenerAktiv = true
        } catch (_: Throwable) {
            // SecurityException, wenn die Berechtigung zwischenzeitlich weg ist.
        }
    }

    private fun anzeigeListenerStoppen() {
        val tm = context.getSystemService(TelephonyManager::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (telephonyCallback as? TelephonyCallback)?.let { tm?.unregisterTelephonyCallback(it) }
            } else {
                @Suppress("DEPRECATION")
                phoneStateListener?.let { tm?.listen(it, PhoneStateListener.LISTEN_NONE) }
            }
        } catch (_: Throwable) {
        }
        telephonyCallback = null
        phoneStateListener = null
        listenerAktiv = false
    }

    // ── Momentaufnahme ──────────────────────────────────────────────────────

    private fun momentaufnahme(): Map<String, Any?> {
        // Später erteilte Berechtigung nachziehen, falls beim Start noch keine da war.
        if (!listenerAktiv) anzeigeListenerStarten()

        val d = HashMap<String, Any?>()
        d["zeit_ms"] = System.currentTimeMillis()
        d["hat_telefon_recht"] = hatTelefonRecht()
        d["hat_ort_recht"] = hatOrtRecht()

        transportLesen(d)
        if (d["transport"] == "cellular") mobilfunkLesen(d) else wlanLesen(d)
        geraetezustand(d)

        return d
    }

    /** Transport und die vom Netz SELBST behauptete Bandbreite. */
    private fun transportLesen(d: HashMap<String, Any?>) {
        try {
            val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
            val netz = cm.activeNetwork ?: run { d["transport"] = "none"; return }
            val f = cm.getNetworkCapabilities(netz) ?: run { d["transport"] = "none"; return }

            d["transport"] = when {
                f.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                f.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                f.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                f.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                else -> "sonstige"
            }
            // Der Vergleich dieser Zahl mit dem tatsächlich Gemessenen ist das
            // schärfste Einzelargument gegenüber dem Anbieter: das Netz sagt
            // selbst, was es könnte.
            d["gemeldet_down_kbps"] = f.linkDownstreamBandwidthKbps
            d["gemeldet_up_kbps"] = f.linkUpstreamBandwidthKbps
            d["nicht_getaktet"] = !f.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } catch (_: Throwable) {
        }
    }

    private fun mobilfunkLesen(d: HashMap<String, Any?>) {
        val tm = context.getSystemService(TelephonyManager::class.java) ?: return
        try {
            d["operator"] = tm.networkOperatorName
            val mccMnc = tm.networkOperator
            if (!mccMnc.isNullOrEmpty()) d["mcc_mnc"] = mccMnc
            d["sim_operator"] = tm.simOperatorName
            @Suppress("DEPRECATION")
            d["roaming"] = tm.isNetworkRoaming
        } catch (_: Throwable) {
        }

        var datenTyp: Int? = null
        if (hatTelefonRecht()) {
            try {
                datenTyp = tm.dataNetworkType
                d["data_network_type"] = netzTypName(datenTyp)
            } catch (_: Throwable) {
            }
        }

        val ov = letzterOverride
        if (ov != null) d["override_network_type"] = overrideName(ov)
        d["netz_generation"] = generationBestimmen(datenTyp, ov)

        signalLesen(tm, d)
        if (hatOrtRecht()) zelleLesen(tm, d)
    }

    /**
     * Endgültige Einstufung. Der Override schlägt den Datentyp — genau dafür
     * existiert er (siehe Kommentarkopf: NSA-5G meldet sich als LTE).
     */
    private fun generationBestimmen(datenTyp: Int?, override: Int?): String {
        if (override != null) {
            when (override) {
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA -> return "5G-NSA"
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED -> return "5G+"
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_CA -> return "LTE-CA"
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_ADVANCED_PRO -> return "LTE+"
            }
        }
        return when (datenTyp) {
            TelephonyManager.NETWORK_TYPE_NR -> "5G-SA"
            TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
            TelephonyManager.NETWORK_TYPE_HSPAP,
            TelephonyManager.NETWORK_TYPE_HSPA,
            TelephonyManager.NETWORK_TYPE_HSDPA,
            TelephonyManager.NETWORK_TYPE_HSUPA,
            TelephonyManager.NETWORK_TYPE_UMTS -> "3G"
            TelephonyManager.NETWORK_TYPE_EDGE,
            TelephonyManager.NETWORK_TYPE_GPRS -> "2G"
            null -> "unbekannt"
            else -> netzTypName(datenTyp)
        }
    }

    private fun signalLesen(tm: TelephonyManager, d: HashMap<String, Any?>) {
        if (!hatTelefonRecht() || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        try {
            val s = tm.signalStrength ?: return
            d["signal_stufe"] = s.level          // 0..4, wie die Balken oben rechts
            for (teil in s.cellSignalStrengths) {
                when (teil) {
                    is CellSignalStrengthNr -> {
                        d["nr_ss_rsrp"] = teil.ssRsrp
                        d["nr_ss_rsrq"] = teil.ssRsrq
                        d["nr_ss_sinr"] = teil.ssSinr
                        d["dbm"] = teil.dbm
                    }
                    is CellSignalStrengthLte -> {
                        d["lte_rsrp"] = teil.rsrp
                        d["lte_rsrq"] = teil.rsrq
                        d["lte_rssnr"] = teil.rssnr
                        d["lte_cqi"] = teil.cqi
                        d["lte_ta"] = teil.timingAdvance
                        if (d["dbm"] == null) d["dbm"] = teil.dbm
                    }
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun zelleLesen(tm: TelephonyManager, d: HashMap<String, Any?>) {
        try {
            @Suppress("DEPRECATION")
            val zellen: List<CellInfo> = tm.allCellInfo ?: return
            // Nur die Zelle, in der wir tatsächlich eingebucht sind. Nachbarn
            // stünden sonst zufällig im Datensatz und würden Ortsvergleiche
            // über die Messreihe hinweg unbrauchbar machen.
            val aktiv = zellen.firstOrNull { it.isRegistered } ?: return
            when (aktiv) {
                is CellInfoNr -> (aktiv.cellIdentity as? CellIdentityNr)?.let {
                    d["zelle_typ"] = "NR"
                    d["zelle_nci"] = it.nci
                    d["zelle_tac"] = it.tac
                    d["zelle_pci"] = it.pci
                    d["zelle_arfcn"] = it.nrarfcn
                }
                is CellInfoLte -> (aktiv.cellIdentity as? CellIdentityLte)?.let {
                    d["zelle_typ"] = "LTE"
                    d["zelle_ci"] = it.ci
                    d["zelle_tac"] = it.tac
                    d["zelle_pci"] = it.pci
                    d["zelle_arfcn"] = it.earfcn
                    d["zelle_bandbreite_khz"] = it.bandwidth
                }
                else -> d["zelle_typ"] = aktiv.javaClass.simpleName
            }
        } catch (_: Throwable) {
        }
    }

    private fun wlanLesen(d: HashMap<String, Any?>) {
        try {
            val wm = context.applicationContext.getSystemService(WifiManager::class.java) ?: return
            @Suppress("DEPRECATION")
            val info: WifiInfo = wm.connectionInfo ?: return
            // SSID/BSSID liefert Android ohne Ortsberechtigung nur als
            // Platzhalter ("<unknown ssid>", 02:00:00:00:00:00).
            if (hatOrtRecht()) {
                d["wlan_ssid"] = info.ssid?.trim('"')
                d["wlan_bssid"] = info.bssid
            }
            d["wlan_rssi"] = info.rssi
            d["wlan_link_mbps"] = info.linkSpeed
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                d["wlan_frequenz_mhz"] = info.frequency
                d["wlan_standard"] = wlanStandardName(info.wifiStandard)
                d["wlan_rx_mbps"] = info.rxLinkSpeedMbps
                d["wlan_tx_mbps"] = info.txLinkSpeedMbps
            }
        } catch (_: Throwable) {
        }
    }

    // ── Namen ───────────────────────────────────────────────────────────────

    private fun netzTypName(t: Int?): String = when (t) {
        TelephonyManager.NETWORK_TYPE_NR -> "NR"
        TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
        TelephonyManager.NETWORK_TYPE_HSPAP -> "HSPA+"
        TelephonyManager.NETWORK_TYPE_HSPA -> "HSPA"
        TelephonyManager.NETWORK_TYPE_HSDPA -> "HSDPA"
        TelephonyManager.NETWORK_TYPE_HSUPA -> "HSUPA"
        TelephonyManager.NETWORK_TYPE_UMTS -> "UMTS"
        TelephonyManager.NETWORK_TYPE_EDGE -> "EDGE"
        TelephonyManager.NETWORK_TYPE_GPRS -> "GPRS"
        TelephonyManager.NETWORK_TYPE_IWLAN -> "IWLAN"
        TelephonyManager.NETWORK_TYPE_UNKNOWN -> "unbekannt"
        else -> "typ_$t"
    }

    private fun overrideName(o: Int): String = when (o) {
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NONE -> "NONE"
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_CA -> "LTE_CA"
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_ADVANCED_PRO -> "LTE_ADVANCED_PRO"
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA -> "NR_NSA"
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED -> "NR_ADVANCED"
        else -> "override_$o"
    }

    /**
     * Die WIFI_STANDARD_*-Konstanten liegen auf [ScanResult], nicht auf [WifiInfo] —
     * `WifiInfo.getWifiStandard()` liefert zwar den Standard, definiert sind die Werte
     * aber dort.
     *
     * Es sind genau diese sieben (nachgesehen in android.jar, API 36). Für 802.11a/g/b
     * gibt es KEINE eigenen Konstanten — die fallen alle unter LEGACY. Ein `when`-Zweig
     * dafür sähe vollständiger aus, ließe sich aber gar nicht erst übersetzen.
     */
    private fun wlanStandardName(s: Int): String = when (s) {
        ScanResult.WIFI_STANDARD_11N -> "11n"
        ScanResult.WIFI_STANDARD_11AC -> "11ac"
        ScanResult.WIFI_STANDARD_11AX -> "11ax (Wi-Fi 6)"
        ScanResult.WIFI_STANDARD_11AD -> "11ad (60 GHz)"
        ScanResult.WIFI_STANDARD_11BE -> "11be (Wi-Fi 7)"
        ScanResult.WIFI_STANDARD_LEGACY -> "legacy (a/b/g)"
        ScanResult.WIFI_STANDARD_UNKNOWN -> "unbekannt"
        else -> "standard_$s"
    }

    companion object {
        /** Muss zu `icdNetinfoChannelName` in icd_netinfo.dart passen. */
        const val CHANNEL = "de.icd360sev.vorsitzer/netinfo"
        private const val PERMISSION_REQUEST = 47021
    }
}
