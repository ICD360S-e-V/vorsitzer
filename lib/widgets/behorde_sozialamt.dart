import 'package:flutter/material.dart';

class BehordeSozialamtContent extends StatelessWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeSozialamtContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  static const type = 'sozialamt';

  @override
  Widget build(BuildContext context) {
    final data = getData(type);
    if (data.isEmpty && !isLoading(type)) {
      loadData(type);
    }
    if (isLoading(type)) {
      return const Center(child: CircularProgressIndicator());
    }
    final dienststelleController = TextEditingController(text: data['dienststelle'] ?? '');
    final aktenzeichenController = TextEditingController(text: data['aktenzeichen'] ?? '');
    final sachbearbeiterController = TextEditingController(text: data['sachbearbeiter'] ?? '');
    final bewilligungVonController = TextEditingController(text: data['bewilligung_von'] ?? '');
    final bewilligungBisController = TextEditingController(text: data['bewilligung_bis'] ?? '');
    final notizenController = TextEditingController(text: data['notizen'] ?? '');
    String leistungsart = data['leistungsart'] ?? '';

    final leistungsarten = {
      '': 'Nicht ausgewählt',
      'grundsicherung_alter': 'Grundsicherung im Alter',
      'grundsicherung_erwerbsminderung': 'Grundsicherung bei Erwerbsminderung',
      'hilfe_lebensunterhalt': 'Hilfe zum Lebensunterhalt',
      'eingliederungshilfe': 'Eingliederungshilfe',
      'hilfe_pflege': 'Hilfe zur Pflege',
      'hilfe_gesundheit': 'Hilfe zur Gesundheit',
      'hilfe_besondere_lebenslagen': 'Hilfe in besonderen Lebenslagen',
      'sonstige': 'Sonstige Leistungen',
    };

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dienststelleBuilder(type, dienststelleController),
              // Aktenzeichen
              Text('Aktenzeichen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: aktenzeichenController,
                decoration: InputDecoration(
                  hintText: 'Aktenzeichen / Geschäftszeichen',
                  prefixIcon: const Icon(Icons.folder, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),

              // Sachbearbeiter
              Text('Sachbearbeiter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: sachbearbeiterController,
                decoration: InputDecoration(
                  hintText: 'Name des/der Sachbearbeiter/in',
                  prefixIcon: const Icon(Icons.support_agent, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),

              // Leistungsart
              Text('Leistungsart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: leistungsarten.containsKey(leistungsart) ? leistungsart : '',
                    isExpanded: true,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    items: leistungsarten.entries.map((e) {
                      return DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (v) => setLocalState(() => leistungsart = v ?? ''),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Bewilligungszeitraum
              Text('Bewilligungszeitraum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bewilligungVonController,
                      decoration: InputDecoration(
                        hintText: 'Von (TT.MM.JJJJ)',
                        prefixIcon: const Icon(Icons.calendar_today, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('bis', style: TextStyle(color: Colors.grey.shade600)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: bewilligungBisController,
                      decoration: InputDecoration(
                        hintText: 'Bis (TT.MM.JJJJ)',
                        prefixIcon: const Icon(Icons.calendar_today, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Notizen
              Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: notizenController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Zusätzliche Informationen...',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(Icons.note, size: 20),
                  ),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),

              // Save button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: isSaving(type) == true ? null : () {
                    saveData(type, {
                      'dienststelle': dienststelleController.text.trim(),
                      'aktenzeichen': aktenzeichenController.text.trim(),
                      'sachbearbeiter': sachbearbeiterController.text.trim(),
                      'leistungsart': leistungsart,
                      'bewilligung_von': bewilligungVonController.text.trim(),
                      'bewilligung_bis': bewilligungBisController.text.trim(),
                      'notizen': notizenController.text.trim(),
                    });
                  },
                  icon: isSaving(type) == true
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Speichern'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}
