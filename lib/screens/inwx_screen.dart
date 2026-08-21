import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../widgets/eastern.dart';
import '../widgets/korrespondenz_message_dialog.dart';
import '../widgets/phone_link.dart';
import '../utils/app_farben.dart';

/// Der Leistungskatalog von inwx.de, so wie er dort heißt.
/// Der Schlüssel muss mit INWX_KATEGORIEN in api/vereinverwaltung/inwx_lib.php
/// übereinstimmen — der Server verwirft alles andere und legt es unter
/// „Sonstige" ab.
class InwxKategorie {
  final String key;
  final String label;
  final String beschreibung;
  final IconData icon;
  final String? url;
  const InwxKategorie(this.key, this.label, this.beschreibung, this.icon, [this.url]);
}

const List<InwxKategorie> kInwxKategorien = [
  InwxKategorie('domain', 'Domain', 'Registrierung und Verwaltung einer Domain',
      Icons.language, 'https://www.inwx.de/de/domain/pricelist'),
  InwxKategorie('transfer', 'Transfer Service', 'Domainumzug zu INWX inkl. Begleitung',
      Icons.swap_horiz, 'https://www.inwx.de/de/domain/transfer-service'),
  InwxKategorie('dns', 'DNS / Nameserver', 'Nameserver ns.inwx.de, ns2.inwx.de, ns3.inwx.eu',
      Icons.dns, 'https://www.inwx.de/de/nameserver'),
  InwxKategorie('dyndns', 'Dynamic DNS', 'Fester Hostname für eine wechselnde IP',
      Icons.sync_alt, 'https://www.inwx.de/de/offer/dyndns'),
  InwxKategorie('ssl', 'SSL-Zertifikat', 'TLS-Zertifikate für Domains und Subdomains',
      Icons.verified_user, 'https://www.inwx.de/de/ssl'),
  InwxKategorie('hosting', 'Shared Hosting', 'Webspace-Paket',
      Icons.storage, 'https://www.inwx.de/de/hosting/shared'),
  InwxKategorie('email', 'E-Mail Hosting', 'Postfächer und Weiterleitungen',
      Icons.alternate_email, 'https://www.inwx.de/de/hosting/email'),
  InwxKategorie('whoisprivacy', 'Whois Privacy', 'Inhaberdaten aus der öffentlichen Whois-Abfrage nehmen',
      Icons.visibility_off, 'https://www.inwx.de/de/offer/whoisprivacy'),
  InwxKategorie('registrylock', 'Registry Lock', 'Sperre gegen Transfer und Löschung direkt bei der Registry',
      Icons.lock, 'https://www.inwx.de/de/offer/registrylock'),
  InwxKategorie('trustee', 'Trustee / Local Presence', 'Treuhänder für Endungen mit Wohnsitzpflicht',
      Icons.handshake, 'https://www.inwx.de/de/offer/localpresence'),
  InwxKategorie('api', 'API-Zugang (DomRobot)', 'Programmgesteuerte Kontoverwaltung',
      Icons.terminal, 'https://account.inwx.de/de/help/apidoc'),
  InwxKategorie('sonstige', 'Sonstige Leistung', 'Alles, was oben nicht passt',
      Icons.more_horiz, null),
];

/// Unbekannter Schlüssel landet bei „Sonstige" statt zu werfen — der Server
/// darf eine Kategorie hinzubekommen, ohne dass ältere Clients grau werden.
InwxKategorie inwxKategorieFinden(String? key) => kInwxKategorien.firstWhere(
      (k) => k.key == key,
      orElse: () => kInwxKategorien.last,
    );

/// ⚠️ PHP kennt nur einen Array-Typ: eine leere Liste kodiert `json_encode`
/// als `[]`, dieselbe Struktur mit String-Schlüsseln als Objekt. Ein `as Map`
/// auf einer Liste wirft — genau daran blieb der Speedtest-Bildschirm am
/// 05.08.2026 in der Produktion grau hängen. Deshalb lesen diese Helfer
/// beide Formen und geben im Zweifel Leeres zurück, nie eine Ausnahme.
List<Map<String, dynamic>> inwxListe(dynamic roh) {
  if (roh is! List) return const [];
  return roh.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Map<String, dynamic>? inwxAlsMap(dynamic roh) {
  if (roh is Map) return Map<String, dynamic>.from(roh);
  return null; // eine Liste (auch die leere) ist hier keine Map
}

/// Für Listen von blanken Zeichenketten (Zonennamen, Nameserver).
List<String> inwxTextListe(dynamic roh) {
  if (roh is! List) return const [];
  return roh.where((e) => e != null).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
}

/// Die dringlichste noch laufende Leistung. Gekündigtes und Abgelaufenes
/// zählt nicht — sonst warnte der Bildschirm ewig wegen einer Domain,
/// die absichtlich weg ist.
int? inwxKritischsteFrist(List<Map<String, dynamic>> leistungen) {
  int? min;
  for (final l in leistungen) {
    if (l['status'] == 'gekuendigt' || l['status'] == 'abgelaufen') continue;
    final t = l['tage_bis_ablauf'];
    if (t is! int) continue;
    if (min == null || t < min) min = t;
  }
  return min;
}

/// 'YYYY-MM-DD' → 'DD.MM.YYYY'; alles andere bleibt, wie es kam.
String inwxDatumDeutsch(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
}

/// Die von INWX erlaubten Record-Typen (Datentyp `recordType` der API-Doku).
/// Muss mit INWX_RECORD_TYPEN in api/vereinverwaltung/inwx_lib.php
/// übereinstimmen.
const List<String> kInwxRecordTypen = [
  'A', 'AAAA', 'AFSDB', 'ALIAS', 'CAA', 'CERT', 'CNAME', 'HINFO', 'HTTPS',
  'IPSECKEY', 'LOC', 'MX', 'NAPTR', 'NS', 'OPENPGPKEY', 'PTR', 'RP', 'SMIMEA',
  'SOA', 'SRV', 'SSHFP', 'SVCB', 'TLSA', 'TXT', 'URI', 'URL',
];

/// `renewalMode` von INWX. AUTODELETE und AUTOEXPIRE geben die Domain am
/// Ablaufdatum auf — die Beschriftung sagt das, statt das Kürzel zu zeigen.
const Map<String, String> kInwxRenewalModi = {
  'AUTORENEW': 'Automatisch verlängern',
  'AUTOEXPIRE': 'Auslaufen lassen',
  'AUTODELETE': 'Am Ablauftag löschen',
};

/// Beschriftungen für unser eigenes Änderungsprotokoll.
const Map<String, String> kInwxAktionLabel = {
  'dns_anlegen': 'DNS-Eintrag angelegt',
  'dns_aendern': 'DNS-Eintrag geändert',
  'dns_loeschen': 'DNS-Eintrag gelöscht',
  'domain_update': 'Domain-Einstellung',
  'kontakt_update': 'Inhaberdaten',
  'domain_renew': 'Verlängerung',
  'meldung_quittiert': 'Meldung quittiert',
  'domain_geloescht': 'Domain gelöscht',
  'domain_hold_an': 'Domain abgeschaltet',
  'domain_hold_aus': 'Domain wieder aktiv',
  'transfer_zugestimmt': 'Umzug freigegeben',
  'transfer_abgelehnt': 'Umzug abgelehnt',
  'domain_uebergeben': 'Domain übergeben',
  'inhaberwechsel': 'Inhaberwechsel',
  'authinfo_erzeugt': 'AuthInfo-Code erzeugt',
  'kontakt_geloescht': 'Kontakt gelöscht',
  'erstattung': 'Erstattung',
  'passwort_gewechselt': 'Kontopasswort gewechselt',
};

/// Ein Beispielwert im Eingabefeld erspart den Blick in die Doku.
String inwxWertBeispiel(String typ) {
  switch (typ) {
    case 'A':     return '203.0.113.7';
    case 'AAAA':  return '2001:db8::1';
    case 'CNAME': return 'ziel.example.org';
    case 'MX':    return 'mail.icd360s.de';
    case 'TXT':   return 'v=spf1 ip4:… -all';
    case 'CAA':   return '0 issue "letsencrypt.org"';
    case 'SRV':   return '0 5 443 ziel.example.org';
    case 'NS':    return 'ns.inwx.de';
    case 'TLSA':  return '3 1 1 <hex>';
    default:      return '';
  }
}

/// Spiegelt inwxRecordPruefen() aus api/vereinverwaltung/inwx_lib.php.
///
/// ⚠️ Bewusst doppelt: hier für die sofortige Rückmeldung im Dialog, auf dem
/// Server als verbindliche Kontrolle. Ändert sich eine Regel, müssen BEIDE
/// Stellen mit — der Test `inwx_antwort_test.dart` prüft dieselben Fälle,
/// die der Selbsttest auf dem Server prüft.
List<String> inwxRecordPruefen({
  required String typ,
  required String name,
  required String inhalt,
  required int ttl,
  required String zone,
  int prio = 0,
}) {
  final fehler = <String>[];
  final t = typ.toUpperCase().trim();
  final n = name.toLowerCase().trim();
  final z = zone.toLowerCase().trim();
  final w = inhalt.trim();

  if (!kInwxRecordTypen.contains(t)) return ['Unbekannter Eintragstyp „$t".'];
  if (t == 'SOA') {
    fehler.add('Der SOA-Eintrag wird von INWX selbst gepflegt und ist hier nicht änderbar.');
  }
  if (n.isEmpty) {
    fehler.add('Der Name fehlt.');
  } else if (n != z && !n.endsWith('.$z')) {
    fehler.add('Der Name muss auf „$z" enden.');
  }
  if (w.isEmpty) fehler.add('Der Wert fehlt.');
  if (ttl < 60 || ttl > 604800) fehler.add('TTL muss zwischen 60 und 604800 Sekunden liegen.');

  switch (t) {
    case 'A':
      if (InternetAddress.tryParse(w)?.type != InternetAddressType.IPv4) {
        fehler.add('A verlangt eine IPv4-Adresse (AAAA ist der Eintrag für IPv6).');
      }
      break;
    case 'AAAA':
      if (InternetAddress.tryParse(w)?.type != InternetAddressType.IPv6) {
        fehler.add('AAAA verlangt eine IPv6-Adresse (A ist der Eintrag für IPv4).');
      }
      break;
    case 'CNAME':
      // Ein CNAME auf der Hauptdomain verdrängt MX, TXT und NS — Post und
      // Delegierung wären sofort weg.
      if (n == z) {
        fehler.add('Ein CNAME auf der Hauptdomain ist nicht zulässig — er verdrängt MX, TXT und NS.');
      }
      break;
    case 'MX':
    case 'SRV':
      if (prio < 0 || prio > 65535) fehler.add('Priorität muss zwischen 0 und 65535 liegen.');
      break;
    case 'TXT':
      if (w.length > 4096) fehler.add('TXT-Wert ist zu lang.');
      break;
  }
  return fehler;
}

/// Tage bis zu einem ISO-Datum. Negativ heißt: schon vorbei.
int? inwxTageBis(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  final heute = DateTime.now();
  return DateTime(d.year, d.month, d.day)
      .difference(DateTime(heute.year, heute.month, heute.day))
      .inDays;
}

/// Wie viel der Laufzeit schon verbraucht ist, 0..1.
/// Ohne Anfangsdatum wird von einem Jahr ausgegangen — das ist bei Domains
/// die Regel, und ein grob richtiger Balken sagt mehr als gar keiner.
double inwxLaufzeitAnteil({String? von, String? bis}) {
  final rest = inwxTageBis(bis);
  if (rest == null) return 0;
  final start = von == null ? null : DateTime.tryParse(von);
  final ende = DateTime.tryParse(bis!);
  if (ende == null) return 0;
  final gesamt = start == null ? 365 : ende.difference(start).inDays;
  if (gesamt <= 0) return 1;
  return (1 - rest / gesamt).clamp(0.0, 1.0);
}

/// Rechnungen neueste zuerst.
///
/// ISO-Datumsangaben (`2025-08-31`) sortieren als Zeichenkette in derselben
/// Reihenfolge wie als Datum — deshalb ohne Umweg über `DateTime`, das bei
/// einem leeren Feld `null` liefert und die Sortierung werfen ließe. Eine
/// Rechnung ohne Datum landet hinten, statt die Reihenfolge zu sprengen.
List<Map<String, dynamic>> inwxRechnungenSortiert(List<Map<String, dynamic>> roh) {
  final liste = [...roh];
  liste.sort((a, b) {
    final da = a['datum']?.toString() ?? '';
    final db = b['datum']?.toString() ?? '';
    if (da.isEmpty && db.isEmpty) return 0;
    if (da.isEmpty) return 1;
    if (db.isEmpty) return -1;
    return db.compareTo(da);
  });
  return liste;
}

/// Summe eines Betragsfeldes über eine Liste.
/// Fehlende Beträge zählen als 0 — ein `null` in einer Zeile darf nicht die
/// ganze Summe zu `null` machen, sonst verschwindet auch das, was da ist.
double inwxSummeFeld(List<Map<String, dynamic>> liste, String feld) =>
    liste.fold<double>(0, (s, r) => s + ((r[feld] as num?)?.toDouble() ?? 0));

/// Vorgänge, die Geld gekostet haben und noch auf keiner Rechnung stehen.
///
/// ⚠️ Das ist die Antwort auf „ich habe verlängert, wo ist die Rechnung?".
/// Sie steht nicht in der Rechnungsliste, sondern im Protokoll: `domain.log`
/// führt zu jedem kostenpflichtigen Vorgang eine Rechnungsnummer mit — solange
/// die leer ist, hat INWX den Posten berechnet, aber noch keiner Rechnung
/// zugeordnet. Das ist INWX' eigene Auskunft, keine Rechnung von uns aus
/// Guthabenständen; die wäre nur so gut wie unser Modell ihrer Buchhaltung.
///
/// ⚠️ Der Preis im Protokoll ist **brutto**, nicht netto. Gemessen, nicht
/// angenommen: die Registrierung steht dort mit 5,97 — und genau 5,97 ist der
/// `afterTax`-Wert der zugehörigen Rechnung (netto wären 5,02). Wer ihn für
/// netto hält, schlägt noch einmal Umsatzsteuer drauf und behauptet eine
/// Forderung, die es nicht gibt.
List<Map<String, dynamic>> inwxOffenePosten(List<Map<String, dynamic>> aktivitaeten) =>
    aktivitaeten
        .where((a) =>
            ((a['preis'] as num?)?.toDouble() ?? 0) > 0 &&
            (a['rechnung']?.toString() ?? '').isEmpty)
        .toList();

/// Rückfrage für Aktionen, die niemand versehentlich auslösen darf.
///
/// Ein „Sind Sie sicher?" klickt man weg, ohne es gelesen zu haben. Deshalb
/// muss hier der Name des Objekts abgetippt werden — dieselbe Bremse, die
/// GitHub vor dem Löschen eines Repositorys setzt. Der Server prüft die
/// Eingabe noch einmal; der Bildschirm allein ist keine Sicherung.
Future<String?> inwxTippBestaetigung({
  required BuildContext context,
  required String titel,
  required String erklaerung,
  required String wort,
  String knopf = 'Ausführen',
  String? preisHinweis,
}) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) {
      final passt = c.text.trim().toLowerCase() == wort.toLowerCase();
      return AlertDialog(
        title: Row(children: [
          Icon(Icons.report_problem, size: 20, color: F.h(Colors.red, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text(titel, style: const TextStyle(fontSize: 15))),
        ]),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: F.h(Colors.red, 50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: F.h(Colors.red, 200)),
              ),
              child: Text(erklaerung, style: TextStyle(fontSize: 12, color: F.h(Colors.red, 900))),
            ),
            if (preisHinweis != null) ...[
              const SizedBox(height: 8),
              Text(preisHinweis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 14),
            Text('Zum Bestätigen „$wort" eingeben:', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: c,
              autofocus: true,
              onChanged: (_) => setD(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: wort,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: passt ? () => Navigator.pop(dCtx, c.text.trim()) : null,
            child: Text(knopf),
          ),
        ],
      );
    }),
  );
}

/// Farbe für einen Protokoll-Vorgang aus `domain.log`.
///
/// Die Vorgangsnamen sind das offene Vokabular der Registry — „UPDATE NOTIFY",
/// „DNSSEC DEACTIVATION SUCCESSFUL", „TRANSFER FAILED". Eine Übersetzungs-
/// tabelle würde jeden unbekannten Vorgang still falsch beschriften, also
/// bleibt der Originaltext stehen und nur die Farbe wird abgeleitet.
/// Gescheitertes hat Vorrang: „TRANSFER FAILED" enthält kein SUCCESS, aber
/// zusammengesetzte Meldungen können beides tragen.
MaterialColor inwxVorgangFarbe(String vorgang) {
  final v = vorgang.toUpperCase();
  if (v.contains('FAIL') || v.contains('ERROR') || v.contains('REJECT') ||
      v.contains('DENIED') || v.contains('CANCEL')) {
    return Colors.red;
  }
  if (v.contains('SUCCESS')) return Colors.green;
  if (v.contains('REQUEST')) return Colors.blue;
  if (v.contains('NOTIFY')) return Colors.grey;
  return Colors.blueGrey;
}

const Map<String, String> _kStatusLabel = {
  'aktiv': 'Aktiv',
  'gekuendigt': 'Gekündigt',
  'geplant': 'Geplant',
  'abgelaufen': 'Abgelaufen',
};

const Map<String, String> _kIntervallLabel = {
  'jaehrlich': 'jährlich',
  'monatlich': 'monatlich',
  'quartal': 'vierteljährlich',
  'einmalig': 'einmalig',
  'inklusive': 'inklusive',
};

class InwxScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;
  const InwxScreen({super.key, required this.apiService, required this.onBack});

  @override
  State<InwxScreen> createState() => _InwxScreenState();
}

class _InwxScreenState extends State<InwxScreen> with TickerProviderStateMixin {
  late final TabController _tab;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _leistungen = [];
  bool _loading = true;

  /// Ein Abruf für zwei Tabs — „Konto" und „Rechnungen" lesen dieselben
  /// Daten, sollen aber nur eine Anmeldung bei INWX kosten.
  late final _InwxKontoDaten _kontoDaten;

