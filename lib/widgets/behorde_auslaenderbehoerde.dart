import 'package:flutter/material.dart';

class BehordeAuslaenderbehoerdeContent extends StatefulWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeAuslaenderbehoerdeContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  @override
  State<BehordeAuslaenderbehoerdeContent> createState() => _BehordeAuslaenderbehoerdeContentState();
}

class _BehordeAuslaenderbehoerdeContentState extends State<BehordeAuslaenderbehoerdeContent> {
  static const type = 'auslaenderbehoerde';

  late TextEditingController dienststelleController;
  late TextEditingController aktenzeichenController;
  late TextEditingController aufenthaltstitelController;
  late TextEditingController ablaufdatumController;
  late TextEditingController sachbearbeiterController;
  late TextEditingController notizenController;
  bool _controllersInitialized = false;

  void _initControllers(Map<String, dynamic> data) {
    dienststelleController = TextEditingController(text: data['dienststelle'] ?? '');
    aktenzeichenController = TextEditingController(text: data['aktenzeichen'] ?? '');
    aufenthaltstitelController = TextEditingController(text: data['aufenthaltstitel'] ?? '');
    ablaufdatumController = TextEditingController(text: data['ablaufdatum'] ?? '');
    sachbearbeiterController = TextEditingController(text: data['sachbearbeiter'] ?? '');
    notizenController = TextEditingController(text: data['notizen'] ?? '');
    _controllersInitialized = true;
  }

  void _updateControllers(Map<String, dynamic> data) {
    _setIfDifferent(dienststelleController, data['dienststelle'] ?? '');
    _setIfDifferent(aktenzeichenController, data['aktenzeichen'] ?? '');
    _setIfDifferent(aufenthaltstitelController, data['aufenthaltstitel'] ?? '');
    _setIfDifferent(ablaufdatumController, data['ablaufdatum'] ?? '');
    _setIfDifferent(sachbearbeiterController, data['sachbearbeiter'] ?? '');
    _setIfDifferent(notizenController, data['notizen'] ?? '');
  }

  void _setIfDifferent(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.text = value;
    }
  }

  @override
  void dispose() {
    if (_controllersInitialized) {
      dienststelleController.dispose();
      aktenzeichenController.dispose();
      aufenthaltstitelController.dispose();
      ablaufdatumController.dispose();
      sachbearbeiterController.dispose();
      notizenController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.getData(type);
    if (data.isEmpty && !widget.isLoading(type)) {
      widget.loadData(type);
    }
    if (widget.isLoading(type)) {
      return const Center(child: CircularProgressIndicator());
    }

    // Initialize or update controllers
    if (!_controllersInitialized) {
      _initControllers(data);
    } else {
      _updateControllers(data);
    }

    String aufenthaltsstatus = data['aufenthaltsstatus'] ?? '';

    final statusOptionen = {
      '': 'Nicht ausgewählt',
      'aufenthaltserlaubnis': 'Aufenthaltserlaubnis (befristet)',
      'niederlassungserlaubnis': 'Niederlassungserlaubnis (unbefristet)',
      'blaue_karte': 'Blaue Karte EU',
      'duldung': 'Duldung',
      'gestattung': 'Aufenthaltsgestattung',
      'visum': 'Visum',
      'eu_buerger': 'EU-Freizügigkeit',
      'einbuergerung': 'Einbürgerung beantragt',
    };

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.dienststelleBuilder(type, dienststelleController),
              Text('Aktenzeichen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: aktenzeichenController,
                decoration: InputDecoration(hintText: 'Aktenzeichen Ausländerbehörde', prefixIcon: const Icon(Icons.folder, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text('Aufenthaltsstatus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: statusOptionen.containsKey(aufenthaltsstatus) ? aufenthaltsstatus : '',
                    isExpanded: true,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    items: statusOptionen.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setLocalState(() => aufenthaltsstatus = v ?? ''),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Aufenthaltstitel / Bescheinigung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: aufenthaltstitelController,
                decoration: InputDecoration(hintText: 'z.B. §25 Abs.1 AufenthG', prefixIcon: const Icon(Icons.description, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text('Gültig bis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: ablaufdatumController,
                decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.event, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text('Sachbearbeiter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: sachbearbeiterController,
                decoration: InputDecoration(hintText: 'Name des/der Sachbearbeiter/in', prefixIcon: const Icon(Icons.support_agent, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: notizenController,
                maxLines: 3,
                decoration: InputDecoration(hintText: 'Zusätzliche Informationen...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: widget.isSaving(type) ? null : () {
                    widget.saveData(type, {
                      'dienststelle': dienststelleController.text.trim(),
                      'aktenzeichen': aktenzeichenController.text.trim(),
                      'aufenthaltsstatus': aufenthaltsstatus,
                      'aufenthaltstitel': aufenthaltstitelController.text.trim(),
                      'ablaufdatum': ablaufdatumController.text.trim(),
                      'sachbearbeiter': sachbearbeiterController.text.trim(),
                      'notizen': notizenController.text.trim(),
                    });
                  },
                  icon: widget.isSaving(type)
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
