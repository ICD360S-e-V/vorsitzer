import 'package:flutter/material.dart';

class BehordeVermieterContent extends StatefulWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeVermieterContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeVermieterContent> createState() => _BehordeVermieterContentState();
}

class _BehordeVermieterContentState extends State<BehordeVermieterContent> {
  static const type = 'vermieter';

  late TextEditingController firmaController;
  late TextEditingController firmaAdresseController;
  late TextEditingController telefonController;
  late TextEditingController emailController;
  late TextEditingController strasseController;
  late TextEditingController hausnummerController;
  late TextEditingController plzController;
  late TextEditingController ortController;
  late TextEditingController kaltmieteController;
  late TextEditingController warmmieteController;
  late TextEditingController faelligkeitController;
  late TextEditingController notizenController;
  bool _controllersInitialized = false;

  void _initControllers(Map<String, dynamic> data) {
    firmaController = TextEditingController(text: data['firma']?.toString() ?? '');
    firmaAdresseController = TextEditingController(text: data['firma_adresse']?.toString() ?? '');
    telefonController = TextEditingController(text: data['telefon']?.toString() ?? '');
    emailController = TextEditingController(text: data['email']?.toString() ?? '');
    strasseController = TextEditingController(text: data['strasse']?.toString() ?? '');
    hausnummerController = TextEditingController(text: data['hausnummer']?.toString() ?? '');
    plzController = TextEditingController(text: data['plz']?.toString() ?? '');
    ortController = TextEditingController(text: data['ort']?.toString() ?? '');
    kaltmieteController = TextEditingController(text: data['kaltmiete']?.toString() ?? '');
    warmmieteController = TextEditingController(text: data['warmmiete']?.toString() ?? '');
    faelligkeitController = TextEditingController(text: data['faelligkeit']?.toString() ?? '');
    notizenController = TextEditingController(text: data['notizen']?.toString() ?? '');
    _controllersInitialized = true;
  }

  void _updateControllers(Map<String, dynamic> data) {
    _setIfDifferent(firmaController, data['firma']?.toString() ?? '');
    _setIfDifferent(firmaAdresseController, data['firma_adresse']?.toString() ?? '');
    _setIfDifferent(telefonController, data['telefon']?.toString() ?? '');
    _setIfDifferent(emailController, data['email']?.toString() ?? '');
    _setIfDifferent(strasseController, data['strasse']?.toString() ?? '');
    _setIfDifferent(hausnummerController, data['hausnummer']?.toString() ?? '');
    _setIfDifferent(plzController, data['plz']?.toString() ?? '');
    _setIfDifferent(ortController, data['ort']?.toString() ?? '');
    _setIfDifferent(kaltmieteController, data['kaltmiete']?.toString() ?? '');
    _setIfDifferent(warmmieteController, data['warmmiete']?.toString() ?? '');
    _setIfDifferent(faelligkeitController, data['faelligkeit']?.toString() ?? '');
    _setIfDifferent(notizenController, data['notizen']?.toString() ?? '');
  }

