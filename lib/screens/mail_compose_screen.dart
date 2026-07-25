import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/mail_models.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';

/// Verfassen-Ansicht für eine neue, beantwortete oder weitergeleitete E-Mail.
class MailComposeScreen extends StatefulWidget {
  final String selfEmail;
  final String? to;
  final String? cc;
  final String? subject;

  /// Vorbelegter Nachrichtentext (Zitat bei Antwort/Weiterleitung).
  final String? quotedBody;

  /// Message-ID der Nachricht, auf die geantwortet wird (Threading).
  final String? inReplyTo;

  /// Bereits übernommene Anhänge (Weiterleitung).
  final List<MailOutgoingAttachment> initialAttachments;

  const MailComposeScreen({
    super.key,
    required this.selfEmail,
    this.to,
    this.cc,
    this.subject,
    this.quotedBody,
    this.inReplyTo,
    this.initialAttachments = const [],
  });

  @override
  State<MailComposeScreen> createState() => _MailComposeScreenState();
}

class _MailComposeScreenState extends State<MailComposeScreen> {
  final _api = ApiService();
  final _toCtrl = TextEditingController();
  final _ccCtrl = TextEditingController();
  final _bccCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  final List<MailOutgoingAttachment> _attachments = [];
  bool _showCcBcc = false;
  bool _requestReceipt = false;
  bool _sending = false;
  bool _picking = false;
  String _signature = '';

  static const int _maxTotal = ApiService.mailMaxAttachmentBytes;

  /// PHP nimmt pro Request nur 20 Dateien an (max_file_uploads) und verwirft
  /// den Rest still — deshalb hier hart begrenzen.
  static const int _maxFiles = 20;

  @override
  void initState() {
    super.initState();
    _toCtrl.text = widget.to ?? '';
    _ccCtrl.text = widget.cc ?? '';
    _subjectCtrl.text = widget.subject ?? '';
    _showCcBcc = (widget.cc ?? '').isNotEmpty;
    _attachments.addAll(widget.initialAttachments);
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    try {
      final res = await _api.getMailSignature();
      if (res['success'] != true || !mounted) return;
      _signature = '${res['signature'] ?? ''}';
      final receiptDefault = res['request_receipt_default'] == true;
      setState(() {
        _requestReceipt = receiptDefault;
        // Signature and quote are only inserted while the body is untouched, so
        // a fast typist never loses what they wrote.
        if (_bodyCtrl.text.isEmpty) _bodyCtrl.text = _initialBody();
      });
    } catch (_) {
      if (mounted && _bodyCtrl.text.isEmpty) {
        setState(() => _bodyCtrl.text = _initialBody());
      }
    }
  }

