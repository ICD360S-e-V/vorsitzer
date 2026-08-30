// Prüft die Güte-Messung an erfundenen, aber formgleichen `getStats()`-Berichten.
//
// ⚠️ Jeder Fall hier steht für eine Art, wie die Zahl still falsch werden kann —
// nicht für „die Funktion läuft durch". Eine Messung, die plausibel aussieht und
// falsch ist, wäre schlimmer als gar keine: sie landet am Ende in einer
// Beschwerde.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:icd360sev_vorsitzer/services/qualitaets_sonde.dart';
import 'package:icd360sev_vorsitzer/utils/gespraechsqualitaet.dart';
import 'package:icd360sev_vorsitzer/widgets/guete_anzeige.dart';

StatsReport _b(String id, String type, Map<String, dynamic> v) =>
    StatsReport(id, type, 0, v);

/// Ein Satz Berichte mit den Werten, die eine Messung braucht.
List<StatsReport> berichte({
  required int empfangen,
  required int verloren,
  double pufferSumme = 0,
  double pufferProben = 0,
  double proben = 0,
  double verdeckt = 0,
  double still = 0,
  int gesendet = 0,
  int? fernVerloren,
  String? fmtp,
}) =>
    [
      _b('in', 'inbound-rtp', {
        'kind': 'audio',
        'packetsReceived': empfangen,
        'packetsLost': verloren,
        'jitter': 0.01,
        'jitterBufferDelay': pufferSumme,
        'jitterBufferEmittedCount': pufferProben,
        'totalSamplesReceived': proben,
        'concealedSamples': verdeckt,
        'silentConcealedSamples': still,
        'bytesReceived': empfangen * 100,
      }),
      _b('out', 'outbound-rtp',
          {'kind': 'audio', 'packetsSent': gesendet, 'bytesSent': gesendet * 100}),
      if (fernVerloren != null)
        _b('rem', 'remote-inbound-rtp', {
          'kind': 'audio',
          'packetsLost': fernVerloren,
          'jitter': 0.02,
          'roundTripTime': 0.04,
        }),
      if (fmtp != null)
        _b('cod', 'codec',
            {'mimeType': 'audio/opus', 'clockRate': 48000, 'sdpFmtpLine': fmtp}),
    ];