  static const _farbe = Colors.blueGrey;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this);
    _kontoDaten = _InwxKontoDaten(widget.apiService);
    _kontoDaten.addListener(_neuZeichnen);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _kontoDaten.removeListener(_neuZeichnen);
    _kontoDaten.dispose();
    super.dispose();
  }

  /// Nur für die Anzahl am Tab „Rechnungen" — die Tabs selbst hören einzeln zu.
  void _neuZeichnen() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final r = await widget.apiService.inwxAction({'action': 'get_all'});
      if (r['success'] == true && mounted) {
        setState(() {
          _data = inwxAlsMap(r['data']) ?? {};
          _leistungen = inwxListe(r['leistungen']);
          _loading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('[INWX] load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  String _s(String key) => (_data[key] ?? '').toString();

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  Future<void> _oeffne(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // Die dringlichste Leistung bestimmt das Warnzeichen am Tab.
    final frist = inwxKritischsteFrist(_leistungen);
    final warnung = frist != null && frist <= 30;

    return SeasonalBackground(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack, tooltip: 'Zurück zu Partner'),
            const SizedBox(width: 8),
            Icon(Icons.language, size: 32, color: F.h(_farbe, 700)),
            const SizedBox(width: 12),
            const Text('INWX', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Expanded(child: Text('INWX GmbH · Domain-Registrar, Berlin',
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)), overflow: TextOverflow.ellipsis)),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Neu laden',
              onPressed: () { setState(() => _loading = true); _load(); },
            ),
          ]),
          const SizedBox(height: 12),
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: F.h(_farbe, 700),
            unselectedLabelColor: F.h(Colors.grey, 600),
            indicatorColor: _farbe.shade700,
            tabs: [
              const Tab(icon: Icon(Icons.business, size: 18), text: 'Zuständige Firma'),
              Tab(
                icon: Stack(clipBehavior: Clip.none, children: [
                  const Icon(Icons.checklist, size: 18),
                  if (warnung)
                    Positioned(right: -4, top: -3, child: Container(width: 9, height: 9,
                      decoration: BoxDecoration(color: frist < 14 ? Colors.red : Colors.orange, shape: BoxShape.circle))),
                ]),
                text: _leistungen.isEmpty ? 'Leistungen' : 'Leistungen (${_leistungen.length})',
              ),
              const Tab(icon: Icon(Icons.account_balance_wallet, size: 18), text: 'Konto'),
              // Die Anzahl steht erst dran, wenn sie bekannt ist: „Rechnungen (0)"
              // vor dem ersten Abruf hieße „keine Rechnungen", und das wäre eine
              // Aussage, die wir zu dem Zeitpunkt gar nicht treffen können.
              Tab(
                icon: const Icon(Icons.receipt_long, size: 18),
                text: _kontoDaten.geladen && _kontoDaten.rechnungen.isNotEmpty
                    ? 'Rechnungen (${_kontoDaten.rechnungen.length})'
                    : 'Rechnungen',
              ),
              const Tab(icon: Icon(Icons.travel_explore, size: 18), text: 'DNS & Zone'),
              const Tab(icon: Icon(Icons.vpn_key, size: 18), text: 'Zugang & API'),
              const Tab(icon: Icon(Icons.forum_outlined, size: 18), text: 'Korrespondenz'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(controller: _tab, children: [
                    _FirmaTab(
                      data: _data,
                      apiService: widget.apiService,
                      onSaved: _load,
                      oeffne: _oeffne,
                    ),
                    _LeistungenTab(
                      apiService: widget.apiService,
                      leistungen: _leistungen,
                      onChanged: (neu) => setState(() => _leistungen = neu),
                      melde: _melde,
                    ),
                    _KontoTab(apiService: widget.apiService, daten: _kontoDaten, melde: _melde),
                    _RechnungenTab(daten: _kontoDaten, melde: _melde),
                    _DnsTab(apiService: widget.apiService, melde: _melde),
                    _ZugangTab(
                      apiService: widget.apiService,
                      data: _data,
                      onSaved: _load,
                      onLeistungen: (neu) => setState(() => _leistungen = neu),
                      melde: _melde,
                      oeffne: _oeffne,
                      lies: _s,
                    ),
                    _KorrespondenzTab(apiService: widget.apiService, melde: _melde),
                  ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════ Tab 1: Zuständige Firma ══════════════════════

class _FirmaTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final ApiService apiService;
  final Future<void> Function() onSaved;
  final Future<void> Function(String) oeffne;

  const _FirmaTab({
    required this.data,
    required this.apiService,
    required this.onSaved,
    required this.oeffne,
  });

  String _s(String k) => (data[k] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final name = _s('firma.firma_name');
    final anschrift = [
      _s('firma.hauptzentrale_strasse'),
      '${_s('firma.hauptzentrale_plz')} ${_s('firma.hauptzentrale_ort')}'.trim(),
      _s('firma.hauptzentrale_land'),
    ].where((e) => e.isNotEmpty).join(', ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.business, size: 20, color: F.h(Colors.blueGrey, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständige Firma',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: F.h(Colors.blueGrey, 700)))),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(name.isEmpty ? 'Auswählen' : 'Ändern', style: const TextStyle(fontSize: 12)),
            onPressed: () => _firmaWaehlen(context),
          ),
        ]),
        const SizedBox(height: 14),
        if (name.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: F.h(Colors.grey, 50),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: F.h(Colors.grey, 300)),
            ),
            child: Column(children: [
              Icon(Icons.business_outlined, size: 44, color: F.h(Colors.grey, 400)),
              const SizedBox(height: 8),
              Text('Keine Firma ausgewählt', style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
            ]),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: F.h(Colors.blueGrey, 50),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: F.h(Colors.blueGrey, 200)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: F.h(Colors.blueGrey, 100),
                  child: Icon(Icons.language, size: 24, color: F.h(Colors.blueGrey, 700)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: F.h(Colors.blueGrey, 900))),
                  if (_s('firma.branche').isNotEmpty)
                    Text(_s('firma.branche'), style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
                ])),
              ]),
              const Divider(height: 24),
              _zeile(Icons.location_on, 'Anschrift', anschrift),
              _zeile(Icons.phone, 'Telefon', _s('firma.hauptzentrale_telefon')),
              _zeile(Icons.support_agent, 'Support', _s('firma.support_telefon')),
              _zeile(Icons.print, 'Fax', _s('firma.hauptzentrale_fax')),
              _zeile(Icons.email, 'E-Mail', _s('firma.hauptzentrale_email')),
              _zeile(Icons.mail_outline, 'Support-E-Mail', _s('firma.support_email')),
              _zeile(Icons.receipt_long, 'Rechnungen', _s('firma.billing_email')),
              _zeile(Icons.person, 'Geschäftsführer', _s('firma.geschaeftsfuehrer')),
              _zeile(Icons.gavel, 'Registergericht',
                  [_s('firma.registergericht'), _s('firma.registernummer')].where((e) => e.isNotEmpty).join(', ')),
              _zeile(Icons.numbers, 'USt-IdNr.', _s('firma.ust_id')),
              _zeile(Icons.shield_outlined, 'Datenschutzbeauftragter', _s('firma.datenschutz')),
              _zeile(Icons.verified, 'Akkreditierungen', _s('firma.akkreditierung')),
            ]),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_s('firma.website').isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Website', style: TextStyle(fontSize: 12)),
                onPressed: () => oeffne(_s('firma.website')),
              ),
            if (_s('firma.impressum_url').isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.article_outlined, size: 15),
                label: const Text('Impressum', style: TextStyle(fontSize: 12)),
                onPressed: () => oeffne(_s('firma.impressum_url')),
              ),
          ]),
          if (_s('firma.quelle').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_s('firma.quelle'),
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: F.h(Colors.grey, 600))),
          ],
        ],
      ]),
    );
  }

  Widget _zeile(IconData icon, String label, String wert) {
    if (wert.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: F.h(Colors.blueGrey, 600)),
        const SizedBox(width: 10),
        SizedBox(width: 150, child: Text(label, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        Expanded(child: phoneAwareText(icon, wert, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  /// Gleicher Weg wie bei servdiscount: die Firma kommt aus dem gemeinsamen
  /// Firmenregister (arbeitgeber_db), nicht aus einem zweiten Datensatz.
  Future<void> _firmaWaehlen(BuildContext context) async {
    final res = await apiService.getArbeitgeberStammdaten();
    if (res['success'] != true || !context.mounted) return;
    final alle = inwxListe(res['data']);

    final sel = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dCtx) {
        var treffer = alle;
        return StatefulBuilder(builder: (dCtx, setS) => AlertDialog(
          title: Row(children: [
            Icon(Icons.business, size: 18, color: F.h(Colors.blueGrey, 700)),
            const SizedBox(width: 8),
            const Text('Firma auswählen', style: TextStyle(fontSize: 14)),
          ]),
          content: SizedBox(width: 460, height: 420, child: Column(children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Suchen …',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setS(() {
                final q = v.toLowerCase();
                treffer = alle.where((a) => (a['firma_name']?.toString() ?? '').toLowerCase().contains(q)).toList();
              }),
            ),
            const SizedBox(height: 8),
            Expanded(child: treffer.isEmpty
                ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: F.h(Colors.grey, 500))))
                : ListView.builder(
                    itemCount: treffer.length,
                    itemBuilder: (_, i) {
                      final a = treffer[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.business, size: 18, color: Colors.blueGrey.shade400),
                        title: Text(a['firma_name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [a['branche'], a['hauptzentrale_ort']]
                              .where((v) => v != null && v.toString().isNotEmpty).join(' · '),
                          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
                        ),
                        onTap: () => Navigator.pop(dCtx, a),
                      );
                    })),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Abbrechen'))],
        ));
      },
    );
    if (sel == null) return;

    const felder = [
      'firma_name', 'rechtsform', 'branche',
      'hauptzentrale_strasse', 'hauptzentrale_plz', 'hauptzentrale_ort', 'hauptzentrale_land',
      'hauptzentrale_telefon', 'hauptzentrale_fax', 'hauptzentrale_email',
      'geschaeftsfuehrer', 'registergericht', 'registernummer', 'ust_id', 'website',
    ];
    final m = <String, dynamic>{for (final f in felder) 'firma.$f': sel[f]?.toString() ?? ''};
    await apiService.inwxAction({'action': 'save_data', 'data': m});
    await onSaved();
  }
}

// ═════════════════════════ Tab 2: Leistungen ═════════════════════════

class _LeistungenTab extends StatelessWidget {
  final ApiService apiService;
  final List<Map<String, dynamic>> leistungen;
  final void Function(List<Map<String, dynamic>>) onChanged;
  final void Function(String, {bool fehler}) melde;

  const _LeistungenTab({
    required this.apiService,
    required this.leistungen,
    required this.onChanged,
    required this.melde,
  });

  void _uebernehmen(Map<String, dynamic> antwort) {
    if (antwort['leistungen'] is List) onChanged(inwxListe(antwort['leistungen']));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Row(children: [
          Text(
            leistungen.isEmpty ? 'Noch keine Leistung erfasst' : '${leistungen.length} Leistungen',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
          ),
          const Spacer(),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Leistung', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blueGrey.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
            ),
            onPressed: () => _dialog(context, null),
          ),
        ]),
      ),
      Expanded(
        child: leistungen.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.checklist, size: 48, color: F.h(Colors.grey, 300)),
                const SizedBox(height: 10),
                Text('Keine Leistungen', style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 500))),
                const SizedBox(height: 4),
                Text('Über „+ Leistung" hinzufügen oder im Tab „Zugang & API"\naus dem INWX-Konto übernehmen.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: leistungen.length,
                itemBuilder: (_, i) => _karte(context, leistungen[i]),
              ),
      ),
    ]);
  }

  Widget _karte(BuildContext context, Map<String, dynamic> l) {
    final kat = inwxKategorieFinden(l['kategorie']?.toString());
    final status = l['status']?.toString() ?? 'aktiv';
    final tage = l['tage_bis_ablauf'];
    final gekuendigt = status == 'gekuendigt' || status == 'abgelaufen';

    Color rahmen = Colors.blueGrey.shade200;
    Color fuellung = Colors.blueGrey.shade50;
    if (gekuendigt) {
      rahmen = Colors.grey.shade300;
      fuellung = Colors.grey.shade50;
    } else if (tage is int && tage <= 14) {
      rahmen = Colors.red.shade300;
      fuellung = Colors.red.shade50;
    } else if (tage is int && tage <= 30) {
      rahmen = Colors.orange.shade300;
      fuellung = Colors.orange.shade50;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _dialog(context, l),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: fuellung, borderRadius: BorderRadius.circular(10), border: Border.all(color: rahmen)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(kat.icon, size: 22, color: gekuendigt ? F.h(Colors.grey, 500) : F.h(Colors.blueGrey, 700)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(
                l['bezeichnung']?.toString() ?? '',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: gekuendigt ? F.h(Colors.grey, 600) : F.h(Colors.blueGrey, 900),
                  decoration: gekuendigt ? TextDecoration.lineThrough : null,
                ),
              )),
              _chip(_kStatusLabel[status] ?? status,
                  status == 'aktiv' ? Colors.green : (status == 'geplant' ? Colors.blue : Colors.grey)),
            ]),
            const SizedBox(height: 3),
            Text(kat.label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
            if ((l['objekt']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(l['objekt'].toString(),
                    style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: F.h(Colors.blueGrey, 700))),
              ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if ((l['kosten']?.toString() ?? '').isNotEmpty)
                _chip('${l['kosten']} · ${_kIntervallLabel[l['intervall']] ?? l['intervall']}', Colors.blueGrey),
              if ((l['ablauf_datum']?.toString() ?? '').isNotEmpty)
                _chip(
                  'Ablauf ${inwxDatumDeutsch(l['ablauf_datum'].toString())}'
                  '${tage is int ? (tage >= 0 ? ' · in $tage T.' : ' · seit ${-tage} T.') : ''}',
                  gekuendigt
                      ? Colors.grey
                      : (tage is int && tage <= 14 ? Colors.red : (tage is int && tage <= 30 ? Colors.orange : Colors.blueGrey)),
                ),
              if (l['auto_renew'] == true) _chip('Auto-Verlängerung', Colors.teal),
              if (l['quelle'] == 'api') _chip('aus INWX-Konto', Colors.indigo),
            ]),
          ])),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            tooltip: 'Löschen',
            onPressed: () => _loeschen(context, l),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String text, MaterialColor c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: F.h(c, 100), borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: F.h(c, 800))),
      );

  Future<void> _loeschen(BuildContext context, Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leistung löschen?', style: TextStyle(fontSize: 15)),
        content: Text('„${l['bezeichnung']}" wird entfernt.', style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await apiService.inwxAction({'action': 'delete_leistung', 'id': l['id']});
    if (r['success'] == true) {
      _uebernehmen(r);
      melde('Leistung gelöscht');
    } else {
      melde('Löschen fehlgeschlagen', fehler: true);
    }
  }

  Future<void> _dialog(BuildContext context, Map<String, dynamic>? vorhanden) async {
    final neu = vorhanden == null;
    var kategorie = vorhanden?['kategorie']?.toString() ?? 'domain';
    var status = vorhanden?['status']?.toString() ?? 'aktiv';
    var intervall = vorhanden?['intervall']?.toString() ?? 'jaehrlich';
    var autoRenew = vorhanden?['auto_renew'] == true;

    // Bei einer neuen Leistung steht der Name der vorgewählten Kategorie schon
    // drin — sonst startet man auf einem Pflichtfeld, das leer ist.
    final bezC = TextEditingController(
        text: vorhanden?['bezeichnung']?.toString() ?? inwxKategorieFinden(kategorie).label);
    final objC = TextEditingController(text: vorhanden?['objekt']?.toString() ?? '');
    final kostenC = TextEditingController(text: vorhanden?['kosten']?.toString() ?? '');
    final notizC = TextEditingController(text: vorhanden?['notiz']?.toString() ?? '');
    final beginnC = TextEditingController(text: vorhanden?['beginn_datum']?.toString() ?? '');
    final ablaufC = TextEditingController(text: vorhanden?['ablauf_datum']?.toString() ?? '');
    // Nur ein leeres Feld darf die Kategorie nachziehen — sonst überschriebe
    // ein Kategoriewechsel beim Bearbeiten den getippten Namen.
    var bezVorschlag = neu;

    final gespeichert = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) {
        Future<void> datumWaehlen(TextEditingController c) async {
          final vorher = DateTime.tryParse(c.text) ?? DateTime.now();
          final p = await showDatePicker(
            context: dCtx,
            initialDate: vorher,
            firstDate: DateTime(2000),
            lastDate: DateTime(2060),
            locale: const Locale('de'),
          );
          if (p != null) {
            setD(() => c.text = '${p.year.toString().padLeft(4, '0')}-'
                '${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
          }
        }

        final aktKat = inwxKategorieFinden(kategorie);

        return AlertDialog(
          title: Row(children: [
            Icon(aktKat.icon, size: 18, color: F.h(Colors.blueGrey, 700)),
            const SizedBox(width: 8),
            Text(neu ? 'Leistung hinzufügen' : 'Leistung bearbeiten', style: const TextStyle(fontSize: 15)),
          ]),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Leistung von INWX', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 600))),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final k in kInwxKategorien)
                    ChoiceChip(
                      selected: kategorie == k.key,
                      selectedColor: Colors.blueGrey.shade600,
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(k.icon, size: 13, color: kategorie == k.key ? Colors.white : F.h(Colors.grey, 700)),
                        const SizedBox(width: 4),
                        Text(k.label, style: TextStyle(fontSize: 11, color: kategorie == k.key ? Colors.white : F.h(Colors.grey, 800))),
                      ]),
                      onSelected: (_) => setD(() {
                        kategorie = k.key;
                        if (bezVorschlag && (bezC.text.isEmpty || _istVorschlag(bezC.text))) bezC.text = k.label;
                      }),
                    ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: Text(aktKat.beschreibung, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)))),
                  if (aktKat.url != null)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 13),
                      label: const Text('inwx.de', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
                      onPressed: () async {
                        final uri = Uri.tryParse(aktKat.url!);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                ]),
                const Divider(height: 20),
                TextField(
                  controller: bezC,
                  onChanged: (_) => bezVorschlag = false,
                  decoration: InputDecoration(
                    labelText: 'Bezeichnung *',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: objC,
                  decoration: InputDecoration(
                    labelText: 'Objekt (Domain, Hostname, Postfach …)',
                    hintText: 'z. B. icd360s.de',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    // Ohne `isExpanded` richtet sich ein Dropdown nach seinem
                    // breitesten Eintrag, nicht nach dem Feld. Ein langer Name
                    // sprengte damit die Zeile — gemessen 241 dp in
                    // ordnungsmassnahmen_screen. Als Formularfeld soll es
                    // ohnehin die volle Breite haben.
                    isExpanded: true,
                    initialValue: status,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: 'Status',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [for (final e in _kStatusLabel.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))],
                    onChanged: (v) => setD(() => status = v ?? 'aktiv'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: intervall,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: 'Abrechnung',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [for (final e in _kIntervallLabel.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))],
                    onChanged: (v) => setD(() => intervall = v ?? 'jaehrlich'),
                  )),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: kostenC,
                  decoration: InputDecoration(
                    labelText: 'Kosten',
                    hintText: 'z. B. 9,90 €',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(
                    controller: beginnC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Beginn',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.calendar_today, size: 15),
                      suffixIcon: beginnC.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.clear, size: 15), onPressed: () => setD(() => beginnC.clear())),
                    ),
                    onTap: () => datumWaehlen(beginnC),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: ablaufC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Ablauf / Verlängerung',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.event, size: 15),
                      suffixIcon: ablaufC.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.clear, size: 15), onPressed: () => setD(() => ablaufC.clear())),
                    ),
                    onTap: () => datumWaehlen(ablaufC),
                  )),
                ]),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: autoRenew,
                  activeThumbColor: Colors.blueGrey.shade600,
                  title: const Text('Verlängert sich automatisch', style: TextStyle(fontSize: 13)),
                  onChanged: (v) => setD(() => autoRenew = v),
                ),
                TextField(
                  controller: notizC,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Notiz',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade600),
              onPressed: () async {
                if (bezC.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dCtx).showSnackBar(
                    const SnackBar(content: Text('Bitte eine Bezeichnung eingeben')),
                  );
                  return;
                }
                final r = await apiService.inwxAction({
                  'action': 'save_leistung',
                  'leistung': {
                    if (vorhanden != null) 'id': vorhanden['id'],
                    'kategorie': kategorie,
                    'bezeichnung': bezC.text.trim(),
                    'objekt': objC.text.trim(),
                    'status': status,
                    'kosten': kostenC.text.trim(),
                    'intervall': intervall,
                    'beginn_datum': beginnC.text.trim(),
                    'ablauf_datum': ablaufC.text.trim(),
                    'auto_renew': autoRenew,
                    'notiz': notizC.text.trim(),
                  },
                });
                if (r['success'] == true) _uebernehmen(r);
                if (dCtx.mounted) Navigator.pop(dCtx, r['success'] == true);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      }),
    );

    if (gespeichert == true) melde(neu ? 'Leistung hinzugefügt' : 'Leistung gespeichert');
  }

  static bool _istVorschlag(String text) => kInwxKategorien.any((k) => k.label == text);
}

