import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import 'phone_link.dart';

/// Der Reiter „Zuständige Radiologie" einer Überweisung.
///
/// WOFÜR
/// Eine Überweisung nennt ein Fach, keine Praxis. Wer sie einlöst, muss erst
/// wissen, WO — und bei einer Radiologie hängt daran mehr als eine Adresse:
///
/// 🔴 `kassenpraxis` — eine Privatpraxis nimmt eine Kassen-Überweisung nicht
/// an. Wer das erst am Telefon erfährt, hat Tage verloren; wer es erst vor Ort
/// erfährt, ist umsonst hingefahren. Deshalb steht es als erstes Merkmal auf
/// der Karte und nicht in einer Fußnote.
///
/// 🔴 `mrt_offen` — für einen Menschen mit Platzangst ist eine geschlossene
/// Röhre kein Termin, sondern ein Abbruch. Dieser Verein hat Mitglieder, für
/// die das der Unterschied zwischen Untersuchung und keiner Untersuchung ist.
///
/// ⚠️ `modalitaeten` — eine Überweisung zum MRT an eine Praxis ohne MRT ist
/// eine vertane Anfrage und zwei Wochen Wartezeit.
///
/// ⚠️ Die Praxis wird IN DIE ÜBERWEISUNG kopiert, nicht nur verlinkt. Ändert
/// sich später die Datenbank, bleibt in der Akte, wohin damals überwiesen
/// wurde — eine Akte, die sich rückwirkend ändert, ist als Nachweis wertlos.
class RadiologiePraxisTab extends StatefulWidget {
  /// Die Überweisung. Wird IN PLACE geändert; [speichern] schreibt sie zurück.
  final Map<String, dynamic> ueberweisung;
  final VoidCallback speichern;
  final ApiService apiService;

  const RadiologiePraxisTab({
    super.key,
    required this.ueberweisung,
    required this.speichern,
    required this.apiService,
  });

  @override
  State<RadiologiePraxisTab> createState() => _RadiologiePraxisTabState();
}

class _RadiologiePraxisTabState extends State<RadiologiePraxisTab> {
  Map<String, dynamic> get _u => widget.ueberweisung;

  String _f(String k) => (_u[k]?.toString() ?? '').trim();

  bool get _gewaehlt => _f('rad_praxis_name').isNotEmpty;

  /// Übernimmt die Praxis in die Überweisung.
  void _uebernehmen(Map<String, dynamic> p) {
    _u['rad_praxis_id'] = p['id'];
    _u['rad_praxis_name'] = p['praxis_name']?.toString() ?? '';
    _u['rad_praxis_traeger'] = p['traeger']?.toString() ?? '';
    _u['rad_praxis_strasse'] = p['strasse']?.toString() ?? '';
    _u['rad_praxis_plz_ort'] = p['plz_ort']?.toString() ?? '';
    _u['rad_praxis_telefon'] = p['telefon']?.toString() ?? '';
    _u['rad_praxis_telefon_zusatz'] = p['telefon_zusatz']?.toString() ?? '';
    _u['rad_praxis_fax'] = p['fax']?.toString() ?? '';
    _u['rad_praxis_email'] = p['email']?.toString() ?? '';
    _u['rad_praxis_website'] = p['website']?.toString() ?? '';
    _u['rad_praxis_portal_url'] = p['portal_url']?.toString() ?? '';
    _u['rad_praxis_portal_label'] = p['portal_label']?.toString() ?? '';
    _u['rad_praxis_sprechzeiten'] = p['sprechzeiten']?.toString() ?? '';
    _u['rad_praxis_modalitaeten'] = p['modalitaeten']?.toString() ?? '';
    // ⚠️ Als Zahl gespeichert, nicht als bool: der Server liefert 0/1, und ein
    // `== true` auf einer 1 ist in Dart false. Genau so verschwinden Merkmale
    // lautlos.
    _u['rad_praxis_kassenpraxis'] = (p['kassenpraxis']?.toString() ?? '1') == '1' ? 1 : 0;
    _u['rad_praxis_mrt_offen'] = (p['mrt_offen']?.toString() ?? '0') == '1' ? 1 : 0;
    _u['rad_praxis_mrt_tesla'] = p['mrt_tesla']?.toString() ?? '';
    _u['rad_praxis_max_gewicht'] = p['max_gewicht_kg']?.toString() ?? '';
    _u['rad_praxis_wartezeit'] = p['wartezeit_hinweis']?.toString() ?? '';
    widget.speichern();
    setState(() {});
  }

