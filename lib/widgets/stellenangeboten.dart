import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user.dart';
import '../services/api_service.dart';

/// Stellenangebote — searches the Bundesagentur fuer Arbeit Jobboerse and
/// displays results. Sits next to "Bewerbungsuebersicht" so the Vorsitzer can
/// hand a member a fresh list of open positions during the same session.
///
/// Default search: free-text was=Member's letzter Beruf (if any) + wo=user.plz +
/// umkreis=25. The user can override everything before searching.
class StellenangebotenContent extends StatefulWidget {
  final ApiService apiService;
  final User user;
  /// Berufserfahrung-Liste des Mitglieds (aus _arbeitgeberFromDB) — daraus
  /// extrahieren wir die `funktion`-Felder als Such-Vorschlaege.
  final List<Map<String, dynamic>> berufserfahrung;
  const StellenangebotenContent({
    super.key,
    required this.apiService,
    required this.user,
    this.berufserfahrung = const [],
  });

  @override
  State<StellenangebotenContent> createState() => _StellenangebotenContentState();
}

class _StellenangebotenContentState extends State<StellenangebotenContent>
    with AutomaticKeepAliveClientMixin {
  // KeepAlive sorgt dafuer, dass das Widget beim Wechsel des Eltern-Tabs
  // (Zustaendiger / Stellen / Bewerbungs / Stellenangebote) nicht
  // disposed wird — die Auswahl bleibt zwischen Tab-Klicks erhalten.
  @override
  bool get wantKeepAlive => true;

  final _wasC = TextEditingController();
  final _woC = TextEditingController();
  int _umkreis = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  int _page = 1;
  int? _total;
  int? _initial;
  bool _filterOffen = false;

  // Erweiterte Filter
  String? _arbeitszeit;            // null = alle; sonst vz/tz/snw/ho/mj
  int? _befristung;                // null = alle; 1 = befristet, 2 = unbefristet
  int? _veroeffentlichtSeit;       // null = alle; sonst Tage (3/7/14/30)
  int _angebotsart = 1;            // 1=Arbeit, 2=Selbstaendigkeit, 4=Ausbildung, 34=Praktikum

  // Mehrfachauswahl der Vorerfahrungs-Chips. Leer = nur Freitext aus _wasC.
  final Set<String> _selectedBerufe = {};

  // Smart-Filter: blendet Stellen aus, die eine Qualifikation verlangen,
  // die das Mitglied laut Profil nicht hat. Pro Card ein lazy fetch des
  // Vollinhalts (gecacht nach refnr) — danach Keyword-Match auf
  // titel + beschreibung.
  bool _nurPassendeStellen = true;
  bool _nurNeueStellen = true; // blendet bereits beworbene Stellen aus
  bool _hatFuehrerschein = false;
  bool _hatGabelstapler = false;
  /// Profilwert: true = laut Stellen-Tab keine schweren Lasten heben.
  /// Wird in den Status-Badges angezeigt, aber NIEMALS aus diesem Tab
  /// in die DB zurueckgeschrieben (das macht ausschliesslich der Stellen-Tab).
  bool _koerperlicheEinschraenkung = false;
  /// UI-Filter (lokal, persistiert per SharedPreferences) — entscheidet
  /// ob Schwerlast-Stellen ausgeblendet werden. Default beim ersten Laden
  /// = Profilwert; danach steuert ihn der Vorsitzer ueber den Toggle.
  bool _filterSchwerarbeit = false;
  bool _filterSchwerarbeitInitialized = false;
  final Map<String, Map<String, dynamic>?> _detailCache = {};

  // Bereits beworbene BA-Stellen: refnr → bewerbung row (mit arbeitgeber_id,
  // ba_marked_at usw.). Wird aus bewerbung_list.php geladen und bei jedem
  // 'Habe mich beworben'-Klick aktualisiert.
  final Map<String, Map<String, dynamic>> _bewerbungenByRefnr = {};

  int get _filterAktivCount =>
      (_arbeitszeit != null ? 1 : 0) +
      (_befristung != null ? 1 : 0) +
      (_veroeffentlichtSeit != null ? 1 : 0) +
      (_angebotsart != 1 ? 1 : 0);

  /// Entscheidet pro Stellenangebot, ob sie nach dem aktuellen Filterzustand
  /// sichtbar bleibt — kapselt die Logik fuer 'nur neue' + 'nur passende'.
  bool _isVisible(Map<String, dynamic> s) {
    final refnr = (s['refnr'] ?? '').toString();
    if (_nurNeueStellen && _bewerbungenByRefnr.containsKey(refnr)) return false;
    if (_nurPassendeStellen) {
      final d = _detailCache[refnr];
      if (d != null && d.isNotEmpty) {
        final missG = _needsGabelstapler(d) && !_hatGabelstapler;
        final missF = _needsFuehrerschein(d) && !_hatFuehrerschein;
        // Schwerlast wird nur ausgeblendet, wenn der UI-Toggle hier aktiv ist.
        // Profil-Bit selbst filtert nichts — es spendet nur den Default.
        final missS = _needsSchwerarbeit(d) && _filterSchwerarbeit;
        if (missG || missF || missS) return false;
      }
    }
    return true;
  }

  /// Anzahl der nach allen Filtern sichtbaren Stellen — fuer 'X von Y Treffer'.
  int get _visibleCount {
    if (!_nurPassendeStellen && !_nurNeueStellen) return _results.length;
    return _results.where(_isVisible).length;
  }

  /// Wie viele Stellen verlangen schwere Arbeit, die der Vorsitzer fuer dieses
  /// Mitglied per koerperliche_einschraenkung ausblenden moechte.
  int get _schwerarbeitHiddenCount {
    if (!_filterSchwerarbeit) return 0;
    var n = 0;
    for (final s in _results) {
      final d = _detailCache[(s['refnr'] ?? '').toString()];
      if (d == null || d.isEmpty) continue;
      if (_needsSchwerarbeit(d)) n++;
    }
    return n;
  }

  /// Kompakte Beschreibung der aktiven Filter — landet in der Kopfzeile,
  /// damit man sofort sieht WAS gerade durchgereicht wird.
  String get _aktiveFilterLabel {
    const arbeitszeitMap = {'vz': 'Vollzeit', 'tz': 'Teilzeit', 'mj': 'Minijob', 'snw': 'Schicht/Nacht/Wo', 'ho': 'Home-Office'};
    const angebotMap = {1: 'Arbeit', 2: 'Selbstaendig', 4: 'Ausbildung', 34: 'Praktikum'};
    final teile = <String>[
      if (_arbeitszeit != null) arbeitszeitMap[_arbeitszeit] ?? _arbeitszeit!,
      if (_befristung == 2) 'unbefristet' else if (_befristung == 1) 'befristet',
      if (_veroeffentlichtSeit == 1) 'letzter Tag'
      else if (_veroeffentlichtSeit == 7) 'letzte Woche'
      else if (_veroeffentlichtSeit == 14) 'letzte 2 Wochen'
      else if (_veroeffentlichtSeit == 28) 'letzte 4 Wochen'
      else if (_veroeffentlichtSeit != null) 'letzte ${_veroeffentlichtSeit} Tage',
      if (_angebotsart != 1) angebotMap[_angebotsart] ?? '',
    ];
    return teile.where((t) => t.isNotEmpty).join(' · ');
  }

  /// Eindeutige `funktion`-Werte aus berufserfahrung, in der gleichen
  /// Reihenfolge wie der Stellen-Tab sie zeigt (neueste zuerst — sortiert
  /// nach aktuell-Flag und dann von_jahr/von_monat absteigend).
  List<String> get _vorherigeBerufe {
    final sorted = List<Map<String, dynamic>>.from(widget.berufserfahrung);
    bool aktuell(Map<String, dynamic> x) =>
        x['aktuell'] == true || x['aktuell'] == 'true' || x['aktuell'] == 1 || x['aktuell'] == '1';
    int sortKey(Map<String, dynamic> x) {
      final yj = int.tryParse((x['von_jahr'] ?? '').toString()) ?? 0;
      final ym = int.tryParse((x['von_monat'] ?? '').toString()) ?? 0;
      return yj * 100 + ym;
    }
    sorted.sort((a, b) {
      final aA = aktuell(a), bA = aktuell(b);
      if (aA != bA) return aA ? -1 : 1;
      return sortKey(b).compareTo(sortKey(a));
    });
    final seen = <String>{};
    final out = <String>[];
    for (final ag in sorted) {
      final f = (ag['funktion'] ?? ag['position'] ?? '').toString().trim();
      if (f.isEmpty) continue;
      // Normalisieren: "(m/w/d)" oder andere Klammer-Suffixe wegwerfen, damit
      // gleicher Beruf nicht doppelt erscheint und die Jobsuche breiter trifft.
      final cleaned = f.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
      final key = cleaned.toLowerCase();
      if (seen.add(key)) out.add(cleaned);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    // Zuerst Ort (aus Verifizierung Stufe 1) — falls leer fallback auf PLZ.
    // Damit sucht der Tab standardmaessig nur in der Stadt des Mitglieds.
    final ort = (widget.user.ort ?? '').trim();
    final plz = (widget.user.plz ?? '').trim();
    _woC.text = ort.isNotEmpty ? ort : plz;
    // Wenn das Mitglied Vorerfahrung hat, befuellen wir 'Was' mit der
    // zuletzt ausgeuebten Funktion — der Vorsitzer kann sie ueber die
    // Chip-Leiste schnell tauschen.
    final berufe = _vorherigeBerufe;
    if (berufe.isNotEmpty) _wasC.text = berufe.first;
    // Persistente Auswahl pro Mitglied laden — ueberschreibt die Defaults
    // oben, wenn der Vorsitzer das letzte Mal etwas anderes ausgewaehlt hat.
    _restoreSelection();
    _loadQualifikationen();
    _loadBewerbungen();
  }

  Future<void> _loadBewerbungen() async {
    final r = await widget.apiService.listBewerbungen(widget.user.id);
    if (!mounted || r['success'] != true) return;
    final list = ((r['data'] ?? r)['bewerbungen'] ?? []) as List;
    final map = <String, Map<String, dynamic>>{};
    for (final raw in list) {
      final b = Map<String, dynamic>.from(raw as Map);
      final refnr = (b['ba_refnr'] ?? '').toString();
      if (refnr.isNotEmpty) map[refnr] = b;
    }
    setState(() {
      _bewerbungenByRefnr
        ..clear()
        ..addAll(map);
    });
  }

  Future<void> _markAsApplied(Map<String, dynamic> jobDetail, Map<String, dynamic> suchergebnis) async {
    final refnr = (suchergebnis['refnr'] ?? '').toString();
    if (refnr.isEmpty) return;
    final firma = (jobDetail['firma'] ?? suchergebnis['arbeitgeber'] ?? '').toString().trim();
    if (firma.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arbeitgeber unbekannt — kann nicht markieren')));
      return;
    }
    final loc = (jobDetail['stellenlokationen'] is List && (jobDetail['stellenlokationen'] as List).isNotEmpty)
        ? (jobDetail['stellenlokationen'] as List).first as Map<String, dynamic>
        : null;
    final adr = (loc?['adresse'] is Map) ? loc!['adresse'] as Map : const {};
    final strasse = [(adr['strasse'] ?? '').toString(), (adr['hausnummer'] ?? '').toString()]
        .where((e) => e.isNotEmpty).join(' ');
    final eintritt = ((jobDetail['eintrittszeitraum'] is Map ? jobDetail['eintrittszeitraum']['von'] : null) ?? '').toString().split('T').first;
    final res = await widget.apiService.quickApplyBaJob(widget.user.id, {
      'firma_name': firma,
      'ba_refnr': refnr,
      'ba_titel': (jobDetail['stellenangebotsTitel'] ?? suchergebnis['titel'] ?? '').toString(),
      'ba_beruf': (jobDetail['hauptberuf'] ?? suchergebnis['beruf'] ?? '').toString(),
      'ba_eintrittsdatum': eintritt,
      'strasse': strasse,
      'plz': (adr['plz'] ?? '').toString(),
      'ort': (adr['ort'] ?? '').toString(),
    });
    if (!mounted) return;
    if (res['success'] == true) {
      await _loadBewerbungen();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Als Bewerbung markiert — Status in Bewerbungsuebersicht setzen'),
        backgroundColor: Colors.green.shade700,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message']?.toString() ?? 'Markieren fehlgeschlagen'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _loadQualifikationen() async {
    final res = await widget.apiService.getUserQualifikationen(widget.user.id);
    if (!mounted || res['success'] != true) return;
    final fs = List<Map<String, dynamic>>.from(res['fuehrerschein'] ?? []);
    final hatFs = fs.any((f) => (f['klasse'] ?? '').toString().toLowerCase() != 'keinen');
    final g = res['gabelstaplerschein'];
    final k = res['koerperliche_einschraenkung'];
    final koerper = k == 1 || k == '1' || k == true;
    setState(() {
      _hatFuehrerschein = hatFs;
      _hatGabelstapler = g == 1 || g == '1' || g == true;
      _koerperlicheEinschraenkung = koerper;
      // Erstes Laden: Filter spiegelt das Profil. Spaeter steuert ihn nur
      // noch der lokale Toggle — wir ueberschreiben die Vorsitzer-Auswahl
      // nicht jedes Mal, wenn _loadQualifikationen laeuft.
      if (!_filterSchwerarbeitInitialized) {
        _filterSchwerarbeit = koerper;
        _filterSchwerarbeitInitialized = true;
      }
    });
  }

  Future<void> _prefetchDetails(List<Map<String, dynamic>> results) async {
    for (final s in results) {
      final r = (s['refnr'] ?? '').toString();
      if (r.isEmpty || _detailCache.containsKey(r)) continue;
      _detailCache[r] = null;
      // Fire and don't await — onboarding-style: each card updates itself
      // when its detail comes in. Limit through Future.microtask to avoid
      // hammering the API with 25 simultaneous requests on slow networks.
      Future<void>(() async {
        final d = await widget.apiService.getStellenangebotDetail(r);
        if (!mounted) return;
        setState(() => _detailCache[r] = d ?? const {});
      });
    }
  }

  // Substring-Suche statt regex \b — \b ist in Dart auf ASCII-Wortgrenzen
  // beschränkt und matcht bei umlautlastigen Begriffen (führerschein, gehört)
  // unzuverlässig. Wir scannen die ersten 60 Zeichen ums Keyword nach
  // 'nicht erforderlich' / 'wünschenswert' / 'von vorteil' und schalten
  // den Treffer dann auf 'optional'.
  static const _kwStapler = ['gabelstapler', 'staplerschein', 'flurförder', 'flurfoerder'];
  static const _kwFuehrer = ['führerschein', 'fuehrerschein', 'fahrerlaubnis', 'pkw-schein'];
  // Keywords aus realen Stellenanzeigen + DGUV-Vokabular für schweres Heben.
  // Schwellenwert für die kg-Erkennung: 15 kg (BAuA-Orientierung Frauen,
  // ab dem die Belastung als signifikantes Risiko gilt).
  static const _kwSchwer = [
    'heben und tragen',
    'schwere lasten',
    'schwerere paketstücke',
    'schwere paketstücke',
    'heben von lasten',
    'heben von packstücken',
    'körperlich belastbar',
    'körperliche belastbarkeit',
    'körperlich anspruchsvoll',
    'körperlich anstrengend',
    'schwere körperliche arbeit',
    'körperliche fitness',
    'schwerarbeit',
  ];
  // Regex zieht 15..999 kg (mit optionalem Dezimalpunkt für '31,5 kg').
  static final _kwSchwerKg = RegExp(
    r'\b(1[5-9]|[2-9]\d|\d{3})(?:[.,]\d{1,2})?\s*kg\b',
    caseSensitive: false,
  );
  static final _kwOptional = RegExp(
    r'(nicht erforderlich|nicht notwendig|von vorteil|wünschenswert|wuenschenswert|wäre vorteilhaft|waere vorteilhaft)',
    caseSensitive: false,
  );

  bool _matchAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      final i = text.indexOf(kw);
      if (i < 0) continue;
      final start = (i - 60).clamp(0, text.length);
      final end = (i + kw.length + 60).clamp(0, text.length);
      if (!_kwOptional.hasMatch(text.substring(start, end))) return true;
    }
    return false;
  }

  bool _needsGabelstapler(Map<String, dynamic> d) {
    final t = '${d['stellenangebotsBeschreibung'] ?? ''} ${d['stellenangebotsTitel'] ?? ''}'.toLowerCase();
    return _matchAny(t, _kwStapler);
  }

  bool _needsFuehrerschein(Map<String, dynamic> d) {
    final t = '${d['stellenangebotsBeschreibung'] ?? ''} ${d['stellenangebotsTitel'] ?? ''}'.toLowerCase();
    if (_matchAny(t, _kwFuehrer)) return true;
    // 'Klasse B' / 'Klasse C/CE' — kommt manchmal isoliert, ohne dass das Wort
    // 'Führerschein' im Satz steht.
    final i = RegExp(r'klasse [a-zäöü]+', caseSensitive: false).firstMatch(t);
    if (i == null) return false;
    final start = (i.start - 60).clamp(0, t.length);
    final end = (i.end + 60).clamp(0, t.length);
    return !_kwOptional.hasMatch(t.substring(start, end));
  }

  /// True wenn die Stelle eindeutig schweres Heben verlangt — entweder durch
  /// Standard-Formulierungen ('Heben und Tragen', 'körperlich belastbar', ...)
  /// oder konkrete Gewichtsangaben ab 15 kg. Negationskontext im 60-Zeichen-
  /// Fenster ('leichte Lasten', 'nicht erforderlich', ...) hebt den Treffer auf.
  bool _needsSchwerarbeit(Map<String, dynamic> d) {
    final t = '${d['stellenangebotsBeschreibung'] ?? ''} ${d['stellenangebotsTitel'] ?? ''}'.toLowerCase();
    if (_matchAny(t, _kwSchwer)) return true;
    final m = _kwSchwerKg.firstMatch(t);
    if (m == null) return false;
    final start = (m.start - 60).clamp(0, t.length);
    final end = (m.end + 60).clamp(0, t.length);
    return !_kwOptional.hasMatch(t.substring(start, end));
  }

  Future<void> _restoreSelection() async {
    try {
      // Cross-device per Mitglied: gespeichert in users.stellenangebote_prefs
      // (JSON-Blob). Vorher lagen die Daten in SharedPreferences — bei
      // App-Neuinstallation oder Geraetewechsel waren sie weg.
      final m = await widget.apiService.getStellenangebotePrefs(widget.user.id);
      if (m == null || !mounted) return;
      setState(() {
        final savedBerufe = (m['berufe'] as List?)?.cast<String>() ?? const [];
        _selectedBerufe..clear()..addAll(savedBerufe);
        if (m['was'] is String && (m['was'] as String).isNotEmpty) _wasC.text = m['was'];
        if (m['wo'] is String && (m['wo'] as String).isNotEmpty) _woC.text = m['wo'];
        _umkreis = (m['umkreis'] as int?) ?? _umkreis;
        _arbeitszeit = m['arbeitszeit'] as String?;
        _befristung = m['befristung'] as int?;
        _veroeffentlichtSeit = m['veroeffentlichtSeit'] as int?;
        _angebotsart = (m['angebotsart'] as int?) ?? 1;
        if (m['nurPassendeStellen'] is bool) _nurPassendeStellen = m['nurPassendeStellen'] as bool;
        if (m['nurNeueStellen'] is bool) _nurNeueStellen = m['nurNeueStellen'] as bool;
        if (m['filterSchwerarbeit'] is bool) {
          _filterSchwerarbeit = m['filterSchwerarbeit'] as bool;
          _filterSchwerarbeitInitialized = true;
        }
      });
    } catch (_) { /* corrupted prefs — ignore, defaults gelten */ }
  }

  Future<void> _persistSelection() async {
    // Fire-and-forget DB save — cross-device by design.
    widget.apiService.saveStellenangebotePrefs(widget.user.id, {
      'berufe': _selectedBerufe.toList(),
      'was': _wasC.text,
      'wo': _woC.text,
      'umkreis': _umkreis,
      'arbeitszeit': _arbeitszeit,
      'befristung': _befristung,
      'veroeffentlichtSeit': _veroeffentlichtSeit,
      'angebotsart': _angebotsart,
      'nurPassendeStellen': _nurPassendeStellen,
      'nurNeueStellen': _nurNeueStellen,
      'filterSchwerarbeit': _filterSchwerarbeit,
    });
  }

  @override
  void dispose() { _wasC.dispose(); _woC.dispose(); super.dispose(); }

  Future<void> _search({bool resetPage = true}) async {
    if (resetPage) _page = 1;
    setState(() { _loading = true; _error = null; });
    // Persist current selection so the next time this user opens the tab
    // (incl. after an app restart) we land on the same filter/chip set.
    _persistSelection();
    // Re-fetch the member's qualifications on every search — the Stellen-tab
    // toggle (Gabelstapler, Fuehrerschein, koerperliche Einschraenkung) can
    // have changed since this widget was last mounted (KeepAlive cache).
    await _loadQualifikationen();

    // Bei Mehrfach-Berufen feuern wir parallele Requests und vereinigen die
    // Treffer (dedupe nach refnr/hashId) — die API selbst kennt kein OR.
    final wasQueries = _selectedBerufe.isNotEmpty
        ? _selectedBerufe.toList()
        : [_wasC.text.trim()];

    try {
      final responses = await Future.wait(wasQueries.map((q) =>
        widget.apiService.searchArbeitsagenturJobs(
          was: q,
          wo: _woC.text,
          umkreis: _umkreis,
          page: _page,
          size: 25,
          angebotsart: _angebotsart,
          arbeitszeit: _arbeitszeit,
          befristung: _befristung,
          veroeffentlichtSeitTage: _veroeffentlichtSeit,
        )));

      if (!mounted) return;

      final firstFail = responses.firstWhere((r) => r['success'] != true, orElse: () => {});
      if (firstFail.isNotEmpty) {
        setState(() {
          _loading = false;
          _error = firstFail['message']?.toString() ?? 'Suche fehlgeschlagen';
          _results = [];
        });
        return;
      }

      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];
      var totalSum = 0;
      for (final res in responses) {
        totalSum += (res['maxErgebnisse'] as int?) ?? 0;
        for (final raw in (res['stellenangebote'] as List? ?? [])) {
          final item = Map<String, dynamic>.from(raw as Map);
          final key = (item['refnr'] ?? item['hashId'] ?? item.hashCode).toString();
          if (seen.add(key)) merged.add(item);
        }
      }

      setState(() {
        _loading = false;
        _results = merged;
        _total = wasQueries.length == 1 ? totalSum : merged.length;
        _initial ??= _total;
      });
      _prefetchDetails(merged);
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); _results = []; });
    }
  }

  /// Kompakter Status-Badge fuer eine Qualifikations-Achse. green=OK,
  /// red=fehlt/eingeschraenkt. Wird in der Header-Leiste neben dem
  /// 'Nur passende'-Toggle angezeigt.
  Widget _qualBadge(IconData icon, String label, bool ok, String tooltip) => Tooltip(
    message: tooltip,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ok ? Colors.green.shade300 : Colors.red.shade300, width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: ok ? Colors.green.shade800 : Colors.red.shade800),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: ok ? Colors.green.shade900 : Colors.red.shade900, fontWeight: FontWeight.w600)),
        const SizedBox(width: 3),
        Text(ok ? '✓' : '✗', style: TextStyle(fontSize: 11, color: ok ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.bold)),
      ]),
    ),
  );

  Widget _smallBadge(IconData icon, String text, MaterialColor color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color.shade800), const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 10, color: color.shade900, fontWeight: FontWeight.w600)),
    ]),
  );

  String _arbeitsort(Map<String, dynamic> ag) {
    final ort = (ag['arbeitsort']?['ort'] ?? ag['arbeitsorte']?[0]?['ort'] ?? '').toString();
    final plz = (ag['arbeitsort']?['plz'] ?? ag['arbeitsorte']?[0]?['plz'] ?? '').toString();
    return [if (plz.isNotEmpty) plz, ort].where((s) => s.isNotEmpty).join(' ');
  }

  Future<void> _openExtern(String refnr) async {
    final url = Uri.parse('https://www.arbeitsagentur.de/jobsuche/jobdetail/$refnr');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Konnte $url nicht oeffnen')));
    }
  }

  Future<void> _openDetails(Map<String, dynamic> ag) async {
    final refnr = (ag['refnr'] ?? '').toString();
    await showDialog(
      context: context,
      builder: (_) => _StellenDetailDialog(
        apiService: widget.apiService,
        suchergebnis: ag,
        refnr: refnr,
        arbeitsortLabel: _arbeitsort(ag),
        onOpenExtern: () { Navigator.pop(context); _openExtern(refnr); },
        bewerbung: _bewerbungenByRefnr[refnr],
        onMarkApplied: (detail) async { await _markAsApplied(detail, ag); },
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 6),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
  ]));

  @override
  Widget build(BuildContext context) {
    super.build(context); // KeepAlive contract
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.indigo.shade50, border: Border(bottom: BorderSide(color: Colors.indigo.shade200))),
        child: Column(children: [
          Row(children: [
            Icon(Icons.search, size: 18, color: Colors.indigo.shade800),
            const SizedBox(width: 6),
            Expanded(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              Text('Bundesagentur – Jobsuche', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
              Text(_umkreis == 0 ? 'nur ${_woC.text}' : '${_woC.text} +${_umkreis}km',
                  style: TextStyle(fontSize: 11, color: Colors.indigo.shade600, fontStyle: FontStyle.italic)),
              if (_aktiveFilterLabel.isNotEmpty)
                Text('· $_aktiveFilterLabel', style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
            ])),
            if (_total != null) Builder(builder: (_) {
              final visible = _visibleCount;
              final total = _total!;
              final showSplit = _nurPassendeStellen && visible != _results.length;
              return Text(
                showSplit ? '$visible von $total Treffer' : '$total Treffer',
                style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w600),
              );
            }),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(flex: 3, child: TextField(
              controller: _wasC,
              decoration: const InputDecoration(
                labelText: 'Was (Beruf, Stichwort)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.work, size: 16),
              ),
              onSubmitted: (_) => _search(),
            )),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: TextField(
              controller: _woC,
              decoration: const InputDecoration(
                labelText: 'Wo (PLZ/Ort)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on, size: 16),
              ),
              onSubmitted: (_) => _search(),
            )),
            const SizedBox(width: 6),
            SizedBox(width: 112, child: DropdownButtonFormField<int>(
              initialValue: _umkreis,
              decoration: const InputDecoration(labelText: 'Umkreis', isDense: true, border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 0,   child: Text('nur Stadt')),
                DropdownMenuItem(value: 5,   child: Text('5 km')),
                DropdownMenuItem(value: 10,  child: Text('10 km')),
                DropdownMenuItem(value: 25,  child: Text('25 km')),
                DropdownMenuItem(value: 50,  child: Text('50 km')),
                DropdownMenuItem(value: 100, child: Text('100 km')),
              ],
              onChanged: (v) { setState(() => _umkreis = v ?? 0); _search(); },
            )),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: _loading ? null : () => _search(),
              icon: _loading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search, size: 16),
              label: const Text('Suchen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
            ),
          ]),
          if (_vorherigeBerufe.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('Berufe (Mehrfach):', style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Expanded(child: Wrap(spacing: 6, runSpacing: 4, children: [
                ..._vorherigeBerufe.map((b) {
                  final selected = _selectedBerufe.contains(b);
                  return FilterChip(
                    label: Text(b, style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    backgroundColor: Colors.white,
                    selectedColor: Colors.indigo.shade100,
                    checkmarkColor: Colors.indigo.shade800,
                    side: BorderSide(color: selected ? Colors.indigo : Colors.indigo.shade200),
                    visualDensity: VisualDensity.compact,
                    onSelected: _loading ? null : (v) {
                      setState(() {
                        if (v) { _selectedBerufe.add(b); } else { _selectedBerufe.remove(b); }
                        if (_selectedBerufe.length == 1) _wasC.text = _selectedBerufe.first;
                        if (_selectedBerufe.isEmpty) _wasC.clear();
                      });
                      _search();
                    },
                  );
                }),
                if (_selectedBerufe.isNotEmpty) ActionChip(
                  label: const Text('alle abwaehlen', style: TextStyle(fontSize: 11)),
                  avatar: const Icon(Icons.clear, size: 14),
                  backgroundColor: Colors.grey.shade100,
                  onPressed: _loading ? null : () { setState(() { _selectedBerufe.clear(); _wasC.clear(); }); _search(); },
                ),
              ])),
            ]),
          ),
          const SizedBox(height: 4),
          // Smart-Filter Toggle: blendet Stellen aus, die Qualifikationen
          // verlangen, die das Mitglied nicht hat (Gabelstapler/Fuehrerschein).
          Wrap(spacing: 12, runSpacing: 4, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: _nurPassendeStellen,
                activeThumbColor: Colors.indigo.shade700,
                onChanged: (v) { setState(() => _nurPassendeStellen = v); _persistSelection(); },
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Blendet Stellen aus, die eine Qualifikation\nverlangen, die dem Mitglied fehlt:\n• Fuehrerschein\n• Gabelstaplerschein\n• Koerperliche Belastbarkeit (schweres Heben)',
                child: const Text('Nur passende', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              // Drei sichtbare Status-Badges direkt am Toggle. Klick auf das
              // Info-Icon erklaert, was 'aktiv' jeweils bedeutet.
              _qualBadge(Icons.directions_car, 'FS', _hatFuehrerschein,
                  _hatFuehrerschein ? 'Fuehrerschein vorhanden' : 'Kein Fuehrerschein'),
              const SizedBox(width: 3),
              _qualBadge(Icons.local_shipping, 'Stapler', _hatGabelstapler,
                  _hatGabelstapler ? 'Gabelstaplerschein vorhanden' : 'Kein Gabelstaplerschein'),
              const SizedBox(width: 3),
              // Schwerlast: gruen = unbeschraenkt, rot = darf nicht schwer heben
              _qualBadge(Icons.fitness_center, 'Heben', !_koerperlicheEinschraenkung,
                  _koerperlicheEinschraenkung ? 'Keine schweren Lasten' : 'Schwere Lasten OK'),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: _nurNeueStellen,
                activeThumbColor: Colors.green.shade700,
                onChanged: (v) { setState(() => _nurNeueStellen = v); _persistSelection(); },
              ),
              const SizedBox(width: 4),
              const Text('Nur neue', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              if (_bewerbungenByRefnr.isNotEmpty) Text('(${_bewerbungenByRefnr.length} beworben)',
                  style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
            ]),
            // Schwerlast-Toggle ist hier reiner UI-Filter — Profil bleibt
            // unveraendert (das setzt nur der Stellen-Tab). Default kommt
            // beim ersten Mal aus dem Profil, danach steuert ihn der Vorsitzer.
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: _filterSchwerarbeit,
                activeThumbColor: Colors.deepPurple.shade700,
                onChanged: (v) {
                  setState(() => _filterSchwerarbeit = v);
                  _persistSelection();
                },
              ),
              const SizedBox(width: 4),
              const Text('Schwere Arbeit ausblenden', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              if (_schwerarbeitHiddenCount > 0) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.deepPurple.shade200)),
                child: Text('${_schwerarbeitHiddenCount} ausgeblendet',
                    style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade900, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Blendet Stellen mit Heben/Tragen ueber 15 kg aus.\nNur UI-Filter — Profil wird nicht veraendert.\n(Profilwert setzt der Stellen-Tab.)',
                child: Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
              ),
            ]),
          ]),
          // Toggle fuer erweiterte Filter — eingeklappt, damit der Tab
          // nicht ueberladen wirkt; im offenen Zustand vier Dropdowns.
          InkWell(
            onTap: () => setState(() => _filterOffen = !_filterOffen),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              Icon(_filterOffen ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.indigo.shade700),
              const SizedBox(width: 4),
              Text('Erweiterte Filter', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
              if (_filterAktivCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.orange.shade200, borderRadius: BorderRadius.circular(8)),
                  child: Text('$_filterAktivCount aktiv', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ])),
          ),
          if (_filterOffen) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              SizedBox(width: 180, child: DropdownButtonFormField<String?>(
                initialValue: _arbeitszeit,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Arbeitszeit', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Alle')),
                  DropdownMenuItem(value: 'vz',  child: Text('Vollzeit')),
                  DropdownMenuItem(value: 'tz',  child: Text('Teilzeit')),
                  DropdownMenuItem(value: 'mj',  child: Text('Minijob')),
                  DropdownMenuItem(value: 'snw', child: Text('Schicht/Nacht/Wochenende')),
                  DropdownMenuItem(value: 'ho',  child: Text('Heim-/Telearbeit')),
                ],
                onChanged: (v) { setState(() => _arbeitszeit = v); _search(); },
              )),
              SizedBox(width: 160, child: DropdownButtonFormField<int?>(
                initialValue: _befristung,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Befristung', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Alle')),
                  DropdownMenuItem(value: 2, child: Text('Unbefristet')),
                  DropdownMenuItem(value: 1, child: Text('Befristet')),
                ],
                onChanged: (v) { setState(() => _befristung = v); _search(); },
              )),
              SizedBox(width: 180, child: DropdownButtonFormField<int?>(
                initialValue: _veroeffentlichtSeit,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Veroeffentlicht seit', isDense: true, border: OutlineInputBorder()),
                items: const [
                  // Bundesagentur akzeptiert nur fixe Stichtage (1/7/14/28).
                  // Andere Werte werden serverseitig stillschweigend ignoriert.
                  DropdownMenuItem(value: null, child: Text('Alle')),
                  DropdownMenuItem(value: 1,    child: Text('Letzter Tag')),
                  DropdownMenuItem(value: 7,    child: Text('Letzte Woche')),
                  DropdownMenuItem(value: 14,   child: Text('Letzte 2 Wochen')),
                  DropdownMenuItem(value: 28,   child: Text('Letzte 4 Wochen')),
                ],
                onChanged: (v) { setState(() => _veroeffentlichtSeit = v); _search(); },
              )),
              SizedBox(width: 160, child: DropdownButtonFormField<int>(
                initialValue: _angebotsart,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Angebotsart', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 1,  child: Text('Arbeit')),
                  DropdownMenuItem(value: 2,  child: Text('Selbstaendigkeit')),
                  DropdownMenuItem(value: 4,  child: Text('Ausbildung')),
                  DropdownMenuItem(value: 34, child: Text('Praktikum')),
                ],
                onChanged: (v) { setState(() => _angebotsart = v ?? 1); _search(); },
              )),
              if (_filterAktivCount > 0) ActionChip(
                label: const Text('Filter zuruecksetzen', style: TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.replay, size: 14),
                backgroundColor: Colors.orange.shade50,
                onPressed: _loading ? null : () { setState(() {
                  _arbeitszeit = null; _befristung = null; _veroeffentlichtSeit = null; _angebotsart = 1;
                }); _search(); },
              ),
            ]),
          ),
        ]),
      ),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
            ]))
          : _results.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text(_initial == null ? 'Suche starten' : 'Keine Treffer', style: TextStyle(color: Colors.grey.shade600)),
              ]))
            : Builder(builder: (_) {
              // Smart-Filter anwenden: pro Card aus Cache entscheiden, ob
              // sie eine fehlende Qualifikation verlangt. Cards ohne Detail
              // bleiben sichtbar (mit Spinner-Hint) — Filter wirkt erst,
              // wenn die Anforderung eindeutig geklärt ist.
              final visible = _results.where(_isVisible).toList();
              final hidden = _results.length - visible.length;
              return Column(children: [
                Builder(builder: (_) {
                  final geprueft = _results.where((s) {
                    final d = _detailCache[(s['refnr'] ?? '').toString()];
                    return d != null;
                  }).length;
                  if (geprueft < _results.length) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.blue.shade50,
                      child: Row(children: [
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Qualifikationen werden geprueft… ($geprueft / ${_results.length})',
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade900))),
                      ]),
                    );
                  }
                  if (hidden > 0) {
                    // Aufschlüsseln wie viel an welcher Filter-Achse verloren geht — Vorsitzer sieht direkt warum.
                    final beworbenCount = _nurNeueStellen
                        ? _results.where((s) => _bewerbungenByRefnr.containsKey((s['refnr'] ?? '').toString())).length
                        : 0;
                    final qualiHidden = hidden - beworbenCount;
                    final teile = <String>[
                      if (beworbenCount > 0) '$beworbenCount bereits beworben',
                      if (qualiHidden > 0) '$qualiHidden ohne passende Qualifikation',
                    ];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.orange.shade50,
                      child: Row(children: [
                        Icon(Icons.filter_alt, size: 14, color: Colors.orange.shade800),
                        const SizedBox(width: 6),
                        Expanded(child: Text('$hidden Stelle(n) ausgeblendet (${teile.join(", ")})', style: TextStyle(fontSize: 11, color: Colors.orange.shade900))),
                      ]),
                    );
                  }
                  return const SizedBox.shrink();
                }),
                Expanded(child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final s = visible[i];
                    final titel = (s['titel'] ?? s['beruf'] ?? '(ohne Titel)').toString();
                    final firma = (s['arbeitgeber'] ?? '').toString();
                    final ort = _arbeitsort(s);
                    final eintritt = (s['eintrittsdatum'] ?? '').toString().split('T').first;
                    final refnr = (s['refnr'] ?? '').toString();
                    final d = _detailCache[refnr];
                    final pruefend = d == null && _detailCache.containsKey(refnr);
                    final needG = d != null && d.isNotEmpty && _needsGabelstapler(d);
                    final needF = d != null && d.isNotEmpty && _needsFuehrerschein(d);
                    final needS = d != null && d.isNotEmpty && _needsSchwerarbeit(d);
                    final bewerbung = _bewerbungenByRefnr[refnr];
                    final beworben = bewerbung != null;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: beworben ? Colors.green.shade50 : null,
                      child: InkWell(
                        onTap: () => _openDetails(s),
                        child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (beworben) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
                            Icon(Icons.check_circle, size: 14, color: Colors.green.shade800),
                            const SizedBox(width: 4),
                            Text('Bereits beworben${bewerbung['ba_marked_at'] != null ? ' am ${bewerbung['ba_marked_at'].toString().split('T').first.split(' ').first}' : ''}',
                                style: TextStyle(fontSize: 11, color: Colors.green.shade900, fontWeight: FontWeight.bold)),
                          ])),
                          Text(titel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          if (firma.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                            Icon(Icons.business, size: 13, color: Colors.grey.shade600), const SizedBox(width: 4),
                            Expanded(child: Text(firma, style: const TextStyle(fontSize: 12))),
                          ])),
                          if (ort.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                            Icon(Icons.location_on, size: 13, color: Colors.grey.shade600), const SizedBox(width: 4),
                            Text(ort, style: const TextStyle(fontSize: 12)),
                            const Spacer(),
                            // Gültigkeits-Badge unmittelbar vor dem Eintritt-Datum:
                            // grün ✓ wenn die Stelle im aktuellen API-Ergebnis ist,
                            // rot ✗ wenn der Bulk-Check sie inzwischen als expired
                            // markiert hat (Mitglied hat sich beworben, BA hat die
                            // Anzeige entfernt).
                            Builder(builder: (_) {
                              final expired = (bewerbung?['ba_stelle_expired_at']?.toString() ?? '').isNotEmpty;
                              return Tooltip(
                                message: expired ? 'BA: nicht mehr verfuegbar' : 'BA: noch verfuegbar',
                                child: Container(
                                  width: 16, height: 16,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: expired ? Colors.red.shade100 : Colors.green.shade100,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: expired ? Colors.red.shade400 : Colors.green.shade400, width: 1.2),
                                  ),
                                  child: Icon(expired ? Icons.close : Icons.check, size: 11,
                                      color: expired ? Colors.red.shade800 : Colors.green.shade800),
                                ),
                              );
                            }),
                            if (eintritt.isNotEmpty) ...[
                              Icon(Icons.event, size: 12, color: Colors.grey.shade600), const SizedBox(width: 3),
                              Text(eintritt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ])),
                          if (pruefend || needG || needF || needS) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 4, runSpacing: 4, children: [
                            if (pruefend) _smallBadge(Icons.hourglass_empty, 'wird geprueft', Colors.grey),
                            if (needG) _smallBadge(Icons.local_shipping, _hatGabelstapler ? 'Gabelstapler ✓' : 'Gabelstapler ✗', _hatGabelstapler ? Colors.green : Colors.red),
                            if (needF) _smallBadge(Icons.directions_car, _hatFuehrerschein ? 'Führerschein ✓' : 'Führerschein ✗', _hatFuehrerschein ? Colors.green : Colors.red),
                            if (needS) _smallBadge(Icons.fitness_center, _koerperlicheEinschraenkung ? 'Schwere Arbeit ✗' : 'Schwere Arbeit', _koerperlicheEinschraenkung ? Colors.red : Colors.green),
                          ])),
                        ])),
                      ),
                    );
                  },
                )),
              ]);
            }),
      ),
      if (_total != null && _total! > _results.length && _results.isNotEmpty) Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade300))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(
            onPressed: _page == 1 || _loading ? null : () { _page--; _search(resetPage: false); },
            icon: const Icon(Icons.chevron_left, size: 16), label: const Text('Zurueck'),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('Seite $_page')),
          TextButton.icon(
            onPressed: _loading ? null : () { _page++; _search(resetPage: false); },
            icon: const Icon(Icons.chevron_right, size: 16), label: const Text('Weiter'),
          ),
        ]),
      ),
    ]);
  }
}

