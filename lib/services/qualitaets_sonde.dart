/// Misst die Güte des laufenden Gesprächs an der WebRTC-Verbindung.
///
/// Die Rechnung (R-Wert, MOS) steht in `lib/utils/gespraechsqualitaet.dart` und
/// war lange fertig — was fehlte, war GENAU DIESE DATEI: `getStats()` wurde auf
/// dem sipgate-Pfad nirgends gerufen, also gab es nichts zu rechnen.
///
/// ⚠️ WAS HIER GEMESSEN WIRD, IST DIE STRECKE BIS SIPGATE — NICHT DAS GANZE
/// GESPRÄCH. Ruft man ins Telefonnetz, ist WebRTC nur das erste Stück bis zum
/// Übergang; was dahinter im Festnetz oder Mobilfunk passiert, sieht niemand
/// von hier aus. Ein guter Wert schliesst schlechten Ton also nicht aus. Das
/// steht deshalb an jeder Ausgabe, nicht bloss hier.
///
/// ⚠️ ALLE ZÄHLER SIND KUMULATIV — und wer sie so nimmt, misst falsch. Eine
/// schlechte erste Minute zöge den Wert für den Rest des Gesprächs herunter,
/// und eine Besserung wäre nie zu sehen. Gerechnet wird darum immer aus dem
/// UNTERSCHIED zweier Abfragen.
library;

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../utils/gespraechsqualitaet.dart';

/// Abstand zwischen zwei Abfragen.
///
/// ⚠️ Nicht kürzer: `getStats()` geht über den Plattformkanal zur nativen
/// WebRTC-Schicht, und die Zähler für Verlust werden ohnehin nur mit den
/// RTCP-Berichten fortgeschrieben (etwa im Sekundentakt). Häufiger zu fragen
/// erzeugt Last, aber keine neue Auskunft.
const Duration kQualitaetTakt = Duration(seconds: 3);

/// Wie viele Momentaufnahmen der Verlauf höchstens behält.
///
/// 200 × 3 s ≈ 10 Minuten. Es geht nicht um eine Aufzeichnung, sondern um
/// Kennzahlen (Mittelwert, schlechtester Wert) am Gesprächsende.
const int kQualitaetVerlaufMax = 200;

num? _z(Map<dynamic, dynamic> m, String k) {
  final w = m[k];
  if (w is num) return w;
  if (w is String) return num.tryParse(w);
  return null;
}

double? _d(Map<dynamic, dynamic> m, String k) => _z(m, k)?.toDouble();
int? _i(Map<dynamic, dynamic> m, String k) => _z(m, k)?.round();

/// Eine Momentaufnahme — bewusst breit, damit man einen Befund auch begründen
/// kann und nicht nur eine Note in der Hand hält.
class QualitaetsProbe {
  const QualitaetsProbe({
    required this.zeit,
    required this.bewertung,
    required this.verlustProzent,
    required this.jitterMs,
    required this.pufferMs,
    required this.paketeEmpfangen,
    required this.paketeVerloren,
    this.rttMs,
    this.fernVerlustProzent,
    this.fernJitterMs,
    this.verdecktAnteil,
    this.stilleAnteil,
    this.verdeckungEreignisse,
    this.gedehnteProben,
    this.gestraffteProben,
    this.bitrateEmpfang,
    this.bitrateSenden,
    this.codec,
    this.abtastrate,
    this.fec = true,
    this.dtx = false,
    this.wegTyp,
    this.wegProtokoll,
    this.netzTyp,
    this.tonPegel,
  });

  final DateTime zeit;
  final Gespraechsqualitaet bewertung;

  // --- Empfang: was WIR hören ---------------------------------------------

  /// Verlust im letzten Takt, in Prozent.
  final double verlustProzent;
  final double jitterMs;

  /// Mittlere Verweildauer im Entzerrerpuffer.
  ///
  /// ⚠️ Ein hoher Wert ist NICHT eindeutig schlecht: der Puffer wächst, um
  /// Schwankungen aufzufangen. Er kauft Verständlichkeit mit Verzögerung.
  final double pufferMs;

  final int paketeEmpfangen;
  final int paketeVerloren;

