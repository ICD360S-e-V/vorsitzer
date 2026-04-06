import 'package:flutter/material.dart';

class BehordeJugendamtContent extends StatelessWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeJugendamtContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  static const type = 'jugendamt';

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
    final notizenController = TextEditingController(text: data['notizen'] ?? '');
    String leistung = data['leistung'] ?? 'Keine';

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dienststelleBuilder(type, dienststelleController),
              Text('Aktenzeichen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: aktenzeichenController,
                decoration: InputDecoration(hintText: 'Aktenzeichen beim Jugendamt', prefixIcon: const Icon(Icons.folder, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
              ),
              const SizedBox(height: 16),
              Text('Leistung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: leistung,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'Keine', child: Text('Keine')),
                      DropdownMenuItem(value: 'Unterhaltsvorschuss', child: Text('Unterhaltsvorschuss')),
                      DropdownMenuItem(value: 'Beistandschaft', child: Text('Beistandschaft')),
                      DropdownMenuItem(value: 'Hilfe zur Erziehung', child: Text('Hilfe zur Erziehung (HzE)')),
                      DropdownMenuItem(value: 'Eingliederungshilfe', child: Text('Eingliederungshilfe')),
                      DropdownMenuItem(value: 'Kindertagesbetreuung', child: Text('Kindertagesbetreuung')),
                      DropdownMenuItem(value: 'Pflegekinderdienst', child: Text('Pflegekinderdienst')),
                      DropdownMenuItem(value: 'Sonstiges', child: Text('Sonstiges')),
                    ],
                    onChanged: (val) => setLocalState(() => leistung = val!),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Sachbearbeiter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: sachbearbeiterController,
                decoration: InputDecoration(hintText: 'Name des Sachbearbeiters', prefixIcon: const Icon(Icons.person, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
              ),
              const SizedBox(height: 16),
              Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: notizenController,
                maxLines: 3,
                decoration: InputDecoration(hintText: 'Weitere Informationen...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isSaving(type) ? null : () {
                    saveData(type, {
                      'dienststelle': dienststelleController.text.trim(),
                      'aktenzeichen': aktenzeichenController.text.trim(),
                      'leistung': leistung,
                      'sachbearbeiter': sachbearbeiterController.text.trim(),
                      'notizen': notizenController.text.trim(),
                    });
                  },
                  icon: isSaving(type)
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Speichern'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
