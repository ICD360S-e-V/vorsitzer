import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/app_farben.dart';

/// Anlegen und Bearbeiten eines Bußgeld-Vorfalls.
///
/// Der Aufbau folgt dem Weg, den ein Schreiben der Bußgeldstelle nimmt:
/// erst was für eine Post es ist, dann die beiden Daten, aus denen sich die
/// Frist ergibt, dann Vorwurf, Tat und Beträge.
class BussgeldVorfallDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  /// Vorbelegung aus der zuständigen Stelle des Mitglieds.
  final int? stelleId;
  final String? stelleName;

  /// Beim Bearbeiten der bereits geladene Vorfall, sonst null.
  final Map<String, dynamic>? vorfall;

  const BussgeldVorfallDialog({
    super.key,
    required this.apiService,
    required this.userId,
    this.stelleId,
    this.stelleName,
    this.vorfall,
  });

  @override
  State<BussgeldVorfallDialog> createState() => _BussgeldVorfallDialogState();
}

/// Fristlänge in Tagen, § 67 Abs. 1 S. 1 OWiG: zwei Wochen nach Zustellung.
const int kBussgeldFristTage = 14;

/// Rechnet den Fristvorschlag aus dem ZUGANGSDATUM.
///
/// ⚠️ Nicht aus dem Datum auf dem Bescheid: § 67 Abs. 1 S. 1 OWiG lässt die
/// Frist „innerhalb von zwei Wochen nach Zustellung" laufen. Zwischen dem
/// aufgedruckten Datum und der Zustellung liegen regelmäßig Tage — wer von
/// oben rechnet, hält die Frist für kürzer als sie ist und verschenkt Zeit;
/// im umgekehrten Fall verpasst er sie.
///
/// Fällt das Ende auf Samstag oder Sonntag, endet die Frist nach
/// § 43 Abs. 2 StPO (über § 46 Abs. 1 OWiG) erst am nächsten Werktag.
///
/// ⚠️ Feiertage bleiben außen vor: sie sind Landesrecht und unterscheiden
/// sich zwischen Baden-Württemberg und Bayern. Ein Feiertag verschiebt das
/// Ende nur nach HINTEN — der Vorschlag ist also nie zu spät, höchstens zu
/// früh. Deshalb ist er als Vorschlag ausgewiesen und überschreibbar.
///
/// ⚠️ Gerechnet wird ueber die KALENDERFELDER, nicht mit [Duration].
/// `add(Duration(days: 14))` addiert 14 mal 24 Stunden - bei der Umstellung
/// auf die Winterzeit hat der Tag aber 25 Stunden, und das Ergebnis landet
/// einen Kalendertag zu frueh. Bei einer Einspruchsfrist ist ein Tag der
/// Unterschied zwischen zulaessig und rechtskraeftig. Der Konstruktor
/// DateTime(jahr, monat, tag + 14) normalisiert dagegen ueber den Kalender
/// und ist von der Zeitumstellung unberuehrt.
DateTime bussgeldFristVorschlag(DateTime zugang) {
  var d = DateTime(zugang.year, zugang.month, zugang.day + kBussgeldFristTage);
  while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseIso(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String _deutsch(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Die Postarten, die eine Bußgeldstelle verschickt — in der Reihenfolge, in
/// der sie im Verfahren auftreten.
const Map<String, String> kBussgeldArten = {
  'anhoerungsbogen': 'Anhörungsbogen',
  'zeugenfragebogen': 'Zeugenfragebogen',
  'verwarnung': 'Verwarnung mit Verwarnungsgeld',
  'bussgeldbescheid': 'Bußgeldbescheid',
  'kostenbescheid': 'Kostenbescheid',
  'mahnung': 'Mahnung',
  'vollstreckung': 'Vollstreckung',
  'sonstiges': 'Sonstiges Schreiben',
};

const Map<String, String> kBussgeldStatus = {
  'offen': 'Offen',
  'frist_laeuft': 'Frist läuft',
  'einspruch_eingelegt': 'Einspruch eingelegt',
  'rechtskraeftig': 'Rechtskräftig',
  'eingestellt': 'Eingestellt',
  'bezahlt': 'Bezahlt',
  'abgeschlossen': 'Abgeschlossen',
};

const Map<String, String> kFristArten = {
  'einspruch': 'Einspruchsfrist (§ 67 OWiG)',
  'anhoerung': 'Äußerungsfrist (Anhörung)',
  'zahlung': 'Zahlungsfrist',
  'sonstige': 'Sonstige Frist',
};

const Map<String, String> kEinspruchWege = {
  'post': 'Post',
  'fax': 'Fax',
  'niederschrift': 'Zur Niederschrift bei der Behörde',
  'elektronisch': 'Elektronisch',
  'sonstige': 'Sonstiger Weg',
};

class _BussgeldVorfallDialogState extends State<BussgeldVorfallDialog> {
  final _aktenzeichen = TextEditingController();
  final _vorwurf = TextEditingController();
  final _tbnr = TextEditingController();
  final _kennzeichen = TextEditingController();
  final _tatortStrasse = TextEditingController();
  final _tatortPlz = TextEditingController();
  final _tatortOrt = TextEditingController();
  final _tatortBemerkung = TextEditingController();
  final _geldbusse = TextEditingController();
  final _gebuehren = TextEditingController();
  final _auslagen = TextEditingController();
  final _punkte = TextEditingController();
  final _fahrverbot = TextEditingController();
  final _sachbearbeiter = TextEditingController();
  final _sachbearbeiterTel = TextEditingController();
  final _beschreibung = TextEditingController();

  String _art = 'bussgeldbescheid';
  String _status = 'offen';
  String _fristArt = 'einspruch';
  String _fahrerWarMitglied = 'unbekannt';
  String? _einspruchWeg;
  bool _einspruchEingelegt = false;

  DateTime? _bescheidDatum;
  DateTime? _zugangDatum;
  DateTime? _fristBis;
  DateTime? _tatzeitDatum;
  DateTime? _einspruchDatum;
  DateTime? _bezahltAm;
  TimeOfDay? _tatzeit;

  /// Solange der Nutzer die Frist nicht selbst angefasst hat, zieht sie beim
  /// Ändern des Zugangsdatums mit. Danach nicht mehr — eine von Hand
  /// gesetzte Frist ist eine Angabe aus dem Bescheid und darf nicht von
  /// unserer Rechnung überschrieben werden.
  bool _fristHandisch = false;

  bool _speichert = false;

  bool get _istNeu => widget.vorfall == null;

  @override
  void initState() {
    super.initState();
    final v = widget.vorfall;
    if (v != null) {
      _art = kBussgeldArten.containsKey(v['art']) ? v['art'] as String : 'bussgeldbescheid';
      _status = kBussgeldStatus.containsKey(v['status']) ? v['status'] as String : 'offen';
      _fristArt = kFristArten.containsKey(v['frist_art']) ? v['frist_art'] as String : 'einspruch';
      _fahrerWarMitglied = v['fahrer_war_mitglied']?.toString() ?? 'unbekannt';
      _einspruchWeg = kEinspruchWege.containsKey(v['einspruch_weg']) ? v['einspruch_weg'] as String : null;
      _einspruchEingelegt = v['einspruch_eingelegt'] == 1 || v['einspruch_eingelegt'] == true;
      _aktenzeichen.text = v['aktenzeichen']?.toString() ?? '';
      _vorwurf.text = v['vorwurf']?.toString() ?? '';
      _tbnr.text = v['tbnr']?.toString() ?? '';
      _kennzeichen.text = v['kennzeichen']?.toString() ?? '';
      _tatortStrasse.text = v['tatort_strasse']?.toString() ?? '';
      _tatortPlz.text = v['tatort_plz']?.toString() ?? '';
      _tatortOrt.text = v['tatort_ort']?.toString() ?? '';
      _tatortBemerkung.text = v['tatort_bemerkung']?.toString() ?? '';
      _geldbusse.text = _betrag(v['betrag_geldbusse']);
      _gebuehren.text = _betrag(v['betrag_gebuehren']);
      _auslagen.text = _betrag(v['betrag_auslagen']);
      _punkte.text = v['punkte']?.toString() ?? '';
      _fahrverbot.text = v['fahrverbot_monate']?.toString() ?? '';
      _sachbearbeiter.text = v['sachbearbeiter_name']?.toString() ?? '';
      _sachbearbeiterTel.text = v['sachbearbeiter_telefon']?.toString() ?? '';
      _beschreibung.text = v['beschreibung']?.toString() ?? '';
      _bescheidDatum = _parseIso(v['bescheid_datum']?.toString());
      _zugangDatum = _parseIso(v['zugang_datum']?.toString());
      _fristBis = _parseIso(v['frist_bis']?.toString());
      _tatzeitDatum = _parseIso(v['tatzeit_datum']?.toString());
      _einspruchDatum = _parseIso(v['einspruch_datum']?.toString());
      _bezahltAm = _parseIso(v['bezahlt_am']?.toString());
      final st = v['tatzeit_stunde'], mi = v['tatzeit_minute'];
      if (st != null) {
        _tatzeit = TimeOfDay(
          hour: int.tryParse(st.toString()) ?? 0,
          minute: int.tryParse(mi?.toString() ?? '0') ?? 0,
        );
      }
      // Eine gespeicherte Frist gilt als gesetzt; sie darf nicht durch
      // bloßes Öffnen des Dialogs neu gerechnet werden.
      _fristHandisch = _fristBis != null;
    }
  }

  static String _betrag(dynamic v) {
    if (v == null) return '';
    final d = double.tryParse(v.toString());
    return d == null ? v.toString() : d.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    for (final c in [
      _aktenzeichen, _vorwurf, _tbnr, _kennzeichen, _tatortStrasse, _tatortPlz,
      _tatortOrt, _tatortBemerkung, _geldbusse, _gebuehren, _auslagen, _punkte,
      _fahrverbot, _sachbearbeiter, _sachbearbeiterTel, _beschreibung,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _datumWaehlen(DateTime? aktuell, ValueChanged<DateTime?> setzen) async {
    final d = await showDatePicker(
      context: context,
      initialDate: aktuell ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      locale: const Locale('de', 'DE'),
    );
    if (d != null) setzen(d);
  }

  double? _zahl(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  double get _gesamt =>
      (_zahl(_geldbusse) ?? 0) + (_zahl(_gebuehren) ?? 0) + (_zahl(_auslagen) ?? 0);

  Future<void> _speichern() async {
    if (_aktenzeichen.text.trim().isEmpty) {
      _melden('Bitte das Aktenzeichen eintragen — ohne das findet die Behörde den Vorgang nicht.');
      return;
    }
    setState(() => _speichert = true);
    final daten = <String, dynamic>{
      if (!_istNeu) 'id': widget.vorfall!['id'],
      'stelle_id': widget.stelleId,
      'stelle_name': widget.stelleName,
      'art': _art,
      'status': _status,
      'frist_art': _fristArt,
      'aktenzeichen': _aktenzeichen.text.trim(),
      'bescheid_datum': _bescheidDatum == null ? null : _iso(_bescheidDatum!),
      'zugang_datum': _zugangDatum == null ? null : _iso(_zugangDatum!),
      // Nur mitschicken, wenn der Nutzer sie selbst gesetzt hat. Sonst
      // rechnet der Server — und bleibt damit die eine Stelle, an der die
      // Frist entsteht.
      if (_fristHandisch && _fristBis != null) 'frist_bis': _iso(_fristBis!),
      'tatzeit_datum': _tatzeitDatum == null ? null : _iso(_tatzeitDatum!),
      'tatzeit_stunde': _tatzeit?.hour,
      'tatzeit_minute': _tatzeit?.minute,
      'tatort_strasse': _tatortStrasse.text.trim(),
      'tatort_plz': _tatortPlz.text.trim(),
      'tatort_ort': _tatortOrt.text.trim(),
      'tatort_bemerkung': _tatortBemerkung.text.trim(),
      'vorwurf': _vorwurf.text.trim(),
      'tbnr': _tbnr.text.trim(),
      'betrag_geldbusse': _geldbusse.text.trim(),
      'betrag_gebuehren': _gebuehren.text.trim(),
      'betrag_auslagen': _auslagen.text.trim(),
      'punkte': _punkte.text.trim(),
      'fahrverbot_monate': _fahrverbot.text.trim(),
      'kennzeichen': _kennzeichen.text.trim(),
      'fahrer_war_mitglied': _fahrerWarMitglied,
      'einspruch_eingelegt': _einspruchEingelegt ? 1 : 0,
      'einspruch_datum': _einspruchDatum == null ? null : _iso(_einspruchDatum!),
      'einspruch_weg': _einspruchWeg,
      'bezahlt_am': _bezahltAm == null ? null : _iso(_bezahltAm!),
      'sachbearbeiter_name': _sachbearbeiter.text.trim(),
      'sachbearbeiter_telefon': _sachbearbeiterTel.text.trim(),
      'beschreibung': _beschreibung.text.trim(),
    };
    final r = await widget.apiService.saveBussgeldVorfall(widget.userId, daten);
    if (!mounted) return;
    setState(() => _speichert = false);
    if (r['success'] == true) {
      Navigator.of(context).pop(true);
    } else {
      // ⚠️ Grund anzeigen, nicht schweigen: ein stiller Fehlschlag ist von
      // „ich habe danebengetippt" nicht zu unterscheiden.
      _melden('Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}');
    }
  }

  void _melden(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final frist = _fristBis ??
        (_zugangDatum == null ? null : bussgeldFristVorschlag(_zugangDatum!));
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.gavel, color: F.h(Colors.deepOrange, 700)),
        const SizedBox(width: 8),
        Expanded(child: Text(_istNeu ? 'Neuer Bußgeld-Vorfall' : 'Vorfall bearbeiten')),
      ]),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.stelleName != null && widget.stelleName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(Icons.account_balance, size: 16, color: F.h(Colors.grey, 600)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(widget.stelleName!,
                      style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
                ]),
              ),

            _abschnitt('Schreiben'),
            DropdownButtonFormField<String>(
              key: const Key('bg_art'),
              initialValue: _art,
              decoration: const InputDecoration(labelText: 'Art des Schreibens', border: OutlineInputBorder(), isDense: true),
              items: [for (final e in kBussgeldArten.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _art = v ?? _art),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('bg_aktenzeichen'),
              controller: _aktenzeichen,
              decoration: const InputDecoration(
                labelText: 'Aktenzeichen *', border: OutlineInputBorder(), isDense: true,
                hintText: 'genau wie auf dem Schreiben',
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _datumFeld('Datum des Schreibens', _bescheidDatum,
                  (d) => setState(() => _bescheidDatum = d), key: const Key('bg_bescheid_datum'))),
              const SizedBox(width: 10),
              Expanded(child: _datumFeld('Zugegangen am', _zugangDatum, (d) {
                setState(() {
                  _zugangDatum = d;
                  if (!_fristHandisch) _fristBis = null; // wird neu vorgeschlagen
                });
              }, key: const Key('bg_zugang_datum'))),
            ]),
            const SizedBox(height: 6),
            Text(
              'Die Frist läuft ab dem Tag der Zustellung, nicht ab dem Datum auf dem Schreiben (§ 67 Abs. 1 OWiG).',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
            ),

            const SizedBox(height: 12),
            _abschnitt('Frist'),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _fristArt,
                  decoration: const InputDecoration(labelText: 'Art der Frist', border: OutlineInputBorder(), isDense: true),
                  items: [for (final e in kFristArten.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _fristArt = v ?? _fristArt),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _datumFeld('Frist endet am', frist, (d) {
                  setState(() { _fristBis = d; _fristHandisch = true; });
                }, key: const Key('bg_frist_bis')),
              ),
            ]),
            if (frist != null) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _fristHinweis(frist),
            ),

            const SizedBox(height: 12),
            _abschnitt('Vorwurf und Tat'),
            TextField(
              key: const Key('bg_vorwurf'),
              controller: _vorwurf,
              decoration: const InputDecoration(
                labelText: 'Vorwurf', border: OutlineInputBorder(), isDense: true,
                hintText: 'z.B. Geschwindigkeitsüberschreitung 21 km/h innerorts',
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _tbnr, decoration: const InputDecoration(
                labelText: 'Tatbestandsnummer (TBNR)', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _kennzeichen, decoration: const InputDecoration(
                labelText: 'Kennzeichen', border: OutlineInputBorder(), isDense: true))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _datumFeld('Tatzeit — Datum', _tatzeitDatum,
                  (d) => setState(() => _tatzeitDatum = d))),
              const SizedBox(width: 10),
              Expanded(child: InkWell(
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _tatzeit ?? TimeOfDay.now());
                  if (t != null) setState(() => _tatzeit = t);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Tatzeit — Uhrzeit', border: OutlineInputBorder(), isDense: true),
                  child: Text(_tatzeit == null
                      ? '—'
                      : '${_tatzeit!.hour.toString().padLeft(2, '0')}:${_tatzeit!.minute.toString().padLeft(2, '0')}'),
                ),
              )),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: _tatortStrasse, decoration: const InputDecoration(
                labelText: 'Tatort — Straße', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _tatortPlz, decoration: const InputDecoration(
                labelText: 'PLZ', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: TextField(controller: _tatortOrt, decoration: const InputDecoration(
                labelText: 'Ort', border: OutlineInputBorder(), isDense: true))),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _fahrerWarMitglied,
              decoration: const InputDecoration(labelText: 'Hat das Mitglied selbst gefahren?', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'ja', child: Text('Ja')),
                DropdownMenuItem(value: 'nein', child: Text('Nein')),
                DropdownMenuItem(value: 'unbekannt', child: Text('Unbekannt / offen')),
              ],
              onChanged: (v) => setState(() => _fahrerWarMitglied = v ?? _fahrerWarMitglied),
            ),

            const SizedBox(height: 12),
            _abschnitt('Beträge und Folgen'),
            Row(children: [
              Expanded(child: _betragFeld('Geldbuße', _geldbusse, const Key('bg_geldbusse'))),
              const SizedBox(width: 10),
              Expanded(child: _betragFeld('Gebühren', _gebuehren, const Key('bg_gebuehren'))),
              const SizedBox(width: 10),
              Expanded(child: _betragFeld('Auslagen', _auslagen, const Key('bg_auslagen'))),
            ]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Gesamt: ${_gesamt.toStringAsFixed(2).replaceAll('.', ',')} €',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _punkte, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Punkte in Flensburg', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _fahrverbot, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Fahrverbot (Monate)', border: OutlineInputBorder(), isDense: true))),
            ]),

            const SizedBox(height: 12),
            _abschnitt('Einspruch und Zahlung'),
            CheckboxListTile(
              key: const Key('bg_einspruch'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _einspruchEingelegt,
              title: const Text('Einspruch eingelegt'),
              subtitle: const Text('schriftlich oder zur Niederschrift bei der Behörde, die den Bescheid erlassen hat',
                  style: TextStyle(fontSize: 11)),
              onChanged: (v) => setState(() {
                _einspruchEingelegt = v ?? false;
                if (_einspruchEingelegt && _status == 'offen') _status = 'einspruch_eingelegt';
              }),
            ),
            if (_einspruchEingelegt) Row(children: [
              Expanded(child: _datumFeld('Einspruch am', _einspruchDatum,
                  (d) => setState(() => _einspruchDatum = d))),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _einspruchWeg,
                decoration: const InputDecoration(labelText: 'Auf welchem Weg', border: OutlineInputBorder(), isDense: true),
                items: [for (final e in kEinspruchWege.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _einspruchWeg = v),
              )),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _datumFeld('Bezahlt am', _bezahltAm, (d) => setState(() {
                _bezahltAm = d;
                if (_status == 'offen' || _status == 'frist_laeuft') _status = 'bezahlt';
              }))),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                key: const Key('bg_status'),
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
                items: [for (final e in kBussgeldStatus.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _status = v ?? _status),
              )),
            ]),

            const SizedBox(height: 12),
            _abschnitt('Sachbearbeitung und Notizen'),
            Row(children: [
              Expanded(child: TextField(controller: _sachbearbeiter, decoration: const InputDecoration(
                labelText: 'Sachbearbeiter/in', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _sachbearbeiterTel, decoration: const InputDecoration(
                labelText: 'Telefon', border: OutlineInputBorder(), isDense: true))),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _beschreibung, maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder(), isDense: true),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _speichert ? null : () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
        ElevatedButton.icon(
          icon: _speichert
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 18),
          label: Text(_istNeu ? 'Anlegen' : 'Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
          onPressed: _speichert ? null : _speichern,
        ),
      ],
    );
  }

  Widget _abschnitt(String titel) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(titel.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: .6, color: F.h(Colors.grey, 600))),
      );

  Widget _betragFeld(String label, TextEditingController c, Key key) => TextField(
        key: key,
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true, suffixText: '€'),
      );

  Widget _datumFeld(String label, DateTime? wert, ValueChanged<DateTime?> setzen, {Key? key}) => InkWell(
        key: key,
        onTap: () => _datumWaehlen(wert, setzen),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder(), isDense: true,
            suffixIcon: wert == null
                ? const Icon(Icons.calendar_today, size: 16)
                : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setzen(null)),
          ),
          child: Text(wert == null ? '—' : _deutsch(wert)),
        ),
      );

  Widget _fristHinweis(DateTime frist) {
    final heute = DateTime.now();
    final tage = DateTime(frist.year, frist.month, frist.day)
        .difference(DateTime(heute.year, heute.month, heute.day))
        .inDays;
    final abgelaufen = tage < 0;
    final knapp = tage >= 0 && tage <= 3;
    final farbe = abgelaufen
        ? F.h(Colors.red, 700)
        : knapp
            ? F.h(Colors.orange, 800)
            : F.h(Colors.grey, 700);
    final text = abgelaufen
        ? 'Frist am ${_deutsch(frist)} abgelaufen (vor ${-tage} Tagen).'
        : tage == 0
            ? 'Frist endet HEUTE, ${_deutsch(frist)}.'
            : 'Noch $tage Tage bis ${_deutsch(frist)}.';
    return Row(children: [
      Icon(abgelaufen ? Icons.error_outline : Icons.schedule, size: 15, color: farbe),
      const SizedBox(width: 6),
      Expanded(child: Text(
        _fristHandisch ? text : '$text  (berechnet — Feiertage nicht berücksichtigt)',
        style: TextStyle(fontSize: 11, color: farbe, fontWeight: knapp || abgelaufen ? FontWeight.bold : null),
      )),
    ]);
  }
}
