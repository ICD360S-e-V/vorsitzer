import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:icd_anruf/icd_anruf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'device_key_service.dart';
import 'logger_service.dart';
import 'signatur_gateway_service.dart';
import 'termin_sms_gateway_service.dart';

final _log = LoggerService();

/// Ferngesteuerter Anruf: geklickt wird am Rechner, gewählt auf dem Telefon.
///
/// WOFÜR DAS DA IST
/// Der Vorsitzer sitzt am Linux-Rechner und findet in einer Behörden- oder
/// Arztkarte eine Rufnummer. Der Rechner hat keine SIM; ein `tel:` dort öffnet
/// bestenfalls irgendeinen Handler und meistens gar nichts. Gewählt werden
/// soll auf dem Telefon, das die SIM hat — ohne es vorher in die Hand zu
/// nehmen.
///
/// Arbeitsteilung, genau wie beim SMS-Gateway: der Rechner reiht einen Auftrag
/// ein, das Telefon holt ihn ab und wählt. Der Server ist nur die Schlange
/// dazwischen.
///
/// ⚠️ WAS DAS NICHT KANN
/// Der Ton bleibt am Telefon. Keine App darf den Gesprächston eines
/// Mobilfunkanrufs anfassen — seit Android 10 ist die Audioquelle `VOICE_CALL`
/// für alles außer System-Dialern gesperrt. Wer vom Rechner aus mitreden will,
/// muss den Rechner per Bluetooth als Freisprecheinrichtung des Telefons
/// koppeln; das ist Sache des Betriebssystems, nicht dieser App.

// ─────────────────────────────────────────────────────────────────────────────
// Empfängerseite: das Telefon mit der SIM
// ─────────────────────────────────────────────────────────────────────────────

/// Was ein Durchlauf des Gateways bewirkt hat.
class AnrufGatewayLauf {
  final int gewaehlt;
  final int liegengeblieben;
  final int fehler;

  /// Warum gar nichts passiert ist. Null heißt: der Durchlauf war in Ordnung,
  /// auch wenn die Schlange leer war.
  final String? note;

  const AnrufGatewayLauf({
    this.gewaehlt = 0,
    this.liegengeblieben = 0,
    this.fehler = 0,
    this.note,
  });

  bool get didSomething => gewaehlt > 0 || liegengeblieben > 0 || fehler > 0;

  @override
  String toString() => note ?? 'gewählt: $gewaehlt, '
      'liegengeblieben: $liegengeblieben, Fehler: $fehler';
}

/// Was dieses Gerät kann, ohne dass etwas versucht wurde.
class AnrufFaehigkeiten {
  final bool telefonie;
  final bool anrufrecht;

  /// „Über anderen Apps anzeigen" — die offizielle Ausnahme von Androids
  /// Sperre gegen Activity-Starts aus dem Hintergrund. Ohne sie wählt das
  /// Telefon nur, solange die App sichtbar ist.
  final bool overlay;

  /// Vollbild-Benachrichtigungen. Ab Android 14 nicht mehr selbstverständlich.
  final bool vollbild;

  final bool imVordergrund;
  final bool imGespraech;

  const AnrufFaehigkeiten({
    this.telefonie = false,
    this.anrufrecht = false,
    this.overlay = false,
    this.vollbild = false,
    this.imVordergrund = false,
    this.imGespraech = false,
  });

  /// Wählt das Gerät auch bei ausgeschaltetem Bildschirm von allein?
  ///
  /// Bewusst streng: „vielleicht" ist hier die schlechteste Antwort. Wer sich
  /// darauf verlässt und klickt, während das Telefon in der Tasche liegt,
  /// merkt den Unterschied erst, wenn niemand zurückruft.
  bool get waehltVonAllein => telefonie && anrufrecht && overlay;

  factory AnrufFaehigkeiten.vonKanal(Map<Object?, Object?> m) => AnrufFaehigkeiten(
        telefonie: m['telefonie'] == true,
        anrufrecht: m['anrufrecht'] == true,
        overlay: m['overlay'] == true,
        vollbild: m['vollbild'] == true,
        imVordergrund: m['imVordergrund'] == true,
        imGespraech: m['imGespraech'] == true,
      );
}