/// Detail-Dialog für ein einzelnes Stellenangebot. Lädt beim Öffnen die
/// vollen Daten via /pc/v4/jobdetails und extrahiert Telefonnummern +
/// E-Mail-Adressen aus dem Beschreibungstext für 1-Klick-Initiativbewerbung.
class _StellenDetailDialog extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> suchergebnis;
  final String refnr;
  final String arbeitsortLabel;
  final VoidCallback onOpenExtern;
  final Map<String, dynamic>? bewerbung;
  final Future<void> Function(Map<String, dynamic> jobDetail)? onMarkApplied;
  const _StellenDetailDialog({
    required this.apiService,
    required this.suchergebnis,
    required this.refnr,
    required this.arbeitsortLabel,
    required this.onOpenExtern,
    this.bewerbung,
    this.onMarkApplied,
  });

  @override
  State<_StellenDetailDialog> createState() => _StellenDetailDialogState();
}

class _StellenDetailDialogState extends State<_StellenDetailDialog> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (widget.refnr.isEmpty) {
      setState(() { _loading = false; _error = 'Keine Referenznummer'; });
      return;
    }
    final res = await widget.apiService.getStellenangebotDetail(widget.refnr);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = res;
      if (res == null) _error = 'Details konnten nicht geladen werden';
    });
  }

  List<String> _extractEmails(String text) {
    final re = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
    return re.allMatches(text).map((m) => m.group(0)!).toSet().toList();
  }

  List<String> _extractTelefone(String text) {
    // German phone numbers: starts +49 or 0, then digits with optional spaces/dashes/slashes/(), 6+ digits
    final re = RegExp(r'(?:\+49[\s\-/]?|\(?0\)?[\s\-/]?)\d[\d\s\-/()]{6,}\d');
    final results = <String>[];
    for (final m in re.allMatches(text)) {
      final raw = m.group(0)!.trim();
      final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
      if (digits.length >= 7) results.add(raw);
    }
    return results.toSet().toList();
  }

  String _arbeitszeitLabel(Map<String, dynamic> d) {
    final parts = <String>[];
    if (d['arbeitszeitVollzeit'] == true) parts.add('Vollzeit');
    if (d['arbeitszeitTeilzeit'] == true) parts.add('Teilzeit');
    if (d['arbeitszeitMinijob'] == true) parts.add('Minijob');
    if (d['arbeitszeitSchichtNachtWochenende'] == true) parts.add('Schicht/Nacht/Wo');
    if (d['arbeitszeitHeimTelearbeit'] == true) parts.add('Home-Office');
    if (d['istGeringfuegigeBeschaeftigung'] == true && !parts.contains('Minijob')) parts.add('Minijob');
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  String _adresseLabel(Map<String, dynamic>? loc) {
    if (loc == null) return '';
    final a = (loc['adresse'] is Map) ? loc['adresse'] as Map : <String, dynamic>{};
    final strasse = a['strasse']?.toString() ?? '';
    final hausnr = a['hausnummer']?.toString() ?? '';
    final plz = a['plz']?.toString() ?? '';
    final ort = a['ort']?.toString() ?? '';
    final adr = [
      if (strasse.isNotEmpty) '$strasse${hausnr.isNotEmpty ? " $hausnr" : ""}',
      if (plz.isNotEmpty || ort.isNotEmpty) '$plz $ort'.trim(),
    ].join(', ');
    return adr;
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Konnte $url nicht oeffnen')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final s = widget.suchergebnis;
    final titel = (d?['stellenangebotsTitel'] ?? s['titel'] ?? s['beruf'] ?? '').toString();
    final firma = (d?['firma'] ?? s['arbeitgeber'] ?? '').toString();
    final hauptberuf = (d?['hauptberuf'] ?? s['beruf'] ?? '').toString();
    final alt1 = (d?['alternativBeruf1'] ?? '').toString();
    final alt2 = (d?['alternativBeruf2'] ?? '').toString();
    final vertrag = (d?['vertragsdauer'] ?? '').toString();
    final vergueteung = (d?['verguetungsangabe'] ?? '').toString();
    final eintritt = ((d?['eintrittszeitraum'] is Map ? d!['eintrittszeitraum']['von'] : null) ?? s['eintrittsdatum'] ?? '').toString().split('T').first;
    final beschreibung = (d?['stellenangebotsBeschreibung'] ?? '').toString();
    final loc = (d?['stellenlokationen'] is List && (d!['stellenlokationen'] as List).isNotEmpty)
        ? (d['stellenlokationen'] as List).first as Map<String, dynamic>
        : null;
    final adresse = _adresseLabel(loc);
    final lat = loc?['breite'];
    final lon = loc?['laenge'];

    final emails = beschreibung.isEmpty ? <String>[] : _extractEmails(beschreibung);
    final tels = beschreibung.isEmpty ? <String>[] : _extractTelefone(beschreibung);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.indigo.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
            child: Row(children: [
              const Icon(Icons.work_outline, color: Colors.white), const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(titel.isEmpty ? hauptberuf : titel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                if (firma.isNotEmpty) Text(firma, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, color: Colors.red.shade300, size: 40),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                ])))
              : SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Metadata row
                Wrap(spacing: 8, runSpacing: 4, children: [
                  if (_arbeitszeitLabel(d ?? {}).isNotEmpty) _badge(Icons.access_time, _arbeitszeitLabel(d ?? {}), Colors.blue),
                  if (vertrag.isNotEmpty) _badge(Icons.event_repeat, vertrag, Colors.purple),
                  if (eintritt.isNotEmpty) _badge(Icons.event, 'ab $eintritt', Colors.green),
                  if (vergueteung.isNotEmpty && vergueteung != 'KEINE_ANGABEN') _badge(Icons.euro, vergueteung, Colors.orange),
                  if (d?['quereinstiegGeeignet'] == true) _badge(Icons.swap_horiz, 'Quereinstieg', Colors.teal),
                ]),
                const SizedBox(height: 12),
                if (hauptberuf.isNotEmpty) _row(Icons.work, 'Hauptberuf: $hauptberuf'),
                if (alt1.isNotEmpty) _row(Icons.alt_route, 'Alternativ: $alt1'),
                if (alt2.isNotEmpty) _row(Icons.alt_route, 'Alternativ: $alt2'),
                if (firma.isNotEmpty) _row(Icons.business, firma),
                if (adresse.isNotEmpty) Row(children: [
                  Expanded(child: _row(Icons.location_on, adresse)),
                  if (lat != null && lon != null) TextButton.icon(
                    onPressed: () => _launch('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),
                    icon: const Icon(Icons.map, size: 14),
                    label: const Text('Karte', style: TextStyle(fontSize: 11)),
                  ),
                ]),
                // Bewerbung-Section: extracted emails + phones
                if (emails.isNotEmpty || tels.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.contact_mail, size: 16, color: Colors.green.shade800), const SizedBox(width: 6),
                        Text('Initiativbewerbung — Kontakt aus Anzeige', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                      ]),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        // Klick auf E-Mail-Chip kopiert in die Zwischenablage —
                        // das ist auf Desktop/Linux viel zuverlaessiger als ein
                        // automatisch geoeffneter Mail-Client. Daneben ein
                        // kleines Pfeil-Icon, wenn jemand doch lieber Thunderbird
                        // & Co. aufruft.
                        ...emails.map((e) => Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.shade300)),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                await Clipboard.setData(ClipboardData(text: e));
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e in Zwischenablage kopiert'), duration: const Duration(seconds: 2)));
                              },
                              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.email, size: 14, color: Colors.green.shade800), const SizedBox(width: 4),
                                Text(e, style: const TextStyle(fontSize: 11)),
                                const SizedBox(width: 4),
                                Icon(Icons.copy, size: 12, color: Colors.grey.shade600),
                              ])),
                            ),
                            IconButton(
                              icon: const Icon(Icons.open_in_new, size: 14),
                              tooltip: 'Mail-Client oeffnen',
                              padding: const EdgeInsets.all(2),
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _launch('mailto:$e?subject=${Uri.encodeComponent("Initiativbewerbung – Ihre Stelle $titel (${widget.refnr})")}'),
                            ),
                          ]),
                        )),
                        ...tels.map((t) {
                          final digits = t.replaceAll(RegExp(r'[^\d+]'), '');
                          return Container(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.shade300)),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await Clipboard.setData(ClipboardData(text: digits));
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$digits in Zwischenablage kopiert'), duration: const Duration(seconds: 2)));
                                },
                                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.phone, size: 14, color: Colors.green.shade800), const SizedBox(width: 4),
                                  Text(t, style: const TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  Icon(Icons.copy, size: 12, color: Colors.grey.shade600),
                                ])),
                              ),
                              IconButton(
                                icon: const Icon(Icons.call, size: 14),
                                tooltip: 'Anrufen',
                                padding: const EdgeInsets.all(2),
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _launch('tel:$digits'),
                              ),
                            ]),
                          );
                        }),
                      ]),
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                if (beschreibung.isNotEmpty) ...[
                  Text('Beschreibung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade200)),
                    child: SelectableText(beschreibung, style: const TextStyle(fontSize: 12, height: 1.4)),
                  ),
                ],
                const SizedBox(height: 8),
                if (widget.refnr.isNotEmpty) SelectableText('Ref-Nr.: ${widget.refnr}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ])),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schliessen')),
              const Spacer(),
              if (widget.bewerbung != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade800),
                const SizedBox(width: 4),
                Text('beworben${widget.bewerbung!['ba_marked_at'] != null ? " am ${widget.bewerbung!['ba_marked_at'].toString().split('T').first.split(' ').first}" : ""}',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.bold)),
              ]))
              else if (widget.onMarkApplied != null && d != null) ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await widget.onMarkApplied!(d);
                },
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Habe mich beworben'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: widget.onOpenExtern,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Auf arbeitsagentur.de'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _badge(IconData icon, String text, MaterialColor color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade200)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color.shade800), const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 11, color: color.shade900)),
    ]),
  );

  Widget _row(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 6),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
  ]));
}
