/// Kindergarten ▸ Zahlung — vierter Reiter neben Kündigung.
///
/// Schwester des Rechtsanwalt-Zweigs am Vertrag
/// (mitgliederverwaltung_vertrag_rechtsanwalt.dart), eigene Datei aus
/// demselben Grund: behorde_kindergarten.dart wird von mehreren Sitzungen
/// angefasst, und der Eingriff dort bleibt so auf einen Import, einen
/// Reiter und eine Zeile in der TabBarView beschränkt.
///
/// 🔴 DIE EINE SACHE, DIE DIESEN ZWEIG VOM VORBILD TRENNT:
///
/// Das Entgelt ist PRIVATRECHTLICH. „Entgeltordnung für die
/// Kinderbetreuungseinrichtungen der Stadt Erbach vom 16.07.2024", § 1
/// Abs. 3: „Die Einrichtungen werden privatrechtlich betrieben. Für die
/// Benutzung wird ein privatrechtliches Entgelt erhoben."
///
/// Daraus folgt für den Bildschirm, und es ist nicht bloß Wortwahl:
///   · Es gibt KEINEN Bescheid und keinen Widerspruch. Das Wort „Bescheid"
///     würde eine Rechtsbehelfsfrist suggerieren, die es nicht gibt — wer
///     sie verstreichen lässt, glaubt, er habe etwas verloren. Deshalb
///     heißt es überall „Festsetzung".
///   · Die härteste Folge ist nicht Geld, sondern der PLATZ DES KINDES
///     (§ 2 Abs. 5: zwei Monate Rückstand trotz schriftlicher Mahnung →
///     Kündigung). Deshalb steht die Warnung ganz oben und nicht in einem
///     Detailfeld.
///
/// ⚠️ ZWEI STELLEN IM SELBEN HAUS, plus zwei außerhalb — und sie sind
/// nicht austauschbar. Die KASSE zieht ein, die FACHSTELLE hat die Akte,
/// das JUGENDAMT entscheidet § 90 Abs. 4 SGB VIII, die
/// DATENSCHUTZAUFSICHT die Beschwerde. Welcher Brief wohin geht,
/// entscheidet der SERVER über das Feld `empfaenger` jeder Vorlage — hier
/// wird es angezeigt, nie bestimmt.
library;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/ra_antwort.dart';
import 'behorde_kindergarten_zahlung_akte.dart';
import 'phone_link.dart';

const Color kZahlungFarbe = Color(0xFFAD1457); // pink.shade800 — unter dem
                                               // Rosa des Kindergartens, aber
                                               // dunkler: es geht um Geld.

/// Dialoge in Bildschirmgröße statt fester Punktzahl.
///
/// ⚠️ Diese App läuft auch auf dem Pixel. Eine fest verdrahtete Breite von
/// 720 dp ist dort breiter als das Gerät — der Inhalt wird gequetscht, ohne
/// dass ein Überlauf gemeldet würde.
Size zahlungDialogGroesse(BuildContext context) {
  final m = MediaQuery.of(context).size;
  return Size(m.width < 760 ? m.width * 0.96 : 760, m.height * 0.88);
}

/// Farbe und Text der Kündigungswarnung.
///
/// ⚠️ `null` heißt UNBEKANNT, nicht „keine Gefahr". Der Server liefert das
/// Feld nur, wenn ein Datum erfasst ist. Beides gleich darzustellen würde
/// einen nicht erfassten Vorgang so ruhig aussehen lassen wie einen
/// wirklich ruhigen — und das ist genau der Fall, in dem jemand den Platz
/// des Kindes verliert, ohne dass es jemand kommen sah.
({Color farbe, IconData symbol}) kuendigungsAussehen(String? stufe) => switch (stufe) {
      'ueberschritten' => (farbe: Colors.red.shade700, symbol: Icons.error),
      'akut' => (farbe: Colors.deepOrange.shade700, symbol: Icons.warning_amber_rounded),
      'bald' => (farbe: Colors.amber.shade800, symbol: Icons.schedule),
      'ruhig' => (farbe: Colors.green.shade700, symbol: Icons.check_circle_outline),
      _ => (farbe: Colors.grey.shade600, symbol: Icons.help_outline),
    };

// ═══════════════════════════════════════════════════════════════════════
// Reiter: Zahlung → Zuständiger Zahlungsempfänger | Kassenzeichen
// ═══════════════════════════════════════════════════════════════════════

class KindergartenZahlungTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String adminMitgliedernummer;
  const KindergartenZahlungTab({
    super.key,
    required this.apiService,
    required this.userId,
    this.adminMitgliedernummer = '',
  });

  @override
  State<KindergartenZahlungTab> createState() => _KindergartenZahlungTabState();
}

