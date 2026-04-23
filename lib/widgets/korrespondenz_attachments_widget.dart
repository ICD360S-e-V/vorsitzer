import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

class KorrAttachmentsWidget extends StatefulWidget {
  final ApiService apiService;
  final String modul;
  final int korrespondenzId;

  const KorrAttachmentsWidget({
    super.key,
    required this.apiService,
    required this.modul,
    required this.korrespondenzId,
  });

  @override
  State<KorrAttachmentsWidget> createState() => _KorrAttachmentsWidgetState();
}

class _KorrAttachmentsWidgetState extends State<KorrAttachmentsWidget> {
  List<Map<String, dynamic>> _attachments = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.listKorrAttachments(widget.modul, widget.korrespondenzId);
    if (!mounted) return;
    setState(() {
      if (r['success'] == true && r['data'] is List) _attachments = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  Future<void> _upload() async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files.where((f) => f.path != null)) {
      await widget.apiService.uploadKorrAttachment(modul: widget.modul, korrespondenzId: widget.korrespondenzId, filePath: file.path!, fileName: file.name);
    }
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
                final resp = await widget.apiService.downloadKorrAttachment(a['id'] as int);
                if (resp.statusCode == 200 && mounted) {
                  final dir = await getTemporaryDirectory();
                  final file = File('${dir.path}/${a['datei_name']}');
                  await file.writeAsBytes(resp.bodyBytes);
                  if (mounted) await FileViewerDialog.show(context, file.path, a['datei_name']?.toString() ?? '');
                }
              } catch (_) {}
            }, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.visibility, size: 14, color: Colors.indigo.shade600))),
            InkWell(onTap: () async {
              try {
                final resp = await widget.apiService.downloadKorrAttachment(a['id'] as int);
                if (resp.statusCode == 200 && mounted) {
                  final dir = await getTemporaryDirectory();
                  final file = File('${dir.path}/${a['datei_name']}');
                  await file.writeAsBytes(resp.bodyBytes);
                  await OpenFilex.open(file.path);
                }
              } catch (_) {}
            }, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.download, size: 14, color: Colors.green.shade700))),
            InkWell(onTap: () async {
              await widget.apiService.deleteKorrAttachment(a['id'] as int);
              _load();
            }, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close, size: 14, color: Colors.red.shade400))),
          ]),
        )),
      ],
    ]);
  }
}