// ═════════ Gemeinsame Kontodaten für „Konto" und „Rechnungen" ═════════

/// Ein Abruf, zwei Tabs.
///
/// `api_konto` ist EIN Login bei INWX und bringt alles auf einmal mit —
/// Kontodaten, Guthaben, Rechnungen, Preise, Protokoll. Seit „Rechnungen"
/// ein eigener Tab ist, hätten zwei getrennte Zustände zwei Anmeldungen je
/// Bildschirm bedeutet. Deshalb liegt der Abruf hier, und beide Tabs hängen
/// an derselben Instanz.
///
/// ⚠️ Geladen wird nicht beim Öffnen des Bildschirms, sondern beim ersten
/// Tab, der die Daten braucht (`sicherstellen()`) — wer nur „Zuständige
/// Firma" ansieht, soll keine Anmeldung bei INWX auslösen.
///
/// Alles hier kommt bei jedem Abruf frisch von INWX — nichts davon liegt in
/// unserer Datenbank. Rechnungen und Protokoll sind bei INWX geführt; eine
/// zweite Kopie wäre nur eine, die auseinanderläuft.
class _InwxKontoDaten extends ChangeNotifier {
  _InwxKontoDaten(this.apiService);

  final ApiService apiService;

  bool laeuft = false;
  bool geladen = false;
  String? fehler;

  Map<String, dynamic>? konto;
  Map<String, dynamic>? guthaben;
  List<Map<String, dynamic>> rechnungen = [];
  List<Map<String, dynamic>> bewegungen = [];
  List<Map<String, dynamic>> aktivitaeten = [];
  List<Map<String, dynamic>> kontakte = [];
  List<Map<String, dynamic>> nicHandles = [];
  List<Map<String, dynamic>> preise = [];
  List<Map<String, dynamic>> preisaenderungen = [];
  List<Map<String, dynamic>> neuigkeiten = [];
  List<Map<String, dynamic>> domains = [];
  int rechnungenAnzahl = 0;
  int bewegungenAnzahl = 0;
  int aktivitaetenAnzahl = 0;
  int meldungenOffen = 0;
  Map<String, dynamic>? meldung;
  String? bewegungenSeit;

  Future<void>? _offen;
  bool _entsorgt = false;

  /// Der erste Tab, der die Daten braucht, holt sie; jeder weitere findet sie
  /// schon vor.
  Future<void> sicherstellen() {
    if (_offen != null) return _offen!;
    if (geladen) return Future<void>.value();
    return laden();
  }

  /// Ein laufender Abruf wird geteilt statt verdoppelt: beide Tabs haben einen
  /// eigenen „Neu abrufen"-Knopf, und zwei gleichzeitige Anmeldungen bei INWX
  /// wären genau das, was dieser Zustand vermeiden soll.
  ///
  /// ⚠️ `Future.microtask`, damit die erste Meldung nicht mitten im Aufbau der
  /// Oberfläche fällt — `sicherstellen()` wird aus `initState` gerufen, und ein
  /// `notifyListeners()` von dort würde die Zuhörer beim Bauen neu bauen lassen.
  Future<void> laden() =>
      _offen ??= Future.microtask(_holen).whenComplete(() => _offen = null);

  Future<void> _holen() async {
    laeuft = true;
    fehler = null;
    _melden();
    try {
      final r = await apiService.inwxAction({'action': 'api_konto'});
      if (r['success'] != true) {
        fehler = r['message']?.toString() ?? 'Abruf fehlgeschlagen';
      } else if (r['verbunden'] != true) {
        // ⚠️ Hier ist 'fehler' eine Zeichenkette, bei 'verbunden' dagegen eine
        // LISTE von Teilfehlern. Beides muss gelesen werden, ohne zu werfen.
        fehler = r['fehler']?.toString() ?? 'Nicht verbunden';
      } else {
        konto = inwxAlsMap(r['konto']);
        guthaben = inwxAlsMap(r['guthaben']);
        rechnungen = inwxListe(r['rechnungen']);
        bewegungen = inwxListe(r['bewegungen']);
        aktivitaeten = inwxListe(r['aktivitaeten']);
        rechnungenAnzahl = (r['rechnungen_anzahl'] as num?)?.toInt() ?? rechnungen.length;
        bewegungenAnzahl = (r['bewegungen_anzahl'] as num?)?.toInt() ?? bewegungen.length;
        aktivitaetenAnzahl = (r['aktivitaeten_anzahl'] as num?)?.toInt() ?? aktivitaeten.length;
        bewegungenSeit = r['bewegungen_seit']?.toString();
        kontakte = inwxListe(r['kontakte']);
        nicHandles = inwxListe(r['nic_handles']);
        preise = inwxListe(r['preise']);
        preisaenderungen = inwxListe(r['preisaenderungen']);
        neuigkeiten = inwxListe(r['neuigkeiten']);
        domains = inwxListe(r['domains']);
        meldungenOffen = (r['meldungen_offen'] as num?)?.toInt() ?? 0;
        meldung = inwxAlsMap(r['meldung']);
        final teil = r['fehler'];
        if (teil is List && teil.isNotEmpty) fehler = teil.join(' · ');
      }
    } catch (e) {
      fehler = 'Fehler: $e';
    }
    laeuft = false;
    geladen = true;
    _melden();
  }

  void _melden() {
    if (!_entsorgt) notifyListeners();
  }

  @override
  void dispose() {
    _entsorgt = true;
    super.dispose();
  }
}

// ═════════════════════ Tab 3: Konto (live) ═════════════════════

class _KontoTab extends StatefulWidget {
  final ApiService apiService;
  final _InwxKontoDaten daten;
  final void Function(String, {bool fehler}) melde;
  const _KontoTab({required this.apiService, required this.daten, required this.melde});

  @override
  State<_KontoTab> createState() => _KontoTabState();
}

class _KontoTabState extends State<_KontoTab> with AutomaticKeepAliveClientMixin {
  bool _pinSichtbar = false;

  // Die abgerufenen Daten liegen im gemeinsamen Zustand; hier stehen nur
  // Zeiger darauf, damit der Rest des Tabs unverändert lesen kann.
  bool get _laeuft => widget.daten.laeuft;
  bool get _geladen => widget.daten.geladen;
  String? get _fehler => widget.daten.fehler;
  Map<String, dynamic>? get _konto => widget.daten.konto;
  Map<String, dynamic>? get _guthaben => widget.daten.guthaben;
  List<Map<String, dynamic>> get _bewegungen => widget.daten.bewegungen;
  List<Map<String, dynamic>> get _aktivitaeten => widget.daten.aktivitaeten;
  List<Map<String, dynamic>> get _kontakte => widget.daten.kontakte;
  List<Map<String, dynamic>> get _nicHandles => widget.daten.nicHandles;
  List<Map<String, dynamic>> get _preise => widget.daten.preise;
  List<Map<String, dynamic>> get _preisaenderungen => widget.daten.preisaenderungen;
  List<Map<String, dynamic>> get _neuigkeiten => widget.daten.neuigkeiten;
  List<Map<String, dynamic>> get _domains => widget.daten.domains;
  int get _bewegungenAnzahl => widget.daten.bewegungenAnzahl;
  int get _aktivitaetenAnzahl => widget.daten.aktivitaetenAnzahl;
  int get _meldungenOffen => widget.daten.meldungenOffen;
  Map<String, dynamic>? get _meldung => widget.daten.meldung;
  String? get _bewegungenSeit => widget.daten.bewegungenSeit;

  // Das Änderungsprotokoll ist ein eigener Abruf (`api_aenderungen`) und wird
  // nur auf Knopfdruck geholt — es bleibt deshalb hier.
  List<Map<String, dynamic>> _aenderungen = [];
  String? _arbeitet;   // Domain oder Kontakt-Id, solange ein Schreibvorgang läuft

