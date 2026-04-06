import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class PersonalDataDialog extends StatefulWidget {
  final String userName;
  final String mitgliedernummer;

  const PersonalDataDialog({
    super.key,
    required this.userName,
    required this.mitgliedernummer,
  });

  @override
  State<PersonalDataDialog> createState() => _PersonalDataDialogState();
}

class _PersonalDataDialogState extends State<PersonalDataDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _vornameController = TextEditingController();
  final _nachnameController = TextEditingController();
  final _strasseController = TextEditingController();
  final _hausnummerController = TextEditingController();
  final _plzController = TextEditingController();
  final _ortController = TextEditingController();
  final _telefonMobilController = TextEditingController();
  final _geburtsdatumController = TextEditingController();
  DateTime? _selectedGeburtsdatum;
  bool _isLoading = false;
  bool _isLoadingData = true;

  // Regex for name validation: letters (including German umlauts), hyphen, space
  static final _nameRegex = RegExp(r'^[a-zA-ZäöüÄÖÜßéèêëàâáíìîïóòôúùûñçÉÈÊËÀÂÁÍÌÎÏÓÒÔÚÙÛÑÇ\-\s]+$');

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final result = await _apiService.getProfile(widget.mitgliedernummer);
      if (result['success'] == true) {
        // API returns data directly in result, not under 'data' key
        setState(() {
          _vornameController.text = result['vorname'] ?? '';
          _nachnameController.text = result['nachname'] ?? '';
          _strasseController.text = result['strasse'] ?? '';
          _hausnummerController.text = result['hausnummer'] ?? '';
          _plzController.text = result['plz'] ?? '';
          _ortController.text = result['ort'] ?? '';
          _telefonMobilController.text = result['telefon_mobil'] ?? '';
          if (result['geburtsdatum'] != null && result['geburtsdatum'].toString().isNotEmpty) {
            _selectedGeburtsdatum = DateTime.tryParse(result['geburtsdatum']);
            if (_selectedGeburtsdatum != null) {
              _geburtsdatumController.text = DateFormat('dd.MM.yyyy').format(_selectedGeburtsdatum!);
            }
          }
          _isLoadingData = false;
        });
      } else {
        _fallbackNameSplit();
      }
    } catch (e) {
      _fallbackNameSplit();
    }
  }

  void _fallbackNameSplit() {
    final nameParts = widget.userName.split(' ');
    if (nameParts.length >= 2) {
      _vornameController.text = nameParts.first;
      _nachnameController.text = nameParts.sublist(1).join(' ');
    } else {
      _nachnameController.text = widget.userName;
    }
    setState(() => _isLoadingData = false);
  }

  @override
  void dispose() {
    _vornameController.dispose();
    _nachnameController.dispose();
    _strasseController.dispose();
    _hausnummerController.dispose();
    _plzController.dispose();
    _ortController.dispose();
    _telefonMobilController.dispose();
    _geburtsdatumController.dispose();
    super.dispose();
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _apiService.updateProfile(
        mitgliedernummer: widget.mitgliedernummer,
        vorname: _vornameController.text.trim(),
        nachname: _nachnameController.text.trim(),
        strasse: _strasseController.text.trim(),
        hausnummer: _hausnummerController.text.trim(),
        plz: _plzController.text.trim(),
        ort: _ortController.text.trim(),
        telefonMobil: _telefonMobilController.text.trim(),
        geburtsdatum: _selectedGeburtsdatum != null
            ? DateFormat('yyyy-MM-dd').format(_selectedGeburtsdatum!)
            : null,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daten erfolgreich gespeichert'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler beim Speichern'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4a90d9).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: Color(0xFF4a90d9),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Persönliche Daten',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Aktualisieren Sie Ihre Kontaktdaten',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 32),

                // Loading indicator while fetching data
                if (_isLoadingData)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Daten werden geladen...'),
                        ],
                      ),
                    ),
                  )
                else ...[
                // Form fields - Vorname & Nachname
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _vornameController,
                        decoration: InputDecoration(
                          labelText: 'Vorname',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-ZäöüÄÖÜßéèêëàâáíìîïóòôúùûñçÉÈÊËÀÂÁÍÌÎÏÓÒÔÚÙÛÑÇ\-\s]')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte Vorname eingeben';
                          }
                          if (!_nameRegex.hasMatch(value)) {
                            return 'Nur Buchstaben und Bindestrich erlaubt';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _nachnameController,
                        decoration: InputDecoration(
                          labelText: 'Nachname',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-ZäöüÄÖÜßéèêëàâáíìîïóòôúùûñçÉÈÊËÀÂÁÍÌÎÏÓÒÔÚÙÛÑÇ\-\s]')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte Nachname eingeben';
                          }
                          if (!_nameRegex.hasMatch(value)) {
                            return 'Nur Buchstaben und Bindestrich erlaubt';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Straße und Hausnummer (separate fields)
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _strasseController,
                        decoration: InputDecoration(
                          labelText: 'Straße',
                          prefixIcon: const Icon(Icons.home),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _hausnummerController,
                        decoration: InputDecoration(
                          labelText: 'Nr.',
                          prefixIcon: const Icon(Icons.numbers),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // PLZ und Ort
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        controller: _plzController,
                        decoration: InputDecoration(
                          labelText: 'PLZ',
                          prefixIcon: const Icon(Icons.pin_drop),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _ortController,
                        decoration: InputDecoration(
                          labelText: 'Ort',
                          prefixIcon: const Icon(Icons.location_city),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Geburtsdatum
                TextFormField(
                  controller: _geburtsdatumController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Geburtsdatum',
                    prefixIcon: const Icon(Icons.cake),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: 'TT.MM.JJJJ',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedGeburtsdatum ?? DateTime(1990, 1, 1),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                          locale: const Locale('de', 'DE'),
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedGeburtsdatum = picked;
                            _geburtsdatumController.text = DateFormat('dd.MM.yyyy').format(picked);
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Telefonnummer
                TextFormField(
                  controller: _telefonMobilController,
                  decoration: InputDecoration(
                    labelText: 'Telefonnummer',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: '+49 170 1234567',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4a90d9),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Daten speichern',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
