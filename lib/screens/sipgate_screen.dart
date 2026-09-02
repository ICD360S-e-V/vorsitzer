import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/anruf_badge_service.dart';
import '../services/phone_call_service.dart';
import '../services/sipgate_service.dart';
import '../services/untertitel_modell.dart';
import '../services/untertitel_service.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/sipgate_anruf_overlay.dart';
import '../widgets/sekunden_takt.dart';
import '../services/qualitaets_sonde.dart';
import '../widgets/guete_anzeige.dart';
import '../widgets/netz_pastille.dart';
import '../widgets/sipgate_waehltastatur.dart';
import 'sipgate_kontakte_screen.dart';
import '../utils/app_farben.dart';
import '../utils/mitschrift_sprachen.dart';

/// Telefonieren über sipgate, direkt in der App.
///
/// Drei Teile: die Anmeldung (oben, weil eine verlorene Registrierung sonst
/// unbemerkt bliebe), das laufende Gespräch, und die Wähltastatur mit Verlauf.
/// Die VoIP-Telefone des Kontos liegen darunter zugeklappt — daran fasst man
/// selten und dann bewusst.
class SipgateScreen extends StatefulWidget {
  const SipgateScreen({super.key});

  @override
  State<SipgateScreen> createState() => _SipgateScreenState();
}

class _SipgateScreenState extends State<SipgateScreen> {
  final SipgateService _dienst = SipgateService();
  final TextEditingController _nummer = TextEditingController();

  bool _auto = false;
  String _wahlweg = 'sim';
  /// Was eine Taste im laufenden Gespräch bedeutet: Ton (true) oder Ziffer.
  bool _toeneModus = false;
  String _gesendeteToene = '';
  bool _ladeVerlauf = true;
  List<Map<String, dynamic>> _verlauf = const [];

  /// Die Güte über die letzten 90 Tage. `null`, solange nicht geladen.
  Map<String, dynamic>? _gueteStatistik;

  /// Was sipgate ueber das VoIP-Telefon sagt — `null`, solange nicht geholt.
  Map<String, dynamic>? _telefonZustand;
  String _eigenerUa = sipgateEigenerUserAgent;
  List<Map<String, dynamic>> _geraete = const [];
  Map<String, dynamic>? _verzeichnis;

  @override
  void initState() {
    super.initState();
    _dienst.zustand.addListener(_aufZustand);
    // Solange dieser Bildschirm offen ist, keine schwebende Karte: das
    // Gesprächsfeld steht hier schon gross auf der Seite, und zweimal dasselbe
    // verdeckt nur die Wähltastatur.
    SipgateAnrufOverlay().unterdruecken(true);
    _laden();
  }

  @override
  void dispose() {
    _dienst.zustand.removeListener(_aufZustand);
    SipgateAnrufOverlay().unterdruecken(false);
    _nummer.dispose();
    super.dispose();
  }

  // Ein beendetes Gespräch schreibt eine Zeile in den Verlauf; ohne das hier
  // müsste man den Bildschirm verlassen und neu öffnen, um sie zu sehen.
  SipgateGespraechStand? _letzterStand;
  void _aufZustand() {
    final jetzt = _dienst.zustand.value.gespraech?.stand;
    // Sobald jemand abnimmt, sind die Tasten Töne — wie auf jedem Telefon. Am
    // Ende des Gesprächs zurück, sonst würde die nächste getippte Nummer als
    // Tonfolge ins Leere gehen und der Anwender sähe nur, dass nichts passiert.
    if (jetzt == SipgateGespraechStand.verbunden &&
        _letzterStand != SipgateGespraechStand.verbunden) {
      _toeneModus = true;
      _gesendeteToene = '';
    }
    if (jetzt == null) {
      _toeneModus = false;
      _gesendeteToene = '';
    }
    if (_letzterStand != null && jetzt == null) {
      _verlaufLaden();
      // Warum das Gespräch endete, sofort und im Klartext. Sonst verschwindet
      // das Gesprächsfeld und übrig bleibt ein Bildschirm, der nichts sagt —
      // und „Fehler" im Verlauf, den man erst aufklappen muss.
      final grund = _dienst.letzteAbsage;
      if (grund != null) _melde(grund, fehler: !grund.startsWith('Niemand'));
    }
    _letzterStand = jetzt;
    if (mounted) setState(() {});
  }

  Future<void> _laden() async {
    _auto = await _dienst.autoAktiv();
    _wahlweg = await SipgateService.wahlwegFuerRechner();
    // Bei jedem Öffnen nachfragen: beide Berechtigungen können zwischendurch
    // entzogen worden sein — vom Nutzer oder vom Play Store.
    await _dienst.vollbildPruefen();
    await _dienst.benachrichtigungPruefen();
    if (mounted) setState(() {});
    await Future.wait([
      _verlaufLaden(),
      _geraeteLaden(),
      _verzeichnisLaden(),
      _zustandLaden(),
    ]);
  }

  Future<void> _gueteStatistikLaden() async {
    try {
      final a = await ApiService()
          .sipgateAction({'action': 'guete_statistik', 'tage': 90});
      final st = a['guete_statistik'];
      if (mounted && st is Map) {
        setState(() => _gueteStatistik = Map<String, dynamic>.from(st));
      }
    } catch (_) {
      // Still. Ohne Statistik fehlt eine Zeile, nicht der Verlauf.
    }
  }