  // Der Abruf kostet eine Anmeldung bei INWX — beim Hin- und Herwechseln
  // zwischen den Tabs soll er sich nicht jedes Mal wiederholen.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.daten.addListener(_aktualisieren);
    widget.daten.sicherstellen();
  }

  @override
  void dispose() {
    widget.daten.removeListener(_aktualisieren);
    super.dispose();
  }

  void _aktualisieren() {
    if (mounted) setState(() {});
  }

  Future<void> _laden() => widget.daten.laden();

  /// Id der Buchung, deren Beleg gerade geholt wird.
  String? _belegLaeuft;

  /// Zahlungsbeleg zu einer Einzahlung.
  ///
  /// ⚠️ Es geht **nur** die Id hinaus. Betrag, Text und Datum liest der Server
  /// selbst aus `accounting.log` — INWX druckt bei `getReceipt` genau das auf
  /// seinen Briefkopf, was man ihm schickt. Käme es von hier, wäre der Beleg
  /// ein Formular zum Selbstausfüllen.
  Future<void> _belegOeffnen(String id) async {
    setState(() => _belegLaeuft = id);
    try {
      final r = await widget.apiService.inwxAction({'action': 'api_beleg_pdf', 'id': id});
      if (r['success'] == true) {
        final bytes = base64Decode(r['pdf_base64'].toString());
        final dir = await getTemporaryDirectory();
        final datei = File('${dir.path}/INWX-Zahlungsbeleg-$id.pdf');
        await datei.writeAsBytes(bytes);
        final auf = await OpenFilex.open(datei.path);
        if (auf.type != ResultType.done) widget.melde('Gespeichert unter ${datei.path}');
      } else {
        widget.melde(r['message']?.toString() ?? 'Beleg nicht abrufbar', fehler: true);
      }
    } catch (e) {
      widget.melde('Beleg konnte nicht geöffnet werden: $e', fehler: true);
    }
    if (mounted) setState(() => _belegLaeuft = null);
  }

  /// Welche Gruppe gerade offen ist. Elf gleich laute Karten untereinander
  /// sind keine Übersicht — sie sind eine Wand.
  String _bereich = 'konto';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_laeuft && !_geladen) return const Center(child: CircularProgressIndicator());

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Kopf: Herkunft der Daten und Neu-Abruf ──
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          Icon(Icons.cloud_download, size: 14, color: Colors.blueGrey.shade400),
          const SizedBox(width: 7),
          Expanded(child: Text('LIVE VON INWX',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 0.9, color: Colors.blueGrey.shade400))),
          if (_laeuft)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              icon: const Icon(Icons.refresh, size: 17),
              tooltip: 'Neu abrufen',
              visualDensity: VisualDensity.compact,
              onPressed: _laden,
            ),
        ]),
      ),

      if (_fehler != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _hinweis(Icons.error_outline, Colors.red, _fehler!),
        ),

      // ── Das Wichtigste, immer sichtbar: die Laufzeit ──
      // Eine Domain ist eine Miete auf Zeit. Alles andere auf diesem
      // Bildschirm existiert, um sie zu verlängern — also steht sie oben und
      // wandert nicht in eine Gruppe, in der man sie erst suchen müsste.
      for (final d in _domains)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _laufzeitBand(d),
        ),

      // ── Gruppen ──
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'konto', label: Text('Konto'), icon: Icon(Icons.badge, size: 15)),
              ButtonSegment(value: 'domains', label: Text('Domains'), icon: Icon(Icons.language, size: 15)),
              ButtonSegment(value: 'geld', label: Text('Geld'), icon: Icon(Icons.euro, size: 15)),
              ButtonSegment(value: 'verlauf', label: Text('Verlauf'), icon: Icon(Icons.history, size: 15)),
            ],
            selected: {_bereich},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              foregroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? Colors.white : Colors.blueGrey.shade700),
              backgroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? Colors.blueGrey.shade600 : null),
            ),
            onSelectionChanged: (v) => setState(() => _bereich = v.first),
          ),
        ),
      ),

      Expanded(
        child: RefreshIndicator(
          onRefresh: _laden,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: _gruppe(),
          ),
        ),
      ),
    ]);
  }

  /// Vier Gruppen statt einer Liste. Die Zuordnung folgt der Frage, mit der
  /// man den Bildschirm öffnet: Wer sind wir? · Was haben wir? · Was kostet
  /// es? · Was ist passiert?
  List<Widget> _gruppe() {
    const luft = SizedBox(height: 22);
    switch (_bereich) {
      case 'domains':
        return [_domainKarte(), luft, _gefaehrlichKarte()];
      case 'geld':
        return [
          if (_guthaben != null) ...[_guthabenKarte(), luft],
          _preiseKarte(), luft,
          _bewegungenKarte(),
          const SizedBox(height: 16),
          // Die Rechnungen standen bis hierher in dieser Gruppe. Sie haben
          // jetzt einen eigenen Tab — der Hinweis bleibt, weil man sie sonst
          // genau an dieser Stelle sucht.
          _hinweis(Icons.receipt_long, Colors.indigo,
              'Die Rechnungen von INWX stehen im eigenen Tab „Rechnungen".'),
        ];
      case 'verlauf':
        return [_aktivitaetenKarte(), luft, _neuigkeitenKarte(), luft, _protokollKarte()];
      default:
        return [
          if (_konto != null) ...[_kontoKarte(), luft],
          _kontakteKarte(),
        ];
    }
  }

  // ─── Laufzeitband ───

  Widget _laufzeitBand(Map<String, dynamic> d) {
    final name   = d['domain']?.toString() ?? '';
    final ablauf = d['ablauf']?.toString();
    final tage   = inwxTageBis(ablauf);
    final anteil = inwxLaufzeitAnteil(von: d['registriert']?.toString(), bis: ablauf);

    final MaterialColor ton = tage == null
        ? Colors.blueGrey
        : (tage <= 14 ? Colors.red : (tage <= 30 ? Colors.orange : Colors.green));

    // Die Rechnung, die den ganzen Bildschirm begründet: reicht das Guthaben
    // für die nächste Verlängerung? Sie steht hier, statt dass man sie sich
    // aus drei Abschnitten zusammensuchen muss.
    final preis = _preise.isEmpty ? null : _preise.first['verlaengerung_brutto'] as num?;
    final frei  = _guthaben?['available'] as num?;
    final waehr = (_guthaben?['waehrung'] ?? 'EUR').toString();
    String? urteil;
    MaterialColor urteilTon = Colors.green;
    if (preis != null && frei != null) {
      if (frei >= preis) {
        urteil = 'Guthaben deckt die Verlängerung';
      } else {
        // ⚠️ Rot nur, wenn es bald fällig ist. Direkt nach einer Verlängerung
        // ist das Guthaben leer und der nächste Termin ein Jahr entfernt —
        // eine rote Warnung sagt dort das Gegenteil dessen, was gerade
        // passiert ist, und wer sie ein Jahr lang sieht, sieht sie nicht mehr.
        final knapp = tage == null || tage <= 60;
        urteil = knapp
            ? 'Guthaben reicht nicht — es fehlen '
                '${(preis - frei).toStringAsFixed(2)} $waehr'
            : 'Für die nächste Verlängerung fehlen noch '
                '${(preis - frei).toStringAsFixed(2)} $waehr — fällig erst '
                '${inwxDatumDeutsch(ablauf ?? '')}';
        urteilTon = knapp ? Colors.red : Colors.blueGrey;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: F.h(ton, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
          Text(tage == null
                  ? '—'
                  : (tage >= 0 ? 'noch $tage ${tage == 1 ? 'Tag' : 'Tage'}' : 'seit ${-tage} Tagen abgelaufen'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(ton, 700))),
        ]),
        const SizedBox(height: 8),
        // Der Balken zeigt die verbrauchte Mietzeit. Bei sechs Tagen Rest ist
        // der helle Streifen am Ende ein Splitter — das sieht man schneller,
        // als man eine Zahl liest.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: anteil,
            minHeight: 6,
            backgroundColor: F.h(ton, 100),
            valueColor: AlwaysStoppedAnimation(ton.shade400),
          ),
        ),
        const SizedBox(height: 10),
        // Weit auseinander, damit die vier Angaben als vier Angaben gelesen
        // werden und nicht als ein Fließtext.
        Wrap(spacing: 32, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.start, children: [
          _bandWert('läuft ab', inwxDatumDeutsch(ablauf ?? '')),
          if (preis != null) _bandWert('Verlängerung', '$preis $waehr'),
          if (frei != null) _bandWert('verfügbar', '$frei $waehr'),
          if ((d['renewal_mode']?.toString() ?? '').isNotEmpty)
            _bandWert('Modus', kInwxRenewalModi[d['renewal_mode']] ?? d['renewal_mode'].toString()),
        ]),
        if (urteil != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            // Drei Zustände, drei Zeichen: Problem · Hinweis ohne Eile · in Ordnung.
            // Ein Häkchen an „es fehlen 5,54" wäre schlicht falsch.
            Icon(urteilTon == Colors.red
                    ? Icons.error_outline
                    : (urteilTon == Colors.green ? Icons.check_circle_outline : Icons.info_outline),
                size: 14, color: F.h(urteilTon, 600)),
            const SizedBox(width: 6),
            Expanded(child: Text(urteil,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(urteilTon, 800)))),
          ]),
        ],
      ]),
    );
  }

  Widget _bandWert(String label, String wert) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.7, color: Colors.blueGrey.shade400)),
          Text(wert, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );

  // ─── Kontodaten ───
  Widget _kontoKarte() {
    final k = _konto!;
    final pin = (k['service_pin'] ?? '').toString();
    return _block(Icons.badge, 'Kontodaten', Colors.blueGrey, [
      // Achtzehn Zeilen in einer Spalte sind eine Liste, keine Auskunft.
      // Drei benannte Gruppen, je zweispaltig, beantworten dieselben Fragen
      // auf einem Drittel der Höhe — und sagen nebenbei, was zusammengehört.
      _untertitel('Wer'),
      _kvGitter([
        ('Benutzername', k['username']?.toString() ?? ''),
        ('Kundennummer', k['kundennummer']?.toString() ?? ''),
        ('Konto-ID', k['konto_id']?.toString() ?? ''),
        ('Inhaber', [k['org'], k['inhaber']].where((e) => (e?.toString() ?? '').isNotEmpty).join(' · ')),
        ('Anschrift', k['anschrift']?.toString() ?? ''),
        ('Telefon', k['telefon']?.toString() ?? ''),
        ('E-Mail', k['email']?.toString() ?? ''),
        if ((k['email_rechnung']?.toString() ?? '') != (k['email']?.toString() ?? ''))
          ('E-Mail Rechnungen', k['email_rechnung']?.toString() ?? ''),
        ('Website', k['website']?.toString() ?? ''),
      ]),
      const SizedBox(height: 16),
      _untertitel('Abrechnung'),
      _kvGitter([
        ('Zahlungsart', k['zahlungsart']?.toString() ?? ''),
        ('Umsatzsteuer', (k['ust_satz']?.toString() ?? '').isEmpty ? '' : '${k['ust_satz']} %'),
        ('Verlängerungsmodus', k['renewal_mode']?.toString() ?? ''),
        ('Rechnung als PDF', k['rechnung_pdf'] == true ? 'ja' : 'nein'),
      ]),
      const SizedBox(height: 16),
      _untertitel('Zugriff'),
      _kvGitter([
        ('Zwei-Faktor', k['zwei_fa'] == true ? 'aktiv' : 'nicht aktiv'),
        ('Kunde seit', inwxDatumDeutsch(k['kunde_seit']?.toString() ?? '')),
        ('Letzter Login', k['letzter_login']?.toString() ?? ''),
        ('Anmeldungen gesamt', k['logins']?.toString() ?? ''),
        ('Letzte IP', k['letzte_ip']?.toString() ?? ''),
      ]),
      if (pin.isNotEmpty)
        // Die Service-PIN legitimiert am Telefon bei INWX — sie steht nicht
        // offen da, nur einen Tipp entfernt.
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            SizedBox(width: 160, child: Text('Service-PIN', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
            Expanded(child: Text(_pinSichtbar ? pin : '•' * pin.length,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace'))),
            IconButton(
              icon: Icon(_pinSichtbar ? Icons.visibility_off : Icons.visibility, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: _pinSichtbar ? 'Verbergen' : 'Anzeigen',
              onPressed: () => setState(() => _pinSichtbar = !_pinSichtbar),
            ),
          ]),
        ),
    ]);
  }

  // ─── Guthaben ───
  Widget _guthabenKarte() {
    final g = _guthaben!;
    final w = (g['waehrung'] ?? 'EUR').toString();
    final verfuegbar = g['available'];
    final prepaid = (_konto?['zahlungsart']?.toString() ?? '').toLowerCase() == 'prepaid';
    final leer = prepaid && verfuegbar is num && verfuegbar <= 0;

    // Wie beim Laufzeitband: leeres Guthaben ist erst dann ein Problem, wenn
    // eine Verlängerung ansteht. Am Tag nach einer Verlängerung ist es der
    // Normalzustand — dort in Rot zu warnen, heißt jedes Jahr elf Monate lang
    // eine Warnung zu zeigen, die niemand mehr liest.
    final tage = _domains
        .map((d) => inwxTageBis(d['ablauf']?.toString()))
        .whereType<int>()
        .fold<int?>(null, (klein, t) => klein == null || t < klein ? t : klein);
    final knapp = leer && (tage == null || tage <= 60);

    return _block(Icons.account_balance_wallet, 'Guthaben',
        knapp ? Colors.red : (leer ? Colors.blueGrey : Colors.green), [
      _kv('Gesamt', g['total'] == null ? '–' : '${g['total']} $w'),
      _kv('Davon verfügbar', verfuegbar == null ? '–' : '$verfuegbar $w'),
      if (g['locked'] != null && (g['locked'] as num) != 0) _kv('Reserviert', '${g['locked']} $w'),
      if (g['credit_limit'] != null && (g['credit_limit'] as num) != 0) _kv('Kreditrahmen', '${g['credit_limit']} $w'),
      if (leer) ...[
        const SizedBox(height: 8),
        _hinweis(
          knapp ? Icons.warning_amber : Icons.info_outline,
          knapp ? Colors.red : Colors.blueGrey,
          'Prepaid-Konto ohne verfügbares Guthaben. „Gesamt" zählt bereits '
          'verbrauchte Zahlungen mit — für eine Verlängerung zählt allein '
          '„verfügbar".'
          // Die Gebühr direkt danebenstellen: sonst muss man zum Rechnen erst
          // weiterscrollen, und genau dieser Vergleich ist der ganze Punkt.
          '${_verlaengerungSatz()}'
          '${knapp ? ' Vor dem nächsten Ablaufdatum aufladen.'
                   : ' Das ist nach einer Verlängerung der Normalfall; '
                     'aufzuladen ist erst vor dem nächsten Ablaufdatum nötig.'}',
        ),
      ],
    ]);
  }

  // ─── Guthabenbewegungen ───
  Widget _bewegungenKarte() {
    final mehr = _bewegungenAnzahl > _bewegungen.length;
    return _block(Icons.swap_vert, 'Guthabenbewegungen ($_bewegungenAnzahl)', Colors.teal, [
      if (_bewegungenSeit != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('seit ${inwxDatumDeutsch(_bewegungenSeit!)}',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
        ),
      if (_bewegungen.isEmpty)
        Text(_geladen ? 'Keine Bewegungen im Zeitraum.' : '—',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))
      else
        for (final b in _bewegungen)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(
                (b['betrag'] as num? ?? 0) >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                size: 16,
                color: (b['betrag'] as num? ?? 0) >= 0 ? F.h(Colors.green, 600) : Colors.red.shade500,
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${b['art']} · ${b['details']}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(b['zeitpunkt']?.toString() ?? '',
                    style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
              ])),
              Text(
                '${(b['betrag'] as num? ?? 0) >= 0 ? '+' : ''}${b['betrag']} €',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: (b['betrag'] as num? ?? 0) >= 0 ? F.h(Colors.green, 700) : F.h(Colors.red, 600),
                ),
              ),
              // Beleg gibt es nur zu Einzahlungen — bei einer Abbuchung ist die
              // Rechnung der Beleg. Der Server weist alles andere ohnehin ab.
              if ((b['art']?.toString() ?? '') == 'Payment' &&
                  (b['id']?.toString() ?? '').isNotEmpty)
                _belegLaeuft == b['id'].toString()
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: Icon(Icons.receipt, size: 16, color: F.h(Colors.teal, 700)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        tooltip: 'Zahlungsbeleg als PDF',
                        onPressed: _belegLaeuft != null
                            ? null
                            : () => _belegOeffnen(b['id'].toString()),
                      ),
              // Nur Einzahlungen sind erstattbar; INWX sagt das selbst mit
              // `refundable`, also raten wir es nicht.
              if (b['erstattbar'] == true)
                IconButton(
                  icon: Icon(Icons.undo, size: 16, color: F.h(Colors.orange, 700)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Erstatten',
                  onPressed: () => _erstatten(b),
                ),
            ]),
          ),
      if (mehr)
        Text('… $_bewegungenAnzahl insgesamt, die neuesten ${_bewegungen.length} sind gezeigt.',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: F.h(Colors.grey, 600))),
    ]);
  }

  // ─── Domaininhaber / Kontakt-Handles ───
  Widget _kontakteKarte() {
    // Rollenkontakte von INWX (Hostmaster) sind nicht unsere — sie stehen
    // unten und ohne Prüf-Hinweise, sonst sähen sie nach Handlungsbedarf aus.
    final unsere = _kontakte.where((k) => k['nur_lesen'] != true).toList();
    final fremde = _kontakte.where((k) => k['nur_lesen'] == true).toList();

    return _block(Icons.contact_page, 'Domaininhaber & Kontakte (${_kontakte.length})', Colors.brown, [
      if (_kontakte.isEmpty)
        Text(_geladen ? 'Keine Kontakt-Handles.' : '—',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
      for (final k in [...unsere, ...fremde]) _kontaktZeile(k),
      for (final h in _nicHandles)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('NIC-Handle ${h['handle']} · ${h['domain']} · ${h['status']}',
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: F.h(Colors.grey, 700))),
        ),
    ]);
  }

  Widget _kontaktZeile(Map<String, dynamic> k) {
    final unser = k['nur_lesen'] != true;
    final geprueft = (k['geprueft']?.toString() ?? '').toUpperCase() == 'CONFIRMED';
    // Eine Rufnummer aus lauter Einsen ist eine Platzhalter-Eingabe, kein
    // Anschluss — bei .de-Domains verlangt die DENIC erreichbare Inhaberdaten.
    final tel = k['telefon']?.toString() ?? '';
    final telPlatzhalter = unser && RegExp(r'^\+?[\d.\-]*?(\d)\1{5,}$').hasMatch(tel.replaceAll(' ', ''));

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: unser ? F.h(Colors.brown, 200) : F.h(Colors.grey, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(unser ? Icons.person : Icons.support_agent, size: 15,
              color: unser ? F.h(Colors.brown, 600) : F.h(Colors.grey, 500)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            [k['org'], k['name']].where((e) => (e?.toString() ?? '').isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: unser ? (geprueft ? F.h(Colors.green, 100) : F.h(Colors.orange, 100)) : F.h(Colors.grey, 100),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              unser ? (geprueft ? 'bestätigt' : (k['geprueft']?.toString() ?? '—')) : 'INWX',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: unser ? (geprueft ? F.h(Colors.green, 800) : F.h(Colors.orange, 800)) : F.h(Colors.grey, 700),
              ),
            ),
          ),
          // Rollenkontakte von INWX gehören uns nicht — sie sind auch über
          // die API nicht änderbar, also gibt es dort keinen Knopf.
          if (unser) ...[
            IconButton(
              icon: const Icon(Icons.edit, size: 15),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Inhaberdaten ändern',
              onPressed: () => _kontaktDialog(k),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 15, color: Colors.red.shade400),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Kontakt löschen',
              onPressed: () => _kontaktLoeschen(k),
            ),
          ],
        ]),
        const SizedBox(height: 3),
        Text(
          [
            '#${k['id']} · ${k['typ']}',
            k['anschrift']?.toString() ?? '',
            if (tel.isNotEmpty) tel,
            k['email']?.toString() ?? '',
          ].where((e) => e.isNotEmpty).join(' · '),
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
        ),
        if (telPlatzhalter) ...[
          const SizedBox(height: 5),
          _hinweis(Icons.warning_amber, Colors.orange,
              'Die Rufnummer sieht nach einem Platzhalter aus. Die DENIC verlangt '
              'für .de-Domains erreichbare Inhaberdaten.'),
        ],
      ]),
    );
  }

  /// „ Eine Verlängerung von .de kostet 5,54 EUR brutto." — leer, solange die
  /// Preise noch nicht da sind; ein halber Satz ist schlimmer als keiner.
  String _verlaengerungSatz() {
    final mitPreis = _preise.where((p) => p['verlaengerung_brutto'] != null).toList();
    if (mitPreis.isEmpty) return '';
    final teile = mitPreis
        .map((p) => '.${p['tld']} ${p['verlaengerung_brutto']} ${p['waehrung']}')
        .join(', ');
    return ' Eine Verlängerung kostet brutto: $teile.';
  }

  // ─── Preise ───
  Widget _preiseKarte() {
    return _block(Icons.sell, 'Preise unserer Endungen', Colors.blueGrey, [
      if (_preise.isEmpty)
        Text(_geladen ? 'Keine Preisangaben abrufbar.' : '—',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
      for (final p in _preise) ...[
        Text('.${p['tld']}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.blueGrey, 800))),
        const SizedBox(height: 4),
        // Vom Guthaben geht der Bruttobetrag ab — netto steht daneben, damit
        // die Zahl aus dem Kundencenter wiedererkennbar bleibt.
        _kv('Verlängerung', p['verlaengerung_brutto'] == null
            ? '–'
            : '${p['verlaengerung_brutto']} ${p['waehrung']} brutto  (netto ${p['verlaengerung']}, ${p['ust_satz']} % USt)'),
        _kv('Neuanlage', p['neuanlage'] == null ? '' : '${p['neuanlage']} ${p['waehrung']} netto'),
        _kv('Transfer', p['transfer'] == null ? '' : '${p['transfer']} ${p['waehrung']} netto'),
        _kv('Wiederherstellung', p['wiederherstellung'] == null
            ? ''
            : '${p['wiederherstellung']} ${p['waehrung']} netto — fällig, wenn eine Domain abläuft'),
      ],
      if (_preisaenderungen.isNotEmpty) ...[
        const Divider(height: 18),
        Text('Angekündigte Preisänderungen',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.blueGrey, 800))),
        const SizedBox(height: 4),
        for (final a in _preisaenderungen)
          Text(
            'ab ${inwxDatumDeutsch(a['ab']?.toString() ?? '')}: .${a['tld']} '
            'Verlängerung ${a['verlaengerung']} ${a['waehrung']} netto'
            '${a['betrifft_uns'] == true ? ' — betrifft uns' : ''}',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
          ),
      ],
    ]);
  }

  // ─── Was im Konto getan wurde ───
  Widget _aktivitaetenKarte() {
    final mehr = _aktivitaetenAnzahl > _aktivitaeten.length;
    return _block(Icons.history, 'Aktivitäten im Konto ($_aktivitaetenAnzahl)', Colors.deepPurple, [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Protokoll von INWX: jeder Vorgang an den Domains, neueste zuerst. '
          '„System / Registry" heißt, dass nicht wir ihn ausgelöst haben.',
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
        ),
      ),
      if (_aktivitaeten.isEmpty)
        Text(_geladen ? 'Keine Vorgänge protokolliert.' : '—',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))
      else
        for (final a in _aktivitaeten) _aktivitaetZeile(a),
      if (mehr)
        Text('… $_aktivitaetenAnzahl insgesamt, die neuesten ${_aktivitaeten.length} sind gezeigt.',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: F.h(Colors.grey, 600))),
    ]);
  }

  Widget _aktivitaetZeile(Map<String, dynamic> a) {
    final farbe = inwxVorgangFarbe(a['vorgang']?.toString() ?? '');
    final text = (a['text']?.toString() ?? '').trim();
    final wirSelbst = (a['wer']?.toString() ?? '') != 'System / Registry';
    final preis = a['preis'];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: F.h(farbe, 50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: farbe.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(wirSelbst ? Icons.person : Icons.dns, size: 14, color: F.h(farbe, 700)),
          const SizedBox(width: 6),
          Expanded(child: Text(a['vorgang']?.toString() ?? '',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(farbe, 800)))),
          if (preis is num && preis != 0)
            Text('$preis €', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(farbe, 700))),
          const SizedBox(width: 8),
          Text(a['zeitpunkt']?.toString() ?? '', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 700))),
        ]),
        const SizedBox(height: 3),
        Text(
          [
            a['domain']?.toString() ?? '',
            a['wer']?.toString() ?? '',
            if ((a['ip']?.toString() ?? '').isNotEmpty) 'von ${a['ip']}',
            if ((a['rechnung']?.toString() ?? '').isNotEmpty) 'Rechnung ${a['rechnung']}',
          ].where((e) => e.isNotEmpty).join(' · '),
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(text,
              style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: F.h(Colors.grey, 600)),
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }

  /// Inhaberdaten ändern. Die Rufnummer will INWX im Format +49.30123456;
  /// ohne den Punkt weist die Registry sie zurück, ohne zu sagen warum.
  Future<void> _kontaktDialog(Map<String, dynamic> k) async {
    final id = k['id']?.toString() ?? '';
    if (id.isEmpty) return;

    // Anschrift kommt zusammengesetzt an — für das Ändern braucht es die
    // Einzelfelder, also werden sie hier wieder auseinandergenommen.
    final teile = (k['anschrift']?.toString() ?? '').split(',').map((e) => e.trim()).toList();
    final strasse = teile.isNotEmpty ? teile[0] : '';
    final plzOrt = teile.length > 1 ? teile[1] : '';
    final land = teile.length > 2 ? teile[2] : 'DE';
    final plzOrtTeile = plzOrt.split(RegExp(r'\s+'));
    final plz = plzOrtTeile.isNotEmpty ? plzOrtTeile.first : '';
    final ort = plzOrtTeile.length > 1 ? plzOrtTeile.sublist(1).join(' ') : '';

    final nameC = TextEditingController(text: k['name']?.toString() ?? '');
    final orgC = TextEditingController(text: k['org']?.toString() ?? '');
    final strasseC = TextEditingController(text: strasse);
    final plzC = TextEditingController(text: plz);
    final ortC = TextEditingController(text: ort);
    final landC = TextEditingController(text: land.isEmpty ? 'DE' : land);
    final telC = TextEditingController(text: k['telefon']?.toString() ?? '');
    final mailC = TextEditingController(text: k['email']?.toString() ?? '');
    var speichert = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) => AlertDialog(
        title: Row(children: [
          Icon(Icons.contact_page, size: 18, color: F.h(Colors.brown, 700)),
          const SizedBox(width: 8),
          const Text('Inhaberdaten ändern', style: TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _feld(nameC, 'Name'),
              _feld(orgC, 'Organisation'),
              _feld(strasseC, 'Straße und Hausnummer'),
              Row(children: [
                SizedBox(width: 120, child: _feld(plzC, 'PLZ')),
                const SizedBox(width: 10),
                Expanded(child: _feld(ortC, 'Ort')),
                const SizedBox(width: 10),
                SizedBox(width: 90, child: _feld(landC, 'Land')),
              ]),
              _feld(telC, 'Telefon', hinweis: 'Format +49.73112345678'),
              _feld(mailC, 'E-Mail'),
              const SizedBox(height: 6),
              _hinweis(Icons.gavel, Colors.blue,
                  'Bei .de-Domains verlangt die DENIC erreichbare Inhaberdaten. '
                  'Die Änderung geht zuerst als Probe an INWX.'),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: speichert ? null : () => Navigator.pop(dCtx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.brown.shade600),
            onPressed: speichert ? null : () async {
              final tel = telC.text.trim();
              if (tel.isNotEmpty && !RegExp(r'^\+\d{1,4}\.\d{3,14}$').hasMatch(tel)) {
                ScaffoldMessenger.of(dCtx).showSnackBar(SnackBar(
                  content: const Text('Rufnummer im Format +49.73112345678 angeben.'),
                  backgroundColor: Colors.red.shade700,
                ));
                return;
              }
              setD(() => speichert = true);
              final r = await widget.apiService.inwxAction({
                'action': 'api_kontakt_update',
                'id': int.tryParse(id) ?? 0,
                'name': nameC.text.trim(),
                'org': orgC.text.trim(),
                'street': strasseC.text.trim(),
                'pc': plzC.text.trim(),
                'city': ortC.text.trim(),
                'cc': landC.text.trim().toUpperCase(),
                'voice': tel,
                'email': mailC.text.trim(),
              });
              if (!dCtx.mounted) return;
              if (r['success'] == true) {
                Navigator.pop(dCtx, true);
              } else {
                setD(() => speichert = false);
                ScaffoldMessenger.of(dCtx).showSnackBar(SnackBar(
                  content: Text(r['message']?.toString() ?? 'Fehlgeschlagen'),
                  backgroundColor: Colors.red.shade700,
                ));
              }
            },
            child: speichert
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Speichern'),
          ),
        ],
      )),
    );
    if (ok == true) {
      widget.melde('Inhaberdaten geändert');
      await _laden();
    }
  }

  Widget _feld(TextEditingController c, String label, {String? hinweis}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            helperText: hinweis,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      );

  /// Quittieren entfernt die Meldung endgültig aus der Warteschlange —
  /// deshalb eine Rückfrage, nicht nur ein Knopf.
  Future<void> _meldungQuittieren(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Meldung quittieren?', style: TextStyle(fontSize: 15)),
        content: Text(
          '„${m['typ']} · ${m['objekt']}" wird endgültig aus der Warteschlange '
          'der Registry entfernt und ist danach nicht mehr abrufbar.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quittieren')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await widget.apiService.inwxAction({
      'action': 'api_message_ack',
      'id': int.tryParse(m['id']?.toString() ?? '') ?? 0,
    });
    if (!mounted) return;
    if (r['success'] == true) {
      widget.melde('Meldung quittiert');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Fehlgeschlagen', fehler: true);
    }
  }

  // ─── Domain-Einstellungen: Verlängerung, Sperre, jetzt verlängern ───
  Widget _domainKarte() {
    return _block(Icons.language, 'Domain-Einstellungen', Colors.blueGrey, [
      if (_domains.isEmpty)
        Text(_geladen ? 'Keine Domains im Konto.' : '—',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
      for (final d in _domains) _domainZeile(d),
    ]);
  }

  Widget _domainZeile(Map<String, dynamic> d) {
    final name = d['domain']?.toString() ?? '';
    final modus = d['renewal_mode']?.toString() ?? '';
    final laeuft = _arbeitet == name;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(Colors.blueGrey, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
          Text('läuft ab ${inwxDatumDeutsch(d['ablauf']?.toString() ?? '')}',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          if (laeuft) ...[
            const SizedBox(width: 8),
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 150, child: Text('Verlängerung', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
          Expanded(child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: kInwxRenewalModi.containsKey(modus) ? modus : null,
            isDense: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: [for (final e in kInwxRenewalModi.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))],
            onChanged: laeuft ? null : (v) {
              if (v == null || v == modus) return;
              _domainAendern(name, {'renewal_mode': v},
                  'Verlängerungsmodus auf „${kInwxRenewalModi[v]}" setzen?',
                  v == 'AUTODELETE' || v == 'AUTOEXPIRE'
                      ? 'Damit läuft $name am Ablaufdatum aus. Danach ist sie für jeden frei registrierbar.'
                      : 'Die Domain wird künftig automatisch verlängert.');
            },
          )),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(width: 150, child: Text('Transfersperre', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
          Switch(
            value: d['transferlock'] == true,
            activeThumbColor: Colors.green.shade600,
            onChanged: laeuft ? null : (v) => _domainAendern(name, {'transfer_lock': v},
                v ? 'Transfersperre einschalten?' : 'Transfersperre ausschalten?',
                v
                    ? 'Niemand kann $name zu einem anderen Anbieter umziehen.'
                    : 'Ohne Sperre kann $name mit dem AuthInfo-Code umgezogen werden. '
                      'Nur ausschalten, wenn ein Umzug wirklich geplant ist.'),
          ),
          Expanded(child: Text(
            d['transferlock'] == true ? 'gesperrt — Umzug nicht möglich' : 'offen — Umzug möglich',
            style: TextStyle(fontSize: 11, color: d['transferlock'] == true ? F.h(Colors.green, 700) : F.h(Colors.orange, 800)),
          )),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.event_repeat, size: 15),
            label: const Text('Jetzt verlängern …', style: TextStyle(fontSize: 12)),
            onPressed: laeuft ? null : () => _verlaengern(name),
          ),
        ),
      ]),
    );
  }

  /// Erst die Probe bei INWX, dann eine Rückfrage im Klartext, dann echt.
  Future<void> _domainAendern(String domain, Map<String, dynamic> aenderung,
                              String frage, String folge) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(frage, style: const TextStyle(fontSize: 15)),
        content: Text(folge, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade600),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Ausführen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _arbeitet = domain);
    final r = await widget.apiService.inwxAction({
      'action': 'api_domain_update',
      'domain': domain,
      ...aenderung,
    });
    if (!mounted) return;
    setState(() => _arbeitet = null);
    if (r['success'] == true) {
      widget.melde('Gespeichert');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Fehlgeschlagen', fehler: true);
    }
  }

  /// Verlängern kostet Geld — deshalb zuerst eine reine Probe, die den Preis
  /// liefert, und erst nach ausdrücklicher Bestätigung die echte Buchung.
  Future<void> _verlaengern(String domain) async {
    setState(() => _arbeitet = domain);
    final probe = await widget.apiService.inwxAction({
      'action': 'api_domain_renew',
      'domain': domain,
      'periode': '1Y',
      'nur_probe': true,
    });
    if (!mounted) return;
    setState(() => _arbeitet = null);

    if (probe['success'] != true) {
      // Der häufigste Grund ist fehlendes Guthaben — die Meldung von INWX
      // sagt das deutlicher, als eine eigene Formulierung es könnte.
      widget.melde(probe['message']?.toString() ?? 'Verlängerung nicht möglich', fehler: true);
      return;
    }

    final preis = probe['preis'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Domain um ein Jahr verlängern?', style: TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(domain, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text(preis == null
                  ? 'INWX hat die Probe angenommen, aber keinen Preis genannt.'
                  : 'Kosten laut Probe: $preis ${probe['waehrung'] ?? ''}',
              style: const TextStyle(fontSize: 13)),
          if (probe['altes_ablauf'] != null)
            Text('bisher bis ${inwxDatumDeutsch(probe['altes_ablauf'].toString())}',
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 8),
          Text('Der Betrag wird vom Guthaben abgebucht.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kostenpflichtig verlängern'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _arbeitet = domain);
    final r = await widget.apiService.inwxAction({
      'action': 'api_domain_renew',
      'domain': domain,
      'periode': '1Y',
      'nur_probe': false,
    });
    if (!mounted) return;
    setState(() => _arbeitet = null);
    if (r['success'] == true) {
      widget.melde('Verlängert bis ${inwxDatumDeutsch(r['neues_ablauf']?.toString() ?? '')}');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Verlängerung fehlgeschlagen', fehler: true);
    }
  }

  /// Ein Kontakt, der noch an einer Domain hängt, lässt sich nicht löschen —
  /// INWX weist das ab. `verwendet` sagt uns das vorher, also sagen wir es
  /// auch vorher, statt einen Fehlercode zu zeigen.
  Future<void> _kontaktLoeschen(Map<String, dynamic> k) async {
    final id = k['id']?.toString() ?? '';
    final verwendet = (k['verwendet'] as num?)?.toInt() ?? 0;
    if (id.isEmpty) return;
    if (verwendet > 0) {
      widget.melde(
        'Dieser Kontakt ist noch bei $verwendet Domain(s) eingetragen und kann '
        'deshalb nicht gelöscht werden. Erst dort einen anderen Inhaber eintragen.',
        fehler: true,
      );
      return;
    }
    final bestaetigt = await inwxTippBestaetigung(
      context: context,
      titel: 'Kontakt-Handle löschen?',
      erklaerung: '„${k['org']} · ${k['name']}" (Handle $id) wird bei INWX gelöscht. '
                  'Das lässt sich nicht rückgängig machen.',
      wort: id,
      knopf: 'Löschen',
    );
    if (bestaetigt == null || !mounted) return;
    final r = await widget.apiService.inwxAction({
      'action': 'api_kontakt_delete',
      'id': int.tryParse(id) ?? 0,
      'bestaetigung': bestaetigt,
    });
    if (!mounted) return;
    if (r['success'] == true) {
      widget.melde('Kontakt gelöscht');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Fehlgeschlagen', fehler: true);
    }
  }

  /// ⚠️ `accounting.refund` kennt als einzige Schreibmethode KEIN `testing`.
  /// Es gibt also keine Probe — der Aufruf wirkt sofort.
  Future<void> _erstatten(Map<String, dynamic> b) async {
    final betrag = (b['betrag'] as num?)?.toDouble() ?? 0;
    final nummer = b['id']?.toString() ?? '';
    if (nummer.isEmpty) {
      widget.melde('Zu dieser Buchung liefert INWX keine Nummer — Erstattung nur im Kundencenter.', fehler: true);
      return;
    }
    final bestaetigt = await inwxTippBestaetigung(
      context: context,
      titel: 'Guthaben erstatten?',
      erklaerung: 'Die Einzahlung „${b['art']} · ${b['details']}" über $betrag € wird '
                  'zurückerstattet. Diese Aktion kennt bei INWX keine Probe — sie '
                  'wirkt sofort. Danach steht das Guthaben nicht mehr für '
                  'Verlängerungen zur Verfügung.',
      wort: nummer,
      knopf: 'Erstatten',
    );
    if (bestaetigt == null || !mounted) return;
    final r = await widget.apiService.inwxAction({
      'action': 'api_refund',
      'credit_log_id': int.tryParse(nummer) ?? 0,
      'betrag': betrag,
      'bestaetigung': bestaetigt,
    });
    if (!mounted) return;
    if (r['success'] == true) {
      widget.melde('Erstattung veranlasst');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Fehlgeschlagen', fehler: true);
    }
  }

  // ─── Unumkehrbares ───

  /// Zugeklappt, weil hier nichts liegt, was man im Vorbeigehen braucht.
  /// Jede Aktion verlangt zusätzlich den abgetippten Domainnamen.
  Widget _gefaehrlichKarte() {
    return Container(
      decoration: BoxDecoration(
        color: F.h(Colors.red, 50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: F.h(Colors.red, 200)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(Icons.dangerous, size: 20, color: F.h(Colors.red, 700)),
          title: Text('Unumkehrbares',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.red, 800))),
          subtitle: Text('Umzug, Inhaberwechsel, Abschalten, Löschen',
              style: TextStyle(fontSize: 11, color: F.h(Colors.red, 700))),
          children: [
            _hinweis(Icons.info_outline, Colors.red,
                'Diese Aktionen lassen sich nicht zurücknehmen. Jede verlangt, dass '
                'der Domainname abgetippt wird — ein Fehlklick allein löst nichts aus.'),
            const SizedBox(height: 10),
            for (final d in _domains) _gefaehrlichZeile(d),
          ],
        ),
      ),
    );
  }

  Widget _gefaehrlichZeile(Map<String, dynamic> d) {
    final name = d['domain']?.toString() ?? '';
    final laeuft = _arbeitet == name;
    final aufHold = (d['status']?.toString() ?? '').toUpperCase().contains('HOLD');

    Widget knopf(IconData icon, String text, VoidCallback? bei, {Color? farbe}) => OutlinedButton.icon(
          icon: Icon(icon, size: 15, color: farbe),
          label: Text(text, style: TextStyle(fontSize: 11, color: farbe)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: (farbe ?? Colors.red).withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
          ),
          onPressed: laeuft ? null : bei,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
          if (laeuft) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          knopf(Icons.key, 'AuthInfo-Code', () => _authInfo(name), farbe: Colors.orange.shade800),
          knopf(aufHold ? Icons.play_circle : Icons.pause_circle,
                aufHold ? 'Wieder aktivieren' : 'Abschalten (ClientHold)',
                () => _hold(name, !aufHold), farbe: Colors.orange.shade800),
          knopf(Icons.how_to_reg, 'Inhaberwechsel', () => _inhaberwechsel(name)),
          knopf(Icons.forward_to_inbox, 'Umzug freigeben', () => _transferOut(name, true)),
          knopf(Icons.block, 'Umzug ablehnen', () => _transferOut(name, false), farbe: Colors.blueGrey.shade700),
          knopf(Icons.move_down, 'An anderes Konto', () => _push(name)),
          knopf(Icons.delete_forever, 'Domain löschen', () => _domainLoeschen(name)),
        ]),
      ]),
    );
  }

  Future<void> _riskant(String domain, Map<String, dynamic> anfrage, String titel,
                        String erklaerung, {String knopf = 'Ausführen'}) async {
    final bestaetigt = await inwxTippBestaetigung(
      context: context, titel: titel, erklaerung: erklaerung, wort: domain, knopf: knopf);
    if (bestaetigt == null || !mounted) return;
    setState(() => _arbeitet = domain);
    final r = await widget.apiService.inwxAction({...anfrage, 'domain': domain, 'bestaetigung': bestaetigt});
    if (!mounted) return;
    setState(() => _arbeitet = null);
    if (r['success'] == true) {
      widget.melde(r['message']?.toString() ?? 'Ausgeführt');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Fehlgeschlagen', fehler: true);
    }
  }

  Future<void> _domainLoeschen(String domain) => _riskant(domain, {'action': 'api_domain_delete'},
      'Domain löschen?',
      '$domain wird bei der Registry gelöscht. Web, E-Mail und alles andere '
      'unter diesem Namen hören sofort auf zu funktionieren. Nach der Löschfrist '
      'kann sie jeder registrieren — auch jemand anderes.',
      knopf: 'Endgültig löschen');

  Future<void> _hold(String domain, bool an) => _riskant(domain, {'action': 'api_domain_hold', 'an': an},
      an ? 'Domain abschalten?' : 'Domain wieder aktivieren?',
      an
          ? '$domain wird von der Registry auf ClientHold gesetzt und ist damit '
            'im Netz nicht mehr erreichbar — Web, E-Mail und Chat gleichzeitig. '
            'Die Domain bleibt uns erhalten und lässt sich wieder aktivieren.'
          : '$domain wird bei der Registry wieder freigegeben und ist danach '
            'erreichbar (die Verbreitung im DNS dauert etwas).',
      knopf: an ? 'Abschalten' : 'Aktivieren');

  Future<void> _transferOut(String domain, bool zustimmen) =>
      _riskant(domain, {'action': 'api_domain_transfer_out', 'antwort': zustimmen ? 'ACK' : 'NACK'},
          zustimmen ? 'Umzug freigeben?' : 'Umzug ablehnen?',
          zustimmen
              ? '$domain geht an den anfragenden Anbieter über. Der Verein '
                'verliert die Verwaltung — zurück geht es nur mit einem neuen Umzug.'
              : 'Die Umzugsanfrage für $domain wird abgelehnt. Die Domain bleibt bei uns.',
          knopf: zustimmen ? 'Freigeben' : 'Ablehnen');

  Future<void> _push(String domain) async {
    final zielC = TextEditingController();
    final ziel = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('An anderes INWX-Konto übergeben', style: TextStyle(fontSize: 15)),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$domain wird einem anderen INWX-Kunden übergeben. Ohne Angabe '
               'entscheidet INWX über das Ziel.', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
            controller: zielC,
            decoration: InputDecoration(
              labelText: 'Zielkonto (optional)',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, zielC.text.trim()), child: const Text('Weiter')),
        ],
      ),
    );
    if (ziel == null || !mounted) return;
    await _riskant(domain, {'action': 'api_domain_push', 'ziel': ziel},
        'Domain übergeben?',
        '$domain wechselt in ein anderes INWX-Konto. Der Verein hat danach '
        'keinen Zugriff mehr darauf.',
        knopf: 'Übergeben');
  }

  Future<void> _inhaberwechsel(String domain) async {
    // Nur unsere eigenen Handles kommen als neuer Inhaber in Frage; die
    // Rollenkontakte von INWX gehören uns nicht.
    final eigene = _kontakte.where((k) => k['nur_lesen'] != true).toList();
    if (eigene.isEmpty) {
      widget.melde('Kein eigener Kontakt-Handle vorhanden', fehler: true);
      return;
    }
    final gewaehlt = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Neuer Domaininhaber', style: TextStyle(fontSize: 15)),
        content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ein Inhaberwechsel („Trade") wird bei der Registry eingetragen '
               'und kann kostenpflichtig sein.', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 10),
          for (final k in eigene)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person, size: 18),
              title: Text('${k['org']} · ${k['name']}', style: const TextStyle(fontSize: 13)),
              subtitle: Text('Handle ${k['id']}', style: const TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(c, k['id']?.toString()),
            ),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen'))],
      ),
    );
    if (gewaehlt == null || !mounted) return;
    await _riskant(domain, {'action': 'api_domain_trade', 'registrant': int.tryParse(gewaehlt) ?? 0},
        'Inhaber wechseln?',
        'Der eingetragene Inhaber von $domain wird auf Handle $gewaehlt geändert. '
        'Das ist ein Vorgang bei der Registry und kann Gebühren auslösen.',
        knopf: 'Wechseln');
  }

  /// Der AuthInfo-Code ist der Schlüssel zum Umzug. Er wird EINMAL angezeigt
  /// und nirgends gespeichert — weder in unserer Datenbank noch im Protokoll.
  Future<void> _authInfo(String domain) async {
    final bestaetigt = await inwxTippBestaetigung(
      context: context,
      titel: 'AuthInfo-Code erzeugen?',
      erklaerung: 'Mit diesem Code kann $domain zu einem anderen Anbieter umgezogen '
                  'werden. Er wird einmal angezeigt und nirgends gespeichert. '
                  'Die Erzeugung kann kostenpflichtig sein.',
      wort: domain,
      knopf: 'Erzeugen',
    );
    if (bestaetigt == null || !mounted) return;
    setState(() => _arbeitet = domain);
    final r = await widget.apiService.inwxAction({
      'action': 'api_authinfo2',
      'domain': domain,
      'bestaetigung': bestaetigt,
    });
    if (!mounted) return;
    setState(() => _arbeitet = null);
    if (r['success'] != true) {
      widget.melde(r['message']?.toString() ?? 'Fehlgeschlagen', fehler: true);
      return;
    }
    final code = r['auth_code']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('AuthInfo-Code', style: TextStyle(fontSize: 15)),
        content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(domain, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(height: 10),
          SelectableText(code.isEmpty ? '(INWX hat keinen Code zurückgegeben)' : code,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          const SizedBox(height: 10),
          Text('Jetzt notieren — der Code wird nirgends gespeichert.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.red, 800))),
          if (r['preis'] != null)
            Text('Kosten: ${r['preis']} ${r['waehrung'] ?? ''}',
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
        ])),
        actions: [
          if (code.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Kopieren'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                widget.melde('Code kopiert');
              },
            ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen')),
        ],
      ),
    );
    await _laden();
  }

  // ─── Änderungsprotokoll ───
  Widget _protokollKarte() {
    return _block(Icons.fact_check, 'Unsere Änderungen', Colors.grey, [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Was aus dieser App heraus im Konto geändert wurde — auch abgelehnte '
          'und gescheiterte Versuche. INWX protokolliert nur, was bei der '
          'Registry ankam, nicht wer hier den Knopf gedrückt hat.',
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.history, size: 15),
          label: Text(_aenderungen.isEmpty ? 'Protokoll laden' : 'Neu laden',
              style: const TextStyle(fontSize: 12)),
          onPressed: _protokollLaden,
        ),
      ),
      if (_aenderungen.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final a in _aenderungen) _protokollZeile(a),
      ],
    ]);
  }

  Future<void> _protokollLaden() async {
    final r = await widget.apiService.inwxAction({'action': 'api_aenderungen', 'limit': 50});
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() => _aenderungen = inwxListe(r['aenderungen']));
      if (_aenderungen.isEmpty) widget.melde('Noch keine Änderungen protokolliert');
    } else {
      widget.melde(r['message']?.toString() ?? 'Protokoll nicht abrufbar', fehler: true);
    }
  }

  Widget _protokollZeile(Map<String, dynamic> a) {
    final erg = a['ergebnis']?.toString() ?? '';
    final farbe = erg == 'ok'
        ? Colors.green
        : (erg == 'probe' ? Colors.blue : (erg == 'abgelehnt' ? Colors.orange : Colors.red));
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: F.h(farbe, 50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: farbe.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${kInwxAktionLabel[a['aktion']] ?? a['aktion']} · ${a['objekt'] ?? ''}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(farbe, 800)))),
          Text(a['zeitpunkt']?.toString() ?? '', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
        ]),
        if ((a['vorher']?.toString() ?? '').isNotEmpty)
          Text('vorher:  ${a['vorher']}',
              style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: F.h(Colors.grey, 700)),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        if ((a['nachher']?.toString() ?? '').isNotEmpty)
          Text('nachher: ${a['nachher']}',
              style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: F.h(Colors.grey, 700)),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        if ((a['meldung']?.toString() ?? '').isNotEmpty)
          Text(a['meldung'].toString(), style: TextStyle(fontSize: 10, color: F.h(farbe, 900))),
      ]),
    );
  }

  // ─── Mitteilungen von INWX ───
  Widget _neuigkeitenKarte() {
    return _block(Icons.campaign, 'Mitteilungen von INWX', Colors.orange, [
      if (_meldungenOffen > 0) ...[
        _hinweis(Icons.mark_email_unread, Colors.orange,
            '$_meldungenOffen unbestätigte Meldung(en) der Registry in der Warteschlange.'),
        if (_meldung != null) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: F.flaeche,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: F.h(Colors.orange, 200)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_meldung!['typ']} · ${_meldung!['objekt']} · ${_meldung!['status']}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              if ((_meldung!['details']?.toString() ?? '').isNotEmpty)
                Text(_meldung!['details'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
              Text(_meldung!['zeitpunkt']?.toString() ?? '',
                  style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.done_all, size: 15),
                  label: const Text('Quittieren', style: TextStyle(fontSize: 12)),
                  onPressed: () => _meldungQuittieren(_meldung!),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
      ],
      if (_neuigkeiten.isEmpty)
        Text(_geladen ? 'Keine Mitteilungen.' : '—',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))
      else
        for (final n in _neuigkeiten)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(n['titel']?.toString() ?? '',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.orange, 900)))),
                Text(inwxDatumDeutsch(n['datum']?.toString() ?? ''),
                    style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
              ]),
              if ((n['text']?.toString() ?? '').isNotEmpty)
                Text(n['text'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
            ]),
          ),
    ]);
  }

  // ─── Bausteine ───

  /// Ein Abschnitt, keine Kachel.
  ///
  /// Vorher war jeder Abschnitt ein farbig gefüllter Kasten mit eigenem Rand —
  /// elf davon untereinander, in elf verschiedenen Farben, die nichts
  /// bedeuteten. Jetzt trägt die Farbe nur noch Bedeutung (rot = Problem,
  /// grün = in Ordnung); die Gliederung machen eine kleine Versalzeile und
  /// eine Haarlinie. Das ist ruhiger und lässt Platz für das, was zählt.
  Widget _block(IconData icon, String titel, MaterialColor farbe, List<Widget> kinder) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: farbe.shade400),
            const SizedBox(width: 7),
            Text(titel.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 0.9, color: Colors.blueGrey.shade500)),
            const SizedBox(width: 12),
            Expanded(child: Container(height: 1, color: F.h(Colors.blueGrey, 100))),
          ]),
          const SizedBox(height: 12),
          ...kinder,
        ],
      );

  /// Kleine Zwischenüberschrift innerhalb eines Abschnitts.
  Widget _untertitel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: F.h(Colors.blueGrey, 700))),
      );

  /// Schlüssel-Wert-Paare zweispaltig, sobald Platz da ist.
  ///
  /// Auf dem Schreibtisch stehen sonst 160 px Beschriftung, 200 px Wert und
  /// 700 px Nichts nebeneinander — und man scrollt durch Leere. Unter 620 px
  /// (Tablet hochkant) bleibt es einspaltig, sonst bricht der Wert um.
  Widget _kvGitter(List<(String, String)> paare) {
    final sichtbar = paare.where((p) => p.$2.trim().isNotEmpty).toList();
    if (sichtbar.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (_, c) {
      final zweispaltig = c.maxWidth >= 620;
      final breite = zweispaltig ? (c.maxWidth - 28) / 2 : c.maxWidth;
      return Wrap(
        spacing: 28,
        runSpacing: 6,
        children: [for (final p in sichtbar) SizedBox(width: breite, child: _kv(p.$1, p.$2))],
      );
    });
  }

  Widget _kv(String k, String v, {IconData? icon}) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 160, child: Text(k, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        Expanded(
          child: icon == null
              ? Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))
              : phoneAwareText(icon, v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _hinweis(IconData icon, MaterialColor farbe, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(farbe, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(farbe, 200)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: F.h(farbe, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: F.h(farbe, 900)))),
        ]),
      );
}