  Future<void> _suchen() async {
    final gewaehlt = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RadiologieSucheDialog(
        apiService: widget.apiService,
        // Was auf der Überweisung steht, ist der sinnvolle Vorfilter.
        modalitaet: _modalitaetAusUeberweisung(),
      ),
    );
    if (gewaehlt != null) _uebernehmen(gewaehlt);
  }

  /// Rät aus dem Überweisungstext, welches Gerät gemeint ist.
  ///
  /// ⚠️ Nur ein VORFILTER, kein Urteil: im Suchdialog lässt er sich abschalten.
  /// Eine Überweisung, in der „MRT" nicht wörtlich steht, würde sonst alle
  /// Praxen ausblenden.
  String _modalitaetAusUeberweisung() {
    final text = [
      _f('untersuchung'), _f('fragestellung'), _f('diagnose'), _f('befunde'),
      _f('fachrichtung'), _f('an'),
    ].join(' ').toUpperCase();
    for (final m in const [
      ('MRT', ['MRT', 'KERNSPIN', 'MAGNETRESONANZ']),
      ('CT', ['CT ', 'COMPUTERTOMO']),
      ('Mammographie', ['MAMMOGRAF', 'MAMMOGRAPH']),
      ('Nuklearmedizin', ['SZINTIGRAF', 'SZINTIGRAPH', 'NUKLEAR']),
      ('Roentgen', ['RÖNTGEN', 'ROENTGEN']),
    ]) {
      for (final wort in m.$2) {
        if (text.contains(wort)) return m.$1;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.medical_information, size: 18, color: F.h(Colors.deepPurple, 700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Zuständige Praxis',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.deepPurple, 800))),
          ),
          IconButton(
            tooltip: 'In der Radiologie-Datenbank suchen',
            icon: Icon(Icons.search, size: 20, color: F.h(Colors.deepPurple, 700)),
            onPressed: _suchen,
          ),
        ]),
        const SizedBox(height: 8),
        if (!_gewaehlt)
          _leer()
        else
          _karte(),
      ]),
    );
  }

  Widget _leer() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: F.h(Colors.amber, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.amber, 300)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Noch keine Praxis ausgewählt',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.amber, 900))),
          const SizedBox(height: 6),
          Text('Über die Lupe eine Praxis aus der Radiologie-Datenbank wählen. '
               'Von dort kommen Anschrift, Telefon, Fax und E-Mail — und damit '
               'auch die Wege, auf denen eine Terminanfrage rausgehen kann.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.amber, 900))),
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Praxis suchen', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: F.h(Colors.deepPurple, 600)),
            onPressed: _suchen,
          ),
        ]),
      );

  Widget _karte() {
    final kasse = _u['rad_praxis_kassenpraxis']?.toString() == '1';
    final offen = _u['rad_praxis_mrt_offen']?.toString() == '1';
    final mod = _f('rad_praxis_modalitaeten')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F.h(Colors.deepPurple, 50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(Colors.deepPurple, 150)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(_f('rad_praxis_name'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.deepPurple, 900))),
          ),
          TextButton.icon(
            icon: Icon(Icons.swap_horiz, size: 14, color: F.h(Colors.deepPurple, 600)),
            label: Text('Ändern', style: TextStyle(fontSize: 11, color: F.h(Colors.deepPurple, 600))),
            onPressed: _suchen,
          ),
        ]),

        // 🔴 Das wichtigste Merkmal steht ganz oben und farbig: eine
        // Privatpraxis nimmt die Kassen-Überweisung nicht an.
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _merkmal(
            kasse ? Icons.verified : Icons.euro,
            kasse ? 'Kassenpraxis' : 'PRIVATPRAXIS — keine Kassen-Überweisung',
            kasse ? Colors.green : Colors.red,
          ),
          // ⚠️ Nicht zeigen, wenn der Träger dasselbe sagt wie die Plakette
          // daneben: „PRIVATPRAXIS — keine Kassen-Überweisung" und
          // „Privatpraxis" standen sonst nebeneinander. Auf dem gerenderten
          // Bild sofort zu sehen, im Code nicht.
          if (_f('rad_praxis_traeger').isNotEmpty &&
              !(!kasse && _f('rad_praxis_traeger').toLowerCase().contains('privat')))
            _merkmal(Icons.business, _f('rad_praxis_traeger'), Colors.blueGrey),
          if (offen) _merkmal(Icons.open_in_full, 'Offenes MRT', Colors.teal),
          if (_f('rad_praxis_mrt_tesla').isNotEmpty)
            _merkmal(Icons.speed, 'MRT ${_f('rad_praxis_mrt_tesla')}', Colors.indigo),
          if (_f('rad_praxis_max_gewicht').isNotEmpty)
            _merkmal(Icons.monitor_weight, 'bis ${_f('rad_praxis_max_gewicht')} kg', Colors.orange),
        ]),

        if (mod.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Geräte', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          Wrap(spacing: 5, runSpacing: 4, children: [
            for (final m in mod)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: F.h(Colors.deepPurple, 100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(m, style: TextStyle(fontSize: 10, color: F.h(Colors.deepPurple, 900))),
              ),
          ]),
        ],

        const SizedBox(height: 10),
        _zeile(Icons.place, [_f('rad_praxis_strasse'), _f('rad_praxis_plz_ort')]
            .where((e) => e.isNotEmpty)
            .join(', ')),
        _zeile(Icons.phone, _f('rad_praxis_telefon')),
        _zeile(Icons.dialpad, _f('rad_praxis_telefon_zusatz')),
        _zeile(Icons.fax, _f('rad_praxis_fax')),
        _zeile(Icons.email, _f('rad_praxis_email')),
        _zeile(Icons.schedule, _f('rad_praxis_sprechzeiten')),
        _zeile(Icons.hourglass_bottom, _f('rad_praxis_wartezeit')),

        // Woran die Terminanfrage hängt: ohne einen dieser beiden Wege geht
        // von hier nichts raus. Lieber vorher sagen als hinterher ausgrauen.
        if (_f('rad_praxis_email').isEmpty && _f('rad_praxis_fax').isEmpty) ...[
          const SizedBox(height: 8),
          Text('Für diese Praxis ist weder E-Mail noch Fax hinterlegt — eine '
               'Terminanfrage kann von hier nicht rausgehen. Telefonisch '
               'erfragen und in der Radiologie-Datenbank nachtragen.',
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: F.h(Colors.red, 700))),
        ],
      ]),
    );
  }

  /// Eine Zeile der Praxiskarte.
  ///
  /// ⚠️ Der Wert geht durch [phoneAwareText], nicht durch ein blosses [Text].
  /// Der Helfer entscheidet selbst: hinter einem Telefon-Icon wird eine
  /// wählbare Nummer tippbar, alles andere bleibt, wie es ist. Ein eigenes
  /// [PhoneTapTarget] darumzuwickeln funktioniert zwar auch, aber der
  /// Wächtertest `rufnummern_waehlbar_test.dart` kann das nicht sehen — und
  /// genau der hat hier zugeschlagen.
  ///
  /// ⚠️ `telefon_zusatz` bleibt bewusst NICHT tippbar: dort stehen mehrere
  /// Durchwahlen in einem Fließtext („MRT: …, Mammographie: …"). Welche davon
  /// gemeint ist, kann niemand raten, und ein Tipper, der die falsche wählt,
  /// ist schlimmer als einer, der die Nummer abliest. Nachgesehen am
  /// gerenderten Bild — der Satz stimmt mit dem überein, was zu sehen ist.
  Widget _zeile(IconData i, String wert) => wert.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 13, color: F.h(Colors.grey, 500)),
            const SizedBox(width: 6),
            Expanded(
              child: phoneAwareText(
                i,
                wert,
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 800)),
                label: _f('rad_praxis_name'),
              ),
            ),
          ]),
        );

  Widget _merkmal(IconData i, String text, MaterialColor c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: F.h(c, 100), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 12, color: F.h(c, 800)),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: F.h(c, 800))),
        ]),
      );
}