  /// Anteil der Tonproben, die der Decoder selbst erfinden musste — OHNE die
  /// stillen.
  ///
  /// ⚠️ `silentConcealedSamples` ist laut Spezifikation eine TEILMENGE von
  /// `concealedSamples`: eingefügte Stille oder Komfortrauschen. Zöge man sie
  /// nicht ab, würde jede Sprechpause mit aktivem DTX als Schaden gezählt —
  /// und ausgerechnet ein sparsam übertragenes Gespräch sähe am schlimmsten
  /// aus.
  final double? verdecktAnteil;

  /// Der stille Anteil, getrennt ausgewiesen. Gehört zur Auskunft, nicht zum
  /// Schaden.
  final double? stilleAnteil;

  /// Wie oft eine Lücke BEGONNEN hat. Viele kurze Lücken hört man anders als
  /// eine lange gleicher Gesamtdauer — deshalb steht beides da.
  final int? verdeckungEreignisse;

  /// Proben, die der Entzerrer eingefügt bzw. weggelassen hat, um den Puffer
  /// zu halten. Das ist die hörbare Seite von Schwankung.
  final int? gedehnteProben;
  final int? gestraffteProben;

  final int? bitrateEmpfang;
  final int? bitrateSenden;
  final String? codec;
  final int? abtastrate;
  final bool fec;
  final bool dtx;

  /// Aussteuerung der Gegenstelle (0–1). Nahe 0 über längere Zeit heisst:
  /// die Verbindung steht, aber es kommt kein Ton — ein ganz anderer Befund
  /// als schlechte Güte.
  final double? tonPegel;

  // --- Senderichtung: was die GEGENSTELLE über UNS meldet ------------------

  /// ⚠️ DIE EINZIGE SICHT AUF DIE ANDERE RICHTUNG. Alles übrige misst, was bei
  /// uns ankommt; ob die Gegenstelle UNS versteht, steht nur im RTCP-Bericht,
  /// den sie zurückschickt.
  ///
  /// ⚠️ Deshalb ist `null` hier häufig und harmlos: der Bericht kommt erst
  /// nach ein paar Sekunden. `null` heisst „noch keine Rückmeldung", NIEMALS
  /// „kein Verlust" — als 0 % dargestellt wäre es eine Behauptung über eine
  /// Richtung, die wir noch gar nicht kennen.
  final double? fernVerlustProzent;
  final double? fernJitterMs;

  /// Umlaufzeit. Bevorzugt aus dem RTCP-Bericht; sonst aus dem ICE-Paar.
  final double? rttMs;

  // --- Der Weg -------------------------------------------------------------

  /// `host`, `srflx`, `prflx` oder `relay`. ⚠️ `relay` heisst: der Ton läuft
  /// über den TURN-Server, also einen Umweg — das erklärt Verzögerung, ohne
  /// dass die Leitung schlecht wäre.
  final String? wegTyp;
  final String? wegProtokoll;

  /// `wifi`, `cellular`, `ethernet` … soweit die Plattform es hergibt.
  final String? netzTyp;

  double get mos => bewertung.mos;
  QualitaetsStufe get stufe => bewertung.stufe;

  /// Für das Protokoll am Gesprächsende. ⚠️ Bewusst ohne Adressen: der Weg
  /// wird als TYP festgehalten (`relay`), nie als IP.
  Map<String, dynamic> alsKarte() => <String, dynamic>{
    'mos': bewertung.mos,
    'r': bewertung.r.round(),
    'verlust': double.parse(verlustProzent.toStringAsFixed(2)),
    'jitter_ms': jitterMs.round(),
    'puffer_ms': pufferMs.round(),
    if (rttMs != null) 'rtt_ms': rttMs!.round(),
    if (fernVerlustProzent != null)
      'fern_verlust': double.parse(fernVerlustProzent!.toStringAsFixed(2)),
    if (verdecktAnteil != null)
      'verdeckt': double.parse((verdecktAnteil! * 100).toStringAsFixed(2)),
    if (bitrateEmpfang != null) 'bitrate_ein': bitrateEmpfang,
    if (bitrateSenden != null) 'bitrate_aus': bitrateSenden,
    if (codec != null) 'codec': codec,
    'fec': fec,
    'dtx': dtx,
    if (wegTyp != null) 'weg': wegTyp,
    if (netzTyp != null) 'netz': netzTyp,
  };
}