// ═════════════════════ Tab 4: Rechnungen (live) ═════════════════════

/// Die Rechnungen des INWX-Kontos, mit PDF auf Verlangen.
///
/// ⚠️ Eigener Tab, aber **kein** eigener Abruf: die Liste kommt aus demselben
/// `_InwxKontoDaten` wie der Konto-Tab. Ein zweiter Abruf wäre eine zweite
/// Anmeldung bei INWX für denselben Bildschirm.
///
/// Das PDF wird erst beim Antippen geholt (`api_rechnung_pdf`) und landet im
/// temporären Verzeichnis der App. Eine Rechnung, die bei INWX geführt wird,
/// bewahren wir nicht ein zweites Mal auf — die Kopie liefe nur auseinander.
class _RechnungenTab extends StatefulWidget {
  final _InwxKontoDaten daten;
  final void Function(String, {bool fehler}) melde;
  const _RechnungenTab({required this.daten, required this.melde});

  @override
  State<_RechnungenTab> createState() => _RechnungenTabState();
}

class _RechnungenTabState extends State<_RechnungenTab> with AutomaticKeepAliveClientMixin {
  String? _pdfLaeuft;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.daten.addListener(_aktualisieren);
    widget.daten.sicherstellen();
  }

  @override
  void dispose() {
    widget.daten.removeListener(_aktualisieren);
    super.dispose();
  }

  void _aktualisieren() {
    if (mounted) setState(() {});
  }

  String get _waehrung => (widget.daten.konto?['waehrung'] ?? 'EUR').toString();

  /// Beträge einheitlich auf zwei Stellen. INWX liefert 5.97 und 5.9 als
  /// dieselbe Art Zahl — untereinander gelesen sieht das nach zwei
  /// verschiedenen Angaben aus.
  String _geld(dynamic v) => v is num ? v.toStringAsFixed(2) : '–';

  /// Neueste zuerst, wie überall sonst auf diesem Bildschirm.
  List<Map<String, dynamic>> get _sortiert => inwxRechnungenSortiert(widget.daten.rechnungen);

  /// Kennzeichen der Vorschau im selben Ladeanzeiger wie die Rechnungen —
  /// eine Rechnungsnummer kann so nie heißen (sie ist rein numerisch).
  static const _kVorschau = 'vorschau';

  Future<void> _rechnungOeffnen(String nummer) =>
      _pdfHolen(nummer, {'action': 'api_rechnung_pdf', 'nummer': nummer},
          'INWX-Rechnung-$nummer.pdf');

  Future<void> _vorschauOeffnen() {
    final jetzt = DateTime.now();
    return _pdfHolen(
      _kVorschau,
      {'action': 'api_rechnung_vorschau', 'jahr': jetzt.year, 'monat': jetzt.month},
      'INWX-Vorschau-${jetzt.year}-${jetzt.month.toString().padLeft(2, '0')}.pdf',
    );
  }

  /// Ein PDF holen, ablegen, öffnen.
  ///
  /// Rechnung und Vorschau unterscheiden sich nur in Aktion und Dateiname; die
  /// Fehlerbehandlung — samt der Rückmeldung, wohin die Datei gelegt wurde,
  /// wenn kein Betrachter da ist — soll für beide dieselbe sein.
  Future<void> _pdfHolen(String kennung, Map<String, dynamic> anfrage, String dateiname) async {
    setState(() => _pdfLaeuft = kennung);
    try {
      final r = await widget.daten.apiService.inwxAction(anfrage);
      if (r['success'] == true) {
        final bytes = base64Decode(r['pdf_base64'].toString());
        final dir = await getTemporaryDirectory();
        final datei = File('${dir.path}/$dateiname');
        await datei.writeAsBytes(bytes);
        final auf = await OpenFilex.open(datei.path);
        if (auf.type != ResultType.done) widget.melde('Gespeichert unter ${datei.path}');
      } else {
        widget.melde(r['message']?.toString() ?? 'PDF nicht abrufbar', fehler: true);
      }
    } catch (e) {
      widget.melde('PDF konnte nicht geöffnet werden: $e', fehler: true);
    }
    if (mounted) setState(() => _pdfLaeuft = null);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = widget.daten;
    if (d.laeuft && !d.geladen) return const Center(child: CircularProgressIndicator());

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Kopf: Herkunft der Daten und Neu-Abruf ──
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          Icon(Icons.cloud_download, size: 14, color: Colors.blueGrey.shade400),
          const SizedBox(width: 7),
          Expanded(child: Text('LIVE VON INWX',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 0.9, color: Colors.blueGrey.shade400))),
          if (d.laeuft)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              icon: const Icon(Icons.refresh, size: 17),
              tooltip: 'Neu abrufen',
              visualDensity: VisualDensity.compact,
              onPressed: d.laden,
            ),
        ]),
      ),

      if (d.fehler != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _hinweis(Icons.error_outline, Colors.red, d.fehler!),
        ),

      if (d.rechnungen.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _summenband(),
        ),

      Expanded(
        child: RefreshIndicator(
          onRefresh: d.laden,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: _liste(),
          ),
        ),
      ),
    ]);
  }

  /// Was das Jahr gekostet hat — die Frage, mit der man diesen Tab öffnet.
  Widget _summenband() {
    final liste = _sortiert;
    final brutto = inwxSummeFeld(liste, 'brutto');
    final netto = inwxSummeFeld(liste, 'netto');
    final daten = liste
        .map((r) => r['datum']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();

    return Container(
      // ⚠️ `width` ist nötig: die Spalte richtet ihre Kinder links aus, und
      // ein Wrap nimmt sich nur so viel Breite, wie sein Inhalt braucht — das
      // Band endete sonst mitten im Bildschirm, während die Zeilen darunter
      // (die ein Expanded tragen) bis zum Rand gingen.
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Wrap(spacing: 32, runSpacing: 10, children: [
        _bandWert('Rechnungen', '${liste.length}'),
        _bandWert('Summe brutto', '${_geld(brutto)} $_waehrung'),
        _bandWert('davon netto', '${_geld(netto)} $_waehrung'),
        if (daten.isNotEmpty)
          _bandWert('Zeitraum',
              daten.first == daten.last
                  ? inwxDatumDeutsch(daten.first)
                  : '${inwxDatumDeutsch(daten.first)} – ${inwxDatumDeutsch(daten.last)}'),
      ]),
    );
  }

  Widget _bandWert(String label, String wert) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.7, color: Colors.blueGrey.shade400)),
          Text(wert, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );

  /// Was schon bezahlt wurde, wofür es aber noch kein Papier gibt.
  ///
  /// Ohne diesen Abschnitt sieht der Tab nach einer Verlängerung falsch aus:
  /// die Domain läuft ein Jahr länger, das Guthaben ist weg — und in der
  /// Rechnungsliste steht unverändert eine einzige Rechnung von letztem Jahr.
  Widget _offeneKarte(List<Map<String, dynamic>> offen) {
    final summe = inwxSummeFeld(offen, 'preis');
    final gekuerzt = widget.daten.aktivitaetenAnzahl > widget.daten.aktivitaeten.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: F.h(Colors.amber, 50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: F.h(Colors.amber, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.pending_actions, size: 15, color: F.h(Colors.amber, 800)),
          const SizedBox(width: 7),
          Expanded(child: Text('BERECHNET, NOCH OHNE RECHNUNG',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 0.9, color: F.h(Colors.amber, 900)))),
          Text('${_geld(summe)} $_waehrung',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.amber, 900))),
        ]),
        const SizedBox(height: 10),
        for (final a in offen)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: LayoutBuilder(builder: (_, c) {
              final text = Text(
                [
                  inwxDatumDeutsch((a['zeitpunkt']?.toString() ?? '').split(' ').first),
                  a['domain']?.toString() ?? '',
                  a['vorgang']?.toString() ?? '',
                ].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 12),
              );
              final preis = Text('${_geld(a['preis'])} $_waehrung brutto',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600));
              // ⚠️ Auf dem Telefon bricht „RENEWAL SUCCESSFUL" um, und der
              // Betrag stand dann mitten im Satz — zwischen „RENEWAL" und
              // „SUCCESSFUL". Schmal deshalb untereinander.
              if (c.maxWidth < 420) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  text,
                  const SizedBox(height: 2),
                  preis,
                ]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: text),
                const SizedBox(width: 10),
                preis,
              ]);
            }),
          ),
        const SizedBox(height: 8),
        Text(
          'INWX hat diese Vorgänge berechnet, ihnen aber noch keine '
          'Rechnungsnummer zugeordnet — deshalb fehlen sie oben. Die bisherige '
          'Rechnung trug das Datum des Monatsendes: die Registrierung vom 14.08. '
          'erschien auf der Rechnung vom 31.08. Die Beträge sind brutto, so wie '
          'INWX sie im Protokoll führt. Für die Einzahlung selbst gibt es sofort '
          'einen Zahlungsbeleg von INWX — im Tab „Konto" unter Geld ▸ '
          'Guthabenbewegungen.'
          '${gekuerzt ? ' Gezeigt sind nur die neuesten Vorgänge — es können mehr sein.' : ''}',
          style: TextStyle(fontSize: 11, color: F.h(Colors.amber, 900)),
        ),
        const SizedBox(height: 10),
        _vorschauKnopf(),
      ]),
    );
  }

  /// Die Proformarechnung des laufenden Monats.
  ///
  /// ⚠️ Sie heißt hier überall „Vorschau (Proforma)", nie „Rechnung": INWX
  /// druckt selbst darauf, dass sie weder Zahlungsaufforderung ist noch zum
  /// Vorsteuerabzug berechtigt. Als Beleg für die Buchhaltung taugt sie nicht —
  /// als Antwort auf „was steht auf der nächsten Rechnung?" ist sie genau das,
  /// was man sehen will.
  Widget _vorschauKnopf() {
    final laeuft = _pdfLaeuft == _kVorschau;
    // ⚠️ `Flexible`, sonst nimmt sich der Knopf seine natürliche Breite und
    // läuft auf 412 dp um 11 px über den Rand — gemessen beim Rendern, nicht
    // vermutet. Eingeengt bricht die Beschriftung stattdessen um.
    return Row(children: [
      Flexible(
        child: OutlinedButton.icon(
          icon: laeuft
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.preview, size: 16),
          label: const Text('Vorschau des laufenden Monats (Proforma)',
              style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: F.h(Colors.amber, 900),
            side: BorderSide(color: F.h(Colors.amber, 300)),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _pdfLaeuft != null ? null : _vorschauOeffnen,
        ),
      ),
    ]);
  }

  List<Widget> _liste() {
    final d = widget.daten;
    final aus = <Widget>[];

    // Zuerst das, was fehlt — nicht das, was schon da ist.
    final offen = inwxOffenePosten(d.aktivitaeten);
    if (offen.isNotEmpty) {
      aus.add(_offeneKarte(offen));
      aus.add(const SizedBox(height: 22));
    }

    if (d.rechnungen.isEmpty) {
      // ⚠️ Nach einem gescheiterten Abruf steht hier NICHTS über den Bestand.
      // „Keine Rechnungen im Konto" wäre eine Aussage über ein Konto, das wir
      // gar nicht lesen konnten — der Grund steht bereits oben.
      if (d.fehler != null) return aus;
      aus.add(_hinweis(
        Icons.receipt_long,
        Colors.blueGrey,
        d.geladen
            ? 'Keine Rechnungen im Konto. Bei einem Prepaid-Konto entsteht eine '
              'Rechnung erst, wenn eine Leistung abgerechnet wird — eine Einzahlung '
              'allein ist noch keine.'
            : 'Noch nicht abgerufen.',
      ));
      return aus;
    }

    // Nach Jahr gebündelt: eine Domain wird jährlich verlängert, also wächst
    // die Liste Jahr für Jahr um dieselben Posten. Die Jahreszahl davor macht
    // aus einer langen Liste eine Abfolge.
    String? jahr;
    for (final r in _sortiert) {
      final datum = r['datum']?.toString() ?? '';
      final j = datum.length >= 4 ? datum.substring(0, 4) : 'ohne Datum';
      if (j != jahr) {
        // Der Abstand trennt zwei Jahre; vor dem ersten steht keiner. Das
        // richtet sich nach `jahr`, nicht nach `aus`, denn über den
        // Jahresgruppen kann schon die Karte der offenen Posten stehen.
        final erste = jahr == null;
        jahr = j;
        aus.add(Padding(
          padding: EdgeInsets.only(top: erste ? 0 : 16, bottom: 8),
          child: Row(children: [
            Text(j,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: 0.6, color: F.h(Colors.blueGrey, 600))),
            const SizedBox(width: 12),
            Expanded(child: Container(height: 1, color: F.h(Colors.blueGrey, 100))),
          ]),
        ));
      }
      aus.add(_zeile(r));
    }

    if (d.rechnungenAnzahl > d.rechnungen.length) {
      aus.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '… ${d.rechnungenAnzahl} insgesamt, die neuesten ${d.rechnungen.length} sind gezeigt.',
          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: F.h(Colors.grey, 600)),
        ),
      ));
    }

    // Die XML-Fassung (E-Rechnung) liegt bei INWX, wir holen hier das PDF.
    // Erwähnt wird sie nur, wenn es sie gibt — sonst wäre es eine Belehrung
    // über etwas, das gar nicht vorhanden ist.
    if (d.rechnungen.any((r) => r['hat_xml'] == true)) {
      aus.add(Padding(
        padding: const EdgeInsets.only(top: 14),
        child: _hinweis(Icons.code, Colors.blueGrey,
            'Zu diesen Rechnungen liegt bei INWX zusätzlich eine XML-Fassung '
            '(E-Rechnung). Hier wird das PDF geholt; das XML gibt es im '
            'INWX-Kundencenter.'),
      ));
    }

    return aus;
  }

  Widget _zeile(Map<String, dynamic> r) {
    final nummer = r['nummer']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(children: [
        Icon(Icons.description, size: 18, color: Colors.indigo.shade500),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nr. $nummer',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          Text(
            '${inwxDatumDeutsch(r['datum']?.toString() ?? '')} · ${r['art'] ?? ''}',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
          ),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${_geld(r['brutto'])} $_waehrung',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 800))),
          Text('netto ${_geld(r['netto'])} $_waehrung',
              style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
        ]),
        const SizedBox(width: 8),
        _pdfLaeuft == nummer
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                icon: const Icon(Icons.picture_as_pdf, size: 20),
                color: Colors.red.shade600,
                tooltip: 'Rechnung als PDF öffnen',
                onPressed: _pdfLaeuft != null ? null : () => _rechnungOeffnen(nummer),
              ),
      ]),
    );
  }

  Widget _hinweis(IconData icon, MaterialColor farbe, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(farbe, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(farbe, 200)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: F.h(farbe, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: F.h(farbe, 900)))),
        ]),
      );
}

