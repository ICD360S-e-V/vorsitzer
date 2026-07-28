import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/global_chat_service.dart';
import '../services/secure_cloud_service.dart';
import '../utils/file_picker_helper.dart';
import 'cloud_file_picker.dart';
import 'file_viewer_dialog.dart';
import '../utils/cloud_picker_helper.dart';

/// Wie viele Dateien noch angenommen werden dürfen.
///
/// `null` heißt „keine Grenze" — entweder weil [maxTotal] nicht gesetzt ist,
/// oder weil der Bestand noch nicht [geladen] wurde. Der zweite Fall ist
/// Absicht: vor dem ersten Laden ist `bestand` immer 0, eine Sperre daraus
/// abzuleiten würde einen vollen Anhang fälschlich als leer behandeln — besser
/// kurz zu viel erlauben und nach dem Reload korrigieren, als zu blockieren.
int? freieAnhangSlots({required int? maxTotal, required int bestand, required bool geladen}) {
  if (maxTotal == null || !geladen) return null;
  final rest = maxTotal - bestand;
  return rest < 0 ? 0 : rest;
}

/// Ob neben „Datei" auch „Cloud" erscheint.
///
/// [eigenerSpeicher] = Augenarzt/HNO/Krankenhaus. Die legen ihre Anhänge über
/// eigene Endpunkte ab; nur der Weg über eine temporäre Datei trifft dort das
/// Richtige, und der braucht [memberId]. Fehlt sie, fiele die Übernahme auf
/// den Standard-Endpunkt zurück und legte die Datei still im falschen Ordner
/// ab — deshalb bleibt der Knopf dann lieber weg.
///
/// Als eigenständige Funktion, weil das Widget in `initState` vom Server lädt
/// und sich ohne registriertes Gerät nicht darstellen lässt; so ist die
/// Entscheidung trotzdem prüfbar.
bool zeigeCloudKnopf({
  required bool eigenerSpeicher,
  required int? memberId,
  required String? adminCloud,
}) =>
    eigenerSpeicher ? memberId != null : (memberId != null || adminCloud != null);

class KorrAttachmentsWidget extends StatefulWidget {
  final ApiService apiService;
  final String modul;
  final int korrespondenzId;
  /// true = eigene augenarzt_attachment-Speicherung (entkoppelt, eigener Ordner).
  final bool augenarzt;
  /// true = eigene hno_attachment-Speicherung (entkoppelt, eigener Ordner).
  final bool hno;
  /// true = eigene krankenhaus_attachment-Speicherung (entkoppelt, eigener Ordner).
  final bool krankenhaus;
  /// true = eigene md_attachment-Speicherung (Medizinischer Dienst, eigener Ordner).
  final bool md;
  /// Optional: erlaubte Dateiendungen beim Upload (Default: pdf/jpg/jpeg/png).
  final List<String>? allowedExtensions;
  /// Optional: max. Anzahl Dateien pro Upload-Vorgang (Default: unbegrenzt).
  final int? maxFiles;
  /// Optional: Gesamtobergrenze über ALLE Uploads hinweg (Default: unbegrenzt).
  /// Anders als [maxFiles] zählt hier der Bestand mit — ist er erreicht, sind
  /// „Datei" und „Cloud" gesperrt. Für Dokumente mit fester Seitenzahl, z. B.
  /// den Schwerbehindertenausweis.
  final int? maxTotal;
  /// Wessen Akte gerade bearbeitet wird. Ist sie gesetzt, erscheint neben
  /// „Datei" auch „Cloud".
  ///
  /// Welcher der beiden Speicher sich öffnet, entscheidet das Widget selbst:
  /// der verschlüsselte 50-GB-Cloud, wenn der angemeldete Vorsitzende seine
  /// EIGENE Akte bearbeitet, sonst der 1-GB-Cloud des Mitglieds.
  ///
  /// Beim Standardpfad kopiert der Server direkt, die Datei berührt das Gerät
  /// nie. Augenarzt/HNO/Krankenhaus haben keinen solchen Endpunkt — dort wird
  /// die Datei lokal geholt und wie eine Geräte-Datei abgelegt.
  final int? memberId;
  /// Mitgliedsnummer für den **eigenen 50-GB-Cloud** (Ende-zu-Ende
  /// verschlüsselt). Ist sie gesetzt, greift „Cloud" auf diesen Speicher zu
  /// statt auf den 1-GB-Cloud des Mitglieds — gedacht für den Vorsitzenden,
  /// der eigene Unterlagen an eine Behörde hängt.
  final String? adminCloudMitgliedernummer;

