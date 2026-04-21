import 'package:flutter/material.dart';
import '../services/api_service.dart';

class BehordeLandratsamtContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeLandratsamtContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeLandratsamtContent> createState() => _BehordeLandratsamtContentState();
}

class _BehordeLandratsamtContentState extends State<BehordeLandratsamtContent> {
  static const type = 'landratsamt';
  Map<String, Map<String, dynamic>> _dbData = {};
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFromDB();
  }

  Future<void> _loadFromDB() async {
    final r = await widget.apiService.getLandratsamtData(widget.userId);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      setState(() {
        final raw = r['data'] as Map;
        _dbData = {};
        for (final entry in raw.entries) {
          _dbData[entry.key.toString()] = Map<String, dynamic>.from(entry.value as Map);
        }
        _loaded = true;
      });
    } else {
      setState(() => _loaded = true);
    }
  }

  Future<void> _saveToDB() async {
    setState(() => _saving = true);
    await widget.apiService.saveLandratsamtData(widget.userId, _dbData);
    if (mounted) setState(() => _saving = false);
  }

  Map<String, dynamic> _bereich(String key) {
    _dbData[key] ??= {};
    return _dbData[key]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 6,
      child: Column(children: [
        TabBar(
          labelColor: Colors.brown.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.brown.shade700,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Amt'),
            Tab(icon: Icon(Icons.directions_car, size: 16), text: 'KFZ'),
            Tab(icon: Icon(Icons.badge, size: 16), text: 'Führerschein'),
            Tab(icon: Icon(Icons.home_work, size: 16), text: 'Bau & Wohnen'),
            Tab(icon: Icon(Icons.eco, size: 16), text: 'Umwelt & Natur'),
            Tab(icon: Icon(Icons.more_horiz, size: 16), text: 'Sonstiges'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _buildAmtTab(),
            _buildKfzTab(),
            _buildFuehrerscheinTab(),
            _buildBauTab(),
            _buildUmweltTab(),
            _buildSonstigesTab(),
          ]),
        ),
        _buildSaveFooter(),
      ]),
    );
  }

  // ============ AMT (zuständiges Landratsamt) ============
  Widget _buildAmtTab() {
    final amt = _bereich('amt');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.account_balance, 'Zuständiges Landratsamt', Colors.brown),
        const SizedBox(height: 16),
        _field('Name', amt, 'name', Icons.account_balance, hint: 'z.B. Landratsamt Neu-Ulm'),
        _field('Straße + Hausnr.', amt, 'strasse', Icons.location_on, hint: 'z.B. Kantstraße 8'),
        _field('PLZ + Ort', amt, 'plz_ort', Icons.location_city, hint: 'z.B. 89231 Neu-Ulm'),
        _field('Telefon (Zentrale)', amt, 'telefon', Icons.phone, hint: 'z.B. 0731 7040-0'),
        _field('E-Mail', amt, 'email', Icons.email, hint: 'z.B. info@lra.neu-ulm.de'),
        _field('Website', amt, 'website', Icons.language, hint: 'z.B. www.landkreis-nu.de'),
        _field('Öffnungszeiten', amt, 'oeffnungszeiten', Icons.access_time, hint: 'Mo-Fr 08:00-12:00, Do 14:00-17:30', maxLines: 2),
        _field('Notizen', amt, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ KFZ ZULASSUNGSSTELLE ============
  Widget _buildKfzTab(Map<String, dynamic> data) {
    final kfz = _bereich('kfz');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.directions_car, 'KFZ-Zulassungsstelle', Colors.blue),
        const SizedBox(height: 4),
        Text('Landratsamt Neu-Ulm · Kantstraße 8 · 89231 Neu-Ulm', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', kfz, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', kfz, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Kennzeichen', kfz, 'kennzeichen', Icons.confirmation_number, hint: 'z.B. NU-AB 1234'),
        _field('Fahrzeug', kfz, 'fahrzeug', Icons.directions_car, hint: 'z.B. VW Golf 7 1.6 TDI'),
        _field('FIN (Fahrgestell-Nr.)', kfz, 'fin', Icons.qr_code, hint: '17-stellig'),
        _field('Erstzulassung', kfz, 'erstzulassung', Icons.calendar_today, hint: 'TT.MM.JJJJ'),
        _field('Nächste HU/TÜV', kfz, 'naechste_hu', Icons.build, hint: 'MM/JJJJ'),
        _field('Versicherung', kfz, 'versicherung', Icons.shield, hint: 'z.B. HUK-COBURG'),
        _field('Versicherungsscheinnummer', kfz, 'evb_nr', Icons.tag, hint: 'eVB-Nr.'),
        _field('KFZ-Steuer €/Jahr', kfz, 'kfz_steuer', Icons.euro, hint: 'z.B. 120'),
        _dropDown('Status', kfz, 'status', Icons.check_circle, {'aktiv': 'Zugelassen', 'abgemeldet': 'Abgemeldet', 'stillgelegt': 'Stillgelegt', 'export': 'Exportiert'}),
        _field('Notizen', kfz, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ FÜHRERSCHEINSTELLE ============
  Widget _buildFuehrerscheinTab(Map<String, dynamic> data) {
    final fs = _bereich('fuehrerschein');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.badge, 'Führerscheinstelle', Colors.green),
        const SizedBox(height: 4),
        Text('Landratsamt Neu-Ulm · Kantstraße 8 · 89231 Neu-Ulm', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', fs, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', fs, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Führerscheinnummer', fs, 'fs_nummer', Icons.credit_card, hint: 'Auf dem Führerschein'),
        _field('Ausstellungsdatum', fs, 'ausstellungsdatum', Icons.calendar_today, hint: 'TT.MM.JJJJ'),
        _field('Gültig bis', fs, 'gueltig_bis', Icons.event, hint: 'TT.MM.JJJJ (oder unbefristet)'),
        _field('Ausstellende Behörde', fs, 'aussteller', Icons.account_balance, hint: 'z.B. Landratsamt Neu-Ulm'),
        _field('Klassen', fs, 'klassen', Icons.category, hint: 'z.B. B, AM, L'),
        _dropDown('Internationaler FS', fs, 'international', Icons.language, {'': 'Nicht vorhanden', 'beantragt': 'Beantragt', 'vorhanden': 'Vorhanden'}),
        _dropDown('Umtausch-Status', fs, 'umtausch', Icons.swap_horiz, {'': 'Nicht erforderlich', 'faellig': 'Fällig (bis 2033)', 'beantragt': 'Umtausch beantragt', 'erledigt': 'Neuer FS erhalten'}),
        _field('Auflagen / Schlüsselzahlen', fs, 'auflagen', Icons.info, hint: 'z.B. 01.01 — Brille'),
        _field('Notizen', fs, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ BAU & WOHNEN ============
  Widget _buildBauTab(Map<String, dynamic> data) {
    final bau = _bereich('bau');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.home_work, 'Bauordnung & Wohnen', Colors.orange),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', bau, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', bau, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Baugenehmigung Nr.', bau, 'genehmigung_nr', Icons.description),
        _field('Objekt / Adresse', bau, 'objekt', Icons.location_on),
        _dropDown('Status', bau, 'status', Icons.check_circle, {'': '–', 'beantragt': 'Beantragt', 'genehmigt': 'Genehmigt', 'abgelehnt': 'Abgelehnt', 'im_bau': 'Im Bau', 'fertiggestellt': 'Fertiggestellt'}),
        _field('Notizen', bau, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ UMWELT & NATUR ============
  Widget _buildUmweltTab(Map<String, dynamic> data) {
    final umw = _bereich('umwelt');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.eco, 'Umwelt, Natur & Abfall', Colors.green),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', umw, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', umw, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Biotonne Nr.', umw, 'biotonne', Icons.delete),
        _field('Restmülltonne Nr.', umw, 'restmuell', Icons.delete_outline),
        _field('Wertstofftonne Nr.', umw, 'wertstoff', Icons.recycling),
        _field('Sperrmüll-Termin', umw, 'sperrmuell', Icons.calendar_today),
        _field('Notizen', umw, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ SONSTIGES ============
  Widget _buildSonstigesTab(Map<String, dynamic> data) {
    final son = _bereich('sonstiges');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.more_horiz, 'Sonstige Anliegen', Colors.grey),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', son, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', son, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Waffenschein', son, 'waffenschein', Icons.gavel, hint: 'Nr. oder Status'),
        _field('Jagdschein', son, 'jagdschein', Icons.park, hint: 'Nr. oder Status'),
        _field('Fischereischein', son, 'fischereischein', Icons.water, hint: 'Nr. oder Status'),
        _field('Notizen', son, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ HELPERS ============
  Widget _header(IconData icon, String title, Color color) {
    return Row(children: [
      Icon(icon, size: 22, color: color),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _field(String label, Map<String, dynamic> map, String key, IconData icon, {String hint = '', int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: TextEditingController(text: map[key]?.toString() ?? ''),
        maxLines: maxLines,
        onChanged: (v) => map[key] = v,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _dropDown(String label, Map<String, dynamic> map, String key, IconData icon, Map<String, String> options) {
    final current = map[key]?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: options.containsKey(current) ? current : '',
            isDense: true,
            isExpanded: true,
            items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => setState(() => map[key] = v ?? ''),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveFooter(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton.icon(
          onPressed: widget.isSaving(type) ? null : () => widget.saveData(type, data),
          icon: widget.isSaving(type)
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 18),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
        ),
      ),
    );
  }
}
