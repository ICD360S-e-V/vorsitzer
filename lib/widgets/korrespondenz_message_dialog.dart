import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/mail_html_sanitizer.dart';
import '../utils/mail_html_text.dart';
import 'mail_html_view.dart';

/// Reads an archived mail back out of Finanzamt ▸ Korrespondenz.
///
/// Clicking a correspondence entry used to do nothing: the only clickable thing
/// was the .eml chip, and that went to the file viewer, which renders PDFs and
/// images and shows nothing at all for message/rfc822.
///
/// The server decrypts the stored message and parses the MIME (the same parser
/// the import cron uses, so both read a message the same way). Here we only
/// render it — through the app's existing sanitiser, so an archived mail is
/// held to exactly the same rules as a live one.
class KorrespondenzMessageDialog extends StatefulWidget {
  final ApiService apiService;

  /// Id of the stored file whose `rolle` is 'eml'.
  final int fileId;

  const KorrespondenzMessageDialog({
    super.key,
    required this.apiService,
    required this.fileId,
  });

  static Future<void> show(BuildContext context, ApiService api, int fileId) {
    return showDialog<void>(
      context: context,
      builder: (_) => KorrespondenzMessageDialog(apiService: api, fileId: fileId),
    );
  }

  @override
  State<KorrespondenzMessageDialog> createState() =>
      _KorrespondenzMessageDialogState();
}

class _KorrespondenzMessageDialogState extends State<KorrespondenzMessageDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _msg = {};

  /// Start on the formatted view when there is HTML — that is how the mail was
  /// meant to be read. The toggle is there for when it renders badly.
  bool _showFormatted = true;

  MailSanitizedHtml? _sanitized;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await widget.apiService.getKorrespondenzMessage(widget.fileId);
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Die Nachricht konnte nicht geladen werden.';
      });
      return;
    }
    final data = res['data'] ?? res;
    final msg = Map<String, dynamic>.from(data['message'] ?? {});
    final html = '${msg['body_html'] ?? ''}';
    setState(() {
      _msg = msg;
      _sanitized = html.trim().isEmpty ? null : sanitizeMailHtml(html);
      _loading = false;
    });
  }

  String get _plain {
    final t = '${_msg['body_text'] ?? ''}'.trim();
    if (t.isNotEmpty) return t;
    return mailHtmlToText('${_msg['body_html'] ?? ''}');
  }

  bool get _hasHtml => _sanitized != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subject = '${_msg['subject'] ?? ''}'.trim();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.mail_outline, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subject.isEmpty ? '(kein Betreff)' : subject,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_hasHtml)
                    IconButton(
                      tooltip: _showFormatted ? 'Als Text anzeigen' : 'Formatiert anzeigen',
                      icon: Icon(_showFormatted ? Icons.subject : Icons.article_outlined),
                      onPressed: () => setState(() => _showFormatted = !_showFormatted),
                    ),
                  IconButton(
                    tooltip: 'Schließen',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(child: _buildBody(cs)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: cs.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: true,
      children: [
        _kv('Von', '${_msg['from'] ?? ''}'),
        _kv('An', '${_msg['to'] ?? ''}'),
        if ('${_msg['cc'] ?? ''}'.trim().isNotEmpty) _kv('Cc', '${_msg['cc']}'),
        if ('${_msg['datum'] ?? ''}'.trim().isNotEmpty) _kv('Datum', '${_msg['datum']}'),
        const Divider(height: 24),
        if (_showFormatted && _hasHtml)
          MailHtmlView(sanitized: _sanitized!)
        else
          SelectableText(
            _plain.isEmpty ? '(kein Inhalt)' : _plain,
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        // Attachments are separate rows in the Korrespondenz entry with their
        // own download; listing them here would only duplicate that, so this is
        // just a hint that they exist.
        if ((_msg['attachments'] as List?)?.isNotEmpty ?? false) ...[
          const Divider(height: 24),
          Text(
            '${(_msg['attachments'] as List).length} Anhang/Anhänge — '
            'unterhalb des Eintrags abrufbar',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _kv(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(k,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