class AnrufGatewayService {
  static const _kEnabledKey = 'anruf.gateway_enabled';
  static const _kLastRunKey = 'anruf.gateway_last_run';

  /// Takt, solange die App im Vordergrund läuft.
  ///
  /// Fünf Sekunden, nicht zwanzig wie bei den SMS: der Auftrag entsteht, weil
  /// jemand JETZT telefonieren will, und er gilt nur zwei Minuten. Zwanzig
  /// Sekunden Wartezeit nach einem Klick fühlen sich an wie ein Ausfall, und
  /// nach der dritten Wiederholung klickt der Vorsitzer noch dreimal.
  static const takt = Duration(seconds: 5);

  static Timer? _vordergrundTimer;

  static bool get istUnterstuetzt => Platform.isAndroid;

  // ── Schalter ────────────────────────────────────────────────────────────

  static Future<bool> isEnabled() async {
    if (!istUnterstuetzt) return false;
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kEnabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabledKey, value);
    if (value) {
      starteVordergrundTakt();
      // Ohne den Wachdienst wählt das Telefon nur, solange die App offen
      // dasteht — und genau dann braucht niemand die Fernwahl.
      await SignaturGatewayService.starten();
      await SignaturGatewayService.taktAnpassen();
    } else {
      stoppeVordergrundTakt();
      // Den Dienst nur stoppen, wenn ihn auch das SMS-Gateway nicht braucht.
      if (!await TerminSmsGatewayService.isEnabled()) {
        await SignaturGatewayService.stoppen();
      } else {
        await SignaturGatewayService.taktAnpassen();
      }
    }
    _log.info('Anruf-Gateway ${value ? 'ein' : 'aus'}geschaltet', tag: 'ANRUF_GW');
  }

  static Future<DateTime?> lastRun() async {
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(_kLastRunKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Takt im laufenden Prozess.
  ///
  /// Deckt dieselbe Lücke wie beim SMS-Gateway: der Vordergrunddienst ist der
  /// verlässliche Weg bei geschlossener App, aber solange die App offen
  /// dasteht, ist ein simpler Timer die genauere Uhr.
  static void starteVordergrundTakt() {
    if (!istUnterstuetzt) return;
    _vordergrundTimer?.cancel();
    _vordergrundTimer = Timer.periodic(takt, (_) async {
      if (!await isEnabled()) {
        stoppeVordergrundTakt();
        return;
      }
      await runOnce();
    });
  }

  static void stoppeVordergrundTakt() {
    _vordergrundTimer?.cancel();
    _vordergrundTimer = null;
  }

  // ── Auskunft ────────────────────────────────────────────────────────────

  static Future<AnrufFaehigkeiten> faehigkeiten() async {
    if (!istUnterstuetzt) return const AnrufFaehigkeiten();
    try {
      final m = await icdAnrufChannel.invokeMethod<Map<Object?, Object?>>('faehigkeiten');
      return m == null ? const AnrufFaehigkeiten() : AnrufFaehigkeiten.vonKanal(m);
    } on MissingPluginException {
      // Ältere Installation ohne das Plugin.
      return const AnrufFaehigkeiten();
    } catch (e) {
      _log.warning('Fähigkeiten nicht lesbar: $e', tag: 'ANRUF_GW');
      return const AnrufFaehigkeiten();
    }
  }

  /// Fragt `CALL_PHONE` an — der Dialog geht nur bei offener App auf.
  ///
  /// Musste nachgereicht werden: bisher fragte nur der Tipp auf eine Rufnummer
  /// AM TELEFON danach. Wer die Fernwahl benutzt, tippt am Rechner, also kam
  /// der Dialog nie. Der erste echte Versuch endete deshalb mit
  /// „Anrufberechtigung fehlt — Benachrichtigung gelegt": die Kette lief bis
  /// zum Schluss und scheiterte an einem Häkchen, das niemand setzen konnte.
  ///
  /// @return "erteilt", "abgelehnt", "dauerhaft_abgelehnt", "kein_dialog",
  ///         "laeuft_schon" oder "nicht_unterstuetzt".
  static Future<String> anrufrechtAnfragen() async {
    if (!istUnterstuetzt) return 'nicht_unterstuetzt';
    try {
      return await icdAnrufChannel.invokeMethod<String>('anrufrechtAnfragen') ??
          'abgelehnt';
    } on MissingPluginException {
      return 'nicht_unterstuetzt';
    } catch (e) {
      _log.warning('Anrufrecht-Anfrage fehlgeschlagen: $e', tag: 'ANRUF_GW');
      return 'abgelehnt';
    }
  }

  static Future<bool> overlayEinstellungOeffnen() =>
      _schalter('overlayEinstellungOeffnen');

  static Future<bool> vollbildEinstellungOeffnen() =>
      _schalter('vollbildEinstellungOeffnen');

  static Future<bool> _schalter(String methode) async {
    if (!istUnterstuetzt) return false;
    try {
      return await icdAnrufChannel.invokeMethod<bool>(methode) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Durchlauf ───────────────────────────────────────────────────────────

  /// Holt offene Aufträge, belegt sie und wählt.
  ///
  /// Läuft sowohl im Vordergrundtakt als auch im Isolate des Wachdienstes.
  /// Wirft nie: ein Fehlschlag ist ein Ergebnis. Sonst risse ein einzelner
  /// Wackler den ganzen Durchlauf des Dienstes mit — samt der Warteschlangen,
  /// die danach dran gewesen wären.
  static Future<AnrufGatewayLauf> runOnce({bool background = false}) async {
    if (!istUnterstuetzt) {
      return const AnrufGatewayLauf(note: 'Nur auf Android');
    }
    if (!await isEnabled()) {
      return const AnrufGatewayLauf(note: 'Anruf-Gateway ist aus');
    }

    final geraet = DeviceKeyService().deviceId;
    if (geraet == null || geraet.isEmpty) {
      return const AnrufGatewayLauf(note: 'Gerät nicht angemeldet');
    }

    final api = ApiService();

    final liste = await api.anrufQueueListe(deviceId: geraet);
    if (liste['success'] != true) {
      return AnrufGatewayLauf(note: (liste['message'] ?? 'Warteschlange nicht lesbar').toString());
    }

    final roh = (liste['data']?['queue'] ?? liste['queue']) as List<dynamic>?;
    if (roh == null || roh.isEmpty) {
      await _merkeLauf();
      return const AnrufGatewayLauf();
    }

    // Nur der älteste Auftrag. Zwei Anrufe hintereinander automatisch zu
    // wählen ergibt keinen Sinn — es kann nur einer geführt werden, und der
    // zweite würde den ersten unterbrechen.
    final auftrag = roh.first as Map<String, dynamic>;
    final id = (auftrag['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return const AnrufGatewayLauf(note: 'Auftrag ohne id');

    final claim = await api.anrufQueueClaim(deviceId: geraet, ids: [id]);
    final belegt = ((claim['data']?['claimed'] ?? claim['claimed']) as List<dynamic>?) ?? [];
    if (!belegt.map((e) => (e as num).toInt()).contains(id)) {
      // Ein anderes Gerät war schneller, oder der Auftrag ist inzwischen
      // abgelaufen. Beides ist normal und kein Fehler.
      await _merkeLauf();
      return const AnrufGatewayLauf();
    }

    final nummer = (auftrag['nummer'] ?? '').toString();
    final bezeichnung = (auftrag['bezeichnung'] ?? '').toString();

    final ergebnis = await _waehlen(nummer, bezeichnung);

    await api.anrufQueueReport(
      id: id,
      deviceId: geraet,
      ergebnis: ergebnis.code,
      meldung: ergebnis.meldung,
      weg: ergebnis.weg,
    );

    await _merkeLauf();

    final wortlaut = 'Auftrag $id ($bezeichnung${bezeichnung.isEmpty ? '' : ' '}'
        '${_gekuerzt(nummer)}): ${ergebnis.code} über ${ergebnis.weg}';
    if (ergebnis.code == IcdAnrufErgebnis.gewaehlt) {
      _log.info(wortlaut, tag: 'ANRUF_GW');
      return const AnrufGatewayLauf(gewaehlt: 1);
    }
    if (ergebnis.code == IcdAnrufErgebnis.bestaetigungNoetig) {
      _log.warning(wortlaut, tag: 'ANRUF_GW');
      return const AnrufGatewayLauf(liegengeblieben: 1);
    }
    _log.error(wortlaut, tag: 'ANRUF_GW');
    return const AnrufGatewayLauf(fehler: 1);
  }

  /// Die letzten vier Ziffern reichen fürs Protokoll. Eine vollständige
  /// Rufnummer gehört nicht in eine Logdatei, die zum Server hochgeladen wird.
  static String _gekuerzt(String nummer) =>
      nummer.length <= 4 ? nummer : '…${nummer.substring(nummer.length - 4)}';

  static Future<_WaehlErgebnis> _waehlen(String nummer, String bezeichnung) async {
    try {
      final m = await icdAnrufChannel.invokeMethod<Map<Object?, Object?>>('waehlen', {
        'nummer': nummer,
        'bezeichnung': bezeichnung,
      });
      if (m == null) {
        return const _WaehlErgebnis(IcdAnrufErgebnis.fehler, 'Keine Antwort vom Kanal', 'keiner');
      }
      return _WaehlErgebnis(
        (m['ergebnis'] ?? IcdAnrufErgebnis.fehler).toString(),
        (m['meldung'] ?? '').toString(),
        (m['weg'] ?? 'keiner').toString(),
      );
    } on MissingPluginException {
      return const _WaehlErgebnis(
          IcdAnrufErgebnis.fehler, 'Diese Installation kennt den Anruf-Kanal nicht', 'keiner');
    } catch (e) {
      return _WaehlErgebnis(IcdAnrufErgebnis.fehler, '$e', 'keiner');
    }
  }

  static Future<void> _merkeLauf() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kLastRunKey, DateTime.now().millisecondsSinceEpoch);
  }
}

class _WaehlErgebnis {
  final String code;
  final String meldung;
  final String weg;
  const _WaehlErgebnis(this.code, this.meldung, this.weg);
}

// ─────────────────────────────────────────────────────────────────────────────
// Absenderseite: der Rechner
// ─────────────────────────────────────────────────────────────────────────────

/// Wie ein abgeschickter Auftrag ausgegangen ist.
enum AnrufFernStand {
  /// Das Telefon wählt.
  gewaehlt,

  /// Das Telefon hat den Auftrag, konnte aber nicht von allein wählen — es
  /// liegt dort eine Benachrichtigung.
  liegtAmTelefon,

  /// Niemand hat den Auftrag abgeholt, er ist verfallen.
  keinGeraet,

  /// Ein Telefon läuft nachweislich, macht aber gerade eine Schlafpause. Der
  /// Auftrag gilt weiter und wird gewählt, sobald es aufwacht — das ist kein
  /// Fehlschlag, sondern der Normalfall bei ausgeschaltetem Bildschirm.
  schlaeft,

  /// Das Telefon hat einen Fehler gemeldet.
  fehler,

  /// Der Auftrag ging gar nicht erst raus.
  nichtGesendet,
}

class AnrufFernErgebnis {
  final AnrufFernStand stand;
  final String meldung;

  const AnrufFernErgebnis(this.stand, this.meldung);

  bool get erfolgreich => stand == AnrufFernStand.gewaehlt;
}

/// Schickt den Wählauftrag von einem Gerät ohne SIM an das Gerät mit SIM.
class AnrufFernwahl {
  static const _kAktivKey = 'anruf.fernwahl';

  /// Wie lange auf eine Rückmeldung gewartet wird.
  ///
  /// Der Auftrag gilt serverseitig 120 Sekunden, aber so lange darf niemand
  /// vor einem Fortschrittsbalken sitzen. 20 Sekunden decken den Takt des
  /// Telefons (5 s) mit reichlich Luft ab; danach bleibt der Auftrag gültig
  /// und wird trotzdem noch gewählt, wenn das Telefon spät aufwacht — der
  /// Rechner hört nur auf hinzusehen und sagt das auch.
  static const _wartefrist = Duration(seconds: 20);
  static const _nachfrageTakt = Duration(milliseconds: 1500);

  /// Muss zu `ANRUF_GUELTIG_SEKUNDEN` in `api/anruf/queue.php` passen. Wird
  /// nur für die Restzeit im Hinweistext gebraucht — der Server entscheidet.
  static const _gueltigSekunden = 120;

  /// Ab wann ein Lebenszeichen des Telefons zu alt ist, um noch zu zählen.
  ///
  /// ⚠️ Hier stand vorher eine Abkürzung: „nach elf Sekunden ohne Belegung
  /// hört keiner zu". Der erste Versuch in Produktion hat sie widerlegt.
  /// Das Pixel fragte um 22:33:38 ab, der Klick kam um 22:34:06, der Rechner
  /// gab um 22:34:18 auf, und um 22:34:34 war das Telefon wieder da — es hatte
  /// nur eine Pause gemacht, wie Android sie jedem Hintergrunddienst gönnt.
  /// Der Auftrag hätte noch 108 Sekunden gegolten.
  ///
  /// Aus Stille lässt sich also nichts schließen. Der Server weiß dagegen
  /// genau, wann zuletzt ein Telefon nachgesehen hat, und sagt es jetzt. Zwei
  /// Minuten Toleranz: länger als jede beobachtete Pause, kürzer als ein
  /// Gerät, das wirklich aus ist.
  static const _lebenszeichenGiltFuer = Duration(minutes: 2);

  /// Ist die Fernwahl auf diesem Gerät eingeschaltet?
  ///
  /// Standard AN auf Geräten ohne Telefonie: dort ist ein Klick auf eine
  /// Rufnummer sonst folgenlos, also ist der Auftrag ans Telefon die einzige
  /// sinnvolle Deutung. Auf Android bleibt sie AUS — dieses Gerät wählt
  /// selbst.
  static Future<bool> istAktiv() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kAktivKey) ?? !Platform.isAndroid;
  }

  static Future<void> setAktiv(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAktivKey, value);
  }

  /// Reiht den Auftrag ein und verfolgt ihn bis zur Rückmeldung.
  ///
  /// Wartet bewusst auf das Ergebnis, statt nach dem Abschicken „erledigt" zu
  /// melden. Ohne die Rückfrage sähe der Vorsitzer immer dasselbe grüne
  /// „abgeschickt" — auch dann, wenn gar kein Telefon läuft und niemals
  /// jemand wählt.
  static Future<AnrufFernErgebnis> waehlenLassen(
    String nummer, {
    String? bezeichnung,
    void Function(String zwischenstand)? melde,
  }) async {
    final api = ApiService();

    final gesendet = await api.anrufAuftragSenden(
      nummer: nummer,
      bezeichnung: bezeichnung,
      deviceId: DeviceKeyService().deviceId,
      plattform: Platform.operatingSystem,
    );

    if (gesendet['success'] != true) {
      return AnrufFernErgebnis(
        AnrufFernStand.nichtGesendet,
        (gesendet['message'] ?? 'Auftrag konnte nicht abgeschickt werden').toString(),
      );
    }

    final id = ((gesendet['data']?['id'] ?? gesendet['id']) as num?)?.toInt() ?? 0;
    if (id <= 0) {
      return const AnrufFernErgebnis(
          AnrufFernStand.nichtGesendet, 'Server gab keine Auftragsnummer zurück');
    }

    // Bevor irgendwer wartet: hat in letzter Zeit überhaupt ein Telefon in die
    // Schlange gesehen? Wenn nie eines da war, ist Warten sinnlos, und der
    // Vorsitzer soll sofort erfahren, wo der Schalter sitzt — nicht nach
    // Sekunden des Zusehens.
    final lebenszeichen =
        ((gesendet['data']?['gateway_vor_sekunden'] ?? gesendet['gateway_vor_sekunden'])
                as num?)
            ?.toInt();

    if (lebenszeichen == null ||
        lebenszeichen > _lebenszeichenGiltFuer.inSeconds) {
      await abbrechen(id);
      return AnrufFernErgebnis(
        AnrufFernStand.keinGeraet,
        lebenszeichen == null
            ? 'Kein Telefon nimmt Aufträge entgegen. Auf dem Vereinstelefon '
                'unter Einstellungen „Dieses Gerät wählt für die anderen" '
                'einschalten.'
            : 'Das Vereinstelefon hat sich zuletzt vor '
                '${_dauerText(lebenszeichen)} gemeldet — es ist vermutlich aus.',
      );
    }

    melde?.call('Auftrag am Telefon…');

    final start = DateTime.now();
    final ende = start.add(_wartefrist);

    while (DateTime.now().isBefore(ende)) {
      await Future.delayed(_nachfrageTakt);

      final stand = await api.anrufAuftragStand(id);
      if (stand['success'] != true) continue;

      final a = (stand['data']?['auftrag'] ?? stand['auftrag']) as Map<String, dynamic>?;
      if (a == null) continue;

      switch ((a['status'] ?? '').toString()) {
        case 'gewaehlt':
          return const AnrufFernErgebnis(AnrufFernStand.gewaehlt, 'Das Telefon wählt.');

        case 'fehler':
          final code = (a['ergebnis'] ?? '').toString();
          final meldung = (a['meldung'] ?? '').toString();
          if (code == IcdAnrufErgebnis.bestaetigungNoetig) {
            return AnrufFernErgebnis(
              AnrufFernStand.liegtAmTelefon,
              meldung.isEmpty
                  ? 'Am Telefon liegt eine Benachrichtigung — dort antippen.'
                  : '$meldung — am Telefon antippen.',
            );
          }
          return AnrufFernErgebnis(
            AnrufFernStand.fehler,
            meldung.isEmpty ? _klartext(code) : meldung,
          );

        case 'abgelaufen':
          return const AnrufFernErgebnis(
            AnrufFernStand.keinGeraet,
            'Kein Telefon hat den Auftrag abgeholt.',
          );

        case 'claimed':
          melde?.call('Telefon hat den Auftrag…');
          break;

        case 'abgebrochen':
          // Fast immer der eigene Doppelklick: der neuere Auftrag hat den
          // hier ersetzt. Das gehört so gesagt — vorher lief dieser Zweig ins
          // Zeitfenster und meldete „keine Rückmeldung vom Telefon", was den
          // Verdacht auf das Telefon lenkte statt auf den zweiten Klick.
          return AnrufFernErgebnis(
            AnrufFernStand.fehler,
            (a['meldung'] ?? 'Auftrag wurde abgebrochen').toString(),
          );

        case 'offen':
          // Bewusst KEIN Abbruch mehr. Ein Telefon, das sich eben noch
          // gemeldet hat, macht nur eine Schlafpause; der Auftrag gilt weiter
          // und wird gewählt, sobald es aufwacht.
          break;
      }
    }

    // Nicht abbrechen: der Auftrag ist noch gültig und wird gewählt, sobald
    // das Telefon aus seiner Schlafpause kommt. Nur das Zusehen endet hier —
    // und das wird auch genau so gesagt, statt dem Telefon die Schuld zu
    // geben, das nachweislich läuft.
    final restSekunden =
        _gueltigSekunden - DateTime.now().difference(start).inSeconds;
    return AnrufFernErgebnis(
      AnrufFernStand.schlaeft,
      'Das Telefon macht gerade eine Schlafpause. Der Auftrag bleibt noch '
      '${_dauerText(restSekunden)} gültig und wird gewählt, sobald es aufwacht.',
    );
  }

  /// Sekunden als knapper deutscher Text: „40 Sekunden", „3 Minuten".
  static String _dauerText(int sekunden) {
    if (sekunden < 0) return '0 Sekunden';
    if (sekunden < 90) return '$sekunden Sekunden';
    final min = (sekunden / 60).round();
    if (min < 60) return '$min Minuten';
    final std = (min / 60).round();
    return std == 1 ? 'einer Stunde' : '$std Stunden';
  }

  /// Bricht einen noch offenen Auftrag ab.
  static Future<void> abbrechen(int id) => ApiService().anrufAuftragAbbrechen(id);

  static String _klartext(String code) => switch (code) {
        IcdAnrufErgebnis.keineBerechtigung =>
          'Dem Telefon fehlt die Anrufberechtigung.',
        IcdAnrufErgebnis.keinTelefon => 'Das Gateway-Gerät kann nicht telefonieren.',
        IcdAnrufErgebnis.notruf => 'Notrufe werden nicht ferngesteuert gewählt.',
        IcdAnrufErgebnis.ungueltig => 'Die Rufnummer war nicht wählbar.',
        _ => 'Das Telefon konnte nicht wählen.',
      };
}
