import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/notar_cards.dart';
import '../widgets/notar_dialogs.dart';
import '../widgets/responsive_layout.dart';

class NotarScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const NotarScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<NotarScreen> createState() => _NotarScreenState();
}

class _NotarScreenState extends State<NotarScreen> {
  Map<String, dynamic>? _notarData;
  bool _isLoadingNotar = true;
  List<Map<String, dynamic>> _notarRechnungen = [];
  List<Map<String, dynamic>> _notarBesuche = [];
  List<Map<String, dynamic>> _notarDokumente = [];
  List<Map<String, dynamic>> _notarZahlungen = [];
  List<Map<String, dynamic>> _notarAufgaben = [];
  bool _isLoadingNotarDetails = true;

  @override
  void initState() {
    super.initState();
    _loadNotarData();
  }

  Future<void> _loadNotarData() async {
    setState(() {
      _isLoadingNotar = true;
      _isLoadingNotarDetails = true;
    });
    try {
      final result = await widget.apiService.getVereinverwaltung(kategorie: 'notar');
      if (mounted && result['success'] == true) {
        final data = result['data'] as List?;
        if (data != null && data.isNotEmpty) {
          setState(() {
            _notarData = data[0];
            _isLoadingNotar = false;
          });
          _loadNotarDetails(data[0]['id']);
        } else {
          setState(() {
            _notarData = null;
            _isLoadingNotar = false;
            _isLoadingNotarDetails = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingNotar = false;
          _isLoadingNotarDetails = false;
        });
      }
    }
  }

  Future<void> _loadNotarDetails(int notarId) async {
    setState(() => _isLoadingNotarDetails = true);
    try {
      final results = await Future.wait([
        widget.apiService.getNotarRechnungen(notarId: notarId),
        widget.apiService.getNotarBesuche(notarId: notarId),
        widget.apiService.getNotarDokumente(notarId: notarId),
        widget.apiService.getNotarZahlungen(notarId: notarId),
        widget.apiService.getNotarAufgaben(notarId: notarId),
      ]);
      if (mounted) {
        setState(() {
          _notarRechnungen = List<Map<String, dynamic>>.from(
              results[0]['success'] == true ? (results[0]['data'] ?? []) : []);
          _notarBesuche = List<Map<String, dynamic>>.from(
              results[1]['success'] == true ? (results[1]['data'] ?? []) : []);
          _notarDokumente = List<Map<String, dynamic>>.from(
              results[2]['success'] == true ? (results[2]['data'] ?? []) : []);
          _notarZahlungen = List<Map<String, dynamic>>.from(
              results[3]['success'] == true ? (results[3]['data'] ?? []) : []);
          _notarAufgaben = List<Map<String, dynamic>>.from(
              results[4]['success'] == true ? (results[4]['data'] ?? []) : []);
          _isLoadingNotarDetails = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingNotarDetails = false);
    }
  }

  Future<void> _handleEditNotar() async {
    final data = _notarData;
    if (data == null) return;

    final success = await showEditNotarDialog(
      context: context,
      data: data,
      apiService: widget.apiService,
    );

    if (success && mounted) {
      _loadNotarData();
    }
  }

  Future<void> _handleAddRechnung() async {
    final notarId = _notarData?['id'];
    if (notarId == null) return;

    final success = await showAddRechnungDialog(
      context: context,
      notarId: notarId,
      apiService: widget.apiService,
    );

    if (success && mounted) {
      _loadNotarDetails(notarId);
    }
  }

  Future<void> _handleAddBesuch() async {
    final notarId = _notarData?['id'];
    if (notarId == null) return;

    final success = await showAddBesuchDialog(
      context: context,
      notarId: notarId,
      apiService: widget.apiService,
    );

    if (success && mounted) {
      _loadNotarDetails(notarId);
    }
  }

  Future<void> _handleAddDokument() async {
    final notarId = _notarData?['id'];
    if (notarId == null) return;

    final success = await showAddDokumentDialog(
      context: context,
      notarId: notarId,
      apiService: widget.apiService,
    );

    if (success && mounted) {
      _loadNotarDetails(notarId);
    }
  }

  Future<void> _handleAddZahlung() async {
    final notarId = _notarData?['id'];
    if (notarId == null) return;

    final success = await showAddZahlungDialog(
      context: context,
      notarId: notarId,
      apiService: widget.apiService,
    );

    if (success && mounted) {
      _loadNotarDetails(notarId);
    }
  }

  Future<void> _handleAddAufgabe() async {
    final notarId = _notarData?['id'];
    if (notarId == null) return;

    final success = await showAddAufgabeDialog(
      context: context,
      notarId: notarId,
      apiService: widget.apiService,
    );

    if (success && mounted) {
      _loadNotarDetails(notarId);
    }
  }

  Future<void> _handleAufgabeTap(Map<String, dynamic> aufgabe) async {
    final notarId = _notarData?['id'];
    if (notarId == null) return;

    final success = await showAufgabeDetailDialog(
      context: context,
      aufgabe: aufgabe,
      apiService: widget.apiService,
    );

    if (success && mounted) {
      _loadNotarDetails(notarId);
    }
  }

  /// Die sechs Karten in der Reihenfolge, in der sie auf breiten
  /// Bildschirmen nebeneinander stehen. Eine Quelle für beide Anordnungen —
  /// sonst driften Telefon- und Tablet-Ansicht bei der nächsten Änderung
  /// auseinander.
  List<Widget> _notarKarten() => [
        NotarDataCard(data: _notarData, onEdit: _handleEditNotar),
        NotarRechnungenCard(
            rechnungen: _notarRechnungen,
            isLoading: _isLoadingNotarDetails,
            onAdd: _handleAddRechnung),
        NotarBesucheCard(
            besuche: _notarBesuche,
            isLoading: _isLoadingNotarDetails,
            onAdd: _handleAddBesuch),
        NotarDokumenteCard(
            dokumente: _notarDokumente,
            isLoading: _isLoadingNotarDetails,
            onAdd: _handleAddDokument),
        NotarZahlungenCard(
            zahlungen: _notarZahlungen,
            isLoading: _isLoadingNotarDetails,
            onAdd: _handleAddZahlung),
        NotarAufgabenCard(
            aufgaben: _notarAufgaben,
            isLoading: _isLoadingNotarDetails,
            onAdd: _handleAddAufgabe,
            onTap: _handleAufgabeTap),
      ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 8),
              Icon(Icons.gavel, size: 32, color: Colors.orange.shade700),
              const SizedBox(width: 12),
              const Text(
                'Notar',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Content - 2 rows with 3 cards each
          Expanded(
            child: _isLoadingNotar
                ? const Center(child: CircularProgressIndicator())
                : ResponsiveLayout.istTelefon(context)
                    // ⚠️ Sechs Karten in zwei festen Dreierreihen: auf einem
                    // 411-dp-Telefon bekommt jede Karte 120 dp, ihre eigene
                    // Kopfzeile braucht aber 104 dp fest (Symbolkachel 44 +
                    // Abstand 12 + Bearbeiten-Knopf 48). Ergebnis: sechsmal
                    // 34 dp Überlauf. Untereinander statt nebeneinander —
                    // die feste Höhe, weil jede Karte innen ein `Expanded`
                    // hat und damit eine begrenzte Höhe braucht.
                    ? ListView(
                        children: [
                          for (final karte in _notarKarten())
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: SizedBox(height: 320, child: karte),
                            ),
                        ],
                      )
                    : Column(
                    children: [
                      // Row 1: Notardaten, Rechnungen, Besuche
                      Expanded(
                        flex: 1,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: NotarDataCard(
                                data: _notarData,
                                onEdit: _handleEditNotar,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: NotarRechnungenCard(
                                rechnungen: _notarRechnungen,
                                isLoading: _isLoadingNotarDetails,
                                onAdd: _handleAddRechnung,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: NotarBesucheCard(
                                besuche: _notarBesuche,
                                isLoading: _isLoadingNotarDetails,
                                onAdd: _handleAddBesuch,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Row 2: Dokumente, Zahlungen
                      Expanded(
                        flex: 1,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: NotarDokumenteCard(
                                dokumente: _notarDokumente,
                                isLoading: _isLoadingNotarDetails,
                                onAdd: _handleAddDokument,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: NotarZahlungenCard(
                                zahlungen: _notarZahlungen,
                                isLoading: _isLoadingNotarDetails,
                                onAdd: _handleAddZahlung,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: NotarAufgabenCard(
                                aufgaben: _notarAufgaben,
                                isLoading: _isLoadingNotarDetails,
                                onAdd: _handleAddAufgabe,
                                onTap: _handleAufgabeTap,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