// ═════════════════════ Tab 5: DNS & Zone (live) ═════════════════════

/// Die vollständige Zone aus `nameserver.info` samt DNSSEC-Schlüsseln.
///
/// Nur Anzeige — die API könnte Einträge auch anlegen und löschen, aber ein
/// vertippter DNS-Eintrag nimmt Web, Post und Chat gleichzeitig vom Netz.
/// Das gehört ins Kundencenter, wo es eine Bestätigung gibt.
class _DnsTab extends StatefulWidget {
  final ApiService apiService;
  final void Function(String, {bool fehler}) melde;
  const _DnsTab({required this.apiService, required this.melde});

  @override
  State<_DnsTab> createState() => _DnsTabState();
}

class _DnsTabState extends State<_DnsTab> with AutomaticKeepAliveClientMixin {
  bool _laeuft = false;
  bool _geladen = false;
  String? _fehler;
  List<String> _zonen = [];
  String? _gewaehlt;
  Map<String, dynamic>? _zone;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden([String? domain]) async {
    setState(() {
      _laeuft = true;
      _fehler = null;
    });
    try {
      final r = await widget.apiService.inwxAction({
        'action': 'api_dns',
        if (domain != null) 'domain': domain,
      });
      if (!mounted) return;
      if (r['success'] != true) {
        _fehler = r['message']?.toString() ?? 'Abruf fehlgeschlagen';
      } else if (r['verbunden'] != true) {
        _fehler = r['fehler']?.toString() ?? 'Nicht verbunden';
      } else {
        _zonen = inwxTextListe(r['zonen']);
        _zone = inwxAlsMap(r['zone']);
        _gewaehlt = _zone?['domain']?.toString();
        if (_zone != null && _zone!['fehler'] != null) _fehler = _zone!['fehler'].toString();
      }
    } catch (e) {
      if (mounted) _fehler = 'Fehler: $e';
    }
    if (mounted) {
      setState(() {
        _laeuft = false;
        _geladen = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_laeuft && !_geladen) return const Center(child: CircularProgressIndicator());

    final records = _zone == null ? <Map<String, dynamic>>[] : inwxListe(_zone!['records']);
    final hinweise = _zone == null ? <Map<String, dynamic>>[] : inwxListe(_zone!['hinweise']);
    final dnssec = _zone == null ? <Map<String, dynamic>>[] : inwxListe(_zone!['dnssec_aktiv']);

    // Nach Typ gruppieren — der Server sortiert bereits danach.
    final nachTyp = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      nachTyp.putIfAbsent(r['typ']?.toString() ?? '?', () => []).add(r);
    }

    return RefreshIndicator(
      onRefresh: () => _laden(_gewaehlt),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Icon(Icons.travel_explore, size: 18, color: F.h(Colors.blueGrey, 700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _gewaehlt == null ? 'DNS-Zone' : 'Zone ${_gewaehlt!} · ${records.length} Einträge',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.blueGrey, 800)),
              ),
            ),
            if (_gewaehlt != null && !_laeuft)
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Eintrag', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
                onPressed: () => _eintragDialog(null),
              ),
            const SizedBox(width: 6),
            if (_laeuft)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Neu abrufen',
                onPressed: () => _laden(_gewaehlt),
              ),
          ]),
          if (_zonen.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final z in _zonen)
                ChoiceChip(
                  label: Text(z, style: const TextStyle(fontSize: 11)),
                  selected: z == _gewaehlt,
                  selectedColor: Colors.blueGrey.shade600,
                  onSelected: _laeuft ? null : (_) => _laden(z),
                ),
            ]),
          ],
          if (_fehler != null) ...[
            const SizedBox(height: 10),
            _hinweisBox(Icons.error_outline, Colors.red, _fehler!),
          ],
          if (hinweise.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final h in hinweise)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _hinweisBox(
                  h['stufe'] == 'warnung' ? Icons.warning_amber : Icons.info_outline,
                  h['stufe'] == 'warnung' ? Colors.orange : Colors.blue,
                  h['text']?.toString() ?? '',
                ),
              ),
          ],
          if (_geladen && hinweise.isEmpty && _fehler == null) ...[
            const SizedBox(height: 12),
            _hinweisBox(Icons.check_circle_outline, Colors.green,
                'SPF, DKIM, DMARC, CAA und DNSSEC sind gesetzt — nichts zu beanstanden.'),
          ],
          const SizedBox(height: 14),
          _dnssecKarte(dnssec),
          const SizedBox(height: 14),
          for (final eintrag in nachTyp.entries) ...[
            _typBlock(eintrag.key, eintrag.value),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _dnssecKarte(List<Map<String, dynamic>> aktiv) {
    final abgeloest = (_zone?['dnssec_abgeloest'] as num?)?.toInt() ?? 0;
    final an = aktiv.isNotEmpty;
    final farbe = an ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F.h(farbe, 50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(farbe, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(an ? Icons.lock : Icons.lock_open, size: 16, color: F.h(farbe, 700)),
          const SizedBox(width: 8),
          Text(an ? 'DNSSEC aktiv' : 'DNSSEC nicht aktiv',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(farbe, 800))),
        ]),
        for (final k in aktiv)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              'Key-Tag ${k['key_tag']} · Algorithmus ${k['algorithmus']} · angelegt ${k['angelegt']}',
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: F.h(Colors.grey, 700)),
            ),
          ),
        if (abgeloest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text('$abgeloest abgelöste Schlüssel im Protokoll',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ),
      ]),
    );
  }

  Widget _typBlock(String typ, List<Map<String, dynamic>> eintraege) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: F.h(Colors.blueGrey, 100), borderRadius: BorderRadius.circular(5)),
          child: Text(typ,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.blueGrey, 800))),
        ),
        const SizedBox(width: 8),
        Text('${eintraege.length}', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
      ]),
      const SizedBox(height: 6),
      for (final r in eintraege) _recordZeile(r),
    ]);
  }

  Widget _recordZeile(Map<String, dynamic> r) {
    final inhalt = r['inhalt']?.toString() ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _eintragDialog(r),
      // Ein DKIM-Schlüssel lässt sich nicht abschreiben — langes Drücken
      // kopiert ihn, ohne den Bearbeiten-Weg zu verstellen.
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: inhalt));
        widget.melde('Wert kopiert');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: F.flaeche,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: F.h(Colors.grey, 200)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(r['name']?.toString() ?? '',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
            ),
            if (r['prio'] != null && (r['prio'] as num) != 0)
              Text('Prio ${r['prio']}  ', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
            Text('TTL ${r['ttl'] ?? '–'}', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 500))),
          ]),
          const SizedBox(height: 3),
          Text(inhalt,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: F.h(Colors.blueGrey, 800)),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _hinweisBox(IconData icon, MaterialColor farbe, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(farbe, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(farbe, 200)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: F.h(farbe, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: F.h(farbe, 900)))),
        ]),
      );

  // ─────────────── Anlegen / Ändern / Löschen ───────────────

  /// [vorhanden] null = neuer Eintrag.
  ///
  /// Die Prüfungen laufen hier NUR für die sofortige Rückmeldung mit; die
  /// verbindliche Kontrolle steht auf dem Server, und dahinter noch die
  /// Probe bei INWX. Ein Client, der die Regeln umgeht, kommt nicht durch.
  Future<void> _eintragDialog(Map<String, dynamic>? vorhanden) async {
    final zone = _gewaehlt;
    if (zone == null) return;
    final neu = vorhanden == null;

    var typ = vorhanden?['typ']?.toString() ?? 'A';
    final nameC = TextEditingController(text: vorhanden?['name']?.toString() ?? zone);
    final inhaltC = TextEditingController(text: vorhanden?['inhalt']?.toString() ?? '');
    final ttlC = TextEditingController(text: (vorhanden?['ttl'] ?? 3600).toString());
    final prioC = TextEditingController(text: (vorhanden?['prio'] ?? 0).toString());
    var speichert = false;

    final fertig = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) {
        final brauchtPrio = typ == 'MX' || typ == 'SRV';
        return AlertDialog(
          title: Row(children: [
            Icon(neu ? Icons.add_circle_outline : Icons.edit, size: 18, color: F.h(Colors.blueGrey, 700)),
            const SizedBox(width: 8),
            Text(neu ? 'DNS-Eintrag anlegen' : 'DNS-Eintrag ändern', style: const TextStyle(fontSize: 15)),
          ]),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: kInwxRecordTypen.contains(typ) ? typ : 'A',
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Typ',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [for (final t in kInwxRecordTypen)
                    DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))],
                  onChanged: (v) => setD(() => typ = v ?? 'A'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameC,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    helperText: 'muss auf $zone enden',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: inhaltC,
                  maxLines: typ == 'TXT' ? 3 : 1,
                  decoration: InputDecoration(
                    labelText: 'Wert',
                    hintText: inwxWertBeispiel(typ),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(
                    controller: ttlC,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'TTL (Sekunden)',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
                  if (brauchtPrio) ...[
                    const SizedBox(width: 10),
                    Expanded(child: TextField(
                      controller: prioC,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Priorität',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )),
                  ],
                ]),
                const SizedBox(height: 10),
                _hinweisBox(Icons.info_outline, Colors.blue,
                    'Die Änderung wird zuerst als Probe an INWX geschickt. Erst wenn die '
                    'durchgeht, wird sie wirklich ausgeführt.'),
              ]),
            ),
          ),
          actions: [
            if (!neu)
              TextButton.icon(
                icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade500),
                label: Text('Löschen', style: TextStyle(fontSize: 13, color: F.h(Colors.red, 600))),
                onPressed: speichert ? null : () async {
                  final ok = await _loeschenBestaetigen(vorhanden);
                  if (ok && dCtx.mounted) Navigator.pop(dCtx, true);
                },
              ),
            TextButton(onPressed: speichert ? null : () => Navigator.pop(dCtx, false), child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade600),
              onPressed: speichert ? null : () async {
                final mangel = inwxRecordPruefen(
                  typ: typ,
                  name: nameC.text.trim(),
                  inhalt: inhaltC.text.trim(),
                  ttl: int.tryParse(ttlC.text.trim()) ?? 0,
                  zone: zone,
                );
                if (mangel.isNotEmpty) {
                  ScaffoldMessenger.of(dCtx).showSnackBar(SnackBar(
                    content: Text(mangel.join('\n')),
                    backgroundColor: Colors.red.shade700,
                  ));
                  return;
                }
                setD(() => speichert = true);
                final r = await widget.apiService.inwxAction({
                  'action': 'api_dns_speichern',
                  'domain': zone,
                  if (!neu) 'id': vorhanden['id'],
                  'name': nameC.text.trim(),
                  'typ': typ,
                  'inhalt': inhaltC.text.trim(),
                  'ttl': int.tryParse(ttlC.text.trim()) ?? 3600,
                  'prio': brauchtPrio ? (int.tryParse(prioC.text.trim()) ?? 0) : 0,
                });
                if (!dCtx.mounted) return;
                if (r['success'] == true) {
                  Navigator.pop(dCtx, true);
                } else {
                  setD(() => speichert = false);
                  ScaffoldMessenger.of(dCtx).showSnackBar(SnackBar(
                    content: Text(r['message']?.toString() ?? 'Fehlgeschlagen'),
                    backgroundColor: Colors.red.shade700,
                  ));
                }
              },
              child: speichert
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(neu ? 'Anlegen' : 'Speichern'),
            ),
          ],
        );
      }),
    );

    if (fertig == true) {
      widget.melde('Zone geändert');
      await _laden(zone);
    }
  }

  Future<bool> _loeschenBestaetigen(Map<String, dynamic> r) async {
    final zone = _gewaehlt;
    if (zone == null) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('DNS-Eintrag löschen?', style: TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['typ']}  ${r['name']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text(r['inhalt']?.toString() ?? '',
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: F.h(Colors.grey, 700))),
          const SizedBox(height: 12),
          Text('Ein gelöschter Eintrag lässt sich nur von Hand wieder anlegen — '
               'der genaue Wert steht danach nirgends mehr außer im Änderungsprotokoll.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    final res = await widget.apiService.inwxAction({
      'action': 'api_dns_loeschen',
      'domain': zone,
      'id': r['id'],
    });
    if (res['success'] != true) {
      widget.melde(res['message']?.toString() ?? 'Löschen fehlgeschlagen', fehler: true);
      return false;
    }
    return true;
  }
}