  String _initialBody() {
    final sb = StringBuffer('\n');
    if (_signature.isNotEmpty) sb.write('\n$_signature');
    if ((widget.quotedBody ?? '').isNotEmpty) sb.write('\n${widget.quotedBody}');
    return sb.toString();
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _ccCtrl.dispose();
    _bccCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  int get _totalBytes => _attachments.fold(0, (s, a) => s + a.size);

  bool _validEmail(String s) =>
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(s.trim());

  /// Prüft eine Komma-Liste von Adressen; gibt die erste ungültige zurück.
  String? _firstInvalid(String raw) {
    for (final a in raw.split(',')) {
      if (a.trim().isEmpty) continue;
      if (!_validEmail(a)) return a.trim();
    }
    return null;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickAttachments() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePickerHelper.pickFiles(
        dialogTitle: 'Anhänge auswählen',
        allowMultiple: true,
        withData: true,
      );
      if (result == null || !mounted) return;

      var used = _totalBytes;
      var count = _attachments.length;
      final added = <MailOutgoingAttachment>[];
      final tooBig = <String>[];
      final tooMany = <String>[];
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) {
          tooBig.add(f.name);
          continue;
        }
        if (count >= _maxFiles) {
          tooMany.add(f.name);
          continue;
        }
        if (used + bytes.length > _maxTotal) {
          tooBig.add(f.name);
          continue;
        }
        used += bytes.length;
        count++;
        added.add(MailOutgoingAttachment(
          filename: f.name,
          bytes: Uint8List.fromList(bytes),
        ));
      }
      setState(() => _attachments.addAll(added));
      if (tooBig.isNotEmpty) {
        _toast('Kein Platz mehr für: ${tooBig.join(', ')} — '
            'insgesamt sind 25 MB möglich.');
      }
      if (tooMany.isNotEmpty) {
        _toast('Mehr als $_maxFiles Dateien pro E-Mail sind nicht möglich. '
            'Nicht übernommen: ${tooMany.join(', ')}');
      }
    } catch (e) {
      _toast('Anhang konnte nicht gelesen werden.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    final to = _toCtrl.text.trim();
    if (to.isEmpty) {
      _toast('Bitte mindestens einen Empfänger angeben.');
      return;
    }
    for (final field in [to, _ccCtrl.text, _bccCtrl.text]) {
      final bad = _firstInvalid(field);
      if (bad != null) {
        _toast('Diese Adresse stimmt nicht: $bad');
        return;
      }
    }
    if (_subjectCtrl.text.trim().isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ohne Betreff senden?'),
          content: const Text('Die E-Mail hat keinen Betreff.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Zurück')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Trotzdem senden')),
          ],
        ),
      );
      if (go != true) return;
    }

    setState(() => _sending = true);
    try {
      final res = await _api.sendMail(
        to: to,
        cc: _ccCtrl.text.trim(),
        bcc: _bccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text,
        requestReceipt: _requestReceipt,
        inReplyTo: widget.inReplyTo ?? '',
        attachments: _attachments,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => _sending = false);
        _toast(res['message']?.toString() ?? 'Senden fehlgeschlagen.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('Keine Verbindung zum Server.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neue E-Mail'),
        actions: [
          if (_sending)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: 'Anhang hinzufügen',
              onPressed: _picking ? null : _pickAttachments,
            ),
            IconButton(
              icon: const Icon(Icons.send),
              tooltip: 'Senden',
              onPressed: _send,
            ),
          ],
        ],
      ),
      body: AbsorbPointer(
        absorbing: _sending,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text('Von: ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                Expanded(
                  child: Text(widget.selfEmail,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                if (!_showCcBcc)
                  TextButton(
                    onPressed: () => setState(() => _showCcBcc = true),
                    child: const Text('Cc/Bcc'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _toCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'An',
                helperText: 'Mehrere Adressen mit Komma trennen',
                border: OutlineInputBorder(),
              ),
            ),
            if (_showCcBcc) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _ccCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Cc', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bccCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Bcc', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(
                  labelText: 'Betreff', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              minLines: 10,
              maxLines: 24,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Nachricht',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _attachmentSection(cs),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _requestReceipt,
              onChanged: (v) => setState(() => _requestReceipt = v),
              title: const Text('Lesebestätigung anfordern',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Der Empfänger wird gefragt, ob er das Öffnen bestätigt. '
                'Der Status steht danach im Ausgang.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (_sending) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _attachments.isEmpty
                      ? 'Wird gesendet …'
                      : 'Wird gesendet — ${_fmtSize(_totalBytes)} Anhänge werden übertragen …',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _attachmentSection(ColorScheme cs) {
    final total = _totalBytes;
    final ratio = (total / _maxTotal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Anhänge',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Text(
                _attachments.isEmpty
                    ? 'max. 25 MB'
                    : '${_attachments.length}/$_maxFiles · ${_fmtSize(total)} von 25 MB',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          if (_attachments.isEmpty) ...[
            const SizedBox(height: 8),
            Text('Noch keine Dateien ausgewählt.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _picking ? null : _pickAttachments,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Dateien auswählen'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                color: ratio > 0.9 ? const Color(0xFFE08A00) : cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _attachments.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_iconFor(_attachments[i].filename), size: 20),
                title: Text(_attachments[i].filename,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(_fmtSize(_attachments[i].size),
                    style: const TextStyle(fontSize: 11.5)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Anhang entfernen',
                  onPressed: () => setState(() => _attachments.removeAt(i)),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: (_picking || _attachments.length >= _maxFiles)
                    ? null
                    : _pickAttachments,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Weitere Datei'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _iconFor(String filename) {
  final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'heic':
      return Icons.image_outlined;
    case 'doc':
    case 'docx':
    case 'odt':
    case 'rtf':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
    case 'ods':
    case 'csv':
      return Icons.table_chart_outlined;
    case 'zip':
    case '7z':
    case 'rar':
    case 'gz':
      return Icons.folder_zip_outlined;
    case 'mp3':
    case 'wav':
    case 'ogg':
    case 'm4a':
      return Icons.audiotrack_outlined;
    case 'mp4':
    case 'mov':
    case 'mkv':
    case 'webm':
      return Icons.movie_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