  /// Die Güte über viele Gespräche.
  ///
  /// ⚠️ DAS IST DIE ZAHL, MIT DER MAN ARGUMENTIERT. Ein einzelnes schlechtes
  /// Gespräch beweist nichts — jeder kennt einen Anruf, der schlecht war. Was
  /// zählt, ist wie oft. Dieselbe Lehre wie beim Speedtest, wo der Anteil der
  /// schlechten Tage die Beschwerde trägt und nicht der schlimmste Einzelwert.
  Widget _gueteUeberblick() {
    final st = _gueteStatistik;
    if (st == null) return const SizedBox.shrink();
    final n = (st['gespraeche'] as num?)?.toInt() ?? 0;
    if (n == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Für die Güte gibt es noch keine Messwerte — sie entstehen ab dem '
          'nächsten Gespräch.',
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
        ),
      );
    }
    final median = (st['mos_median'] as num?)?.toDouble() ?? 0;
    final anteil = (st['anteil_schlecht'] as num?)?.toDouble() ?? 0;
    final schlecht = (st['schlecht'] as num?)?.toInt() ?? 0;
    final eingebrochen = (st['eingebrochen'] as num?)?.toInt() ?? 0;
    final minuten = (st['minuten'] as num?)?.toInt() ?? 0;
    final stufe = gueteStufeAusMos(median);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: gueteFarbe(stufe).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: gueteFarbe(stufe).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.graphic_eq, size: 16, color: gueteFarbe(stufe)),
            const SizedBox(width: 6),
            Text('Verbindungsgüte, 90 Tage',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gueteFarbe(stufe))),
          ]),
          const SizedBox(height: 4),
          Text(
            '$n Gespräche · $minuten Minuten gemessen · '
            'Median MOS ${median.toStringAsFixed(2)} (${gueteStufeText(stufe)})',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '$schlecht davon unter „brauchbar" '
            '(${anteil.toStringAsFixed(0)} %)'
            // ⚠️ Getrennt ausgewiesen: ein Gespräch, dessen Median in Ordnung
            // war und das trotzdem zeitweise einbrach, fällt aus jeder
            // Durchschnittsbetrachtung heraus — und ist doch genau das, was
            // man am Telefon erlebt hat.
            '${eingebrochen > 0 ? ' · $eingebrochen weitere brachen zeitweise ein' : ''}',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
          ),
          const SizedBox(height: 3),
          Text(
            '⚠️ Gemessen wird die Strecke bis sipgate, nicht das ganze '
            'Gespräch — und nur, was dieses Gerät mitbekommen hat.',
            style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
          ),
        ],
      ),
    );
  }

  Future<void> _verlaufLaden() async {
    try {
      final a = await ApiService().sipgateAction({'action': 'list_anrufe', 'limit': 40});
      // Flach, kein `data` — jsonResponse() macht array_merge.
      final liste = a['anrufe'];
      // Die Antwort bringt die Zahl schon mit — eine zweite Anfrage nur fuers
      // Abzeichen waere Arbeit fuer nichts.
      AnrufBadgeService().uebernehmen(a);
      // ⚠️ Getrennte Anfrage, und ein Fehlschlag darf den Verlauf nicht
      // mitnehmen: die Statistik ist Beiwerk, die Liste ist der Zweck.
      unawaited(_gueteStatistikLaden());
      if (mounted) {
        setState(() {
          _verlauf = liste is List ? liste.cast<Map<String, dynamic>>() : const [];
          _ladeVerlauf = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ladeVerlauf = false);
    }
  }

  /// Holt bei sipgate, ob das VoIP-Telefon angemeldet ist.
  ///
  /// ⚠️ Nicht beim Geraet selbst erfragt, sondern beim Registrar. Ein
  /// Lebenszeichen des Tablets bewiese nur „die App laeuft", nicht „sie ist
  /// angemeldet" — und die beiden gehen genau in dem Fall auseinander, um den
  /// es hier geht.
  Future<void> _zustandLaden({bool frisch = false}) async {
    try {
      final a = await ApiService()
          .sipgateAction({'action': 'geraete_zustand', if (frisch) 'frisch': true});
      if (!mounted) return;
      final liste = a['zustand'];
      setState(() {
        _telefonZustand = (liste is List && liste.isNotEmpty)
            ? Map<String, dynamic>.from(liste.first as Map)
            : null;
        final ua = a['eigener_user_agent'];
        if (ua is String && ua.isNotEmpty) _eigenerUa = ua;
      });
    } catch (_) {
      // Kein Zustand ist etwas anderes als „nicht angemeldet" — der letzte
      // bekannte Stand bleibt stehen, und die Anzeige sagt „unbekannt".
    }
  }

  /// Die Karte, die sagt, ob ueber sipgate ueberhaupt telefoniert werden kann.
  ///
  /// ⚠️ Steht auf BEIDEN Geraeten, und auf dem Rechner ist sie der eigentliche
  /// Gewinn: von dort gehen die Waehlauftraege aus, und seit „nur das Geraet
  /// mit eigenem Telefon meldet sich an" scheitert ein Auftrag mit
  /// `wahlweg: sipgate` ehrlich, wenn das Tablet nicht angemeldet ist — nur
  /// erfuhr man das bis jetzt erst NACH dem Klick.
  Widget _telefonLage() {
    final z = _telefonZustand;
    final lage = sipgateTelefonLage(
      online: z?['online'] as bool?,
      dnd: z?['dnd'] as bool?,
      userAgent: z?['user_agent'] as String?,
      eigenerUserAgent: _eigenerUa,
    );
    final (farbe, symbol, titel, text) = switch (lage) {
      SipgateTelefonLage.bereit => (
          Colors.green,
          Icons.cloud_done,
          'Das Tablet ist bei sipgate angemeldet',
          'Ein Anruf über sipgate kann zustande kommen.',
        ),
      SipgateTelefonLage.fremdesGeraet => (
          Colors.orange,
          Icons.devices_other,
          'Angemeldet — aber nicht von dieser App',
          'Die Anmeldung hält „${z?['user_agent'] ?? '?'}". Ein Auftrag über '
              'sipgate würde scheitern, weil unsere App die Leitung nicht hält.',
        ),
      SipgateTelefonLage.nichtStoeren => (
          Colors.orange,
          Icons.do_not_disturb_on,
          'Nicht stören ist eingeschaltet',
          'Das Telefon ist angemeldet, aber bei sipgate auf „nicht stören" '
              'gestellt — eingehende Anrufe klingeln nicht. Umzustellen im '
              'sipgate-Konto.',
        ),
      SipgateTelefonLage.abgemeldet => (
          Colors.red,
          Icons.cloud_off,
          'Das Tablet ist NICHT bei sipgate angemeldet',
          'Ein Anruf über sipgate würde jetzt scheitern. Es wird nicht auf die '
              'SIM ausgewichen — das wäre eine andere Leitung mit einer anderen '
              'Absendernummer.',
        ),
      SipgateTelefonLage.unbekannt => (
          Colors.grey,
          Icons.help_outline,
          'Anmeldezustand unbekannt',
          'Der Zustand konnte nicht bei sipgate erfragt werden. Das ist etwas '
              'anderes als „nicht angemeldet".',
        ),
    };

    final stand = '${z?['stand_am'] ?? ''}';
    return Card(
      color: F.h(farbe, 50),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(symbol, size: 22, color: F.h(farbe, 700)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titel,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: F.h(farbe, 900))),
                  const SizedBox(height: 4),
                  Text(text,
                      style:
                          TextStyle(fontSize: 12, color: F.h(Colors.grey, 800))),
                  if (stand.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    // Der Zeitpunkt gehoert dazu: die Auskunft ist bis zu einer
                    // Minute alt, und ohne ihn liest man sie als „jetzt".
                    Text('Bei sipgate erfragt: $stand',
                        style: TextStyle(
                            fontSize: 11, color: F.h(Colors.grey, 600))),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Jetzt neu bei sipgate erfragen',
              visualDensity: VisualDensity.compact,
              onPressed: () => _zustandLaden(frisch: true),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _geraeteLaden() async {
    try {
      final a = await ApiService().sipgateAction({'action': 'list_geraete'});
      final liste = a['geraete'];
      if (mounted && liste is List) {
        setState(() => _geraete = liste.cast<Map<String, dynamic>>());
      }
    } catch (_) {/* Der Bildschirm bleibt ohne Geräteliste benutzbar. */}
  }

  Future<void> _verzeichnisLaden() async {
    try {
      final a = await ApiService().sipgateAction({'action': 'verzeichnis_stand'});
      if (mounted && a['success'] == true) {
        setState(() => _verzeichnis = Map<String, dynamic>.from(a));
      }
    } catch (_) {/* Der Bildschirm bleibt ohne diese Zeile benutzbar. */}
  }

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : null,
      duration: Duration(seconds: fehler ? 7 : 4),
    ));
  }

  // ── Aktionen ───────────────────────────────────────────────────────────────

  Future<void> _anrufen() async {
    final roh = _nummer.text.trim();
    if (roh.isEmpty) return;

    // ⚠️ NOTRUFE: die Absage allein war zu wenig.
    // `SipgateService.anrufen()` weist 110/112 zu Recht ab — im sipgate-Konto
    // steht die Adresse zwar VERIFIZIERT und am Telefon, aber ihr
    // `emergencyState` ist `NONE`; der Ruf landete also im besten Fall bei der
    // falschen Leitstelle. Bisher stand danach nur ein roter Satz auf dem
    // Schirm, der auf „das Telefon mit SIM-Karte" verwies — und genau das
    // Gerät hält man in der Hand.
    //
    // ⚠️ Es wird NICHTS von selbst gewählt. `PhoneCallService` erkennt
    // Notrufnummern und öffnet für sie ausschliesslich die Telefon-App
    // (`emergency_dialer`); den Anruf löst ein Mensch aus. Eine App darf einen
    // Notruf nicht selbst absetzen, und ein versehentlicher 112-Anruf bindet
    // eine Leitstelle, die jemand anderes gerade braucht.
    if (SipgateService.istNotruf(roh)) {
      await _notrufWeg(roh);
      return;
    }

    final meldung = await _dienst.anrufen(roh);
    if (meldung != null) {
      _melde(meldung, fehler: true);
    } else {
      _nummer.clear();
    }
  }

  /// Zeigt, warum ein Notruf nicht über sipgate geht — und bietet den Weg an,
  /// der funktioniert.
  Future<void> _notrufWeg(String nummer) async {
    final hatSim = _dienst.plattformFaehig; // Android = das Gerät mit SIM
    final weiter = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.emergency_share, color: Colors.red, size: 32),
        title: Text('Notruf $nummer'),
        content: Text(
          hatSim
              ? 'Notrufe gehen nicht über sipgate: dafür fehlt im Konto ein '
                  'freigeschalteter Notrufstandort, der Ruf käme sonst bei der '
                  'falschen Leitstelle an.\n\n'
                  'Über die SIM-Karte funktioniert er — und zwar auch dann, '
                  'wenn gerade kein Internet da ist.\n\n'
                  'Es wird nichts automatisch gewählt: die Telefon-App geht '
                  'auf, den Anruf lösen Sie dort selbst aus.'
              : 'Notrufe gehen weder über sipgate noch über diesen Rechner.\n\n'
                  'Bitte ein Telefon mit SIM-Karte benutzen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          if (hatSim)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.phone_in_talk),
              label: const Text('Telefon-App öffnen'),
            ),
        ],
      ),
    );
    if (weiter != true || !mounted) return;
    await PhoneCallService.call(context, nummer);
  }

  /// Kontaktliste öffnen und die gewählte Nummer ins Wählfeld holen.
  ///
  /// ⚠️ Sie wählt NICHT selbst. Wer aus einer Liste heraus sofort wählt, ruft
  /// irgendwann das Gericht an, weil er die Zeile darunter treffen wollte —
  /// und ein Anruf lässt sich nicht zurücknehmen. Die Nummer steht danach im
  /// Feld, sichtbar, und der grüne Knopf ist einen bewussten Griff entfernt.
  Future<void> _kontakteOeffnen() async {
    final nummer = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        // Ohne Wählfeld — also überall ausser auf dem Tablet — wählt die Liste
        // selbst über die Fernwahl, sonst käme die Nummer zurück und niemand
        // wüsste, was mit ihr geschehen soll.
        builder: (_) => SipgateKontakteScreen(zurueckgeben: _dienst.plattformFaehig),
      ),
    );
    if (nummer == null || !mounted) return;
    setState(() {
      _nummer.text = nummer;
      // Aus der Liste kommt eine Nummer, kein Tastenton — sonst landete sie im
      // laufenden Gespräch als Piepfolge statt im Feld für das zweite Bein.
      _toeneModus = false;
    });
  }

  Future<void> _autoUmschalten(bool an) async {
    setState(() => _auto = an);
    await _dienst.setAutoAktiv(an);
  }

  Future<void> _selbsttest() async {
    final a = await ApiService().sipgateAction({'action': 'selbsttest'});
    final fehler = (a['fehler'] as List?) ?? const [];
    _melde(
      fehler.isEmpty
          ? 'Selbsttest bestanden — Realm ${a['realm']}, ${a['wss_url']}'
          : 'Selbsttest: ${fehler.join(' · ')}',
      fehler: fehler.isNotEmpty,
    );
  }

  // ── Aufbau ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final z = _dienst.zustand.value;
    final schmal = ResponsiveLayout.istTelefon(context);

    return Scaffold(
      backgroundColor: F.hd(const Color(0xFFF5F5F5), F.flaecheGedaempft),
      appBar: AppBar(
        title: const Text('sipgate — Telefonie'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts_outlined),
            tooltip: 'Kontakte',
            onPressed: _kontakteOeffnen,
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Selbsttest (HA1, Notrufsperre, Rufnummern)',
            onPressed: _selbsttest,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
            onPressed: _laden,
          ),
        ],
      ),
      // Auf allem außer Android ist dieser Bildschirm ein Bedienpult: hier wird
      // eingestellt, WOMIT das Tablet wählt, und nachgesehen, was gelaufen ist.
      // Telefoniert wird auf dem Tablet.
      body: ListView(
        padding: EdgeInsets.all(schmal ? 10 : 16),
        children: [
          if (!_dienst.plattformFaehig) _hinweisBedienpult() else _anmeldung(z),
          const SizedBox(height: 12),
          _telefonLage(),
          if (_dienst.plattformFaehig && z.gespraech != null) ...[
            const SizedBox(height: 12),
            _gespraechsfeld(z),
          ],
          const SizedBox(height: 12),
          _fernwahlweg(),
          if (_dienst.plattformFaehig) ...[
            const SizedBox(height: 12),
            _waehlfeld(schmal),
          ],
          const SizedBox(height: 12),
          _hinweisNotruf(),
          const SizedBox(height: 12),
          _verlaufsfeld(),
          const SizedBox(height: 12),
          _geraetefeld(),
        ],
      ),
    );
  }

  Widget _anmeldung(SipgateZustand z) {
    final (farbe, symbol, text) = switch (z.stand) {
      SipgateStand.registriert => (Colors.green.shade600, Icons.cloud_done, 'Angemeldet'),
      SipgateStand.verbindet => (Colors.orange.shade700, Icons.cloud_sync, 'Melde an …'),
      SipgateStand.fehler => (Colors.red.shade700, Icons.cloud_off, 'Nicht angemeldet'),
      SipgateStand.aus => (Colors.grey.shade600, Icons.cloud_off, 'Aus'),
      // Grau, nicht rot: hier ist nichts kaputt, dieses Gerät ist schlicht
      // nicht dasjenige, das telefoniert. Ein eigenes Symbol, damit es sich
      // von „Aus" (Schalter umgelegt) unterscheidet.
      SipgateStand.fremdesTelefon =>
        (Colors.blueGrey.shade600, Icons.devices_other, 'Anderes Gerät telefoniert'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(symbol, color: farbe, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: farbe)),
                      if (z.sipId != null)
                        Text(
                          z.bezeichnung?.isNotEmpty == true
                              ? '${z.bezeichnung} · ${z.sipId}'
                              : '${z.sipId}',
                          style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)),
                        ),
                    ],
                  ),
                ),
                if (z.stand == SipgateStand.registriert)
                  TextButton.icon(
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Abmelden'),
                    onPressed: _dienst.stoppen,
                  )
                else
                  FilledButton.icon(
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Anmelden'),
                    onPressed: () async {
                      final ok = await _dienst.starten();
                      if (!ok) {
                        _melde(_dienst.zustand.value.meldung ?? 'Anmeldung fehlgeschlagen',
                            fehler: true);
                      }
                    },
                  ),
              ],
            ),
            if (z.sipId != null) ...[
              const SizedBox(height: 10),
              // ⚠️ Steht im Bildschirm, weil es sonst niemand weiss: mit
              // unterdrückter Nummer nehmen viele Ämter und Praxen gar nicht ab
              // und können auf keinen Fall zurückrufen. Wer das nicht sieht,
              // sucht den Fehler bei der Verbindung.
              //
              // ⚠️ DREI ZUSTÄNDE, NICHT ZWEI. Vorher hiess `null` schlicht
              // „unterdrückt" — auch dann, wenn wir aus dem Zwischenspeicher
              // angemeldet waren und es schlicht nicht wussten. Dieser
              // Bildschirm hat dann eine Aussage über die Aussenwirkung JEDES
              // Anrufs getroffen, die falsch war. `notrufstandort` gleich
              // darunter macht es seit jeher richtig vor.
              Builder(builder: (_) {
                final anzeige = sipgateAbsenderAnzeige(
                  bekannt: z.absendernummerBekannt,
                  nummer: z.absendernummer,
                );
                final unbekannt = anzeige == SipgateAbsenderAnzeige.unbekannt;
                final unterdrueckt = anzeige == SipgateAbsenderAnzeige.unterdrueckt;
                final auffaellig = anzeige != SipgateAbsenderAnzeige.nummer;
                return Row(
                  children: [
                    Icon(
                      unbekannt
                          ? Icons.help_outline
                          : (unterdrueckt ? Icons.visibility_off : Icons.badge_outlined),
                      size: 16,
                      color: auffaellig ? F.h(Colors.orange, 700) : F.h(Colors.grey, 700),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        unbekannt
                            ? 'Angerufene sehen: unbekannt — die Angaben konnten '
                                'beim Anmelden nicht vom Server geholt werden'
                            : (unterdrueckt
                                ? 'Angerufene sehen: unterdrückt — viele Ämter nehmen '
                                    'dann nicht ab und können nicht zurückrufen'
                                : 'Angerufene sehen: ${_nummerLesbar(z.absendernummer!)}'),
                        style: TextStyle(
                          fontSize: 12,
                          color: auffaellig ? F.h(Colors.orange, 900) : F.h(Colors.grey, 800),
                          fontWeight: auffaellig ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.emergency_outlined, size: 16, color: F.h(Colors.grey, 700)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      switch (z.notrufstandort) {
                        'gesetzt' => 'Notrufstandort im Konto gesetzt — 110/112 '
                            'gehen hier trotzdem nicht, sondern über die SIM.',
                        'nicht_gesetzt' => 'Notrufstandort NICHT gesetzt — 110/112 '
                            'können über sipgate nicht funktionieren.',
                        _ => 'Notrufstandort unbekannt — 110/112 gehen über die SIM.',
                      },
                      style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 800)),
                    ),
                  ),
                ],
              ),
            ],
            if (z.benachrichtigungenErlaubt == false) ...[
              const SizedBox(height: 8),
              // ⚠️ Der schwerste der drei Fälle: ohne diese Freigabe erscheint
              // bei einem Anruf GAR NICHTS. Es klingelt, aber wer anruft steht
              // nirgends — und eine verworfene Benachrichtigung wirft nicht,
              // also merkt es auch das Protokoll nicht.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: F.h(Colors.red, 50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: F.h(Colors.red, 200)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_off, size: 18, color: F.h(Colors.red, 700)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Benachrichtigungen sind für diese App gesperrt. Ein '
                        'eingehender Anruf klingelt dann, zeigt aber NICHT, wer '
                        'anruft.',
                        style: TextStyle(fontSize: 12, color: F.h(Colors.red, 900)),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await _dienst.benachrichtigungPruefen();
                        if (ok == false) {
                          _melde(
                            'Bitte in den App-Einstellungen unter '
                            '„Benachrichtigungen" erlauben — der Dialog kommt '
                            'nicht wieder.',
                            fehler: true,
                          );
                        }
                      },
                      child: const Text('Erlauben'),
                    ),
                  ],
                ),
              ),
            ],
            if (z.vollbildErlaubt == false) ...[
              const SizedBox(height: 8),
              // ⚠️ Deklariert ist nicht erteilt. Ohne dieses Recht klingelt es
              // und eine Benachrichtigung erscheint — aber kein
              // Anrufbildschirm. Bei einem Tablet, das mit dunklem Display auf
              // dem Tisch liegt, ist das der Unterschied zwischen „Anruf
              // gesehen" und „Anruf verpasst".
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: F.h(Colors.orange, 50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: F.h(Colors.orange, 200)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.fullscreen_exit, size: 18, color: F.h(Colors.orange, 700)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Anrufbildschirm nicht erlaubt. Es klingelt und eine '
                        'Benachrichtigung erscheint, aber bei dunklem Display '
                        'öffnet sich kein Anrufbildschirm — der Anruf fällt '
                        'dann leicht durch.',
                        style: TextStyle(fontSize: 12, color: F.h(Colors.orange, 900)),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _dienst.vollbildEinstellungOeffnen();
                        // Nach der Rückkehr neu fragen — sonst bliebe der
                        // Hinweis stehen, obwohl man ihn gerade erledigt hat.
                        await _dienst.vollbildPruefen();
                      },
                      child: const Text('Einstellen'),
                    ),
                  ],
                ),
              ),
            ],
            if (_btNoetig(z)) ...[
              const SizedBox(height: 8),
              // ⚠️ Der wahrscheinlichste Grund für „ich höre nichts im
              // Kopfhörer": ohne BLUETOOTH_CONNECT findet Android das
              // gekoppelte Headset nicht und der Ton geht in den
              // Tablet-Lautsprecher — ohne jede Fehlermeldung. Deshalb steht es
              // hier und nicht nur im Protokoll.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: F.h(Colors.orange, 50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: F.h(Colors.orange, 200)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.bluetooth_disabled, size: 18, color: F.h(Colors.orange, 700)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        z.bluetoothRecht == 'dauerhaft_abgelehnt'
                            ? 'Bluetooth-Berechtigung dauerhaft abgelehnt — ohne sie '
                                'findet die App das Headset nicht und der Ton geht in '
                                'den Tablet-Lautsprecher. Nur noch über die '
                                'App-Einstellungen zu erlauben.'
                            : 'Bluetooth-Berechtigung fehlt. Ohne sie findet die App '
                                'das gekoppelte Headset nicht und der Ton geht in den '
                                'Tablet-Lautsprecher.',
                        style: TextStyle(fontSize: 12, color: F.h(Colors.orange, 900)),
                      ),
                    ),
                    if (z.bluetoothRecht != 'dauerhaft_abgelehnt')
                      TextButton(
                        onPressed: () async {
                          final stand = await _dienst.bluetoothRechtSichern();
                          if (stand != 'erteilt' && stand != 'nicht_noetig') {
                            _melde('Bluetooth-Berechtigung: $stand', fehler: true);
                          }
                        },
                        child: const Text('Erlauben'),
                      ),
                  ],
                ),
              ),
            ],
            if (z.meldung != null) ...[
              const SizedBox(height: 8),
              Text(z.meldung!, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 800))),
            ],
            // ⚠️ `z.geteilt` ist bewusst NICHT die einzige Bedingung: aus dem
            // Zwischenspeicher heisst `false` nur „unbekannt", und dann fehlte
            // hier stillschweigend der Hinweis, dass ein zweites Gerät
            // mitklingelt. Kein falscher Satz wie oben, aber dieselbe Wurzel.
            if (z.geteilt) ...[
              const SizedBox(height: 8),
              _warnzeile(
                'Dieses VoIP-Telefon wird mit einem anderen Gerät geteilt — '
                'eingehende Anrufe klingeln dann auf beiden.',
                Colors.orange,
              ),
            ],
            const Divider(height: 22),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _auto,
              onChanged: _autoUmschalten,
              title: const Text('Beim App-Start automatisch anmelden'),
              subtitle: const Text(
                'Nötig, um Anrufe in der App zu empfangen. Hält eine Verbindung '
                'zu sipgate offen, solange die App läuft.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Erklärt, warum es hier keine Wähltastatur gibt.
  ///
  /// Ohne diese Karte sähe der Bildschirm am Rechner nach einer halben Funktion
  /// aus — und jemand würde suchen, warum „Anmelden" fehlt.
  Widget _hinweisBedienpult() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.desktop_windows_outlined, size: 24, color: Colors.indigo.shade400),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bedienpult — telefoniert wird auf dem Tablet',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      'Die In-App-Telefonie läuft nur auf dem Samsung-Tablet: dort '
                      'hängt das Bluetooth-Headset, und die App läuft dort dauerhaft. '
                      'Von hier aus wird gewählt, indem der Auftrag ans Tablet geht — '
                      'ein Klick auf eine Rufnummer in einer Behörden- oder Arztkarte '
                      'genügt.',
                      style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 800)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  /// Womit das Vereinstelefon wählt, wenn der Auftrag von hier kommt.
  ///
  /// Der Klick auf eine Rufnummer in einer Behörden- oder Arztkarte bleibt
  /// derselbe; nur der Weg dahinter ändert sich. Über sipgate landet die
  /// Sprache im Bluetooth-Headset am Tablet, über die SIM im Systemdialer.
  Widget _fernwahlweg() {
    final ueberSipgate = _wahlweg == 'sipgate';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_phone, size: 20, color: F.h(Colors.grey, 700)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Anruf vom Rechner: womit wählt das Tablet?',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'sim',
                  icon: Icon(Icons.sim_card, size: 18),
                  label: Text('SIM'),
                ),
                ButtonSegment(
                  value: 'sipgate',
                  icon: Icon(Icons.headset_mic, size: 18),
                  label: Text('sipgate'),
                ),
              ],
              selected: {_wahlweg},
              onSelectionChanged: (s) async {
                final neu = s.first;
                setState(() => _wahlweg = neu);
                await SipgateService.setWahlwegFuerRechner(neu);
              },
            ),
            const SizedBox(height: 8),
            Text(
              ueberSipgate
                  ? 'Das Tablet wählt über VoIP; die Sprache geht in das '
                      'Bluetooth-Headset am Tablet. Setzt voraus, dass dort '
                      '„Beim App-Start automatisch anmelden" an ist.'
                  : 'Das Tablet wählt über die SIM-Karte mit dem Systemdialer '
                      '— der bisherige Weg.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
            ),
            if (ueberSipgate) ...[
              const SizedBox(height: 8),
              // ⚠️ Steht hier, weil es genau der Fall ist, der sonst als
              // „Anruf geht nicht" ankommt: kein Rückfall auf die SIM, sondern
              // eine Fehlermeldung. Ein stiller Umweg über einen anderen
              // Anschluss mit anderer Absendernummer wäre schlimmer.
              _warnzeile(
                'Ist das Tablet nicht bei sipgate angemeldet, meldet der Auftrag '
                'einen Fehler — es wird NICHT still auf die SIM ausgewichen.',
                Colors.orange,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Das Gesprächsfeld — ein Bein oder zwei, plus die Konferenzsteuerung.
  Widget _gespraechsfeld(SipgateZustand z) {
    final beine = z.beine;
    final zwei = beine.length == 2;

    return Card(
      color: z.konferenz
          ? F.h(Colors.deepPurple, 50)
          : (z.verbundeneBeine > 0 ? F.h(Colors.green, 50) : F.h(Colors.blue, 50)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            if (z.konferenz) ...[
              Row(
                children: [
                  Icon(Icons.groups, size: 20, color: F.h(Colors.deepPurple, 700)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zusammengeschaltet — bitte prüfen, ob sich alle hören',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: F.h(Colors.deepPurple, 900)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            // Jedes Bein mit Name, Nummer, Dauer und eigenem Auflegen-Knopf.
            // Ein gemeinsamer Knopf würde bei zwei Gesprächen das falsche
            // beenden, und man erfährt es erst, wenn jemand nicht mehr da ist.
            for (var i = 0; i < beine.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              _beinZeile(beine[i], zweites: i == 1),
            ],

            const SizedBox(height: 12),
            _steuerung(z, zwei),

            if (z.verbundeneBeine > 0) ...[
              const Divider(height: 20),
              _gueteFeld(),
              const Divider(height: 20),
              Text('Tastentöne (DTMF)',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final ton in ['1','2','3','4','5','6','7','8','9','*','0','#'])
                    SizedBox(
                      width: 42,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => _dienst.dtmf(ton),
                        child: Text(ton),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Die Güte des laufenden Gesprächs: zugeklappt eine Zeile, aufgeklappt
  /// alles Gemessene.
  ///
  /// ⚠️ Zugeklappt als Vorgabe. Wer telefoniert, will den Auflegen-Knopf
  /// sehen, nicht zwanzig Kennzahlen — die braucht man erst, wenn etwas nicht
  /// stimmt, und dann sofort vollständig.
  Widget _gueteFeld() {
    return ValueListenableBuilder<QualitaetsProbe?>(
      valueListenable: _dienst.guete,
      builder: (_, probe, __) {
        if (probe == null) {
          return Row(children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: F.h(Colors.grey, 500)),
            ),
            const SizedBox(width: 8),
            Text('Verbindungsgüte wird gemessen …',
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
          ]);
        }
        return Theme(
          // Ohne das zieht ExpansionTile eine Linie quer durch die Karte.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            dense: true,
            leading: Icon(Icons.graphic_eq, color: gueteFarbe(probe.stufe)),
            title: Text(
              'Verbindung ${gueteStufeText(probe.stufe)}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: gueteFarbe(probe.stufe)),
            ),
            subtitle: Text(
              'MOS ${probe.mos.toStringAsFixed(2)} · '
              'Verlust ${probe.verlustProzent.toStringAsFixed(1)} %'
              '${probe.rttMs == null ? '' : ' · ${probe.rttMs!.round()} ms'}',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
            ),
            children: [
              GueteTafel(probe: probe, bilanz: _dienst.gueteBilanz),
            ],
          ),
        );
      },
    );
  }

  Widget _beinZeile(SipgateGespraech g, {required bool zweites}) {
    final verbunden = g.stand == SipgateGespraechStand.verbunden;
    final klingelt = g.stand == SipgateGespraechStand.klingelt;
    return Row(
      children: [
        Icon(
          g.gehalten
              ? Icons.pause_circle_outline
              : (g.eingehend ? Icons.phone_callback : Icons.phone_forwarded),
          color: g.gehalten
              ? F.h(Colors.orange, 700)
              : (verbunden ? F.h(Colors.green, 700) : F.h(Colors.blue, 700)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(g.anzeige,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              // ⚠️ Nur diese Zeile tickt. Der Name darüber, die Knöpfe und
              // die Steuerung darunter ändern sich nur bei einem Ereignis —
              // sie im Sekundentakt mitzubauen wäre Arbeit für nichts.
              SekundenTakt(
                aktiv: verbunden && !g.gehalten,
                bauen: (_) => Text(
                  [
                    if (g.gehalten) 'In der Warteschleife',
                    if (klingelt) 'Eingehender Anruf',
                    if (verbunden && !g.gehalten)
                      'Verbunden · ${SipgateService.dauerUhr(g.dauerSekunden)}',
                    if (g.stand == SipgateGespraechStand.waehlt) 'Wählt',
                    // Nur wenn der Name wirklich ein Name ist — sonst stünde
                    // die Nummer zweimal da, einmal getrennt und einmal nicht.
                    if (g.anzeige != SipgateService.anruferAnzeige(g.nummer))
                      SipgateService.anruferAnzeige(g.nummer),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 800)),
                ),
              ),
            ],
          ),
        ),
        if (klingelt) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            icon: const Icon(Icons.call, size: 18),
            label: const Text('Annehmen'),
            onPressed: () => _dienst.annehmen(),
          ),
          const SizedBox(width: 6),
        ],
        IconButton(
          tooltip: 'Auflegen',
          icon: Icon(Icons.call_end, color: F.h(Colors.red, 700)),
          onPressed: () => _dienst.auflegen(zweites: zweites),
        ),
      ],
    );
  }

  /// Halten, Makeln, Konferenz — und der Hinweis, wenn eines davon nicht geht.
  Widget _steuerung(SipgateZustand z, bool zwei) {
    final aktiv = z.gespraech;
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (z.verbundeneBeine > 0 && !z.konferenz)
              OutlinedButton.icon(
                icon: Icon(aktiv?.gehalten == true ? Icons.play_arrow : Icons.pause),
                label: Text(aktiv?.gehalten == true ? 'Zurückholen (#)' : 'Halten (*3)'),
                onPressed: () => _dienst.halten(!(aktiv?.gehalten ?? false)),
              ),
            if (zwei && !z.konferenz)
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Wechseln (*4)'),
                onPressed: _dienst.makeln,
              ),
            if (_dienst.kannKonferenz)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple.shade600),
                icon: const Icon(Icons.groups),
                label: const Text('Konferenz (*5)'),
                onPressed: () async {
                  final m = await _dienst.konferenzSchalten();
                  if (m != null) _melde(m, fehler: true);
                },
              ),
            if (z.verbundeneBeine > 0)
              ValueListenableBuilder<bool>(
                valueListenable: UntertitelService().aktiv,
                builder: (_, an, __) => OutlinedButton.icon(
                  icon: Icon(an ? Icons.closed_caption : Icons.closed_caption_off),
                  label: Text(an ? 'Mitschrift aus' : 'Mitschrift'),
                  onPressed: _untertitelUmschalten,
                ),
              ),
            // Die Sprache der Mitschrift — nur sichtbar, wenn sie läuft.
            //
            // ⚠️ Sie MUSS von Hand umschaltbar sein. Vorgeschlagen wird sie
            // aus `users.preferred_language`, also aus der Sprache der
            // ANWENDUNG des Mitglieds — und ein Mitglied mit rumänischer
            // Oberfläche kann am Telefon Deutsch sprechen. Die Wahl hier gilt
            // ab sofort und beim nächsten Anruf an dieselbe Nummer.
            if (z.verbundeneBeine > 0)
              ValueListenableBuilder<bool>(
                valueListenable: UntertitelService().aktiv,
                builder: (_, an, __) => !an
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder<String>(
                        valueListenable: UntertitelService().laufendeSprache,
                        builder: (_, spr, __) => PopupMenuButton<String>(
                          tooltip: 'Sprache der Mitschrift',
                          onSelected: _spracheUmschalten,
                          itemBuilder: (_) => [
                            for (final k in kMitschriftSprachen)
                              PopupMenuItem(
                                value: k,
                                child: Row(children: [
                                  Icon(k == spr
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked, size: 18),
                                  const SizedBox(width: 8),
                                  Text(mitschriftSpracheName(k)),
                                ]),
                              ),
                          ],
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.translate),
                            label: Text(mitschriftSpracheName(spr)),
                            onPressed: null,
                          ),
                        ),
                      ),
              ),
            if (z.verbundeneBeine > 0)
              OutlinedButton.icon(
                icon: const Icon(Icons.phone_forwarded),
                label: const Text('Weiterverbinden'),
                onPressed: _weiterverbinden,
              ),
            OutlinedButton.icon(
              icon: Icon(aktiv?.stumm == true ? Icons.mic_off : Icons.mic),
              label: Text(aktiv?.stumm == true ? 'Stumm' : 'Mikrofon an'),
              onPressed: z.verbundeneBeine == 0
                  ? null
                  : () => _dienst.stummSchalten(!(aktiv?.stumm ?? false)),
            ),
          ],
        ),
        _untertitelFeld(),
        if (_dienst.kannHinzuwaehlen) ...[
          const SizedBox(height: 8),
          Text(
            'Für eine Konferenz: unten die zweite Nummer eingeben und '
            '„Hinzuwählen" — das laufende Gespräch wird dabei gehalten.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
          ),
        ],
      ],
    );
  }

  /// Schaltet die Mitschrift dessen ein, was die Gegenstelle sagt.
  ///
  /// ⚠️ Es wird NICHTS aufgezeichnet und NICHTS gespeichert — weder Ton noch
  /// Text. Die Wörter stehen da, solange gesprochen wird, und sind mit dem
  /// Gespräch weg. Siehe [UntertitelService].
  Future<void> _untertitelUmschalten() async {
    final u = UntertitelService();
    if (u.aktiv.value) {
      await u.beenden();
      return;
    }
    // ⚠️ Die LEBENDE Kennung, nicht die gemerkte: eine Neuverhandlung im
    // Gespräch (Halten, Codecwechsel) ersetzt die Tonspur, und die gemerkte
    // zeigt danach ins Leere — auf dem Schirm steht dann „Tonspur der
    // Gegenstelle nicht gefunden", obwohl das Gespräch läuft.
    final grund = await u.starten(
        await _dienst.gegenstelleSpurAktuell() ?? '',
        sprache: u.laufendeSprache.value);
    if (!mounted) return;
    if (grund == null) return;

    // Fehlt nur das Sprachmodell, ist das kein Fehler, sondern ein fehlender
    // Schritt — und der gehört angeboten, nicht bloss gemeldet.
    if (u.modellFehlt.value) {
      await _modellHolen();
      return;
    }
    _melde(grund, fehler: true);
  }

  /// Stellt die laufende Mitschrift auf eine andere Sprache um.
  Future<void> _spracheUmschalten(String k) async {
    final grund = await _dienst.mitschriftSpracheWechseln(k);
    if (!mounted) return;
    if (grund != null) {
      _melde(grund, fehler: true);
    } else {
      _melde('Mitschrift läuft jetzt auf ${mitschriftSpracheName(k)}.');
    }
  }

  /// Holt das Offline-Sprachmodell auf das Gerät.
  ///
  /// ⚠️ Mit ausdrücklicher Frage vorher. Es sind 46 MB, und sie gehen über die
  /// Mobilfunkleitung des Vereins — das löst man nicht nebenbei aus, weil man
  /// einen Knopf gedrückt hat, der „Mitschrift" heisst.
  Future<void> _modellHolen() async {
    final angaben = await ApiService().sprachmodellAngaben('de');
    if (!mounted) return;
    final mb = ((angaben['groesse'] as num?)?.toInt() ?? 0) / 1048576;
    final los = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sprachmodell holen'),
        content: Text(
          'Für die Mitschrift braucht das Tablet ein deutsches Sprachmodell. '
          'Es wird einmal geholt und bleibt dann auf dem Gerät.\n\n'
          '${mb < 1 ? 'Grösse unbekannt' : '${mb.toStringAsFixed(0)} MB'} — '
          'am besten im WLAN.\n\n'
          'Danach läuft die Erkennung vollständig auf dem Tablet: kein Ton und '
          'kein Text verlassen das Gerät.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Später')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Jetzt holen')),
        ],
      ),
    );
    if (los != true || !mounted) return;
    _melde('Sprachmodell wird geholt …');
    final fehler = await UntertitelModell().holen();
    if (!mounted) return;
    _melde(fehler ?? 'Sprachmodell ist da — Mitschrift kann starten.',
        fehler: fehler != null);
  }

  /// Die Mitschrift selbst. Gross, weil sie zum Lesen da ist.
  Widget _untertitelFeld() {
    return ValueListenableBuilder<bool>(
      valueListenable: UntertitelService().aktiv,
      builder: (ctx, an, __) {
        if (!an) return const SizedBox.shrink();
        return ValueListenableBuilder<String>(
          valueListenable: UntertitelService().text,
          builder: (ctx, text, __) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: F.h(Colors.blueGrey, 900),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.closed_caption, size: 15, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text('Mitschrift — wird nicht gespeichert',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                ]),
                const SizedBox(height: 6),
                Text(
                  text.isEmpty ? '…' : text,
                  // ⚠️ Gross und mit Luft zwischen den Zeilen: das hier liest
                  // jemand, der schlecht hört, WÄHREND er spricht — nebenbei,
                  // aus einem Meter Abstand.
                  style: const TextStyle(
                      fontSize: 19, height: 1.45, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Gibt das laufende Gespräch an jemand anderen weiter.
  ///
  /// ⚠️ ÜBER DIE ANLAGE, NICHT ÜBER SIP. `sip_ua` kann zwar `Call.refer()`,
  /// aber nur BLIND — und sein `EventReferFailed`-Zweig ist leer: eine von der
  /// Gegenstelle abgelehnte Übergabe sagt dort gar nichts, der Vorsitzer hielte
  /// sie für geglückt und legte auf. Über `POST /calls/{id}/transfer` kommt ein
  /// HTTP-Status zurück, den man hinschreiben kann — und es gibt die Übergabe
  /// MIT ANSAGE, die der SIP-Weg überhaupt nicht kennt.
  ///
  /// ⚠️ Die Kennung kommt von der Anlage (`pbx-…`), nicht von `sip_ua`. Die
  /// beiden führen verschiedene Nummern; nur mit der der Anlage lässt sich
  /// übergeben.
  Future<void> _weiterverbinden() async {
    final laufend = await ApiService().sipgateAction({'action': 'laufende_gespraeche'});
    if (!mounted) return;
    final liste = (laufend['gespraeche'] as List?) ?? const [];
    if (laufend['success'] != true || liste.isEmpty) {
      _melde(
          liste.isEmpty && laufend['success'] == true
              ? 'Die Anlage meldet gerade kein laufendes Gespräch.'
              : '${laufend['message'] ?? 'Laufende Gespräche nicht abrufbar'}',
          fehler: true);
      return;
    }
    final callId = '${(liste.first as Map)['call_id'] ?? ''}';
    if (callId.isEmpty) {
      _melde('Die Anlage nennt keine Gesprächskennung.', fehler: true);
      return;
    }

    final feld = TextEditingController();
    var mitAnsage = true;
    final los = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setzen) => AlertDialog(
          title: const Text('Weiterverbinden'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: feld,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Zielrufnummer',
                hintText: '+49 731 1234567',
              ),
            ),
            const SizedBox(height: 12),
            // ⚠️ Mit Ansage ist die Voreinstellung, und das ist eine
            // Entscheidung: bei der blinden Übergabe ist der Anrufer verloren,
            // wenn drüben niemand abnimmt. Wer das will, muss es wählen.
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.record_voice_over),
                    label: Text('Mit Ansage')),
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.fast_forward),
                    label: Text('Blind')),
              ],
              selected: {mitAnsage},
              onSelectionChanged: (v) => setzen(() => mitAnsage = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              mitAnsage
                  ? 'Erst wird das Ziel angerufen; zusammengeschaltet wird, '
                      'nachdem dort jemand abgenommen hat.'
                  : 'Sofort weg. Nimmt dort niemand ab, ist der Anruf verloren.',
              style: const TextStyle(fontSize: 12),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Verbinden')),
          ],
        ),
      ),
    );
    if (los != true || !mounted) return;

    final a = await ApiService().sipgateAction({
      'action': 'weiterverbinden',
      'call_id': callId,
      'nummer': feld.text.trim(),
      'mit_ansage': mitAnsage,
    });
    if (!mounted) return;
    if (a['success'] == true) {
      _melde(mitAnsage
          ? 'Das Ziel wird angerufen — zusammengeschaltet wird nach dem Abheben.'
          : 'Übergeben.');
    } else {
      _melde('${a['message'] ?? 'Weiterverbinden fehlgeschlagen'}', fehler: true);
    }
  }

  Widget _waehlfeld(bool schmal) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nummer,
                    keyboardType: TextInputType.phone,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      hintText: '0711 123456',
                      border: const OutlineInputBorder(),
                      suffixIcon: _nummer.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.backspace_outlined),
                              onPressed: () => setState(() {
                                final t = _nummer.text;
                                if (t.isNotEmpty) _nummer.text = t.substring(0, t.length - 1);
                              }),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _anrufen(),
                  ),
                ),
                const SizedBox(width: 8),
                // Neben dem Feld, nicht darunter: wer eine Nummer sucht, sucht
                // sie, BEVOR er tippt.
                IconButton.filledTonal(
                  icon: const Icon(Icons.contacts_outlined),
                  tooltip: 'Kontakte',
                  onPressed: _kontakteOeffnen,
                ),
              ],
            ),
            if (_dienst.hatGespraech) ...[
              const SizedBox(height: 12),
              _tastenzweck(),
            ],
            const SizedBox(height: 14),
            SipgateWaehltastatur(schmal: schmal, beiTaste: _tasteGedrueckt),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: Icon(_dienst.kannHinzuwaehlen ? Icons.group_add : Icons.call),
                label: Text(() {
                  final wohin = _nummer.text.isEmpty
                      ? ''
                      : ': ${SipgateService.normalisieren(_nummer.text) ?? _nummer.text}';
                  return _dienst.kannHinzuwaehlen ? 'Hinzuwählen$wohin' : 'Anrufen$wohin';
                }()),
                // Ein zweiter Anruf ist erlaubt, sobald der erste verbunden ist
                // — das ist der Weg zur Dreierkonferenz. Ein dritter nicht.
                onPressed: _nummer.text.isEmpty ||
                        (_dienst.hatGespraech && !_dienst.kannHinzuwaehlen)
                    ? null
                    : _anrufen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Was eine gedrückte Taste bewirkt — die einzige Stelle, die das entscheidet.
  void _tasteGedrueckt(String zeichen) {
    if (_toeneModus) {
      // Im laufenden Gespräch ist eine Taste ein Ton, keine Eingabe — sonst
      // könnte man kein Sprachmenü bedienen („für Leistungen die 1").
      //
      // ⚠️ Nur was wirklich hinausging, erscheint auch in der Zeile. Vorher
      // stand dort jeder Tastendruck, auch ein abgelehnter — und man hätte im
      // Sprachmenü weitergedrückt, statt den Grund zu lesen.
      final grund = _dienst.dtmf(zeichen);
      if (grund != null) {
        _melde(grund, fehler: true);
        return;
      }
      setState(() => _gesendeteToene += zeichen);
    } else {
      setState(() => _nummer.text += zeichen);
    }
  }

  /// Umschalter zwischen Tastentönen und Wählen — nur während eines Gesprächs.
  ///
  /// ⚠️ Ohne ihn wäre eine Taste zweideutig: in einem Sprachmenü soll sie einen
  /// Ton schicken, beim Hinzuwählen zur Konferenz soll sie eine Nummer bilden.
  /// Rät die App falsch, hört der Gesprächspartner ein Piepen mitten im Satz —
  /// oder das Menü reagiert nicht und man hält das für eine Störung.
  Widget _tastenzweck() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(
              value: true,
              icon: Icon(Icons.dialpad, size: 16),
              label: Text('Tastentöne', style: TextStyle(fontSize: 12)),
            ),
            ButtonSegment(
              value: false,
              icon: Icon(Icons.group_add, size: 16),
              label: Text('Zweite Nummer', style: TextStyle(fontSize: 12)),
            ),
          ],
          selected: {_toeneModus},
          onSelectionChanged: (s) => setState(() => _toeneModus = s.first),
        ),
        if (_toeneModus && _gesendeteToene.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Gesendet: ${_gesendeteToene.split('').join(' ')}',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)),
            ),
          ),
      ],
    );
  }

  /// ⚠️ Steht bewusst im Bildschirm, nicht nur im Code: wer hier telefoniert,
  /// muss wissen, dass 110/112 diesen Weg nicht nehmen.
  Widget _hinweisNotruf() => _warnzeile(
        'Notrufe (110, 112) gehen NICHT über sipgate — dafür fehlt im Konto ein '
        'verifizierter Notrufstandort. Im Notfall das Telefon mit SIM-Karte '
        'benutzen. 115 und 116117 sind keine Notrufe und funktionieren hier.',
        Colors.red,
      );

  Widget _warnzeile(String text, MaterialColor farbe) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(farbe, 50),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: F.h(farbe, 200)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: F.h(farbe, 700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, color: F.h(farbe, 900))),
            ),
          ],
        ),
      );

  Widget _verlaufsfeld() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: F.h(Colors.grey, 700)),
                const SizedBox(width: 8),
                const Text('Verlauf', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Eigenes Protokoll — enthält auch die Anrufe, die nicht zustande '
              'kamen, und warum. Die fehlen im Verlauf von sipgate.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
            ),
            const SizedBox(height: 4),
            // ⚠️ DIESER SATZ IST KEINE HÖFLICHKEIT, SONDERN DIE GRENZE DES
            // ABZEICHENS. Beim Fax holt ein Cron die Liste bei sipgate ab;
            // für Anrufe geht das nicht — am 23.08.2026 gemessen liefert
            // `GET /history?types=CALL` auf diesem Konto null Positionen
            // (auf neo ist der Gesprächsverlauf zu den Channel Events
            // gewandert). Gezählt wird also, was DIESES Gerät mitbekommen
            // hat. Ein Abzeichen, das sich für vollständig ausgibt, wäre
            // schlimmer als eines, das seine Grenze nennt.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 13, color: F.h(Colors.grey, 600)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Aufgezeichnet wird, was dieses Gerät mitbekommen hat. Ein '
                    'Anruf, der eintrifft während die App hier nicht angemeldet '
                    'ist, steht nicht in dieser Liste — sipgate liefert den '
                    'Gesprächsverlauf nicht über die Schnittstelle.',
                    style: TextStyle(
                        fontSize: 11,
                        color: F.h(Colors.grey, 600),
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _gueteUeberblick(),
            if (_ladeVerlauf)
              const Center(child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ))
            else if (_verlauf.isEmpty)
              Text('Noch kein Gespräch.',
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))
            else
              for (final a in _verlauf) _verlaufszeile(a),
          ],
        ),
      ),
    );
  }

  /// Hakt einen verpassten Anruf einzeln ab.
  ///
  /// ⚠️ EINZELN, nicht „alles gelesen beim Öffnen" wie beim Fax. „Ich habe die
  /// Liste gesehen" heisst nicht „ich habe alle zurückgerufen" — ein
  /// Abzeichen, das beim Hinsehen erlischt, verliert genau die Aufgabe, für
  /// die es da ist.
  Future<void> _abhaken(Map<String, dynamic> a) async {
    final id = a['id'];
    if (id == null) return;
    // Sofort im Bild, damit der Tipp nicht ins Leere zu gehen scheint; die
    // Antwort korrigiert die Zahl gleich darauf.
    setState(() => a['gesehen'] = true);
    try {
      final r = await ApiService()
          .sipgateAction({'action': 'anruf_gesehen', 'ids': [id]});
      if (r['success'] == true) {
        AnrufBadgeService().uebernehmen(r);
      } else if (mounted) {
        setState(() => a['gesehen'] = false);
        _melde('Konnte nicht abgehakt werden: ${r['message'] ?? ''}', fehler: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => a['gesehen'] = false);
        _melde('Konnte nicht abgehakt werden: $e', fehler: true);
      }
    }
  }

  /// Ruft die Nummer aus dem Verlauf zurück — und zwar sofort.
  ///
  /// ⚠️ VORHER FÜLLTE DIESER KNOPF NUR DAS EINGABEFELD.
  /// Man musste danach unter der Tastatur ein zweites Mal auf „Anrufen"
  /// drücken. Auf dem Telefon steht die Tastatur ausserdem weit unterhalb des
  /// Verlaufs — der Knopf sah aus, als täte er nichts.
  ///
  /// ⚠️ Auf dem RECHNER tat er tatsächlich nichts. Der Verlauf wird dort
  /// angezeigt, das Wählfeld aber nicht (`if (_dienst.plattformFaehig)`) —
  /// der Knopf schrieb also in ein Feld, das gar nicht auf dem Schirm steht.
  /// Ein Druck, sichtbar keine Wirkung, kein Fehler.
  ///
  /// ⚠️ Und er hakte den verpassten Anruf als erledigt ab, OHNE dass jemand
  /// angerufen hatte. Wer danach nicht auch noch „Anrufen" drückte, hatte den
  /// Anruf aus dem Abzeichen genommen und nie zurückgerufen — genau das, was
  /// das Abzeichen verhindern soll. Abgehakt wird deshalb erst, wenn die Wahl
  /// wirklich angelaufen ist.
  ///
  /// Zwei Wege, weil es zwei Geräte sind: auf dem Tablet telefoniert die App
  /// selbst über sipgate (derselbe Weg wie der Knopf unter der Tastatur), vom
  /// Rechner aus geht ein Fernwahl-Auftrag an das Tablet — dasselbe, was ein
  /// Klick auf eine Rufnummer in einer Behördenkarte tut.
  Future<void> _zurueckrufen(Map<String, dynamic> a) async {
    final nummer = '${a['nummer'] ?? ''}';
    if (nummer.isEmpty) return;
    final name = '${a['bezeichnung'] ?? ''}';
    final offen = sipgateVerpasstOffen(a);

    if (!_dienst.plattformFaehig) {
      await PhoneCallService.call(context, nummer,
          label: name.isEmpty ? null : name);
      if (offen) await _abhaken(a);
      return;
    }

    final meldung =
        await _dienst.anrufen(nummer, bezeichnung: name.isEmpty ? null : name);
    if (!mounted) return;
    if (meldung != null) {
      // Die Nummer nicht verlieren: sie steht jetzt im Feld, damit man es
      // nach dem Grund („Erst muss das laufende Gespräch verbunden sein")
      // noch einmal versuchen kann, ohne sie zu suchen.
      setState(() => _nummer.text = nummer);
      _melde(meldung, fehler: true);
      return;
    }
    if (offen) await _abhaken(a);
  }

  /// Eine Zeile mit der gespeicherten Güte eines beendeten Gesprächs.
  Widget _gueteZeile(Map<String, dynamic> a) {
    final mos = (a['guete_mos'] as num).toDouble();
    final min = a['guete_min'] is num ? (a['guete_min'] as num).toDouble() : null;
    final d = a['guete'] is Map ? Map<String, dynamic>.from(a['guete'] as Map) : null;
    final stufe = gueteStufeAusMos(mos);
    final teile = <String>[
      'MOS ${mos.toStringAsFixed(2)}',
      // ⚠️ Der schlechteste Wert gehört DANEBEN, nicht anstelle des Medians.
      // Ein Gespräch mit einem einzigen Aussetzer ist etwas anderes als eines,
      // das durchgehend schlecht war — und nur beide Zahlen zusammen
      // unterscheiden das.
      if (min != null && min < mos - 0.3) 'zeitweise ${min.toStringAsFixed(2)}',
      if (d?['anteil_schlecht'] is num && (d!['anteil_schlecht'] as num) > 0)
        '${(d['anteil_schlecht'] as num).toStringAsFixed(0)} % schlecht',
      if (d?['verlust_max'] is num && (d!['verlust_max'] as num) > 0)
        'Verlust bis ${(d['verlust_max'] as num).toStringAsFixed(1)} %',
      if (d?['weg'] == 'relay') 'über TURN',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Tooltip(
        message: 'Güte der Strecke bis sipgate — nicht des ganzen Gesprächs. '
            'Geschätzt nach einem für WebRTC abgewandelten E-Modell.',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.graphic_eq, size: 12, color: gueteFarbe(stufe)),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '${gueteStufeText(stufe)} · ${teile.join(' · ')}',
              style: TextStyle(fontSize: 10, color: gueteFarbe(stufe)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _verlaufszeile(Map<String, dynamic> a) {
    final ein = a['richtung'] == 'ein';
    final status = '${a['status']}';
    // Dieselbe Regel wie beim Zurückrufen — einmal geschrieben, siehe
    // [sipgateVerpasstOffen].
    final offen = sipgateVerpasstOffen(a);
    final (farbe, symbol) = switch (status) {
      'beendet' => (Colors.green.shade600, ein ? Icons.call_received : Icons.call_made),
      'verbunden' => (Colors.green.shade600, Icons.call),
      'verpasst' => (Colors.orange.shade700, Icons.call_missed),
      'abgelehnt' => (Colors.grey.shade600, Icons.call_end),
      // ⚠️ Grau und ein Fragezeichen, NICHT rot: `unklar` heisst „das Ende
      // wurde nie protokolliert", nicht „der Anruf ist gescheitert". Der
      // Server vergibt es, wenn eine Zeile zwoelf Stunden lang unfertig
      // liegenblieb — meistens, weil Android die App waehrend des Gespraechs
      // abgeraeumt hat. Rot wuerde behaupten, etwas sei kaputt gewesen; das
      // Warum steht ohnehin daneben, es kommt im Feld `fehler` mit.
      'unklar' => (Colors.grey.shade600, Icons.help_outline),
      'fehler' => (Colors.red.shade700, Icons.error_outline),
      _ => (Colors.blue.shade600, Icons.call_made),
    };
    final dauer = (a['dauer_s'] as int?) ?? 0;
    final fehler = '${a['fehler'] ?? ''}';
    final name = '${a['bezeichnung'] ?? ''}';
    final nummer = '${a['nummer'] ?? ''}';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      tileColor: offen ? F.h(Colors.orange, 50) : null,
      leading: Icon(symbol, size: 20, color: farbe),
      // Nur wenn der Name wirklich einer ist. sipgate schickt bei Anrufen aus
      // dem Telefonnetz die Nummer AUCH als Anzeigenamen — sonst stünde hier
      // „073180159736 · 0731 80159736".
      title: Text(
        SipgateService.istEchterName(name, nummer)
            ? '$name · ${SipgateService.anruferAnzeige(nummer)}'
            : SipgateService.anruferAnzeige(nummer),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              '${a['begonnen_am'] ?? ''}',
              status,
              if (dauer > 0) SipgateService.dauerLesbar(dauer),
              if (fehler.isNotEmpty) fehler,
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
          ),
          // Art, Ort und — bei Mobilnummern — das zugeteilte Netz. Der Server
          // rechnet es aus den Verzeichnissen der Bundesnetzagentur; siehe
          // [NetzPastille], warum das Netz nur „Block" heisst und nicht
          // „Anbieter".
          // Die am Gesprächsende festgehaltene Güte. ⚠️ `null` heisst „nicht
          // gemessen" (alte Zeilen, oder das Gespräch endete vor der zweiten
          // Abfrage) — dann steht hier nichts, statt eine Null zu behaupten.
          if (a['guete_mos'] is num) _gueteZeile(a),
          if (a['einordnung'] is Map)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: NetzPastille(
                einordnung: Map<String, dynamic>.from(a['einordnung'] as Map),
                kompakt: true,
              ),
            ),
        ],
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (offen)
          IconButton(
            icon: const Icon(Icons.done, size: 18),
            tooltip: 'Erledigt — aus dem Abzeichen nehmen',
            visualDensity: VisualDensity.compact,
            onPressed: () => _abhaken(a),
          ),
        // ⚠️ Nur bei einem Anrufer OHNE Namen. Wer schon in den Stammdaten
        // steht, gehört nicht ein zweites Mal in eine eigene Liste — genau
        // diese Doppelpflege ist bei `arzt_telefon` schiefgegangen, wo
        // dieselbe Praxis dreissigmal in verschiedenen Ständen liegt.
        if (nummer.isNotEmpty &&
            !SipgateService.anruferAnonym(nummer) &&
            !SipgateService.istEchterName(name, nummer))
          IconButton(
            icon: const Icon(Icons.person_add_alt, size: 18),
            tooltip: 'Als Kontakt speichern',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SipgateKontakteScreen(
                      zurueckgeben: false, neueNummer: nummer),
                ),
              );
              // Der neue Name soll sofort im Verlauf stehen, nicht erst beim
              // nächsten Öffnen des Bildschirms.
              if (mounted) await _verlaufLaden();
            },
          ),
        IconButton(
          icon: const Icon(Icons.call, size: 18),
          tooltip: 'Zurückrufen',
          visualDensity: VisualDensity.compact,
          onPressed: nummer.isEmpty ? null : () => _zurueckrufen(a),
        ),
      ]),
    );
  }

  Widget _geraetefeld() {
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.sim_card_outlined, color: F.h(Colors.grey, 700)),
        title: const Text('VoIP-Telefone des Kontos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('${_geraete.length} hinterlegt',
            style: const TextStyle(fontSize: 11)),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Das SIP-Passwort bleibt auf dem Server. Die App bekommt nur HA1 '
              '— damit kann man telefonieren, aber nicht ins sipgate-Konto.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
            ),
          ),
          const SizedBox(height: 10),
          for (final g in _geraete) _geraetezeile(g),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('VoIP-Telefon hinzufügen'),
              onPressed: () => _geraetDialog(null),
            ),
          ),
          const Divider(height: 24),
          _verzeichnisZeile(),
        ],
      ),
    );
  }

  /// Was die Rückwärtssuche kennt.
  ///
  /// ⚠️ Es gibt hier nichts zu bauen und nichts aufzufrischen: gesucht wird
  /// live in den Stammtabellen, gemessen 16 ms. Ein Arzt, der vor fünf Minuten
  /// eingetragen wurde, wird sofort gefunden — eine nächtlich gebaute Liste
  /// hätte ihn bis zum nächsten Morgen nicht gekannt, ohne dass irgendwo etwas
  /// darauf hingewiesen hätte.
  Widget _verzeichnisZeile() => Row(
        children: [
          Icon(Icons.contact_phone_outlined, size: 18, color: F.h(Colors.grey, 700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _verzeichnis == null
                  ? 'Anrufer werden in den eigenen Daten gesucht …'
                  : 'Anrufer-Erkennung: ${_verzeichnis!['nummern']} Rufnummern '
                      'aus ${_verzeichnis!['tabellen']} Tabellen — live gesucht, '
                      'immer aktuell',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 800)),
            ),
          ),
        ],
      );

  Widget _geraetezeile(Map<String, dynamic> g) {
    final aktiv = g['aktiv'] == true;
    final hatPass = g['pass_gesetzt'] == true;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        hatPass && aktiv ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
        color: hatPass && aktiv ? F.h(Colors.green, 600) : F.h(Colors.grey, 400),
      ),
      title: Text(
        '${g['bezeichnung']?.toString().isNotEmpty == true ? g['bezeichnung'] : g['sip_id']}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        [
          '${g['sip_id']}',
          '${g['plattform']}',
          if (!hatPass) 'kein Passwort',
          if (!aktiv) 'inaktiv',
          if (g['belegt'] == true) 'einem Gerät zugeordnet',
        ].join(' · '),
        style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (wahl) async {
          switch (wahl) {
            case 'edit':
              _geraetDialog(g);
              break;
            case 'pass':
              await _passZeigen(g);
              break;
            case 'loesen':
              await ApiService().sipgateAction(
                  {'action': 'geraet_loesen', 'id': g['id']});
              await _geraeteLaden();
              _melde('Zuordnung gelöst — ein anderes Gerät kann sie nun belegen.');
              break;
            case 'del':
              await ApiService().sipgateAction(
                  {'action': 'delete_geraet', 'id': g['id']});
              await _geraeteLaden();
              break;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
          const PopupMenuItem(value: 'pass', child: Text('SIP-Passwort zeigen')),
          if (g['belegt'] == true)
            const PopupMenuItem(value: 'loesen', child: Text('Gerätezuordnung lösen')),
          const PopupMenuItem(value: 'del', child: Text('Löschen')),
        ],
      ),
    );
  }

  /// Das Klartextpasswort — gebraucht, um ein Tischtelefon oder ein fremdes
  /// Softphone von Hand einzurichten. Ausdrücklich abgefragt, nicht beiläufig
  /// mitgeladen.
  Future<void> _passZeigen(Map<String, dynamic> g) async {
    final a = await ApiService().sipgateAction({'action': 'reveal_pass', 'id': g['id']});
    if (!mounted) return;
    final d = a;
    if (a['success'] != true) {
      _melde('${a['message'] ?? 'Nicht abrufbar'}', fehler: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${d['sip_id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _feldZeile(ctx, 'SIP-ID', '${d['sip_id']}'),
            _feldZeile(ctx, 'Passwort', '${d['passwort']}'),
            _feldZeile(ctx, 'Domain / Realm', '${d['realm']}'),
            _feldZeile(ctx, 'Proxy (TLS)', '${d['proxy_tls']}'),
            _feldZeile(ctx, 'Proxy (WSS)', '${d['proxy_wss']}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  Widget _feldZeile(BuildContext ctx, String name, String wert) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 118,
              child: Text(name, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500))),
            ),
            Expanded(
              child: SelectableText(wert, style: const TextStyle(fontSize: 13)),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Kopieren',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: wert));
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$name kopiert')));
              },
            ),
          ],
        ),
      );

  Future<void> _geraetDialog(Map<String, dynamic>? vorhanden) async {
    final sipId = TextEditingController(text: '${vorhanden?['sip_id'] ?? ''}');
    final name = TextEditingController(text: '${vorhanden?['bezeichnung'] ?? ''}');
    final pass = TextEditingController();
    final absender = TextEditingController(text: '${vorhanden?['absendernummer'] ?? ''}');
    final notiz = TextEditingController(text: '${vorhanden?['notiz'] ?? ''}');
    var plattform = '${vorhanden?['plattform'] ?? 'alle'}';
    var notrufstandort = '${vorhanden?['notrufstandort'] ?? 'unbekannt'}';
    var aktiv = vorhanden == null ? true : vorhanden['aktiv'] == true;

    // ⚠️ Keine feste Dialogbreite: auf Telefonbreite (411–448 dp) quetscht sich
    // ein 600-dp-Dialog stillschweigend zusammen statt überzulaufen.
    final maxBreite = ResponsiveLayout.istTelefon(context)
        ? MediaQuery.of(context).size.width - 32
        : 520.0;

    final gespeichert = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setzen) => AlertDialog(
          title: Text(vorhanden == null ? 'VoIP-Telefon hinzufügen' : 'VoIP-Telefon bearbeiten'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBreite),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sipId,
                    decoration: const InputDecoration(
                      labelText: 'SIP-ID',
                      hintText: '1234567e0',
                      helperText: 'Steht im sipgate-Konto beim VoIP-Telefon',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Bezeichnung'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'SIP-Passwort',
                      helperText: vorhanden == null
                          ? 'Wird verschlüsselt gespeichert und verlässt den Server nicht'
                          : 'Leer lassen = unverändert',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: absender,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Absendernummer (was der Angerufene sieht)',
                      hintText: '0731 80159736',
                      helperText: 'Leer = unterdrückt. Wird bei sipgate im Channel '
                          'gesetzt; hier nur mitgeschrieben, damit man es beim '
                          'Wählen sieht.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: notrufstandort,
                    decoration: const InputDecoration(labelText: 'Notrufstandort im sipgate-Konto'),
                    items: const [
                      DropdownMenuItem(value: 'unbekannt', child: Text('unbekannt')),
                      DropdownMenuItem(value: 'gesetzt', child: Text('gesetzt')),
                      DropdownMenuItem(value: 'nicht_gesetzt', child: Text('nicht gesetzt')),
                    ],
                    onChanged: (v) => setzen(() => notrufstandort = v ?? 'unbekannt'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: plattform,
                    decoration: const InputDecoration(labelText: 'Für welches Gerät'),
                    items: const [
                      DropdownMenuItem(value: 'alle', child: Text('Beliebig (Pool)')),
                      DropdownMenuItem(value: 'linux', child: Text('Linux')),
                      DropdownMenuItem(value: 'android', child: Text('Android')),
                      DropdownMenuItem(value: 'macos', child: Text('macOS')),
                      DropdownMenuItem(value: 'windows', child: Text('Windows')),
                      DropdownMenuItem(value: 'ios', child: Text('iOS')),
                    ],
                    onChanged: (v) => setzen(() => plattform = v ?? 'alle'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notiz,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notiz'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: aktiv,
                    onChanged: (v) => setzen(() => aktiv = v),
                    title: const Text('Aktiv'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    if (gespeichert != true) return;
    final a = await ApiService().sipgateAction({
      'action': 'save_geraet',
      if (vorhanden != null) 'id': vorhanden['id'],
      'sip_id': sipId.text.trim(),
      'bezeichnung': name.text.trim(),
      'absendernummer': absender.text.trim(),
      'notrufstandort': notrufstandort,
      'passwort': pass.text,
      'plattform': plattform,
      'notiz': notiz.text.trim(),
      'aktiv': aktiv,
    });
    _melde('${a['message'] ?? (a['success'] == true ? 'Gespeichert' : 'Fehler')}',
        fehler: a['success'] != true);
    await _geraeteLaden();
  }

  /// Ob die Bluetooth-Warnung gezeigt werden muss.
  ///
  /// `unbekannt` zählt NICHT als fehlend: das ist der Zustand vor der ersten
  /// Abfrage und auf Nicht-Android. Eine Warnung, die immer da steht, wird
  /// nicht gelesen.
  static bool _btNoetig(SipgateZustand z) =>
      z.bluetoothRecht == 'abgelehnt' ||
      z.bluetoothRecht == 'dauerhaft_abgelehnt' ||
      z.bluetoothRecht == 'kein_dialog';

  /// `073180159736` -> `0731 80159736`.
  ///
  /// Nur eine Lesehilfe, keine Rufnummernlogik: gewählt wird immer der
  /// unformatierte Wert, damit hier nie ein Leerzeichen in eine Nummer gerät.
  static String _nummerLesbar(String roh) {
    final n = roh.trim();
    if (n.startsWith('+')) return n;
    // Ortsvorwahlen in Deutschland sind 3–5 Stellen inkl. der führenden Null.
    // 0731 (Ulm) ist vierstellig; bei allem, was nicht passt, bleibt die Nummer
    // wie sie ist — falsch zu trennen ist schlimmer als nicht zu trennen.
    if (n.length >= 8 && n.startsWith('0')) {
      return '${n.substring(0, 4)} ${n.substring(4)}';
    }
    return n;
  }

}