// ═══════════════════════ Tab 6: Zugang & API ═══════════════════════

class _ZugangTab extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> data;
  final Future<void> Function() onSaved;
  final void Function(List<Map<String, dynamic>>) onLeistungen;
  final void Function(String, {bool fehler}) melde;
  final Future<void> Function(String) oeffne;
  final String Function(String) lies;

  const _ZugangTab({
    required this.apiService,
    required this.data,
    required this.onSaved,
    required this.onLeistungen,
    required this.melde,
    required this.oeffne,
    required this.lies,
  });

  @override
  State<_ZugangTab> createState() => _ZugangTabState();
}

class _ZugangTabState extends State<_ZugangTab> {
  late final TextEditingController _urlC;
  late final TextEditingController _userC;
  final _passC = TextEditingController();
  bool _bearbeiten = false;
  bool _passSichtbar = false;
  bool _laeuft = false;

  Map<String, dynamic>? _status;
  List<Map<String, dynamic>>? _domains;

  @override
  void initState() {
    super.initState();
    _urlC = TextEditingController(text: widget.lies('zugang.url'));
    _userC = TextEditingController(text: widget.lies('api.user'));
  }

  @override
  void dispose() {
    _urlC.dispose();
    _userC.dispose();
    _passC.dispose();
    super.dispose();
  }

  bool get _passGesetzt => widget.lies('api.pass_gesetzt') == '1';

  Future<void> _speichern() async {
    final daten = <String, dynamic>{
      'zugang.url': _urlC.text.trim(),
      'api.user': _userC.text.trim(),
    };
    // Ein leeres Passwortfeld heißt „unverändert", nicht „löschen" — sonst
    // träte jedes Speichern der URL den API-Zugang tot.
    if (_passC.text.isNotEmpty) daten['api.pass'] = _passC.text;
    final r = await widget.apiService.inwxAction({'action': 'save_data', 'data': daten});
    if (r['success'] == true) {
      _passC.clear();
      setState(() => _bearbeiten = false);
      await widget.onSaved();
      widget.melde('Zugang gespeichert');
    } else {
      widget.melde('Speichern fehlgeschlagen', fehler: true);
    }
  }

  Future<void> _passAnzeigen() async {
    final r = await widget.apiService.inwxAction({'action': 'reveal_pass'});
    if (r['success'] == true && mounted) {
      setState(() {
        _passC.text = (r['pass'] ?? '').toString();
        _passSichtbar = true;
      });
    }
  }

