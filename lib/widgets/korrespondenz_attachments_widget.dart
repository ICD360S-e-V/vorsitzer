import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'cloud_file_picker.dart';
import 'file_viewer_dialog.dart';

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
  /// Optional: erlaubte Dateiendungen beim Upload (Default: pdf/jpg/jpeg/png).
  final List<String>? allowedExtensions;
  /// Optional: max. Anzahl Dateien pro Upload-Vorgang (Default: unbegrenzt).
  final int? maxFiles;
  /// Optional: Mitglieds-ID. Ist sie gesetzt, erscheint neben "Datei" auch
  /// "Cloud" — dann kann direkt aus der verschlüsselten Mitglieder-Cloud
  /// übernommen werden (server-zu-server, ohne Umweg über den Admin-PC).
  /// Nur für den Standard-Speicherpfad; augenarzt/hno/krankenhaus haben eigene
  /// Endpoints ohne attach_from_cloud.
  final int? memberId;

  const KorrAttachmentsWidget({
    super.key,
    required this.apiService,
    required this.modul,
    required this.korrespondenzId,
    this.augenarzt = false,
    this.hno = false,
    this.krankenhaus = false,
    this.allowedExtensions,
    this.maxFiles,
    this.memberId,
  });

  @override
  State<KorrAttachmentsWidget> createState() => _KorrAttachmentsWidgetState();
}

class _KorrAttachmentsWidgetState extends State<KorrAttachmentsWidget> {
  List<Map<String, dynamic>> _attachments = [];
  bool _loaded = false;

  // Routet Attachment-Aktionen: für Augenarzt auf augenarzt_attachment.php,
  // für HNO auf hno_attachment.php, sonst generisch.
  Future<Map<String, dynamic>> _apiList() => widget.krankenhaus
      ? widget.apiService.krankenhausListKorrAttachments(widget.modul, widget.korrespondenzId)
      : widget.hno
      ? widget.apiService.hnoListKorrAttachments(widget.modul, widget.korrespondenzId)
      : widget.augenarzt
          ? widget.apiService.augenarztListKorrAttachments(widget.modul, widget.korrespondenzId)
          : widget.apiService.listKorrAttachments(widget.modul, widget.korrespondenzId);
  Future<Map<String, dynamic>> _apiUpload(String filePath, String fileName) => widget.krankenhaus
      ? widget.apiService.krankenhausUploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName)
      : widget.hno
      ? widget.apiService.hnoUploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName)
      : widget.augenarzt
          ? widget.apiService.augenarztUploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName)
          : widget.apiService.uploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: filePath, fileName: fileName);
  Future<Map<String, dynamic>> _apiDelete(int id) => widget.krankenhaus
      ? widget.apiService.krankenhausDeleteKorrAttachment(id)
      : widget.hno
      ? widget.apiService.hnoDeleteKorrAttachment(id)
      : widget.augenarzt
          ? widget.apiService.augenarztDeleteKorrAttachment(id) : widget.apiService.deleteKorrAttachment(id);
  Future _apiDownload(int id) => widget.krankenhaus
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

  Future<void> _upload() async {
    final exts = widget.allowedExtensions ?? const ['pdf', 'jpg', 'jpeg', 'png'];
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: exts, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    var files = result.files.where((f) => f.path != null).toList();
    if (widget.maxFiles != null && files.length > widget.maxFiles!) {
      final max = widget.maxFiles!;
      files = files.take(max).toList();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Maximal $max Dateien gleichzeitig — nur die ersten $max werden hochgeladen.')));
    }
    for (final file in files) {
      await _apiUpload(file.path!, file.name);
    }
    _load();
  }

  /// Nur beim Standard-Speicherpfad und wenn die Mitglieds-ID bekannt ist.
  bool get _cloudAvailable =>
      widget.memberId != null && !widget.augenarzt && !widget.hno && !widget.krankenhaus;

  Future<void> _attachFromCloud() async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await pickAndAttachFromCloud(
      context,
      apiService: widget.apiService,
      memberId: widget.memberId!,
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
        Text('Anhänge${_loaded ? ' (${_attachments.length})' : ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (_cloudAvailable)
          InkWell(
            onTap: _attachFromCloud,
            child: Padding(padding: const EdgeInsets.all(4), child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_download, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 2),
              Text('Cloud', style: TextStyle(fontSize: 10, color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
            ])),
          ),
        InkWell(
          onTap: _upload,
          child: Padding(padding: const EdgeInsets.all(4), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.upload_file, size: 14, color: Colors.indigo.shade600),
            const SizedBox(width: 2),
            Text('Datei', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600, fontWeight: FontWeight.w600)),
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