/// Die Lupe: Suche in `radiologie_praxen`.
class _RadiologieSucheDialog extends StatefulWidget {
  final ApiService apiService;
  final String modalitaet;

  const _RadiologieSucheDialog({required this.apiService, required this.modalitaet});

  @override
  State<_RadiologieSucheDialog> createState() => _RadiologieSucheDialogState();
}

class _RadiologieSucheDialogState extends State<_RadiologieSucheDialog> {
  final _suche = TextEditingController();
  List<Map<String, dynamic>> _treffer = const [];
  bool _laedt = true;
  late String _modalitaet;
  bool _nurKasse = false;

  @override
  void initState() {
    super.initState();
    _modalitaet = widget.modalitaet;
    _laden();
  }

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final r = await widget.apiService.radiologiePraxen(
      search: _suche.text.trim(),
      modalitaet: _modalitaet,
      nurKassenpraxis: _nurKasse,
    );
    if (!mounted) return;
    setState(() {
      _treffer = ((r['praxen'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _laedt = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.search, size: 20, color: F.h(Colors.deepPurple, 700)),
        const SizedBox(width: 8),
        const Expanded(child: Text('Radiologie-Praxis wählen', style: TextStyle(fontSize: 15))),
      ]),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(children: [
          TextField(
            controller: _suche,
            onSubmitted: (_) => _laden(),
            decoration: InputDecoration(
              hintText: 'Name, Ort oder Straße',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, size: 16), onPressed: _laden),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(children: [
            // ⚠️ Der Gerätefilter ist vorbelegt aus dem Überweisungstext, aber
            // abschaltbar: steht dort „MRT" nicht wörtlich, blendete er sonst
            // alles aus.
            Expanded(
              child: Wrap(spacing: 5, children: [
                for (final m in const ['', 'MRT', 'CT', 'Roentgen', 'Mammographie', 'Nuklearmedizin'])
                  ChoiceChip(
                    label: Text(m.isEmpty ? 'alle Geräte' : m, style: const TextStyle(fontSize: 10)),
                    selected: _modalitaet == m,
                    onSelected: (_) { setState(() => _modalitaet = m); _laden(); },
                  ),
              ]),
            ),
          ]),
          Row(children: [
            Checkbox(
              value: _nurKasse,
              onChanged: (v) { setState(() => _nurKasse = v ?? false); _laden(); },
            ),
            Expanded(
              child: Text('nur Kassenpraxen — eine Privatpraxis nimmt die Überweisung nicht an',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
            ),
          ]),
          const Divider(height: 12),
          Expanded(
            child: _laedt
                ? const Center(child: CircularProgressIndicator())
                : _treffer.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Keine Praxis gefunden.\n\nDie Radiologie-Datenbank ist eigenständig — '
                            'was hier fehlt, muss dort angelegt werden.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500)),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _treffer.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _zeile(_treffer[i]),
                      ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      ],
    );
  }

  Widget _zeile(Map<String, dynamic> p) {
    final kasse = p['kassenpraxis']?.toString() == '1';
    final mod = (p['modalitaeten']?.toString() ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(' · ');
    final wege = <String>[
      if ((p['email']?.toString() ?? '').isNotEmpty) 'E-Mail',
      if ((p['fax']?.toString() ?? '').isNotEmpty) 'Fax',
    ];

    return InkWell(
      onTap: () => Navigator.pop(context, p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(p['praxis_name']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            if (!kasse)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: F.h(Colors.red, 100), borderRadius: BorderRadius.circular(10)),
                child: Text('Privat',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: F.h(Colors.red, 800))),
              ),
          ]),
          const SizedBox(height: 2),
          Text([p['strasse'], p['plz_ort']].where((e) => (e?.toString() ?? '').isNotEmpty).join(', '),
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          if (mod.isNotEmpty)
            Text(mod, style: TextStyle(fontSize: 10, color: F.h(Colors.deepPurple, 700))),
          // Woran eine Terminanfrage hängt — auf einen Blick, vor der Auswahl.
          Text(
            wege.isEmpty ? 'kein Versandweg hinterlegt' : 'erreichbar per ${wege.join(' und ')}',
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: wege.isEmpty ? F.h(Colors.red, 700) : F.h(Colors.grey, 600),
            ),
          ),
        ]),
      ),
    );
  }
}