  /// Kontopasswort wechseln.
  ///
  /// ⚠️ Das ist DAS Konto-Passwort — es gilt auch für den Login im
  /// Kundencenter, nicht nur für die API.
  ///
  /// Damit wir uns nicht selbst aussperren, legt der Server das neue Passwort
  /// VOR dem Wechsel als „wartend" ab und schaltet erst nach Erfolg um.
  /// Bricht etwas dazwischen ab, hat INWX schon das neue und wir noch das
  /// alte — dann probiert die nächste Anmeldung das wartende Passwort und
  /// übernimmt es. Der Nutzer merkt davon nichts, und genau deshalb steht es
  /// im Hinweistext: wer es doch merkt, soll wissen, dass es Absicht war.
  Future<void> _passwortWechseln() async {
    final neuC = TextEditingController();
    final wdhC = TextEditingController();
    var sichtbar = false;
    var laeuft = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) => AlertDialog(
        title: Row(children: [
          Icon(Icons.password, size: 18, color: F.h(Colors.orange, 800)),
          const SizedBox(width: 8),
          const Text('Kontopasswort wechseln', style: TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: F.h(Colors.orange, 50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: F.h(Colors.orange, 200)),
              ),
              child: Text(
                'Das neue Passwort gilt auch für den Login im INWX-Kundencenter, '
                'nicht nur für die App. Es wird hier sofort mitgespeichert — der '
                'nächste Abruf läuft damit weiter, ohne dass jemand etwas nachtragen muss.',
                style: TextStyle(fontSize: 12, color: F.h(Colors.orange, 900)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: neuC,
              obscureText: !sichtbar,
              autofocus: true,
              onChanged: (_) => setD(() {}),
              decoration: InputDecoration(
                labelText: 'Neues Passwort',
                helperText: 'mindestens 12 Zeichen',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: IconButton(
                  icon: Icon(sichtbar ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setD(() => sichtbar = !sichtbar),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: wdhC,
              obscureText: !sichtbar,
              onChanged: (_) => setD(() {}),
              decoration: InputDecoration(
                labelText: 'Wiederholen',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                errorText: wdhC.text.isNotEmpty && wdhC.text != neuC.text
                    ? 'Stimmt nicht überein'
                    : null,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: laeuft ? null : () => Navigator.pop(dCtx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: (laeuft || neuC.text.length < 12 || neuC.text != wdhC.text)
                ? null
                : () async {
                    setD(() => laeuft = true);
                    final r = await widget.apiService.inwxAction({
                      'action': 'api_passwort_aendern',
                      'neu': neuC.text,
                    });
                    if (!dCtx.mounted) return;
                    if (r['success'] == true) {
                      Navigator.pop(dCtx, true);
                    } else {
                      setD(() => laeuft = false);
                      ScaffoldMessenger.of(dCtx).showSnackBar(SnackBar(
                        content: Text(r['message']?.toString() ?? 'Fehlgeschlagen'),
                        backgroundColor: Colors.red.shade700,
                      ));
                    }
                  },
            child: laeuft
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Wechseln'),
          ),
        ],
      )),
    );

    if (ok == true) {
      widget.melde('Passwort gewechselt — gilt auch fürs Kundencenter');
      // Ein bereits aufgedecktes altes Passwort darf nicht stehen bleiben.
      setState(() {
        _passC.clear();
        _passSichtbar = false;
      });
      await widget.onSaved();
    }
  }

  Future<void> _mitLadebalken(Future<void> Function() arbeit) async {
    setState(() => _laeuft = true);
    try {
      await arbeit();
    } catch (e) {
      widget.melde('Fehler: $e', fehler: true);
    }
    if (mounted) setState(() => _laeuft = false);
  }

  Future<void> _test() => _mitLadebalken(() async {
        final r = await widget.apiService.inwxAction({'action': 'api_status'});
        if (!mounted) return;
        setState(() => _status = r['success'] == true ? Map<String, dynamic>.from(r) : null);
        if (r['success'] != true) {
          widget.melde(r['message']?.toString() ?? 'Verbindung fehlgeschlagen', fehler: true);
        } else if (r['verbunden'] != true) {
          widget.melde(r['fehler']?.toString() ?? 'Nicht verbunden', fehler: true);
        } else {
          widget.melde('Verbunden mit INWX');
        }
      });

  Future<void> _domainsLaden() => _mitLadebalken(() async {
        final r = await widget.apiService.inwxAction({'action': 'api_domains'});
        if (!mounted) return;
        if (r['success'] == true) {
          setState(() => _domains = inwxListe(r['domains']));
          widget.melde('${_domains!.length} Domain(s) abgerufen');
        } else {
          widget.melde(r['message']?.toString() ?? 'Abruf fehlgeschlagen', fehler: true);
        }
      });

  Future<void> _importieren() => _mitLadebalken(() async {
        final r = await widget.apiService.inwxAction({'action': 'api_import'});
        if (!mounted) return;
        if (r['success'] == true) {
          if (r['leistungen'] is List) widget.onLeistungen(inwxListe(r['leistungen']));
          widget.melde('${r['neu'] ?? 0} neu, ${r['aktualisiert'] ?? 0} aktualisiert');
        } else {
          widget.melde(r['message']?.toString() ?? 'Übernahme fehlgeschlagen', fehler: true);
        }
      });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ─── Zugangsdaten ───
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: F.h(Colors.blueGrey, 50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: F.h(Colors.blueGrey, 200)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.vpn_key, size: 20, color: F.h(Colors.blueGrey, 700)),
              const SizedBox(width: 10),
              Expanded(child: Text('Konto- und API-Zugang',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: F.h(Colors.blueGrey, 800)))),
              TextButton.icon(
                icon: Icon(_bearbeiten ? Icons.lock : Icons.edit, size: 15),
                label: Text(_bearbeiten ? 'Sperren' : 'Bearbeiten', style: const TextStyle(fontSize: 12)),
                onPressed: () => setState(() {
                  _bearbeiten = !_bearbeiten;
                  if (!_bearbeiten) {
                    _passC.clear();
                    _passSichtbar = false;
                  }
                }),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _urlC,
              readOnly: !_bearbeiten,
              decoration: InputDecoration(
                labelText: 'Login-URL',
                prefixIcon: const Icon(Icons.link, size: 18),
                isDense: true,
                filled: !_bearbeiten,
                fillColor: !_bearbeiten ? F.h(Colors.grey, 100) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _userC,
              readOnly: !_bearbeiten,
              decoration: InputDecoration(
                labelText: 'Benutzername',
                prefixIcon: const Icon(Icons.person, size: 18),
                isDense: true,
                filled: !_bearbeiten,
                fillColor: !_bearbeiten ? F.h(Colors.grey, 100) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passC,
              readOnly: !_bearbeiten && !_passSichtbar,
              obscureText: !_passSichtbar,
              decoration: InputDecoration(
                labelText: 'Passwort',
                hintText: _passGesetzt && _passC.text.isEmpty ? 'hinterlegt — leer lassen, um es zu behalten' : null,
                prefixIcon: const Icon(Icons.lock, size: 18),
                isDense: true,
                filled: !_bearbeiten,
                fillColor: !_bearbeiten ? F.h(Colors.grey, 100) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _passSichtbar
                    ? IconButton(
                        icon: const Icon(Icons.visibility_off, size: 18),
                        tooltip: 'Verbergen',
                        onPressed: () => setState(() {
                          _passSichtbar = false;
                          if (!_bearbeiten) _passC.clear();
                        }),
                      )
                    : (_passGesetzt
                        ? IconButton(
                            icon: const Icon(Icons.visibility, size: 18),
                            tooltip: 'Passwort anzeigen',
                            onPressed: _passAnzeigen,
                          )
                        : null),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.info_outline, size: 13, color: F.h(Colors.grey, 600)),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'Das Konto-Passwort wird verschlüsselt gespeichert und nur auf ausdrücklichen '
                'Abruf angezeigt — wer es hat, kann die Domain transferieren.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
              )),
            ]),
            if (_bearbeiten) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Speichern'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  onPressed: _speichern,
                ),
              ),
            ],
            const Divider(height: 26),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: Icon(Icons.password, size: 15, color: F.h(Colors.orange, 800)),
                label: Text('Kontopasswort wechseln …',
                    style: TextStyle(fontSize: 12, color: F.h(Colors.orange, 900))),
                style: OutlinedButton.styleFrom(side: BorderSide(color: F.h(Colors.orange, 300))),
                onPressed: _passwortWechseln,
              ),
            ),
            const Divider(height: 26),
            Row(children: [
              Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 15),
                  label: const Text('Kundencenter', style: TextStyle(fontSize: 12)),
                  onPressed: () => widget.oeffne(_urlC.text.trim()),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.menu_book, size: 15),
                  label: const Text('API-Doku', style: TextStyle(fontSize: 12)),
                  onPressed: () => widget.oeffne(widget.lies('api.doku_url')),
                ),
              ])),
            ]),
            const SizedBox(height: 6),
            Text('Endpunkt: ${widget.lies('api.endpoint')}',
                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: F.h(Colors.grey, 600))),
          ]),
        ),

        const SizedBox(height: 16),

        // ─── API-Aktionen ───
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: F.h(Colors.indigo, 50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: F.h(Colors.indigo, 200)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.api, size: 20, color: F.h(Colors.indigo, 700)),
              const SizedBox(width: 10),
              Text('DomRobot-API',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 800))),
              const Spacer(),
              if (_laeuft) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                icon: const Icon(Icons.wifi_tethering, size: 16),
                label: const Text('Verbindung testen', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600),
                onPressed: _laeuft ? null : _test,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.dns, size: 16),
                label: const Text('Domains abrufen', style: TextStyle(fontSize: 12)),
                onPressed: _laeuft ? null : _domainsLaden,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Als Leistungen übernehmen', style: TextStyle(fontSize: 12)),
                onPressed: _laeuft ? null : _importieren,
              ),
            ]),
            if (_status != null) ...[const SizedBox(height: 14), _statusBlock()],
            if (_domains != null) ...[const SizedBox(height: 14), _domainBlock()],
          ]),
        ),
      ]),
    );
  }

  Widget _statusBlock() {
    final s = _status!;
    if (s['verbunden'] != true) {
      return _hinweis(Icons.error_outline, Colors.red, s['fehler']?.toString() ?? 'Nicht verbunden');
    }
    final k = inwxAlsMap(s['konto']) ?? const <String, dynamic>{};
    final g = inwxAlsMap(s['guthaben']);
    final waehrung = (g?['waehrung'] ?? k['waehrung'] ?? 'EUR').toString();
    final verfuegbar = g?['available'];
    final prepaid = (k['zahlungsart']?.toString() ?? '').toLowerCase() == 'prepaid';
    final knapp = prepaid && verfuegbar is num && verfuegbar <= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.indigo, 200))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle, size: 16, color: F.h(Colors.green, 700)),
          const SizedBox(width: 6),
          Text('Verbunden', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.green, 800))),
        ]),
        const SizedBox(height: 8),
        _kv('Benutzer', k['username']?.toString() ?? ''),
        _kv('Kundennummer', k['kundennummer']?.toString() ?? ''),
        _kv('Inhaber', k['org']?.toString() ?? ''),
        _kv('E-Mail', k['email']?.toString() ?? ''),
        _kv('Zahlungsart', k['zahlungsart']?.toString() ?? ''),
        _kv('Verlängerung', k['renewal_mode']?.toString() ?? ''),
        _kv('Zwei-Faktor', k['zwei_fa'] == true ? 'aktiv' : 'nicht aktiv'),
        if (g != null) ...[
          const Divider(height: 18),
          _kv('Guthaben gesamt', g['total'] == null ? '–' : '${g['total']} $waehrung'),
          _kv('davon verfügbar', verfuegbar == null ? '–' : '$verfuegbar $waehrung'),
          if (g['locked'] != null && (g['locked'] as num) != 0) _kv('reserviert', '${g['locked']} $waehrung'),
        ],
        if (knapp) ...[
          const SizedBox(height: 10),
          _hinweis(
            Icons.warning_amber,
            Colors.red,
            'Prepaid-Konto ohne verfügbares Guthaben. Eine automatische Verlängerung '
            'kann so scheitern — vor dem nächsten Ablaufdatum aufladen.',
          ),
        ],
      ]),
    );
  }

  Widget _domainBlock() {
    final d = _domains!;
    if (d.isEmpty) return _hinweis(Icons.info_outline, Colors.grey, 'Keine Domains im Konto.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${d.length} Domain(s) im Konto',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 800))),
      const SizedBox(height: 6),
      for (final x in d)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade100)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.language, size: 15, color: F.h(Colors.indigo, 600)),
              const SizedBox(width: 6),
              Expanded(child: Text(x['domain']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
              if (x['transferlock'] == true)
                Icon(Icons.lock, size: 13, color: F.h(Colors.green, 600)),
            ]),
            const SizedBox(height: 4),
            Text(
              'Ablauf ${x['ablauf'] ?? '–'} · ${x['renewal_mode'] ?? ''}'
              '${(x['nameserver'] as List?)?.isNotEmpty == true ? '\nNS: ${(x['nameserver'] as List).join(', ')}' : ''}',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
            ),
          ]),
        ),
    ]);
  }

  Widget _kv(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(k, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _hinweis(IconData icon, MaterialColor farbe, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(farbe, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(farbe, 200)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: F.h(farbe, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: F.h(farbe, 900)))),
        ]),
      );
}

// ═══════════════════ Tab 7: Korrespondenz ═══════════════════

const Map<String, String> _kWegLabel = {
  'email': 'E-Mail', 'anruf': 'Anruf', 'online': 'Online',
  'fax': 'Fax', 'post': 'Post', 'persoenlich': 'Persönlich',
};
const Map<String, IconData> _kWegIcon = {
  'email': Icons.mail_outline, 'anruf': Icons.phone, 'online': Icons.language,
  'fax': Icons.print, 'post': Icons.markunread_mailbox_outlined, 'persoenlich': Icons.people_outline,
};

/// Post von und an INWX — genauso aufgebaut wie Finanzamt ▸ Korrespondenz,
/// mit demselben Import: was an inwx@icd360s.de eingeht, landet hier von
/// selbst (Cron, jede Minute).
///
/// ⚠️ Der Eintrag hängt danach nicht mehr an der Mail. Betreff, Absender und
/// Empfänger stehen verschlüsselt in unserer Tabelle, die vollständige
/// Originalnachricht als .eml auf unserer Platte. Wer die Mail im
/// Mailprogramm löscht, löscht hier nichts — nachgewiesen mit einer
/// Probenachricht, die nach dem Import aus dem Postfach entfernt wurde und
/// deren Eintrag samt Volltext danach noch lesbar war.
class _KorrespondenzTab extends StatefulWidget {
  final ApiService apiService;
  final void Function(String, {bool fehler}) melde;
  const _KorrespondenzTab({required this.apiService, required this.melde});

  @override
  State<_KorrespondenzTab> createState() => _KorrespondenzTabState();
}

class _KorrespondenzTabState extends State<_KorrespondenzTab>
    with AutomaticKeepAliveClientMixin {
  static const String _modul = 'inwx';

  bool _laeuft = true;
  List<Map<String, dynamic>> _eintraege = [];
  String _filterRichtung = '';
  String _filterWeg = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _laeuft = true);
    try {
      final r = await widget.apiService.getVereinKorrespondenz(
        richtung: _filterRichtung.isEmpty ? null : _filterRichtung,
        weg: _filterWeg.isEmpty ? null : _filterWeg,
        modul: _modul,
      );
      if (!mounted) return;
      if (r['success'] == true) {
        final d = r['data'] ?? r;
        _eintraege = inwxListe((d is Map ? d['korrespondenz'] : null) ?? r['korrespondenz']);
      } else {
        widget.melde(r['message']?.toString() ?? 'Korrespondenz nicht abrufbar', fehler: true);
      }
    } catch (e) {
      if (mounted) widget.melde('Fehler: $e', fehler: true);
    }
    if (mounted) setState(() => _laeuft = false);
  }

  void _filtern(String richtung, String weg) {
    setState(() {
      _filterRichtung = richtung;
      _filterWeg = weg;
    });
    _laden();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('Alle', _filterRichtung.isEmpty && _filterWeg.isEmpty, () => _filtern('', '')),
                const SizedBox(width: 6),
                _chip('↓ Eingang', _filterRichtung == 'eingang', () => _filtern('eingang', _filterWeg)),
                const SizedBox(width: 6),
                _chip('↑ Ausgang', _filterRichtung == 'ausgang', () => _filtern('ausgang', _filterWeg)),
                const SizedBox(width: 14),
                for (final w in _kWegLabel.keys) ...[
                  ChoiceChip(
                    avatar: Icon(_kWegIcon[w], size: 14),
                    label: Text(_kWegLabel[w]!, style: const TextStyle(fontSize: 12)),
                    selected: _filterWeg == w,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _filtern(_filterRichtung, _filterWeg == w ? '' : w),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Erfassen', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade600),
            onPressed: _erfassen,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Neu laden',
            onPressed: _laden,
          ),
        ]),
      ),
      Expanded(
        child: _laeuft
            ? const Center(child: CircularProgressIndicator())
            : _eintraege.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.forum_outlined, size: 48, color: F.h(Colors.grey, 300)),
                        const SizedBox(height: 10),
                        Text(
                          _filterRichtung.isEmpty && _filterWeg.isEmpty
                              ? 'Noch keine Korrespondenz.\n'
                                'E-Mails an inwx@icd360s.de werden automatisch übernommen.'
                              : 'Kein Eintrag für diesen Filter.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600)),
                        ),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _laden,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _eintraege.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _karte(_eintraege[i]),
                    ),
                  ),
      ),
    ]);
  }

  Widget _chip(String text, bool aktiv, VoidCallback bei) => ChoiceChip(
        label: Text(text, style: const TextStyle(fontSize: 12)),
        selected: aktiv,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => bei(),
      );

  Widget _karte(Map<String, dynamic> k) {
    final eingang = (k['richtung'] ?? 'eingang').toString() == 'eingang';
    final weg = (k['weg'] ?? 'email').toString();
    final betreff = (k['betreff'] ?? '').toString();
    final absender = (k['absender'] ?? '').toString();
    final empfaenger = (k['empfaenger'] ?? '').toString();
    final notiz = (k['notiz'] ?? '').toString();
    final dateien = inwxListe(k['dateien']);
    final ton = eingang ? Colors.indigo : Colors.teal;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(Colors.grey, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(eingang ? Icons.south_west : Icons.north_east, size: 15, color: F.h(ton, 600)),
            const SizedBox(width: 5),
            Text(eingang ? 'EINGANG' : 'AUSGANG',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 0.6, color: F.h(ton, 700))),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_kWegIcon[weg], size: 13, color: F.h(Colors.grey, 600)),
            const SizedBox(width: 4),
            Text(_kWegLabel[weg] ?? weg, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          ]),
          Text(_zeit(k['datum']?.toString() ?? ''),
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          if ((k['quelle'] ?? '').toString() == 'mail')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: F.h(Colors.blue, 50), borderRadius: BorderRadius.circular(4)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.bolt, size: 10, color: Colors.blue.shade400),
                const SizedBox(width: 2),
                Text('automatisch', style: TextStyle(fontSize: 9, color: F.h(Colors.blue, 700))),
              ]),
            ),
        ]),
        const SizedBox(height: 7),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (betreff.isNotEmpty)
              Text(betreff, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              [if (absender.isNotEmpty) absender, if (empfaenger.isNotEmpty) '→ $empfaenger']
                  .join(' '),
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ])),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 17, color: Colors.red.shade400),
            tooltip: 'Löschen',
            visualDensity: VisualDensity.compact,
            onPressed: () => _loeschen(k),
          ),
        ]),
        if (notiz.isNotEmpty) ...[
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: F.h(Colors.grey, 50),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: F.h(Colors.grey, 200)),
            ),
            child: Text(notiz, style: const TextStyle(fontSize: 12)),
          ),
        ],
        if (dateien.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final f in dateien) _dateiChip(f)]),
        ],
      ]),
    );
  }

  Widget _dateiChip(Map<String, dynamic> f) {
    final name = (f['original_name'] ?? 'Datei').toString();
    final eml = (f['rolle'] ?? '').toString() == 'eml';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _oeffnen(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: eml ? F.h(Colors.blueGrey, 50) : F.h(Colors.grey, 50),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: eml ? F.h(Colors.blueGrey, 200) : F.h(Colors.grey, 200)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(eml ? Icons.mail_outline : Icons.description,
              size: 15, color: eml ? F.h(Colors.blueGrey, 600) : F.h(Colors.grey, 600)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(eml ? 'Originalnachricht öffnen' : name,
                style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }

  /// Eine archivierte Nachricht geht in den Mail-Leser. Eine .eml an den
  /// Dateibetrachter zu geben zeigt nichts — der kennt PDFs und Bilder.
  Future<void> _oeffnen(Map<String, dynamic> f) async {
    final id = int.tryParse(f['id']?.toString() ?? '') ?? 0;
    if (id == 0) return;
    if ((f['rolle'] ?? '').toString() == 'eml') {
      await KorrespondenzMessageDialog.show(
        context, widget.apiService, id,
        loader: (fid) => widget.apiService.getKorrespondenzMessage(fid, modul: _modul),
      );
      return;
    }
    final r = await widget.apiService.downloadVereinKorrespondenzFile(id, modul: _modul);
    if (!mounted) return;
    if (r == null) {
      widget.melde('Datei konnte nicht geladen werden', fehler: true);
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final datei = File('${dir.path}/${(f['original_name'] ?? 'datei').toString().replaceAll(RegExp(r'[^\w.\-]'), '_')}');
      await datei.writeAsBytes(r.bodyBytes);
      final auf = await OpenFilex.open(datei.path);
      if (auf.type != ResultType.done) widget.melde('Gespeichert unter ${datei.path}');
    } catch (e) {
      widget.melde('Öffnen fehlgeschlagen: $e', fehler: true);
    }
  }

  Future<void> _loeschen(Map<String, dynamic> k) async {
    final id = int.tryParse(k['id']?.toString() ?? '') ?? 0;
    if (id == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eintrag löschen?', style: TextStyle(fontSize: 15)),
        content: Text(
          '„${k['betreff'] ?? ''}" wird mitsamt Originalnachricht und Anhängen entfernt. '
          'Ist die Mail im Postfach schon gelöscht, ist das die letzte Kopie.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await widget.apiService.deleteVereinKorrespondenz(id, modul: _modul);
    if (!mounted) return;
    if (r['success'] == true) {
      widget.melde('Eintrag gelöscht');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Löschen fehlgeschlagen', fehler: true);
    }
  }

  /// Für alles, was nicht per Mail kommt: Anruf beim Support, Brief, Notiz.
  Future<void> _erfassen() async {
    var richtung = 'ausgang';
    var weg = 'anruf';
    final betreffC = TextEditingController();
    final partnerC = TextEditingController();
    final notizC = TextEditingController();
    final jetzt = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) => AlertDialog(
        title: const Text('Korrespondenz erfassen', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: const Text('↓ Eingang', style: TextStyle(fontSize: 12)),
                  selected: richtung == 'eingang',
                  onSelected: (_) => setD(() => richtung = 'eingang'),
                ),
                ChoiceChip(
                  label: const Text('↑ Ausgang', style: TextStyle(fontSize: 12)),
                  selected: richtung == 'ausgang',
                  onSelected: (_) => setD(() => richtung = 'ausgang'),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final w in _kWegLabel.keys)
                  ChoiceChip(
                    avatar: Icon(_kWegIcon[w], size: 14),
                    label: Text(_kWegLabel[w]!, style: const TextStyle(fontSize: 12)),
                    selected: weg == w,
                    onSelected: (_) => setD(() => weg = w),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: betreffC,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Betreff *',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: partnerC,
                decoration: InputDecoration(
                  labelText: 'Gesprächspartner',
                  hintText: 'z. B. INWX Support',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notizC,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Notiz',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade600),
            onPressed: () {
              if (betreffC.text.trim().isEmpty) {
                ScaffoldMessenger.of(dCtx).showSnackBar(
                    const SnackBar(content: Text('Bitte einen Betreff eingeben')));
                return;
              }
              Navigator.pop(dCtx, true);
            },
            child: const Text('Speichern'),
          ),
        ],
      )),
    );
    if (ok != true) return;

    final datum = '${jetzt.year.toString().padLeft(4, '0')}-'
        '${jetzt.month.toString().padLeft(2, '0')}-${jetzt.day.toString().padLeft(2, '0')} '
        '${jetzt.hour.toString().padLeft(2, '0')}:${jetzt.minute.toString().padLeft(2, '0')}:00';
    final r = await widget.apiService.createVereinKorrespondenz(
      richtung: richtung,
      weg: weg,
      datum: datum,
      betreff: betreffC.text.trim(),
      absender: richtung == 'eingang' ? 'INWX GmbH' : 'ICD360S e.V.',
      empfaenger: richtung == 'eingang' ? 'ICD360S e.V.' : 'INWX GmbH',
      gespraechspartner: partnerC.text.trim(),
      notiz: notizC.text.trim(),
      modul: _modul,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      widget.melde('Korrespondenz gespeichert');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Speichern fehlgeschlagen', fehler: true);
    }
  }

  static String _zeit(String s) {
    if (s.length < 16) return s;
    final d = s.split(' ');
    if (d.length != 2) return s;
    final t = d[0].split('-');
    if (t.length != 3) return s;
    return '${t[2]}.${t[1]}.${t[0]} ${d[1].substring(0, 5)}';
  }
}