  void _setIfDifferent(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.text = value;
    }
  }

  @override
  void dispose() {
    if (_controllersInitialized) {
      firmaController.dispose();
      firmaAdresseController.dispose();
      telefonController.dispose();
      emailController.dispose();
      strasseController.dispose();
      hausnummerController.dispose();
      plzController.dispose();
      ortController.dispose();
      kaltmieteController.dispose();
      warmmieteController.dispose();
      faelligkeitController.dispose();
      notizenController.dispose();
    }
    super.dispose();
  }

  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
        Expanded(child: Divider(color: color.withValues(alpha: 0.3), thickness: 1)),
      ]),
    );
  }

  Widget _textField(String label, TextEditingController controller, {String hint = '', IconData icon = Icons.edit, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
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

    String vertragsart = data['vertragsart']?.toString() ?? '';
    String mietobjekt = data['mietobjekt']?.toString() ?? '';
    String zahlungsart = data['zahlungsart']?.toString() ?? '';

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(Icons.apartment, 'Vermieter / Firma', Colors.deepPurple),
              const SizedBox(height: 8),
              _textField('Firma / Name des Vermieters', firmaController, hint: 'z.B. Vonovia SE', icon: Icons.business),
              const SizedBox(height: 8),
              _textField('Adresse der Firma', firmaAdresseController, hint: 'z.B. Universitätsstr. 133, 44803 Bochum', icon: Icons.location_city),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _textField('Telefonnummer', telefonController, hint: 'z.B. 0234 / 314-0', icon: Icons.phone)),
                const SizedBox(width: 12),
                Expanded(child: _textField('E-Mail-Adresse', emailController, hint: 'vermieter@beispiel.de', icon: Icons.email)),
              ]),

              const SizedBox(height: 20),
              _sectionHeader(Icons.description, 'Mietvertrag', Colors.blue.shade700),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.assignment, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Vertragsart:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                ChoiceChip(label: const Text('Unbefristet'), selected: vertragsart == 'unbefristet', selectedColor: Colors.green.shade100, onSelected: (sel) => setLocalState(() => vertragsart = sel ? 'unbefristet' : '')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Befristet'), selected: vertragsart == 'befristet', selectedColor: Colors.orange.shade100, onSelected: (sel) => setLocalState(() => vertragsart = sel ? 'befristet' : '')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.home_work, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Mietobjekt:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                ChoiceChip(label: const Text('Wohnung'), selected: mietobjekt == 'wohnung', selectedColor: Colors.blue.shade100, onSelected: (sel) => setLocalState(() => mietobjekt = sel ? 'wohnung' : '')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Haus'), selected: mietobjekt == 'haus', selectedColor: Colors.blue.shade100, onSelected: (sel) => setLocalState(() => mietobjekt = sel ? 'haus' : '')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Zimmer'), selected: mietobjekt == 'zimmer', selectedColor: Colors.blue.shade100, onSelected: (sel) => setLocalState(() => mietobjekt = sel ? 'zimmer' : '')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Gewerbe'), selected: mietobjekt == 'gewerbe', selectedColor: Colors.blue.shade100, onSelected: (sel) => setLocalState(() => mietobjekt = sel ? 'gewerbe' : '')),
              ]),

              const SizedBox(height: 20),
              _sectionHeader(Icons.location_on, 'Standort der Mietwohnung', Colors.teal),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(flex: 3, child: _textField('Straße', strasseController, hint: 'Musterstraße', icon: Icons.signpost)),
                const SizedBox(width: 12),
                Expanded(flex: 1, child: _textField('Nr.', hausnummerController, hint: '12a')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(flex: 1, child: _textField('PLZ', plzController, hint: '12345', icon: Icons.pin)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _textField('Ort', ortController, hint: 'Berlin', icon: Icons.location_city)),
              ]),

              const SizedBox(height: 20),
              _sectionHeader(Icons.euro, 'Miete & Zahlung', Colors.green.shade700),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _textField('Kaltmiete (€/Monat)', kaltmieteController, hint: 'z.B. 450,00', icon: Icons.euro)),
                const SizedBox(width: 12),
                Expanded(child: _textField('Warmmiete (€/Monat)', warmmieteController, hint: 'z.B. 580,00', icon: Icons.euro)),
              ]),
              const SizedBox(height: 12),
              _textField('Fälligkeitstag der Miete', faelligkeitController, hint: 'z.B. Zum 1. des Monats / Zum 3. Werktag', icon: Icons.calendar_today),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.payment, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Zahlungsart:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                ChoiceChip(label: const Text('SEPA-Lastschrift'), selected: zahlungsart == 'sepa', selectedColor: Colors.green.shade100, onSelected: (sel) => setLocalState(() => zahlungsart = sel ? 'sepa' : '')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Überweisung'), selected: zahlungsart == 'ueberweisung', selectedColor: Colors.green.shade100, onSelected: (sel) => setLocalState(() => zahlungsart = sel ? 'ueberweisung' : '')),
              ]),

              const SizedBox(height: 20),
              _sectionHeader(Icons.notes, 'Notizen', Colors.grey.shade700),
              const SizedBox(height: 8),
              _textField('Notizen', notizenController, hint: 'Weitere Informationen zum Mietverhältnis...', icon: Icons.notes, maxLines: 3),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.isSaving(type) ? null : () {
                    widget.saveData(type, {
                      'firma': firmaController.text.trim(),
                      'firma_adresse': firmaAdresseController.text.trim(),
                      'telefon': telefonController.text.trim(),
                      'email': emailController.text.trim(),
                      'vertragsart': vertragsart,
                      'mietobjekt': mietobjekt,
                      'strasse': strasseController.text.trim(),
                      'hausnummer': hausnummerController.text.trim(),
                      'plz': plzController.text.trim(),
                      'ort': ortController.text.trim(),
                      'kaltmiete': kaltmieteController.text.trim(),
                      'warmmiete': warmmieteController.text.trim(),
                      'faelligkeit': faelligkeitController.text.trim(),
                      'zahlungsart': zahlungsart,
                      'notizen': notizenController.text.trim(),
                    });
                  },
                  icon: widget.isSaving(type)
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Speichern'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
