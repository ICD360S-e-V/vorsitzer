import 'package:flutter/material.dart';

class BehordeEinwohnermeldeamtContent extends StatefulWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeEinwohnermeldeamtContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  @override
  State<BehordeEinwohnermeldeamtContent> createState() => _BehordeEinwohnermeldeamtContentState();
}

class _BehordeEinwohnermeldeamtContentState extends State<BehordeEinwohnermeldeamtContent> {
  static const type = 'einwohnermeldeamt';

  late TextEditingController dienststelleController;
  late TextEditingController anmeldedatumController;
  late TextEditingController meldeadresseController;
  late TextEditingController meldebescheinigungNrController;
  late TextEditingController nebenwohnsitzController;
  late TextEditingController notizenController;
  bool _controllersInitialized = false;

  void _initControllers(Map<String, dynamic> data) {
    dienststelleController = TextEditingController(text: data['dienststelle'] ?? '');
    anmeldedatumController = TextEditingController(text: data['anmeldedatum'] ?? '');
    meldeadresseController = TextEditingController(text: data['meldeadresse'] ?? '');
    meldebescheinigungNrController = TextEditingController(text: data['meldebescheinigung_nr'] ?? '');
    nebenwohnsitzController = TextEditingController(text: data['nebenwohnsitz'] ?? '');
    notizenController = TextEditingController(text: data['notizen'] ?? '');
    _controllersInitialized = true;
  }

  void _updateControllers(Map<String, dynamic> data) {
    _setIfDifferent(dienststelleController, data['dienststelle'] ?? '');
    _setIfDifferent(anmeldedatumController, data['anmeldedatum'] ?? '');
    _setIfDifferent(meldeadresseController, data['meldeadresse'] ?? '');
    _setIfDifferent(meldebescheinigungNrController, data['meldebescheinigung_nr'] ?? '');
    _setIfDifferent(nebenwohnsitzController, data['nebenwohnsitz'] ?? '');
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
      anmeldedatumController.dispose();
      meldeadresseController.dispose();
      meldebescheinigungNrController.dispose();
      nebenwohnsitzController.dispose();
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

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.dienststelleBuilder(type, dienststelleController),
              Text('Anmeldedatum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: anmeldedatumController,
                decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
              ),
              const SizedBox(height: 16),
              Text('Meldeadresse (Hauptwohnsitz)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: meldeadresseController,
                maxLines: 2,
                decoration: InputDecoration(hintText: 'Straße, Hausnummer, PLZ Ort', prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 20), child: Icon(Icons.location_on, size: 20)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
              ),
              const SizedBox(height: 16),
              Text('Nebenwohnsitz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: nebenwohnsitzController,
                decoration: InputDecoration(hintText: 'Falls vorhanden', prefixIcon: const Icon(Icons.home_work, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
              ),
              const SizedBox(height: 16),
              Text('Meldebescheinigung-Nr.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: meldebescheinigungNrController,
                decoration: InputDecoration(hintText: 'Nummer der Meldebescheinigung', prefixIcon: const Icon(Icons.description, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
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
                  onPressed: widget.isSaving(type) ? null : () {
                    widget.saveData(type, {
                      'dienststelle': dienststelleController.text.trim(),
                      'anmeldedatum': anmeldedatumController.text.trim(),
                      'meldeadresse': meldeadresseController.text.trim(),
                      'nebenwohnsitz': nebenwohnsitzController.text.trim(),
                      'meldebescheinigung_nr': meldebescheinigungNrController.text.trim(),
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
