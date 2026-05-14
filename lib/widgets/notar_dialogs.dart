import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Shows a dialog to edit notar data
Future<bool> showEditNotarDialog({
  required BuildContext context,
  required Map<String, dynamic> data,
  required ApiService apiService,
}) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: data['name'] ?? '');
  final name2Controller = TextEditingController(text: data['name2'] ?? '');
  final strasseController = TextEditingController(text: data['strasse'] ?? '');
  final hausnummerController = TextEditingController(text: data['hausnummer'] ?? '');
  final plzController = TextEditingController(text: data['plz'] ?? '');
  final ortController = TextEditingController(text: data['ort'] ?? '');
  final telefonController = TextEditingController(text: data['telefon'] ?? '');
  final faxController = TextEditingController(text: data['fax'] ?? '');
  final emailController = TextEditingController(text: data['email'] ?? '');
  final websiteController = TextEditingController(text: data['website'] ?? '');
  final notizenController = TextEditingController(text: data['notizen'] ?? '');

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit, color: Colors.orange),
          SizedBox(width: 8),
          Text('Notardaten bearbeiten'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => v?.isEmpty ?? true ? 'Pflichtfeld' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name2Controller,
                  decoration: const InputDecoration(
                    labelText: 'Zusatzname',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Adresse', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: strasseController,
                        decoration: const InputDecoration(
                          labelText: 'Straße',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: hausnummerController,
                        decoration: const InputDecoration(
                          labelText: 'Nr.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        controller: plzController,
                        decoration: const InputDecoration(
                          labelText: 'PLZ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: ortController,
                        decoration: const InputDecoration(
                          labelText: 'Ort',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Kontakt', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: telefonController,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: faxController,
                  decoration: const InputDecoration(
                    labelText: 'Fax',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.fax),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: websiteController,
                  decoration: const InputDecoration(
                    labelText: 'Website',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                TextFormField(
                  controller: notizenController,
                  decoration: const InputDecoration(
                    labelText: 'Notizen',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (formKey.currentState?.validate() ?? false) {
              final navigator = Navigator.of(context);
              final updateResult = await apiService.updateVereinverwaltung({
                'id': data['id'],
                'name': nameController.text,
                'name2': name2Controller.text,
                'strasse': strasseController.text,
                'hausnummer': hausnummerController.text,
                'plz': plzController.text,
                'ort': ortController.text,
                'telefon': telefonController.text,
                'fax': faxController.text,
                'email': emailController.text,
                'website': websiteController.text,
                'notizen': notizenController.text,
              });
              navigator.pop(updateResult['success'] == true);
            }
          },
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows a dialog to add a new Rechnung
Future<bool> showAddRechnungDialog({
  required BuildContext context,
  required int notarId,
  required ApiService apiService,
}) async {
  final formKey = GlobalKey<FormState>();
  final rechnungsnummerController = TextEditingController();
  final betragController = TextEditingController();
  final beschreibungController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  bool bezahlt = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.blue),
            SizedBox(width: 8),
            Text('Neue Rechnung'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: rechnungsnummerController,
                    decoration: const InputDecoration(
                      labelText: 'Rechnungsnummer *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty ?? true ? 'Pflichtfeld' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: betragController,
                    decoration: const InputDecoration(
                      labelText: 'Betrag (€) *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v?.isEmpty ?? true ? 'Pflichtfeld' : null,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Datum'),
                    subtitle: Text('${selectedDate.day}.${selectedDate.month}.${selectedDate.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDate = date);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: beschreibungController,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bezahlt'),
                    value: bezahlt,
                    onChanged: (v) => setDialogState(() => bezahlt = v ?? false),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final navigator = Navigator.of(context);
                final createResult = await apiService.createNotarRechnung({
                  'notar_id': notarId,
                  'rechnungsnummer': rechnungsnummerController.text,
                  'datum': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  'betrag': double.tryParse(betragController.text) ?? 0,
                  'beschreibung': beschreibungController.text,
                  'bezahlt': bezahlt,
                });
                navigator.pop(createResult['success'] == true);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Shows a dialog to add a new Besuch
Future<bool> showAddBesuchDialog({
  required BuildContext context,
  required int notarId,
  required ApiService apiService,
}) async {
  final formKey = GlobalKey<FormState>();
  final zweckController = TextEditingController();
  final teilnehmerController = TextEditingController();
  final notizenController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  TimeOfDay? selectedTime;
  String status = 'geplant';

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.green),
            SizedBox(width: 8),
            Text('Neuer Besuch'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: zweckController,
                    decoration: const InputDecoration(
                      labelText: 'Zweck / Anlass *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty ?? true ? 'Pflichtfeld' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Datum'),
                          subtitle: Text('${selectedDate.day}.${selectedDate.month}.${selectedDate.year}'),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setDialogState(() => selectedDate = date);
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Uhrzeit'),
                          subtitle: Text(selectedTime != null
                              ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                              : 'Nicht gesetzt'),
                          trailing: const Icon(Icons.access_time),
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setDialogState(() => selectedTime = time);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: teilnehmerController,
                    decoration: const InputDecoration(
                      labelText: 'Teilnehmer',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notizenController,
                    decoration: const InputDecoration(
                      labelText: 'Notizen',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'geplant', child: Text('Geplant')),
                      DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen')),
                      DropdownMenuItem(value: 'abgesagt', child: Text('Abgesagt')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v ?? 'geplant'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final navigator = Navigator.of(context);
                final createResult = await apiService.createNotarBesuch({
                  'notar_id': notarId,
                  'datum': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  'uhrzeit': selectedTime != null
                      ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}:00'
                      : null,
                  'zweck': zweckController.text,
                  'teilnehmer': teilnehmerController.text,
                  'notizen': notizenController.text,
                  'status': status,
                });
                navigator.pop(createResult['success'] == true);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Shows a dialog to add a new Dokument
Future<bool> showAddDokumentDialog({
  required BuildContext context,
  required int notarId,
  required ApiService apiService,
}) async {
  final formKey = GlobalKey<FormState>();
  final titelController = TextEditingController();
  final beschreibungController = TextEditingController();
  final urkundennummerController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  String typ = 'sonstiges';

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder_open, color: Colors.purple),
            SizedBox(width: 8),
            Text('Neues Dokument'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titelController,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty ?? true ? 'Pflichtfeld' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: typ,
                    decoration: const InputDecoration(
                      labelText: 'Dokumenttyp',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'urkunde', child: Text('Urkunde')),
                      DropdownMenuItem(value: 'vollmacht', child: Text('Vollmacht')),
                      DropdownMenuItem(value: 'satzung', child: Text('Satzung')),
                      DropdownMenuItem(value: 'protokoll', child: Text('Protokoll')),
                      DropdownMenuItem(value: 'antrag', child: Text('Antrag')),
                      DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges')),
                    ],
                    onChanged: (v) => setDialogState(() => typ = v ?? 'sonstiges'),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Datum'),
                    subtitle: Text('${selectedDate.day}.${selectedDate.month}.${selectedDate.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDate = date);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: urkundennummerController,
                    decoration: const InputDecoration(
                      labelText: 'Urkundennummer',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: beschreibungController,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final navigator = Navigator.of(context);
                final createResult = await apiService.createNotarDokument({
                  'notar_id': notarId,
                  'titel': titelController.text,
                  'typ': typ,
                  'datum': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  'beschreibung': beschreibungController.text,
                  'urkundennummer': urkundennummerController.text,
                });
                navigator.pop(createResult['success'] == true);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Shows a detail dialog for an existing Aufgabe (edit, delete, toggle status)
Future<bool> showAufgabeDetailDialog({
  required BuildContext context,
  required Map<String, dynamic> aufgabe,
  required ApiService apiService,
}) async {
  final formKey = GlobalKey<FormState>();
  final beschreibungController = TextEditingController(text: aufgabe['beschreibung'] ?? '');
  final notizenController = TextEditingController(text: aufgabe['notizen'] ?? '');

  // Parse existing date
  DateTime selectedDate = DateTime.now();
  if (aufgabe['datum'] != null) {
    try {
      selectedDate = DateTime.parse(aufgabe['datum']);
    } catch (_) {}
  }

  // Parse existing time
  TimeOfDay? selectedTime;
  if (aufgabe['uhrzeit'] != null && aufgabe['uhrzeit'].toString().isNotEmpty) {
    final parts = aufgabe['uhrzeit'].toString().split(':');
    if (parts.length >= 2) {
      selectedTime = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 0,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }
  }

  String status = aufgabe['status'] ?? 'offen';
  bool changed = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Row(
          children: [
            Icon(
              status == 'erledigt' ? Icons.check_circle : Icons.task_alt,
              color: status == 'erledigt' ? Colors.green : Colors.deepOrange,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Aufgabe bearbeiten')),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Löschen',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Aufgabe löschen?'),
                    content: Text('„${aufgabe['beschreibung']}" wirklich löschen?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Abbrechen'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Löschen', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  if (!context.mounted) return;
                  final navigator = Navigator.of(context);
                  await apiService.deleteNotarAufgabe(aufgabe['id']);
                  navigator.pop(true);
                }
              },
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status toggle button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(
                        status == 'erledigt' ? Icons.undo : Icons.check_circle,
                        color: status == 'erledigt' ? Colors.orange : Colors.green,
                      ),
                      label: Text(
                        status == 'erledigt' ? 'Als offen markieren' : 'Als erledigt markieren',
                        style: TextStyle(
                          color: status == 'erledigt' ? Colors.orange : Colors.green,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: status == 'erledigt' ? Colors.orange : Colors.green,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        setDialogState(() {
                          status = status == 'erledigt' ? 'offen' : 'erledigt';
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: beschreibungController,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty ?? true ? 'Pflichtfeld' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Datum'),
                          subtitle: Text('${selectedDate.day}.${selectedDate.month}.${selectedDate.year}'),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setDialogState(() => selectedDate = date);
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Uhrzeit'),
                          subtitle: Text(selectedTime != null
                              ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                              : 'Nicht gesetzt'),
                          trailing: const Icon(Icons.access_time),
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setDialogState(() => selectedTime = time);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notizenController,
                    decoration: const InputDecoration(
                      labelText: 'Notizen',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, changed),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final navigator = Navigator.of(context);
                final updateResult = await apiService.updateNotarAufgabe({
                  'id': aufgabe['id'],
                  'beschreibung': beschreibungController.text,
                  'datum': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  'uhrzeit': selectedTime != null
                      ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}:00'
                      : null,
                  'status': status,
                  'notizen': notizenController.text,
                });
                navigator.pop(updateResult['success'] == true);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Shows a dialog to add a new Aufgabe
Future<bool> showAddAufgabeDialog({
  required BuildContext context,
  required int notarId,
  required ApiService apiService,
}) async {
  final formKey = GlobalKey<FormState>();
  final beschreibungController = TextEditingController();
  final notizenController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  TimeOfDay? selectedTime;
  String status = 'offen';

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.task_alt, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('Neue Aufgabe'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: beschreibungController,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty ?? true ? 'Pflichtfeld' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Datum'),
                          subtitle: Text('${selectedDate.day}.${selectedDate.month}.${selectedDate.year}'),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setDialogState(() => selectedDate = date);
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Uhrzeit'),
                          subtitle: Text(selectedTime != null
                              ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                              : 'Nicht gesetzt'),
                          trailing: const Icon(Icons.access_time),
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setDialogState(() => selectedTime = time);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'offen', child: Text('Offen')),
                      DropdownMenuItem(value: 'erledigt', child: Text('Erledigt')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v ?? 'offen'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notizenController,
                    decoration: const InputDecoration(
                      labelText: 'Notizen',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final navigator = Navigator.of(context);
                final createResult = await apiService.createNotarAufgabe({
                  'notar_id': notarId,
                  'datum': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  'uhrzeit': selectedTime != null
                      ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}:00'
                      : null,
                  'beschreibung': beschreibungController.text,
                  'status': status,
                  'notizen': notizenController.text,
                });
                navigator.pop(createResult['success'] == true);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Shows a dialog to add a new Zahlung
Future<bool> showAddZahlungDialog({
  required BuildContext context,
  required int notarId,
  required ApiService apiService,
}) async {
  final formKey = GlobalKey<FormState>();
  final betragController = TextEditingController();
  final verwendungszweckController = TextEditingController();
  final notizenController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  String zahlungsart = 'ueberweisung';

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.euro, color: Colors.teal),
            SizedBox(width: 8),
            Text('Neue Zahlung'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: betragController,
                    decoration: const InputDecoration(
                      labelText: 'Betrag (€) *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v?.isEmpty ?? true ? 'Pflichtfeld' : null,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Datum'),
                    subtitle: Text('${selectedDate.day}.${selectedDate.month}.${selectedDate.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDate = date);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: zahlungsart,
                    decoration: const InputDecoration(
                      labelText: 'Zahlungsart',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ueberweisung', child: Text('Überweisung')),
                      DropdownMenuItem(value: 'bar', child: Text('Bar')),
                      DropdownMenuItem(value: 'lastschrift', child: Text('Lastschrift')),
                      DropdownMenuItem(value: 'karte', child: Text('Karte')),
                    ],
                    onChanged: (v) => setDialogState(() => zahlungsart = v ?? 'ueberweisung'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: verwendungszweckController,
                    decoration: const InputDecoration(
                      labelText: 'Verwendungszweck',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notizenController,
                    decoration: const InputDecoration(
                      labelText: 'Notizen',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final navigator = Navigator.of(context);
                final createResult = await apiService.createNotarZahlung({
                  'notar_id': notarId,
                  'datum': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  'betrag': double.tryParse(betragController.text) ?? 0,
                  'zahlungsart': zahlungsart,
                  'verwendungszweck': verwendungszweckController.text,
                  'notizen': notizenController.text,
                });
                navigator.pop(createResult['success'] == true);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