/// Merkt sich die vorige Abfrage und rechnet daraus die Werte eines Takts.
class QualitaetsSonde {
  Map<dynamic, dynamic>? _vorherEin;
  Map<dynamic, dynamic>? _vorherAus;
  Map<dynamic, dynamic>? _vorherFern;
  DateTime? _vorherZeit;

  /// ⚠️ Wird bei jedem neuen Gespräch gebraucht. Ohne das Zurücksetzen wäre
  /// der erste Takt des zweiten Gesprächs die Differenz zum ERSTEN — also
  /// Unsinn, und zwar plausibel aussehender.
  void zuruecksetzen() {
    _vorherEin = null;
    _vorherAus = null;
    _vorherFern = null;
    _vorherZeit = null;
  }

  /// Eine Abfrage auswerten. `null`, solange es noch keinen Vergleichspunkt
  /// gibt — die erste Abfrage liefert bewusst nichts.
  QualitaetsProbe? auswerten(List<StatsReport> berichte, {DateTime? jetzt}) {
    final zeit = jetzt ?? DateTime.now();

    Map<dynamic, dynamic>? ein, aus, fern, paar, codec, lokalerKand;
    String? gewaehltesPaar;

    for (final b in berichte) {
      final v = b.values;
      switch (b.type) {
        case 'inbound-rtp':
          if (v['kind'] == 'audio' || v['mediaType'] == 'audio') ein = v;
          break;
        case 'outbound-rtp':
          if (v['kind'] == 'audio' || v['mediaType'] == 'audio') aus = v;
          break;
        case 'remote-inbound-rtp':
          if (v['kind'] == 'audio' || v['mediaType'] == 'audio') fern = v;
          break;
        case 'transport':
          gewaehltesPaar ??= v['selectedCandidatePairId'] as String?;
          break;
        case 'codec':
          final m = '${v['mimeType'] ?? ''}';
          if (m.toLowerCase().startsWith('audio/')) codec = v;
          break;
      }
    }
    // Das ICE-Paar erst danach, weil `transport` den Verweis trägt und die
    // Reihenfolge der Berichte nicht zugesichert ist.
    for (final b in berichte) {
      if (b.type != 'candidate-pair') continue;
      final v = b.values;
      final gewaehlt =
          b.id == gewaehltesPaar ||
          v['selected'] == true ||
          (v['nominated'] == true && v['state'] == 'succeeded');
      if (gewaehlt) paar = v;
    }
    if (paar != null) {
      final id = paar['localCandidateId'];
      for (final b in berichte) {
        if (b.type == 'local-candidate' && b.id == id) lokalerKand = b.values;
      }
    }

    if (ein == null) return null;

    final vorherEin = _vorherEin;
    final vorherAus = _vorherAus;
    final vorherFern = _vorherFern;
    final vorherZeit = _vorherZeit;
    _vorherEin = ein;
    _vorherAus = aus;
    _vorherFern = fern;
    _vorherZeit = zeit;
    if (vorherEin == null || vorherZeit == null) return null;

    final sekunden = zeit.difference(vorherZeit).inMilliseconds / 1000.0;
    if (sekunden <= 0) return null;

    // --- Verlust aus dem Unterschied ---------------------------------------
    final empf = _i(ein, 'packetsReceived') ?? 0;
    final verl = _i(ein, 'packetsLost') ?? 0;
    final dEmpf = empf - (_i(vorherEin, 'packetsReceived') ?? 0);
    // ⚠️ `packetsLost` DARF nach RFC 3550 sinken (verspätete Pakete werden
    // nachträglich verrechnet). Ein negativer Unterschied ist kein Fehler,
    // sondern eine Korrektur — als solche behandelt, nicht als Verlust.
    final dVerl = (verl - (_i(vorherEin, 'packetsLost') ?? 0)).clamp(0, 1 << 30);
    final gesamt = dEmpf + dVerl;
    final verlust = gesamt > 0 ? 100.0 * dVerl / gesamt : 0.0;

    // --- Puffer -------------------------------------------------------------
    final dVerz =
        (_d(ein, 'jitterBufferDelay') ?? 0) - (_d(vorherEin, 'jitterBufferDelay') ?? 0);
    final dProben =
        (_d(ein, 'jitterBufferEmittedCount') ?? 0) -
        (_d(vorherEin, 'jitterBufferEmittedCount') ?? 0);
    final puffer = dProben > 0 ? 1000.0 * dVerz / dProben : kQualitaetPufferVorgabeMs;

    // --- Verdeckte Proben, ohne die stillen --------------------------------
    double? verdeckt, stille;
    final dAlle =
        (_d(ein, 'totalSamplesReceived') ?? 0) -
        (_d(vorherEin, 'totalSamplesReceived') ?? 0);
    if (dAlle > 0) {
      final dVerdeckt =
          (_d(ein, 'concealedSamples') ?? 0) - (_d(vorherEin, 'concealedSamples') ?? 0);
      final dStill =
          (_d(ein, 'silentConcealedSamples') ?? 0) -
          (_d(vorherEin, 'silentConcealedSamples') ?? 0);
      stille = (dStill / dAlle).clamp(0.0, 1.0);
      verdeckt = ((dVerdeckt - dStill) / dAlle).clamp(0.0, 1.0);
    }

    // --- Bitraten ------------------------------------------------------------
    int? rate(Map<dynamic, dynamic>? neu, Map<dynamic, dynamic>? alt) {
      if (neu == null || alt == null) return null;
      final d =
          (_d(neu, 'bytesReceived') ?? _d(neu, 'bytesSent') ?? 0) -
          (_d(alt, 'bytesReceived') ?? _d(alt, 'bytesSent') ?? 0);
      if (d <= 0) return null;
      return (d * 8 / sekunden).round();
    }

    // --- Gegenrichtung -------------------------------------------------------
    double? fernVerlust, fernJitter, rtt;
    if (fern != null) {
      fernJitter = (_d(fern, 'jitter') ?? 0) * 1000;
      rtt = _d(fern, 'roundTripTime') == null ? null : _d(fern, 'roundTripTime')! * 1000;
      // Lieber aus dem Unterschied als aus `fractionLost`: jene Zahl gilt für
      // den letzten RTCP-Bericht, dessen Zeitraum wir nicht kennen.
      if (vorherFern != null && vorherAus != null && aus != null) {
        final dGes = (_i(aus, 'packetsSent') ?? 0) - (_i(vorherAus, 'packetsSent') ?? 0);
        final dV = ((_i(fern, 'packetsLost') ?? 0) - (_i(vorherFern, 'packetsLost') ?? 0))
            .clamp(0, 1 << 30);
        if (dGes > 0) fernVerlust = (100.0 * dV / dGes).clamp(0.0, 100.0);
      }
      fernVerlust ??= _d(fern, 'fractionLost') == null
          ? null
          : (_d(fern, 'fractionLost')! * 100).clamp(0.0, 100.0);
    }
    rtt ??= _d(paar ?? const {}, 'currentRoundTripTime') == null
        ? null
        : _d(paar!, 'currentRoundTripTime')! * 1000;

    // --- Codec-Einstellungen aus der SDP-Zeile -------------------------------
    final fmtp = '${codec?['sdpFmtpLine'] ?? ''}';
    final fec = fmtp.contains('useinbandfec=1');
    final dtx = fmtp.contains('usedtx=1');
    final bitEin = rate(ein, vorherEin);

    final bewertung = gespraechsQualitaet(
      verlustProzent: verlust,
      rttMs: rtt,
      pufferMs: puffer,
      bitrate: bitEin,
      // ⚠️ Ohne SDP-Zeile NICHT `true` annehmen: FEC hebt `Bpl` von 10 auf 20
      // und beschönigt damit jeden Verlust. Im Zweifel die vorsichtige Zahl.
      fec: codec == null ? false : fec,
      dtx: dtx,
      verdecktAnteil: verdeckt,
    );

    return QualitaetsProbe(
      zeit: zeit,
      bewertung: bewertung,
      verlustProzent: verlust,
      jitterMs: (_d(ein, 'jitter') ?? 0) * 1000,
      pufferMs: puffer,
      paketeEmpfangen: empf,
      paketeVerloren: verl,
      rttMs: rtt,
      fernVerlustProzent: fernVerlust,
      fernJitterMs: fernJitter,
      verdecktAnteil: verdeckt,
      stilleAnteil: stille,
      verdeckungEreignisse: _i(ein, 'concealmentEvents'),
      gedehnteProben: _i(ein, 'insertedSamplesForDeceleration'),
      gestraffteProben: _i(ein, 'removedSamplesForAcceleration'),
      bitrateEmpfang: bitEin,
      bitrateSenden: rate(aus, vorherAus),
      codec: codec == null ? null : '${codec['mimeType']}'.split('/').last,
      abtastrate: codec == null ? null : _i(codec, 'clockRate'),
      fec: codec == null ? false : fec,
      dtx: dtx,
      wegTyp: paar == null ? null : lokalerKand?['candidateType'] as String?,
      wegProtokoll: lokalerKand?['protocol'] as String?,
      netzTyp: lokalerKand?['networkType'] as String?,
      tonPegel: _d(ein, 'audioLevel'),
    );
  }
}