void main() {
  group('QualitaetsSonde', () {
    test('die erste Abfrage liefert nichts — es fehlt der Vergleichspunkt', () {
      final s = QualitaetsSonde();
      expect(s.auswerten(berichte(empfangen: 100, verloren: 0)), isNull);
    });

    test('gerechnet wird aus dem UNTERSCHIED, nicht aus dem Gesamtstand', () {
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      s.auswerten(berichte(empfangen: 0, verloren: 0), jetzt: t0);
      // Erster Takt: 50 von 100 verloren — katastrophal.
      final schlecht = s.auswerten(
          berichte(empfangen: 50, verloren: 50), jetzt: t0.add(const Duration(seconds: 3)));
      expect(schlecht!.verlustProzent, closeTo(50, 0.01));
      // Zweiter Takt: 100 weitere Pakete, keines verloren.
      final gut = s.auswerten(
          berichte(empfangen: 150, verloren: 50), jetzt: t0.add(const Duration(seconds: 6)));
      // ⚠️ Kumulativ gerechnet stünden hier 25 % — die schlechte erste Minute
      // würde den Rest des Gesprächs vergiften und eine Besserung wäre nie zu
      // sehen.
      expect(gut!.verlustProzent, closeTo(0, 0.01));
    });

    test('ein SINKENDER Verlustzähler ist eine Korrektur, kein Verlust', () {
      // RFC 3550 erlaubt das: verspätet eingetroffene Pakete werden
      // nachträglich verrechnet. Ohne Klemme käme eine negative Zahl heraus.
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      s.auswerten(berichte(empfangen: 100, verloren: 10), jetzt: t0);
      final p = s.auswerten(
          berichte(empfangen: 200, verloren: 4), jetzt: t0.add(const Duration(seconds: 3)));
      expect(p!.verlustProzent, 0);
      expect(p.verlustProzent, isNonNegative);
    });

    test('stille Proben zählen NICHT als Schaden', () {
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      s.auswerten(berichte(empfangen: 0, verloren: 0, proben: 0), jetzt: t0);
      // 1000 Proben, 100 verdeckt — davon 80 still (DTX-Pause).
      final p = s.auswerten(
          berichte(empfangen: 50, verloren: 0, proben: 1000, verdeckt: 100, still: 80),
          jetzt: t0.add(const Duration(seconds: 3)));
      // ⚠️ Ohne den Abzug stünden hier 10 % — und ein sparsam übertragenes
      // Gespräch sähe am schlimmsten aus.
      expect(p!.verdecktAnteil, closeTo(0.02, 0.0001));
      expect(p.stilleAnteil, closeTo(0.08, 0.0001));
    });

    test('ohne RTCP-Bericht ist die Gegenrichtung null, nicht null Prozent', () {
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      s.auswerten(berichte(empfangen: 0, verloren: 0), jetzt: t0);
      final p = s.auswerten(berichte(empfangen: 50, verloren: 0),
          jetzt: t0.add(const Duration(seconds: 3)));
      // ⚠️ Als 0 % dargestellt wäre das eine Behauptung über eine Richtung,
      // über die wir noch gar nichts wissen.
      expect(p!.fernVerlustProzent, isNull);
    });

    test('mit RTCP-Bericht kommt die Gegenrichtung aus dem Unterschied', () {
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      s.auswerten(berichte(empfangen: 0, verloren: 0, gesendet: 0, fernVerloren: 0),
          jetzt: t0);
      final p = s.auswerten(
          berichte(empfangen: 50, verloren: 0, gesendet: 100, fernVerloren: 5),
          jetzt: t0.add(const Duration(seconds: 3)));
      expect(p!.fernVerlustProzent, closeTo(5, 0.01));
      expect(p.rttMs, closeTo(40, 0.01));
    });

    test('ohne Codec-Zeile wird FEC NICHT angenommen', () {
      // ⚠️ FEC hebt Bpl von 10 auf 20 und beschönigt damit jeden Verlust.
      // Im Zweifel die vorsichtige Zahl.
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      s.auswerten(berichte(empfangen: 0, verloren: 0), jetzt: t0);
      final ohne = s.auswerten(berichte(empfangen: 90, verloren: 10),
          jetzt: t0.add(const Duration(seconds: 3)));
      expect(ohne!.fec, isFalse);

      final s2 = QualitaetsSonde();
      s2.auswerten(berichte(empfangen: 0, verloren: 0, fmtp: 'useinbandfec=1'),
          jetzt: t0);
      final mit = s2.auswerten(
          berichte(empfangen: 90, verloren: 10, fmtp: 'useinbandfec=1'),
          jetzt: t0.add(const Duration(seconds: 3)));
      expect(mit!.fec, isTrue);
      // Derselbe Verlust wird mit FEC besser bewertet — das ist der ganze Punkt.
      expect(mit.mos, greaterThan(ohne.mos));
    });

    test('DTX wird aus der SDP-Zeile erkannt', () {
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      const f = 'minptime=10;useinbandfec=1;usedtx=1';
      s.auswerten(berichte(empfangen: 0, verloren: 0, fmtp: f), jetzt: t0);
      final p = s.auswerten(berichte(empfangen: 50, verloren: 0, fmtp: f),
          jetzt: t0.add(const Duration(seconds: 3)));
      expect(p!.dtx, isTrue);
    });

    test('zuruecksetzen verhindert eine Differenz über zwei Gespräche hinweg', () {
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      s.auswerten(berichte(empfangen: 1000, verloren: 0), jetzt: t0);
      s.zuruecksetzen();
      // Neues Gespräch, Zähler beginnen wieder bei 0.
      expect(s.auswerten(berichte(empfangen: 10, verloren: 0),
              jetzt: t0.add(const Duration(seconds: 3))),
          isNull);
    });

    test('der Weg wird als TYP festgehalten, nie als Adresse', () {
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      List<StatsReport> mitWeg() => [
            ...berichte(empfangen: 50, verloren: 0),
            _b('t', 'transport', {'selectedCandidatePairId': 'paar'}),
            _b('paar', 'candidate-pair',
                {'state': 'succeeded', 'nominated': true, 'localCandidateId': 'lk'}),
            _b('lk', 'local-candidate', {
              'candidateType': 'relay',
              'protocol': 'udp',
              'networkType': 'cellular',
              'address': '10.1.2.3',
            }),
          ];
      s.auswerten(mitWeg(), jetzt: t0);
      final p = s.auswerten(mitWeg(), jetzt: t0.add(const Duration(seconds: 3)));
      expect(p!.wegTyp, 'relay');
      expect(p.netzTyp, 'cellular');
      // Keine Adresse im Protokoll — der Weg als Typ genügt.
      expect(p.alsKarte().values.join(' '), isNot(contains('10.1.2.3')));
    });
  });

  group('QualitaetsBilanz', () {
    QualitaetsProbe probeMit(double verlust) {
      final s = QualitaetsSonde();
      final t0 = DateTime(2026, 8, 30, 12, 0, 0);
      s.auswerten(berichte(empfangen: 0, verloren: 0), jetzt: t0);
      final verl = (verlust * 10).round();
      return s.auswerten(berichte(empfangen: 1000 - verl, verloren: verl),
          jetzt: t0.add(const Duration(seconds: 3)))!;
    }

    test('Median, nicht Mittelwert', () {
      final b = QualitaetsBilanz();
      for (var i = 0; i < 9; i++) {
        b.hinzu(probeMit(0));
      }
      b.hinzu(probeMit(80)); // ein katastrophaler Aussetzer
      // ⚠️ Der Median muss GENAU der ungestörte Wert sein — nicht bloss „hoch
      // genug". Mit einer weichen Schranke bestünde dieser Test auch mit einem
      // Mittelwert; nachgemessen kam der auf 4,1 und wäre durchgerutscht.
      final ungestoert = probeMit(0).mos;
      expect(b.mosMedian, ungestoert);
      expect(b.mosMedian, greaterThan(4.0));
      expect(b.mosSchlechtester, lessThan(b.mosMedian));
      expect(b.verlustMax, closeTo(80, 1));
    });

    test('Anteil schlecht zählt Takte, nicht Tiefe', () {
      final b = QualitaetsBilanz();
      for (var i = 0; i < 8; i++) {
        b.hinzu(probeMit(0));
      }
      for (var i = 0; i < 2; i++) {
        b.hinzu(probeMit(60));
      }
      expect(b.anteilSchlecht, closeTo(20, 0.01));
    });

    test('der Verlauf wächst nicht unbegrenzt', () {
      final b = QualitaetsBilanz();
      final p = probeMit(0);
      for (var i = 0; i < kQualitaetVerlaufMax + 50; i++) {
        b.hinzu(p);
      }
      expect(b.proben.length, kQualitaetVerlaufMax);
    });

    test('eine leere Bilanz liefert keine Karte — nicht eine mit Nullen', () {
      // ⚠️ Ein Gespräch, das vor der zweiten Abfrage endete, hat KEINE Güte.
      // Eine Karte voller Nullen würde daraus „war ganz schlecht" machen.
      expect(QualitaetsBilanz().alsKarte(), isNull);
    });
  });

  group('Stufen', () {
    // ⚠️ DIESE GRENZE STEHT AN ZWEI ORTEN, UND DAS PHP LIEGT IN KEINEM REPO.
    // `guete_statistik` in `api/sipgate/sipgate_manage.php` zählt ein Gespräch
    // als schlecht, wenn `guete_mos < 3.4`. Weicht der Client davon ab, urteilen
    // Bildschirm und Statistik verschieden über dasselbe Gespräch — und nichts
    // schlägt fehl. Dieser Test ist die einzige Stelle, an der das auffallen
    // kann. Dasselbe Muster wie bei der Reaktions-Whitelist.
    const grenzeServer = 3.4;

    test('die Grenze „brauchbar" ist dieselbe wie im Server', () {
      expect(gueteStufeAusMos(grenzeServer), QualitaetsStufe.brauchbar);
      expect(gueteStufeAusMos(grenzeServer - 0.01), QualitaetsStufe.schlecht);
    });

    test('die Stufen decken den ganzen Bereich ab', () {
      expect(gueteStufeAusMos(5.0), QualitaetsStufe.gut);
      expect(gueteStufeAusMos(4.0), QualitaetsStufe.gut);
      expect(gueteStufeAusMos(3.99), QualitaetsStufe.brauchbar);
      expect(gueteStufeAusMos(2.6), QualitaetsStufe.schlecht);
      expect(gueteStufeAusMos(2.59), QualitaetsStufe.unbrauchbar);
      expect(gueteStufeAusMos(1.0), QualitaetsStufe.unbrauchbar);
    });

    test('jede Stufe hat ein Wort — Farbe allein trägt keine Auskunft', () {
      // WCAG 1.4.1: in einem Verein für Menschen mit Behinderung keine Feinheit.
      for (final st in QualitaetsStufe.values) {
        expect(gueteStufeText(st), isNotEmpty);
      }
    });
  });
}