  const KorrAttachmentsWidget({
    super.key,
    required this.apiService,
    required this.modul,
    required this.korrespondenzId,
    this.augenarzt = false,
    this.hno = false,
    this.krankenhaus = false,
    this.md = false,
    this.allowedExtensions,
    this.maxFiles,
    this.maxTotal,
    this.memberId,
    this.adminCloudMitgliedernummer,
  });

  @override
  State<KorrAttachmentsWidget> createState() => _KorrAttachmentsWidgetState();
}

class _KorrAttachmentsWidgetState extends State<KorrAttachmentsWidget> {
  List<Map<String, dynamic>> _attachments = [];
  bool _loaded = false;

  // Routet Attachment-Aktionen: für Augenarzt auf augenarzt_attachment.php,
  // für HNO auf hno_attachment.php, sonst generisch.
  Future<Map<String, dynamic>> _apiList() => widget.md
      ? widget.apiService.mdListKorrAttachments(widget.modul, widget.korrespondenzId)
      : widget.krankenhaus
      ? widget.apiService.krankenhausListKorrAttachments(widget.modul, widget.korrespondenzId)
      : widget.hno
      ? widget.apiService.hnoListKorrAttachments(widget.modul, widget.korrespondenzId)
      : widget.augenarzt
          ? widget.apiService.augenarztListKorrAttachments(widget.modul, widget.korrespondenzId)
          : widget.apiService.listKorrAttachments(widget.modul, widget.korrespondenzId);
  Future<Map<String, dynamic>> _apiUpload(String filePath, String fileName) => widget.md
      ? widget.apiService.mdUploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName)
      : widget.krankenhaus
      ? widget.apiService.krankenhausUploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName)
      : widget.hno
      ? widget.apiService.hnoUploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName)
      : widget.augenarzt
          ? widget.apiService.augenarztUploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName)
          : widget.apiService.uploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName);
  Future<Map<String, dynamic>> _apiDelete(int id) => widget.md
      ? widget.apiService.mdDeleteKorrAttachment(id)
      : widget.krankenhaus
      ? widget.apiService.krankenhausDeleteKorrAttachment(id)
      : widget.hno
      ? widget.apiService.hnoDeleteKorrAttachment(id)
      : widget.augenarzt
          ? widget.apiService.augenarztDeleteKorrAttachment(id) : widget.apiService.deleteKorrAttachment(id);
  Future _apiDownload(int id) => widget.md
      ? widget.apiService.mdDownloadKorrAttachment(id)
      : widget.krankenhaus
      ? widget.apiService.krankenhausDownloadKorrAttachment(id)
      : widget.hno
      ? widget.apiService.hnoDownloadKorrAttachment(id)
      : widget.augenarzt
          ? widget.apiService.augenarztDownloadKorrAttachment(id) : widget.apiService.downloadKorrAttachment(id);

  @override
  void initState() { super.initState(); _load(); }

  // CRITICAL: ListView reuses State when a list reorders. Without this, the
  // state's _attachments stay frozen on the OLD korrespondenzId — meaning a
  // newly added Korrespondenz shows attachments from a previous list row.
  @override
  void didUpdateWidget(covariant KorrAttachmentsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.korrespondenzId != widget.korrespondenzId || oldWidget.modul != widget.modul) {
      _attachments = [];
      _loaded = false;
      _load();
    }
  }

  Future<void> _load() async {
    final r = await _apiList();
    if (!mounted) return;
    setState(() {
      if (r['success'] == true && r['data'] is List) {
        _attachments = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _attachments = [];
      }
      _loaded = true;
    });
  }

  int? get _frei => freieAnhangSlots(maxTotal: widget.maxTotal, bestand: _attachments.length, geladen: _loaded);

  bool get _voll => _frei == 0;

  void _meldeVoll() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Maximal ${widget.maxTotal} Dateien — bitte zuerst eine entfernen.'),
      backgroundColor: Colors.orange));
  }

  Future<void> _upload() async {
    if (_voll) {
      _meldeVoll();
      return;
    }
    final exts = widget.allowedExtensions ?? const ['pdf', 'jpg', 'jpeg', 'png'];
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: exts, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    var files = result.files.where((f) => f.path != null).toList();
    if (widget.maxFiles != null && files.length > widget.maxFiles!) {
      final max = widget.maxFiles!;
      files = files.take(max).toList();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Maximal $max Dateien gleichzeitig — nur die ersten $max werden hochgeladen.')));
    }
    // Gesamtgrenze zählt den Bestand mit, greift also auch über mehrere
    // Upload-Vorgänge hinweg.
    final frei = _frei;
    if (frei != null && files.length > frei) {
      final verworfen = files.length - frei;
      files = files.take(frei).toList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nur noch $frei Datei(en) frei — $verworfen übersprungen.'),
          backgroundColor: Colors.orange));
      }
    }
    for (final file in files) {
      await _apiUpload(file.path!, file.name);
    }
    _load();
  }

  /// Augenarzt, HNO und Krankenhaus legen ihre Anhänge in eigenen Ordnern
  /// über eigene Endpunkte ab.
  ///
  /// Für sie gibt es weder eine Server-zu-Server-Übernahme noch einen
  /// Bytes-Upload — beides existiert nur für den Standardpfad. Deshalb wird
  /// die Datei dort erst lokal geholt und dann wie eine Geräte-Datei abgelegt;
  /// [_apiUpload] trifft von selbst den richtigen Endpunkt.
  bool get _eigenerSpeicher => widget.augenarzt || widget.hno || widget.krankenhaus || widget.md;

  /// „Cloud" ist möglich, sobald bekannt ist, um wessen Akte es geht.
  ///
  /// Früher waren die drei Sonderspeicher hier ausgenommen, weil der
  /// Übernahme-Weg fest auf den Standard-Endpunkt zeigte. Seit es den Weg
  /// über eine temporäre Datei gibt, gilt die Einschränkung nicht mehr.
  ///
  /// Für die Sonderspeicher wird die Mitglieds-ID allerdings zwingend
  /// gebraucht — siehe [zeigeCloudKnopf].
  bool get _cloudAvailable => zeigeCloudKnopf(
        eigenerSpeicher: _eigenerSpeicher,
        memberId: widget.memberId,
        adminCloud: _adminCloud,
      );

  /// Gesetzt = „Cloud" liest den verschlüsselten 50-GB-Speicher statt des
  /// Mitglieder-Clouds.
  ///
  /// Wird normalerweise selbst ermittelt: bearbeitet der angemeldete Admin
  /// seine EIGENE Akte, sind seine Unterlagen im 50-GB-Cloud der Kopfzeile
  /// (`admin_cloud_files`) und nicht im 1-GB-Cloud der Mitglieder
  /// (`member_cloud_files`) — dort wäre die Liste schlicht leer.
  ///
  /// Absichtlich hier zentral statt als Pflichtparameter: das Widget wird an
  /// über hundert Stellen verwendet, ein durchgereichtes Flag würde an jeder
  /// vergessenen Stelle still das falsche Cloud öffnen.
  ///
  /// [KorrAttachmentsWidget.adminCloudMitgliedernummer] überschreibt die
  /// Automatik, falls ein Aufrufer es explizit steuern muss.
  String? get _adminCloud {
    final explizit = widget.adminCloudMitgliedernummer;
    if (explizit != null && explizit.isNotEmpty) return explizit;
    final g = GlobalChatService();
    final nr = g.currentMitgliedernummer;
    final ich = g.currentAdminUserId;
    if (nr == null || nr.isEmpty || ich == null) return null;
    return widget.memberId == ich ? nr : null;
  }

  /// Übernahme aus dem verschlüsselten 50-GB-Cloud.
  ///
  /// Hier ist keine Server-zu-Server-Kopie möglich: der Server kennt den
  /// Schlüssel nicht und würde nur einen unlesbaren Blob weiterreichen. Also
  /// herunterladen, im RAM entschlüsseln und den Klartext hochladen — ohne
  /// Umweg über eine temporäre Datei.
  Future<void> _attachFromAdminCloud(String mitgliedernummer) async {
    final messenger = ScaffoldMessenger.of(context);
    final auswahl = await showAdminCloudFilePicker(
      context,
      apiService: widget.apiService,
      mitgliedernummer: mitgliedernummer,
      maxFiles: _frei,
    );
    if (auswahl == null || auswahl.isEmpty || !mounted) return;
    final svc = SecureCloudService(widget.apiService, mitgliedernummer);
    var ok = 0;
    for (final f in auswahl) {
      final klartext = await svc.downloadToMemory(f);
      if (klartext == null) continue;
      final r = await _apiUploadBytes(klartext, f.name);
      if (r['success'] == true) ok++;
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text('$ok von ${auswahl.length} aus dem verschlüsselten Cloud übernommen'),
      backgroundColor: ok == auswahl.length ? Colors.green : Colors.orange,
    ));
    _load();
  }

  Future<Map<String, dynamic>> _apiUploadBytes(Uint8List bytes, String fileName) =>
      widget.apiService.uploadKorrAttachmentBytes(
        modul: widget.modul, korrespondenzId: widget.korrespondenzId,
        bytes: bytes, fileName: fileName);

  /// Übernahme für die Sonderspeicher (Augenarzt/HNO/Krankenhaus).
  ///
  /// [CloudPickerHelper.pickFiles] wählt selbst den zuständigen Speicher —
  /// den verschlüsselten 50-GB-Cloud in der eigenen Akte, sonst den 1-GB-Cloud
  /// des Mitglieds — und legt das Ergebnis als gewöhnliche Datei ab. Damit
  /// trifft [_apiUpload] danach von allein den richtigen Endpunkt.
  Future<void> _ausCloudUeberDatei(int memberId) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await CloudPickerHelper.pickFiles(
      context,
      apiService: widget.apiService,
      memberId: memberId,
      maxFiles: _frei,
    );
    if (r == null || r.files.isEmpty || !mounted) return;
    var ok = 0;
    for (final f in r.files) {
      if (f.path == null) continue;
      final res = await _apiUpload(f.path!, f.name);
      if (res['success'] == true) ok++;
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text('$ok von ${r.files.length} aus Cloud übernommen'),
      backgroundColor: ok == r.files.length ? Colors.green : Colors.orange,
    ));
    _load();
  }

  Future<void> _attachFromCloud() async {
    if (_voll) {
      _meldeVoll();
      return;
    }
    final eigene = widget.memberId;
    if (_eigenerSpeicher && eigene != null) {
      await _ausCloudUeberDatei(eigene);
      return;
    }
    // Vorsitzender: eigener verschlüsselter 50-GB-Speicher statt des
    // 1-GB-Clouds des Mitglieds.
    final adminNr = _adminCloud;
    if (adminNr != null) {
      await _attachFromAdminCloud(adminNr);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final res = await pickAndAttachFromCloud(
      context,
      apiService: widget.apiService,
      memberId: widget.memberId!,
      maxFiles: _frei,
      attach: (id) => widget.apiService.attachKorrAttachmentFromCloud(
        modul: widget.modul,
        korrespondenzId: widget.korrespondenzId,
        userId: widget.memberId!,
        cloudFileId: id,
      ),
    );
    if (res == null || !mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text('${res.ok} von ${res.total} aus Cloud übernommen'),
      backgroundColor: res.ok == res.total ? Colors.green : Colors.orange,
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.attach_file, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(
          'Anhänge${_loaded ? (widget.maxTotal != null ? ' (${_attachments.length}/${widget.maxTotal})' : ' (${_attachments.length})') : ''}',
          style: TextStyle(
            fontSize: 11,
            color: _voll ? Colors.orange.shade800 : Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_cloudAvailable)
          Builder(builder: (_) {
            // Verschlüsselter Eigen-Cloud sieht anders aus als der Mitglieder-
            // Cloud — sonst wäre auf den ersten Blick nicht erkennbar, aus
            // welchem Speicher eine Datei kommt.
            final istAdmin = _adminCloud != null;
            final farbe = _voll
                ? Colors.grey.shade400
                : (istAdmin ? Colors.deepPurple.shade600 : Colors.blue.shade700);
            return Tooltip(
              message: istAdmin
                  ? 'Aus dem eigenen verschlüsselten Cloud (50 GB)'
                  : 'Aus dem Cloud des Mitglieds',
              child: InkWell(
                onTap: _attachFromCloud,
                child: Padding(padding: const EdgeInsets.all(4), child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(istAdmin ? Icons.lock : Icons.cloud_download, size: 14, color: farbe),
                  const SizedBox(width: 2),
                  Text('Cloud', style: TextStyle(fontSize: 10, color: farbe, fontWeight: FontWeight.w600)),
                ])),
              ),
            );
          }),
        InkWell(
          onTap: _upload,
          child: Padding(padding: const EdgeInsets.all(4), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.upload_file, size: 14, color: _voll ? Colors.grey.shade400 : Colors.indigo.shade600),
            const SizedBox(width: 2),
            Text('Datei', style: TextStyle(fontSize: 10, color: _voll ? Colors.grey.shade400 : Colors.indigo.shade600, fontWeight: FontWeight.w600)),
          ])),
        ),
      ]),
      if (_attachments.isNotEmpty) ...[
        const SizedBox(height: 4),
        ..._attachments.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            Icon(Icons.insert_drive_file, size: 12, color: Colors.green.shade600),
            const SizedBox(width: 4),
            Expanded(child: Text(a['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.green.shade800), overflow: TextOverflow.ellipsis)),
            InkWell(onTap: () async {
              try {
                final resp = await _apiDownload(a['id'] as int);
                if (resp.statusCode == 200 && mounted) {
                  final dir = await getTemporaryDirectory();
                  final file = File('${dir.path}/${a['datei_name']}');
                  await file.writeAsBytes(resp.bodyBytes);
                  if (context.mounted) await FileViewerDialog.show(context, file.path, a['datei_name']?.toString() ?? '');
                }
              } catch (_) {}
            }, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.visibility, size: 14, color: Colors.indigo.shade600))),
            InkWell(onTap: () async {
              try {
                final resp = await _apiDownload(a['id'] as int);
                if (resp.statusCode == 200 && mounted) {
                  final dir = await getTemporaryDirectory();
                  final file = File('${dir.path}/${a['datei_name']}');
                  await file.writeAsBytes(resp.bodyBytes);
                  await OpenFilex.open(file.path);
                }
              } catch (_) {}
            }, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.download, size: 14, color: Colors.green.shade700))),
            InkWell(onTap: () async {
              await _apiDelete(a['id'] as int);
              _load();
            }, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close, size: 14, color: Colors.red.shade400))),
          ]),
        )),
      ],
    ]);
  }
}