/// Sammelt die Momentaufnahmen eines Gesprächs zu wenigen Kennzahlen.
class QualitaetsBilanz {
  final List<QualitaetsProbe> proben = <QualitaetsProbe>[];

  void hinzu(QualitaetsProbe p) {
    proben.add(p);
    if (proben.length > kQualitaetVerlaufMax) proben.removeAt(0);
  }

  void leeren() => proben.clear();

  bool get leer => proben.isEmpty;

  /// ⚠️ MEDIAN, NICHT MITTELWERT. Ein einziger Aussetzer von MOS 1,0 zieht
  /// einen Mittelwert weit herunter und behauptet damit ein Gespräch, das so
  /// nicht stattgefunden hat. Der schlechteste Wert steht ohnehin daneben —
  /// die beiden zusammen sagen mehr als jede gemittelte Zahl.
  double get mosMedian {
    if (proben.isEmpty) return 0;
    final w = proben.map((p) => p.mos).toList()..sort();
    final m = w.length ~/ 2;
    return w.length.isOdd ? w[m] : (w[m - 1] + w[m]) / 2;
  }

  double get mosSchlechtester =>
      proben.isEmpty ? 0 : proben.map((p) => p.mos).reduce((a, b) => a < b ? a : b);

  double get verlustMax => proben.isEmpty
      ? 0
      : proben.map((p) => p.verlustProzent).reduce((a, b) => a > b ? a : b);