class _KindergartenZahlungTabState extends State<KindergartenZahlungTab> {
  Map<String, dynamic>? _zuordnung;
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.getKigaZahlungZuordnung(widget.userId);
    if (!mounted) return;
    setState(() {
      // ⚠️ `exists` steht in der WURZEL, `data` ist hier ein echter
      // Schlüssel — genau die Verwechslung, an der der Inkasso-Zweig
      // gescheitert ist: dort sah gespeicherte Arbeit wie „nichts
      // gespeichert" aus.
      _zuordnung = res['exists'] == true ? raKarte(res, 'data') : null;
      _geladen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: kZahlungFarbe.withValues(alpha: 0.08),
          child: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: kZahlungFarbe,
            indicatorColor: kZahlungFarbe,
            tabs: [
              Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Zuständiger Zahlungsempfänger'),
              Tab(icon: Icon(Icons.receipt_long, size: 16), text: 'Kassenzeichen'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            _ZahlungsempfaengerSubTab(
              apiService: widget.apiService,
              userId: widget.userId,
              zuordnung: _zuordnung,
              onSaved: _laden,
            ),
            _KassenzeichenSubTab(
              apiService: widget.apiService,
              userId: widget.userId,
              zuordnung: _zuordnung,
              adminMitgliedernummer: widget.adminMitgliedernummer,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Unterreiter 1: Zuständiger Zahlungsempfänger ─────────────────────

class _ZahlungsempfaengerSubTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic>? zuordnung;
  final VoidCallback onSaved;
  const _ZahlungsempfaengerSubTab({
    required this.apiService,
    required this.userId,
    required this.zuordnung,
    required this.onSaved,
  });

  @override
  State<_ZahlungsempfaengerSubTab> createState() => _ZahlungsempfaengerSubTabState();
}

class _ZahlungsempfaengerSubTabState extends State<_ZahlungsempfaengerSubTab> {
  /// Spiegelt das ENUM `zuord_status` des Servers.
  ///
  /// ⚠️ Ein Wert, den der Server nicht kennt, wird von ihm mit HTTP 400
  /// abgelehnt — er kürzt nicht still auf ''. Wer hier etwas ergänzt, muss
  /// es im Endpunkt mitpflegen, sonst scheitert das Speichern mit einer
  /// Meldung, die man erst beim Lesen versteht.
  static const statusOptionen = [
    ('kein_empfaenger', 'Kein Empfänger', Colors.grey),
    ('zugeordnet', 'Zugeordnet', Colors.blue),
    ('laufend', 'Laufend', Colors.teal),
    ('beitragsfrei', 'Beitragsfrei', Colors.green),
    ('ermaessigt', 'Ermäßigt', Colors.lightGreen),
    ('stundung', 'Stundung', Colors.indigo),
    ('ratenzahlung', 'Ratenzahlung', Colors.cyan),
    ('rueckstand', 'Rückstand', Colors.deepOrange),
    ('vollstreckung', 'Beitreibung', Colors.red),
    ('beendet', 'Beendet', Colors.blueGrey),
  ];

  List<Map<String, dynamic>> _stellen = [];
  int? _gewaehlt;
  bool _geladen = false;
  bool _speichert = false;

  late final TextEditingController _zahlerC;
  late final TextEditingController _verhaeltnisC;
  late final TextEditingController _debitorC;
  late final TextEditingController _sepaC;
  late final TextEditingController _beitragC;
  late final TextEditingController _notizC;
  String _status = 'kein_empfaenger';
  String _zahlungsweise = 'ueberweisung';
  DateTime? _seit;
  DateTime? _bis;

  @override
  void initState() {
    super.initState();
    final z = widget.zuordnung ?? const <String, dynamic>{};
    _gewaehlt = int.tryParse(raWert(z['empfaenger_id']));
    _zahlerC = TextEditingController(text: raWert(z['zahler_name']));
    _verhaeltnisC = TextEditingController(text: raWert(z['zahler_verhaeltnis']));
    _debitorC = TextEditingController(text: raWert(z['debitorennummer']));
    _sepaC = TextEditingController(text: raWert(z['sepa_mandat']));
    _beitragC = TextEditingController(text: raWert(z['beitrag_monatlich']));
    _notizC = TextEditingController(text: raWert(z['notizen']));
    _status = raHat(z['status']) ? raWert(z['status']) : 'kein_empfaenger';
    if (raHat(z['zahlungsweise'])) _zahlungsweise = raWert(z['zahlungsweise']);
    _seit = DateTime.tryParse(raWert(z['zahlung_seit']));
    _bis = DateTime.tryParse(raWert(z['zahlung_bis']));
    _stellenLaden();
  }

  @override
  void dispose() {
    for (final c in [_zahlerC, _verhaeltnisC, _debitorC, _sepaC, _beitragC, _notizC]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _stellenLaden() async {
    final res = await widget.apiService.listZahlungsempfaenger();
    if (!mounted) return;
    setState(() {
      _stellen = raListe(res);
      _geladen = true;
    });
  }

  /// Stelle anlegen oder ändern — und die frisch angelegte gleich
  /// auswählen, damit man nach dem Speichern nicht noch einmal suchen muss.
  Future<void> _stelleBearbeiten({Map<String, dynamic>? vorhanden}) async {
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => ZahlungsempfaengerDialog(
        apiService: widget.apiService,
        vorhanden: vorhanden,
      ),
    );
    if (id == null) return;
    await _stellenLaden();
    if (mounted) setState(() => _gewaehlt = id);
  }

  Future<void> _datumWaehlen(DateTime? start, ValueChanged<DateTime?> gewaehlt) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2060),
    );
    if (d != null) gewaehlt(d);
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    final res = await widget.apiService.saveKigaZahlungZuordnung(widget.userId, {
      'empfaenger_id': _gewaehlt ?? 0,
      'status': _status,
      'zahlung_seit': raIso(_seit),
      'zahlung_bis': raIso(_bis),
      'zahler_name': _zahlerC.text.trim(),
      'zahler_verhaeltnis': _verhaeltnisC.text.trim(),
      'debitorennummer': _debitorC.text.trim(),
      'sepa_mandat': _sepaC.text.trim(),
      'beitrag_monatlich': _beitragC.text.trim(),
      'zahlungsweise': _zahlungsweise,
      'notizen': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Gespeichert' : raWert(res['message']).isEmpty
          ? 'Speichern fehlgeschlagen'
          : raWert(res['message'])),
      backgroundColor: ok ? Colors.green : Colors.red,
      duration: const Duration(seconds: 2),
    ));
    if (ok) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());

    final gewaehlteStelle = _stellen.cast<Map<String, dynamic>?>().firstWhere(
          (s) => int.tryParse(raWert(s?['id'])) == _gewaehlt,
          orElse: () => null,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance, size: 18, color: kZahlungFarbe),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Wer bekommt das Geld?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kZahlungFarbe)),
          ),
          TextButton.icon(
            onPressed: () => _stelleBearbeiten(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 4),
        // ⚠️ Der Satz ist keine Höflichkeit. Die Einrichtung und die Kasse
        // sind zwei Dinge; wer an den Kindergarten überweist, zahlt an
        // jemanden, der die Forderung nicht führt.
        Text(
          'Nicht der Kindergarten, sondern die Stelle, die den Elternbeitrag '
          'einzieht — bei städtischen Einrichtungen die Stadtkasse.',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),

        if (_stellen.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: const Text(
              'Im Nachschlagewerk steht noch keine Stelle. Über „Neu" anlegen — '
              'Anschrift, Kasse, Fachstelle und Bankverbindung.',
              style: TextStyle(fontSize: 12),
            ),
          )
        else
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Zahlungsempfänger',
              isDense: true,
              prefixIcon: const Icon(Icons.business, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _gewaehlt,
                isExpanded: true,
                hint: const Text('Stelle auswählen…', style: TextStyle(fontSize: 13)),
                items: _stellen.map((s) {
                  final id = int.tryParse(raWert(s['id'])) ?? 0;
                  final ort = raWert(s['plz_ort']);
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(
                      raWert(s['name']) + (ort.isEmpty ? '' : ' · $ort'),
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _gewaehlt = v),
              ),
            ),
          ),

        if (gewaehlteStelle != null) ...[
          const SizedBox(height: 12),
          _EmpfaengerKarte(
            stelle: gewaehlteStelle,
            onBearbeiten: () => _stelleBearbeiten(vorhanden: gewaehlteStelle),
          ),
        ],

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        const Text('Zahlung', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 10),

        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Stand',
            isDense: true,
            prefixIcon: const Icon(Icons.flag_outlined, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _status,
              isExpanded: true,
              items: statusOptionen
                  .map((o) => DropdownMenuItem(
                        value: o.$1,
                        child: Row(children: [
                          Container(width: 10, height: 10,
                              decoration: BoxDecoration(color: o.$3, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(o.$2, style: const TextStyle(fontSize: 13)),
                        ]),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? 'kein_empfaenger'),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ⚠️ Wer zahlt, ist eine eigene Angabe — und sie ist wichtiger, als
        // sie aussieht: nach § 4 Abs. 2 der Entgeltordnung haften mehrere
        // Zahlungspflichtige als GESAMTSCHULDNER. Die Stadt darf den vollen
        // Betrag von einem Elternteil verlangen, egal wer ihn üblicherweise
        // überweist.
        Row(children: [
          Expanded(
            child: TextField(
              controller: _zahlerC,
              decoration: InputDecoration(
                labelText: 'Zahlt tatsächlich',
                isDense: true,
                prefixIcon: const Icon(Icons.person_outline, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _verhaeltnisC,
              decoration: InputDecoration(
                labelText: 'Verhältnis',
                hintText: 'Mutter, Vater …',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Mehrere Zahlungspflichtige haften als Gesamtschuldner — die Stelle '
          'darf den vollen Betrag von einer Person verlangen.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(
            child: TextField(
              controller: _beitragC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Beitrag je Monat',
                suffixText: '€',
                isDense: true,
                prefixIcon: const Icon(Icons.euro, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Zahlungsweise',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _zahlungsweise,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'ueberweisung', child: Text('Überweisung', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'dauerauftrag', child: Text('Dauerauftrag', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'lastschrift', child: Text('SEPA-Lastschrift', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _zahlungsweise = v ?? 'ueberweisung'),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(
            child: TextField(
              controller: _debitorC,
              decoration: InputDecoration(
                labelText: 'Debitoren-/Personenkonto',
                isDense: true,
                prefixIcon: const Icon(Icons.tag, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _sepaC,
              decoration: InputDecoration(
                labelText: 'SEPA-Mandatsreferenz',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(child: _DatumFeld(
            label: 'Zahlt seit',
            wert: _seit,
            onTap: () => _datumWaehlen(_seit, (d) => setState(() => _seit = d)),
            onLoeschen: () => setState(() => _seit = null),
          )),
          const SizedBox(width: 8),
          Expanded(child: _DatumFeld(
            label: 'Bis',
            wert: _bis,
            onTap: () => _datumWaehlen(_bis, (d) => setState(() => _bis = d)),
            onLoeschen: () => setState(() => _bis = null),
          )),
        ]),
        const SizedBox(height: 10),

        TextField(
          controller: _notizC,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Notizen',
            isDense: true,
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _speichert ? null : _speichern,
            style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
            icon: _speichert
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 18),
            label: Text(_speichert ? 'Speichert…' : 'Speichern'),
          ),
        ),
      ]),
    );
  }
}

/// Die Karte der gewählten Stelle.
///
/// 🔴 SIE ZEIGT DREI ADRESSEN GETRENNT, und das ist der ganze Zweck.
/// Kasse, Fachstelle und Jugendamt sind verschiedene Empfänger für
/// verschiedene Schreiben. Eine Karte, die nur „die Behörde" zeigt, führt
/// dazu, dass alles an die Kasse geht — und dort bleibt ein
/// Auskunftsersuchen unbeantwortet, weil die Kasse die Akte gar nicht hat.
class _EmpfaengerKarte extends StatelessWidget {
  final Map<String, dynamic> stelle;
  final VoidCallback onBearbeiten;
  const _EmpfaengerKarte({required this.stelle, required this.onBearbeiten});

  @override
  Widget build(BuildContext context) {
    final iban = raWert(stelle['iban']);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kZahlungFarbe.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kZahlungFarbe.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(raWert(stelle['name']),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: 'Bearbeiten',
            onPressed: onBearbeiten,
            visualDensity: VisualDensity.compact,
          ),
        ]),
        if (raHat(stelle['strasse']) || raHat(stelle['plz_ort']))
          Text([raWert(stelle['strasse']), raWert(stelle['plz_ort'])]
                  .where((s) => s.isNotEmpty).join(', '),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),

        const SizedBox(height: 10),
        _RolleZeile(
          symbol: Icons.payments_outlined,
          rolle: 'Kasse',
          zweck: 'Raten, Zahlungen',
          name: raWert(stelle['abteilung']).isEmpty ? 'Kasse' : raWert(stelle['abteilung']),
          telefon: raWert(stelle['telefon']),
          email: raWert(stelle['email']),
        ),
        _RolleZeile(
          symbol: Icons.folder_shared_outlined,
          rolle: 'Fachstelle',
          zweck: 'Akteneinsicht, Härtefall',
          name: raWert(stelle['fachstelle_person']).isNotEmpty
              ? '${raWert(stelle['fachstelle'])} · ${raWert(stelle['fachstelle_person'])}'
              : raWert(stelle['fachstelle']),
          telefon: raWert(stelle['fachstelle_telefon']),
          email: raWert(stelle['fachstelle_email']),
        ),
        _RolleZeile(
          symbol: Icons.family_restroom_outlined,
          rolle: 'Jugendamt',
          zweck: '§ 90 Abs. 4 SGB VIII',
          name: raWert(stelle['jugendamt_name']),
          telefon: '',
          email: raWert(stelle['jugendamt_email']),
        ),

        if (iban.isNotEmpty) ...[
          const Divider(height: 18),
          Row(children: [
            Icon(Icons.account_balance_wallet_outlined, size: 15, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${raIbanLesbar(iban)}'
                '${raHat(stelle['bic']) ? '  ·  ${raWert(stelle['bic'])}' : ''}',
                style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ]),
          if (raHat(stelle['bank_inhaber']))
            Padding(
              padding: const EdgeInsets.only(left: 21, top: 2),
              child: Text('Inhaber: ${raWert(stelle['bank_inhaber'])}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ),
          if (raHat(stelle['zahlungshinweis']))
            Padding(
              padding: const EdgeInsets.only(left: 21, top: 4),
              child: Text(raWert(stelle['zahlungshinweis']),
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ]),
    );
  }
}

class _RolleZeile extends StatelessWidget {
  final IconData symbol;
  final String rolle;
  final String zweck;
  final String name;
  final String telefon;
  final String email;
  const _RolleZeile({
    required this.symbol,
    required this.rolle,
    required this.zweck,
    required this.name,
    required this.telefon,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    // ⚠️ Fehlt die Adresse, wird die Zeile NICHT weggelassen, sondern als
    // fehlend gezeigt. „nicht hinterlegt" ist eine Information: an diese
    // Stelle kann gerade kein Brief gehen, und das merkt man sonst erst,
    // wenn das Senden scheitert.
    final leer = name.isEmpty && email.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(symbol, size: 15, color: leer ? Colors.grey.shade400 : kZahlungFarbe),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(rolle, style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.bold,
                  color: leer ? Colors.grey.shade500 : Colors.black87)),
              const SizedBox(width: 6),
              Text('· $zweck', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            ]),
            if (leer)
              Text('nicht hinterlegt', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500))
            else ...[
              if (name.isNotEmpty)
                Text(name, style: const TextStyle(fontSize: 12)),
              if (email.isNotEmpty)
                Text(email, style: TextStyle(fontSize: 11.5, color: Colors.blue.shade800)),
              // Wählbar statt nur lesbar: auf dem Pixel ist ein Anruf bei
              // der Fachstelle oft schneller als ein Brief.
              if (telefon.isNotEmpty)
                PhoneText(telefon, style: const TextStyle(fontSize: 11.5)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _DatumFeld extends StatelessWidget {
  final String label;
  final DateTime? wert;
  final VoidCallback onTap;
  final VoidCallback onLoeschen;
  const _DatumFeld({
    required this.label,
    required this.wert,
    required this.onTap,
    required this.onLoeschen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: const Icon(Icons.calendar_today, size: 16),
          suffixIcon: wert == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: onLoeschen,
                  visualDensity: VisualDensity.compact,
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(wert == null ? '—' : raDatumDe(raIso(wert)),
            style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

// ─── Unterreiter 2: Kassenzeichen ─────────────────────────────────────

class _KassenzeichenSubTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic>? zuordnung;
  final String adminMitgliedernummer;
  const _KassenzeichenSubTab({
    required this.apiService,
    required this.userId,
    required this.zuordnung,
    required this.adminMitgliedernummer,
  });

  @override
  State<_KassenzeichenSubTab> createState() => _KassenzeichenSubTabState();
}

class _KassenzeichenSubTabState extends State<_KassenzeichenSubTab> {
  List<Map<String, dynamic>> _vorgaenge = [];
  List<Map<String, dynamic>> _kinder = [];
  String _vorbehalt = '';
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.listKigaKassenzeichen(widget.userId);
    final kinder = await widget.apiService.listKigaZahlungKinder(widget.userId);
    if (!mounted) return;
    setState(() {
      _vorgaenge = raListe(res);
      _kinder = raListe(kinder);
      _vorbehalt = raWert(res['vorbehalt']);
      _geladen = true;
    });
  }

  Future<void> _bearbeiten({Map<String, dynamic>? vorhanden}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _KassenzeichenDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        kinder: _kinder,
        vorhanden: vorhanden,
      ),
    );
    if (ok == true) _laden();
  }

  Future<void> _loeschen(Map<String, dynamic> v) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kassenzeichen löschen?'),
        // ⚠️ Die Aufzählung ist keine Zierde. Wer glaubt, nur eine Nummer zu
        // entfernen, verliert den gesamten Schriftwechsel des Vorgangs.
        content: Text(
          'Mit dem Vorgang ${raWert(v['kassenzeichen'])} verschwinden auch:\n\n'
          '· die gesamte Korrespondenz\n'
          '· alle Akteneinsichts-Anfragen und ihre Fristen\n'
          '· der Ratenplan mit allen Raten\n'
          '· alle Vollmachten dieses Vorgangs\n'
          '· alle hochgeladenen Dateien\n\n'
          'Das lässt sich nicht rückgängig machen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    final id = int.tryParse(raWert(v['id'])) ?? 0;
    if (id > 0) {
      await widget.apiService.deleteKigaKassenzeichen(id);
      _laden();
    }
  }

  void _oeffnen(Map<String, dynamic> v) {
    final groesse = zahlungDialogGroesse(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: groesse.width,
          height: groesse.height,
          child: KigaKassenzeichenDetailDialog(
            apiService: widget.apiService,
            userId: widget.userId,
            vorgang: v,
            adminMitgliedernummer: widget.adminMitgliedernummer,
            onChanged: _laden,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());

    // ⚠️ Ohne Zahlungsempfänger kann kein Schreiben rausgehen — der Server
    // fände keine Adresse. Das hier zu sagen ist ehrlicher, als den Reiter
    // scheinbar benutzbar zu lassen und beim Senden zu scheitern.
    final ohneStelle = widget.zuordnung == null ||
        (int.tryParse(raWert(widget.zuordnung?['empfaenger_id'])) ?? 0) <= 0;

    return Column(children: [
      if (ohneStelle)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Noch kein Zahlungsempfänger gewählt. Vorgänge lassen sich erfassen, '
                'aber Schreiben können erst raus, wenn im ersten Reiter eine Stelle steht.',
                style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
              ),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          Expanded(
            child: Text(
              _vorgaenge.isEmpty ? 'Keine Vorgänge' : '${_vorgaenge.length} Vorgang/Vorgänge',
              style: const TextStyle(fontWeight: FontWeight.bold, color: kZahlungFarbe),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _bearbeiten(),
            style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      Expanded(
        child: _vorgaenge.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.receipt_long, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text('Noch kein Kassenzeichen erfasst',
                        style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text(
                      'Ein Vorgang je Kind und Festsetzung.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _vorgaenge.length,
                itemBuilder: (_, i) => _VorgangKarte(
                  vorgang: _vorgaenge[i],
                  onOeffnen: () => _oeffnen(_vorgaenge[i]),
                  onBearbeiten: () => _bearbeiten(vorhanden: _vorgaenge[i]),
                  onLoeschen: () => _loeschen(_vorgaenge[i]),
                ),
              ),
      ),
      if (_vorbehalt.isNotEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          color: Colors.grey.shade100,
          child: Text(_vorbehalt,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        ),
    ]);
  }
}

class _VorgangKarte extends StatelessWidget {
  final Map<String, dynamic> vorgang;
  final VoidCallback onOeffnen;
  final VoidCallback onBearbeiten;
  final VoidCallback onLoeschen;
  const _VorgangKarte({
    required this.vorgang,
    required this.onOeffnen,
    required this.onBearbeiten,
    required this.onLoeschen,
  });

  @override
  Widget build(BuildContext context) {
    final gefahr = vorgang['kuendigungsgefahr'];
    final gefahrMap = gefahr is Map ? Map<String, dynamic>.from(gefahr) : null;
    final aussehen = kuendigungsAussehen(raWert(gefahrMap?['stufe']).isEmpty
        ? null
        : raWert(gefahrMap?['stufe']));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOeffnen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  raWert(vorgang['kassenzeichen']).isEmpty
                      ? '(ohne Kassenzeichen)'
                      : raWert(vorgang['kassenzeichen']),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 16),
                onPressed: onBearbeiten,
                visualDensity: VisualDensity.compact,
                tooltip: 'Bearbeiten',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: onLoeschen,
                visualDensity: VisualDensity.compact,
                tooltip: 'Löschen',
              ),
            ]),
            if (raHat(vorgang['kind_name']) || raHat(vorgang['zeitraum']))
              Text(
                [raWert(vorgang['kind_name']), raWert(vorgang['zeitraum'])]
                    .where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),

            // 🔴 DIE WARNUNG STEHT OBEN, nicht in einem Detailfeld.
            // Es geht nicht um Geld, sondern um den Platz des Kindes.
            if (gefahrMap != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: aussehen.farbe.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: aussehen.farbe.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Icon(aussehen.symbol, size: 15, color: aussehen.farbe),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(raWert(gefahrMap['text']),
                        style: TextStyle(fontSize: 11.5, color: aussehen.farbe,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _Marke(text: _statusText(raWert(vorgang['status'])), farbe: kZahlungFarbe),
              if (raHat(vorgang['betrag']))
                _Marke(text: '${raWert(vorgang['betrag'])} €', farbe: Colors.blueGrey),
              if (vorgang['vollmacht_aktiv'] == true)
                _Marke(text: 'Vollmacht', farbe: Colors.green.shade700),
              if ((int.tryParse(raWert(vorgang['akteneinsicht_offen'])) ?? 0) > 0)
                _Marke(
                  text: 'Akteneinsicht offen: ${raWert(vorgang['akteneinsicht_offen'])}',
                  farbe: Colors.indigo,
                ),
              if (raHat(vorgang['ratenplan_status']))
                _Marke(text: 'Raten: ${raWert(vorgang['ratenplan_status'])}', farbe: Colors.teal),
              if (vorgang['hat_mahnverfahren'] == true)
                _Marke(text: 'Mahnverfahren', farbe: Colors.deepOrange),
              if ((int.tryParse(raWert(vorgang['fristen_offen'])) ?? 0) > 0)
                _Marke(
                  text: '${raWert(vorgang['fristen_offen'])} Frist(en)',
                  farbe: Colors.red.shade700,
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  static String _statusText(String s) => switch (s) {
        'offen' => 'Offen',
        'festgesetzt' => 'Festgesetzt',
        'beanstandet' => 'Beanstandet',
        'haertefall' => 'Härtefall beantragt',
        'jugendamt' => 'Jugendamt beantragt',
        'ratenzahlung' => 'Ratenzahlung',
        'rueckstand' => 'Rückstand',
        'mahnung' => 'Mahnung',
        'mahnverfahren' => 'Mahnverfahren',
        'klageverfahren' => 'Klageverfahren',
        'vergleich' => 'Vergleich',
        'erledigt' => 'Erledigt',
        'ruht' => 'Ruht',
        'abgeschlossen' => 'Abgeschlossen',
        _ => s,
      };
}

class _Marke extends StatelessWidget {
  final String text;
  final Color farbe;
  const _Marke({required this.text, required this.farbe});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: farbe.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10.5, color: farbe, fontWeight: FontWeight.w600)),
      );
}

// ─── Anlegen / Bearbeiten eines Kassenzeichens ────────────────────────

class _KassenzeichenDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final List<Map<String, dynamic>> kinder;
  final Map<String, dynamic>? vorhanden;
  const _KassenzeichenDialog({
    required this.apiService,
    required this.userId,
    required this.kinder,
    this.vorhanden,
  });

  @override
  State<_KassenzeichenDialog> createState() => _KassenzeichenDialogState();
}

class _KassenzeichenDialogState extends State<_KassenzeichenDialog> {
  static const statusOptionen = [
    ('offen', 'Offen'),
    ('festgesetzt', 'Festgesetzt'),
    ('beanstandet', 'Beanstandet'),
    ('haertefall', 'Härtefall beantragt'),
    ('jugendamt', 'Jugendamt beantragt'),
    ('ratenzahlung', 'Ratenzahlung'),
    ('rueckstand', 'Rückstand'),
    ('mahnung', 'Mahnung'),
    ('mahnverfahren', 'Mahnverfahren'),
    ('klageverfahren', 'Klageverfahren'),
    ('vergleich', 'Vergleich'),
    ('erledigt', 'Erledigt'),
    ('ruht', 'Ruht'),
    ('abgeschlossen', 'Abgeschlossen'),
  ];

  late final TextEditingController _kzC;
  late final TextEditingController _azC;
  late final TextEditingController _bezC;
  late final TextEditingController _kindNameC;
  late final TextEditingController _zeitraumC;
  late final TextEditingController _betragC;
  late final TextEditingController _offenC;
  late final TextEditingController _notizC;
  String _status = 'offen';
  int? _kindId;
  DateTime? _festsetzung;
  DateTime? _faellig;
  DateTime? _frist;
  DateTime? _kuendigung;
  bool _speichert = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vorhanden ?? const <String, dynamic>{};
    _kzC = TextEditingController(text: raWert(v['kassenzeichen']));
    _azC = TextEditingController(text: raWert(v['aktenzeichen']));
    _bezC = TextEditingController(text: raWert(v['bezeichnung']));
    _kindNameC = TextEditingController(text: raWert(v['kind_name']));
    _zeitraumC = TextEditingController(text: raWert(v['zeitraum']));
    _betragC = TextEditingController(text: raWert(v['betrag']));
    _offenC = TextEditingController(text: raWert(v['offener_betrag']));
    _notizC = TextEditingController(text: raWert(v['notizen']));
    _status = raHat(v['status']) ? raWert(v['status']) : 'offen';
    _kindId = int.tryParse(raWert(v['kind_id']));
    _festsetzung = DateTime.tryParse(raWert(v['festsetzung_am']));
    _faellig = DateTime.tryParse(raWert(v['faellig_am']));
    _frist = DateTime.tryParse(raWert(v['naechste_frist']));
    _kuendigung = DateTime.tryParse(raWert(v['kuendigungsgefahr_ab']));
  }

  @override
  void dispose() {
    for (final c in [_kzC, _azC, _bezC, _kindNameC, _zeitraumC, _betragC, _offenC, _notizC]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _datum(DateTime? start, ValueChanged<DateTime?> gewaehlt) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2060),
    );
    if (d != null) gewaehlt(d);
  }

  Future<void> _speichern() async {
    if (_kzC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Das Kassenzeichen darf nicht leer sein — ohne es kann die Kasse '
            'eine Zahlung nicht zuordnen.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _speichert = true);
    final id = int.tryParse(raWert(widget.vorhanden?['id'])) ?? 0;
    final res = await widget.apiService.saveKigaKassenzeichen(widget.userId, {
      if (id > 0) 'id': id,
      'status': _status,
      'kind_id': _kindId ?? 0,
      'festsetzung_am': raIso(_festsetzung),
      'faellig_am': raIso(_faellig),
      'naechste_frist': raIso(_frist),
      'kuendigungsgefahr_ab': raIso(_kuendigung),
      'kassenzeichen': _kzC.text.trim(),
      'aktenzeichen': _azC.text.trim(),
      'bezeichnung': _bezC.text.trim(),
      'kind_name': _kindNameC.text.trim(),
      'zeitraum': _zeitraumC.text.trim(),
      'betrag': _betragC.text.trim(),
      'offener_betrag': _offenC.text.trim(),
      'notizen': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    if (res['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(raWert(res['message']).isEmpty
            ? 'Speichern fehlgeschlagen'
            : raWert(res['message'])),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final breite = zahlungDialogGroesse(context).width;
    return AlertDialog(
      title: Text(widget.vorhanden == null ? 'Neues Kassenzeichen' : 'Kassenzeichen bearbeiten',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: breite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ⚠️ Zwei Nummern, zwei Bedeutungen — und die Erklärung steht
            // dabei, weil die Verwechslung Geld kostet: mit dem
            // Aktenzeichen beschriftet, kann die Kasse eine Überweisung
            // nicht zuordnen.
            TextField(
              controller: _kzC,
              autofocus: widget.vorhanden == null,
              decoration: InputDecoration(
                labelText: 'Kassenzeichen *',
                helperText: 'Steht im Verwendungszweck jeder Zahlung',
                isDense: true,
                prefixIcon: const Icon(Icons.pin, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _azC,
              decoration: InputDecoration(
                labelText: 'Aktenzeichen',
                helperText: 'Führt den Vorgang im Amt — nicht für Zahlungen',
                isDense: true,
                prefixIcon: const Icon(Icons.folder_outlined, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),

            if (widget.kinder.isNotEmpty) ...[
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Kind',
                  isDense: true,
                  prefixIcon: const Icon(Icons.child_care, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _kindId,
                    isExpanded: true,
                    hint: const Text('kein Kindbezug', style: TextStyle(fontSize: 13)),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('kein Kindbezug', style: TextStyle(fontSize: 13))),
                      ...widget.kinder.map((k) {
                        final name = [raWert(k['vorname']), raWert(k['nachname'])]
                            .where((s) => s.isNotEmpty).join(' ');
                        return DropdownMenuItem<int?>(
                          value: int.tryParse(raWert(k['id'])),
                          child: Text(name.isEmpty ? '(ohne Namen)' : name,
                              style: const TextStyle(fontSize: 13)),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _kindId = v;
                        // Den Namen mitschreiben: die Schreiben brauchen ihn
                        // im Text, und dort steht er verschlüsselt am Vorgang
                        // — nicht über einen JOIN, den ein gelöschtes Kind
                        // ins Leere laufen ließe.
                        if (v != null) {
                          final k = widget.kinder.firstWhere(
                              (e) => int.tryParse(raWert(e['id'])) == v,
                              orElse: () => const <String, dynamic>{});
                          final name = [raWert(k['vorname']), raWert(k['nachname'])]
                              .where((s) => s.isNotEmpty).join(' ');
                          if (name.isNotEmpty) _kindNameC.text = name;
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _kindNameC,
              decoration: InputDecoration(
                labelText: 'Kind (Name im Schreiben)',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _zeitraumC,
              decoration: InputDecoration(
                labelText: 'Zeitraum',
                hintText: 'z. B. September 2025 bis Februar 2026',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _betragC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Forderung', suffixText: '€', isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _offenC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'davon offen', suffixText: '€', isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Stand', isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _status,
                  isExpanded: true,
                  items: statusOptionen
                      .map((o) => DropdownMenuItem(
                          value: o.$1, child: Text(o.$2, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v ?? 'offen'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _DatumFeld(
                label: 'Festsetzung am',
                wert: _festsetzung,
                onTap: () => _datum(_festsetzung, (d) => setState(() => _festsetzung = d)),
                onLoeschen: () => setState(() => _festsetzung = null),
              )),
              const SizedBox(width: 8),
              Expanded(child: _DatumFeld(
                label: 'Fällig am',
                wert: _faellig,
                onTap: () => _datum(_faellig, (d) => setState(() => _faellig = d)),
                onLoeschen: () => setState(() => _faellig = null),
              )),
            ]),
            const SizedBox(height: 12),
            _DatumFeld(
              label: 'Nächste Frist',
              wert: _frist,
              onTap: () => _datum(_frist, (d) => setState(() => _frist = d)),
              onLoeschen: () => setState(() => _frist = null),
            ),
            const SizedBox(height: 12),

            // 🔴 Das wichtigste Datum des ganzen Vorgangs, deshalb mit
            // eigener Erklärung und farblich abgesetzt.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.deepOrange.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.deepOrange.shade800),
                  const SizedBox(width: 6),
                  Text('Kündigung des Betreuungsplatzes',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold,
                          color: Colors.deepOrange.shade900)),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Nach § 2 Abs. 5 der Entgeltordnung kann der Träger den Platz kündigen, '
                  'wenn zwei Monatsbeiträge trotz schriftlicher Mahnung offen sind. '
                  'Das Datum hier ist der früheste Tag, an dem das möglich wäre — '
                  'daran hängt die Warnung in der Übersicht.',
                  style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade900),
                ),
                const SizedBox(height: 8),
                _DatumFeld(
                  label: 'Kündigung möglich ab',
                  wert: _kuendigung,
                  onTap: () => _datum(_kuendigung, (d) => setState(() => _kuendigung = d)),
                  onLoeschen: () => setState(() => _kuendigung = null),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bezC,
              decoration: InputDecoration(
                labelText: 'Bezeichnung', isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notizC,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notizen', isDense: true, alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _speichert ? null : _speichern,
          style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
          child: Text(_speichert ? 'Speichert…' : 'Speichern'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Pflege des Nachschlagewerks
// ═══════════════════════════════════════════════════════════════════════

/// Anlegen und Ändern einer Stelle im Nachschlagewerk.
///
/// ⚠️ Öffentliche Anschriften einer Behörde — bleiben im Klartext, wie in
/// den 20 anderen Nachschlagewerken. Verschlüsselt gehört, was zum
/// MITGLIED gehört, nicht was am Rathaus steht.
class ZahlungsempfaengerDialog extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic>? vorhanden;
  const ZahlungsempfaengerDialog({super.key, required this.apiService, this.vorhanden});

  @override
  State<ZahlungsempfaengerDialog> createState() => _ZahlungsempfaengerDialogState();
}

class _ZahlungsempfaengerDialogState extends State<ZahlungsempfaengerDialog> {
  final Map<String, TextEditingController> _c = {};
  String _art = 'stadt';
  bool _speichert = false;

  static const felder = <(String, String, String)>[
    ('name', 'Name der Stelle *', ''),
    ('abteilung', 'Kasse / Abteilung', 'Stadtkasse'),
    ('strasse', 'Straße', ''),
    ('plz_ort', 'PLZ und Ort', ''),
    ('bundesland', 'Bundesland', ''),
    ('telefon', 'Telefon', ''),
    ('fax', 'Fax', ''),
    ('email', 'E-Mail der Kasse', 'Raten und Zahlungen gehen hierhin'),
    ('website', 'Website', ''),
    ('fachstelle', 'Fachstelle', 'Amt, das die Akte führt'),
    ('fachstelle_person', 'Ansprechpartner Fachstelle', ''),
    ('fachstelle_telefon', 'Telefon Fachstelle', ''),
    ('fachstelle_email', 'E-Mail der Fachstelle', 'Akteneinsicht und Härtefall gehen hierhin'),
    ('bank_inhaber', 'Kontoinhaber', ''),
    ('iban', 'IBAN', 'Prüfziffer wird geprüft'),
    ('bic', 'BIC', ''),
    ('bank_name', 'Kreditinstitut', ''),
    ('zahlungshinweis', 'Zahlungshinweis', 'z. B. „Kassenzeichen im Verwendungszweck"'),
  ];

  @override
  void initState() {
    super.initState();
    final v = widget.vorhanden ?? const <String, dynamic>{};
    for (final f in felder) {
      _c[f.$1] = TextEditingController(text: raWert(v[f.$1]));
    }
    if (raHat(v['art'])) _art = raWert(v['art']);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _speichern() async {
    if ((_c['name']?.text ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Der Name darf nicht leer sein'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _speichert = true);
    final id = int.tryParse(raWert(widget.vorhanden?['id'])) ?? 0;
    final res = await widget.apiService.saveZahlungsempfaenger({
      if (id > 0) 'id': id,
      'art': _art,
      for (final f in felder) f.$1: _c[f.$1]!.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    if (res['success'] == true) {
      Navigator.pop(context, int.tryParse(raWert(res['id'])) ?? id);
    } else {
      // ⚠️ Die Meldung des Servers wird GEZEIGT, nicht durch eine eigene
      // ersetzt: bei einer falschen IBAN steht dort die Prüfziffer-
      // Begründung, und die ist das Einzige, was weiterhilft.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(raWert(res['message']).isEmpty
            ? 'Speichern fehlgeschlagen'
            : raWert(res['message'])),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final breite = zahlungDialogGroesse(context).width;
    return AlertDialog(
      title: Text(widget.vorhanden == null ? 'Neue Stelle' : 'Stelle bearbeiten',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: breite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Art', isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _art,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'stadt', child: Text('Stadt', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'gemeinde', child: Text('Gemeinde', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'landkreis', child: Text('Landkreis', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'zweckverband', child: Text('Zweckverband', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'freier_traeger', child: Text('Freier Träger', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'kirche', child: Text('Kirchengemeinde', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'sonstige', child: Text('Sonstige', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _art = v ?? 'stadt'),
                ),
              ),
            ),
            for (final f in felder) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _c[f.$1],
                decoration: InputDecoration(
                  labelText: f.$2,
                  helperText: f.$3.isEmpty ? null : f.$3,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _speichert ? null : _speichern,
          style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
          child: Text(_speichert ? 'Speichert…' : 'Speichern'),
        ),
      ],
    );
  }
}
