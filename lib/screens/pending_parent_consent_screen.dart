import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pending_parent_consent_service.dart';
import '../widgets/eastern.dart';

/// "Eltern-Liste" / "Părinți de contactat" — coadă de minori (16-17)
/// pe care wizardul mitglieder a marcat-o `waiting_for_parent_consent`
/// după ce au completat datele unui părinte / Sorgeberechtigter.
/// Vorsitzer sună, notează apelul, leagă părintele (când e gata) și
/// validează semnătura digitală.
class PendingParentConsentScreen extends StatefulWidget {
  final String currentMitgliedernummer;

  const PendingParentConsentScreen({
    super.key,
    required this.currentMitgliedernummer,
  });

  @override
  State<PendingParentConsentScreen> createState() => _PendingParentConsentScreenState();
}

class _PendingParentConsentScreenState extends State<PendingParentConsentScreen> {
  final _service = PendingParentConsentService();
  bool _loading = true;
  List<PendingParentConsent> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _service.list(callerMitgliedernummer: widget.currentMitgliedernummer);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _urgencyColor(int days) {
    if (days >= 5) return Colors.red.shade700;
    if (days >= 3) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return SeasonalBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              children: [
                Icon(Icons.family_restroom, size: 32, color: Colors.purple.shade700),
                const SizedBox(width: 12),
                const Text(
                  'Eltern-Liste · Minder­jährige',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_items.length}',
                    style: TextStyle(color: Colors.purple.shade900, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Aktualisieren',
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Jugendliche (16-17 J.), die das Onboarding gestartet und einen Elternteil '
              'als Sorgeberechtigte/n hinterlegt haben. Vorstand kontaktiert den Elternteil, '
              'protokolliert den Anruf und verknüpft das Konto nach dessen Anmeldung.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade300),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Keine wartenden Anmeldungen',
                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 16, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Sobald ein/e Jugendliche/r das Onboarding mit Elternangaben\nabschließt, erscheint hier eine Karte.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _buildCard(_items[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(PendingParentConsent it) {
    final urgency = _urgencyColor(it.daysWaiting);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: urgency.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Child row
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.purple.shade100,
                  child: Icon(Icons.child_care, color: Colors.purple.shade700, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.childFullName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        '${it.mitgliedernummer} · ${it.age} J.${it.geburtsdatum != null ? " · geb. ${it.geburtsdatum}" : ""}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: urgency.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    it.daysWaiting <= 0 ? 'heute' : 'seit ${it.daysWaiting} Tag${it.daysWaiting > 1 ? "en" : ""}',
                    style: TextStyle(color: urgency, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // Parent row
            Row(
              children: [
                Icon(Icons.person, size: 18, color: Colors.indigo.shade600),
                const SizedBox(width: 6),
                Text('Elternteil zum Kontaktieren',
                    style: TextStyle(fontSize: 11, color: Colors.indigo.shade800, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it.parentFullName.isEmpty ? '— (kein Name hinterlegt)' : it.parentFullName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text('Beziehung: ${it.relationLabel}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  if (it.parentTelefon != null && it.parentTelefon!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone, size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(it.parentTelefon!,
                            style: TextStyle(fontSize: 13, color: Colors.green.shade800, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: it.parentTelefon == null || it.parentTelefon!.trim().isEmpty
                      ? null
                      : () => _call(it.parentTelefon),
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Anrufen', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showComingSoonSnack('Anruf protokollieren'),
                  icon: const Icon(Icons.note_add, size: 16),
                  label: Text(
                    it.callsLogged > 0 ? 'Anruf notieren (${it.callsLogged})' : 'Anruf notieren',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showComingSoonSnack('Eltern-Konto verknüpfen'),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('Elternteil verknüpfen', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoonSnack(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature — kommt im nächsten Patch (eigenes Modal mit Formular).'),
      duration: const Duration(seconds: 3),
    ));
  }
}