  /// Anteil der Takte, in denen es unter „brauchbar" lag. Diese Zahl trägt
  /// eine Beschwerde besser als jeder Einzelwert: sie sagt, wie oft es schlecht
  /// war, nicht wie schlecht es einmal war.
  double get anteilSchlecht {
    if (proben.isEmpty) return 0;
    final n = proben.where((p) => p.mos < 3.4).length;
    return 100.0 * n / proben.length;
  }

  Map<String, dynamic>? alsKarte() {
    if (proben.isEmpty) return null;
    final letzte = proben.last;
    final rtts = proben.map((p) => p.rttMs).whereType<double>().toList()..sort();
    return <String, dynamic>{
      'takte': proben.length,
      'mos_median': double.parse(mosMedian.toStringAsFixed(2)),
      'mos_min': double.parse(mosSchlechtester.toStringAsFixed(2)),
      'verlust_max': double.parse(verlustMax.toStringAsFixed(2)),
      'anteil_schlecht': double.parse(anteilSchlecht.toStringAsFixed(1)),
      if (rtts.isNotEmpty) 'rtt_median_ms': rtts[rtts.length ~/ 2].round(),
      if (letzte.codec != null) 'codec': letzte.codec,
      'fec': letzte.fec,
      if (letzte.wegTyp != null) 'weg': letzte.wegTyp,
      if (letzte.netzTyp != null) 'netz': letzte.netzTyp,
    };
  }
}
