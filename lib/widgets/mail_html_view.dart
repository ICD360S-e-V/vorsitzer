/// Rendert die sanitisierte Teilmenge einer HTML-E-Mail.
///
/// Bekommt ausschließlich die Ausgabe von [sanitizeMailHtml], in der keine
/// Absender-URL mehr steht — Ziele sind Tokens (`lnk:N`, `blk:N`, `cid:N`) und
/// werden hier gegen die Seitentabellen aufgelöst.
///
/// Ladeverhalten, bewusst:
/// * `cid:` — Teile DIESER Nachricht, kein Netz, laden automatisch.
/// * `blk:` — externe Bilder, standardmäßig blockiert. Ein Tracking-Pixel
///   funktioniert nur, wenn der Client eine Anfrage stellt; wer keine stellt,
///   ist per Konstruktion nicht messbar. Freigabe gilt nur für diese Nachricht.
/// * Der Renderer selbst kann nichts nachladen: [_NoNetworkFactory] gibt für
///   Netz-URLs immer `null` zurück, auch wenn je ein `src` durchrutschen würde.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:url_launcher/url_launcher.dart';

import '../services/mail_html_sanitizer.dart';

class MailHtmlView extends StatefulWidget {
  final MailSanitizedHtml sanitized;

  /// Lädt einen Nachrichtenteil über seine Content-ID (kein Netzzugriff).
  final Future<Uint8List?> Function(String contentId)? loadInlineImage;

  const MailHtmlView({
    super.key,
    required this.sanitized,
    this.loadInlineImage,
  });

  @override
  State<MailHtmlView> createState() => _MailHtmlViewState();
}

class _MailHtmlViewState extends State<MailHtmlView> {
  /// Freigabe externer Bilder — nur für diese Nachricht, nie persistent.
  bool _imagesAllowed = false;

  final Map<String, Future<Uint8List?>> _inlineCache = {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.sanitized;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.blockedImageCount > 0 && !_imagesAllowed) _blockedBanner(cs, s),
        if (s.hiddenCharCount > 0) _hiddenBanner(cs, s),
        if (s.truncated) _truncatedBanner(cs),
        HtmlWidget(
          s.html,
          // Große Behördenbriefe nicht auf dem UI-Thread parsen.
          buildAsync: s.html.length > 20000,
          factoryBuilder: _NoNetworkFactory.new,
          customWidgetBuilder: _buildCustom,
          onTapUrl: _onTapUrl,
          textStyle: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurface),
          onErrorBuilder: (_, __, ___) => Text(
            'Dieser Teil der Nachricht konnte nicht dargestellt werden.',
            style: TextStyle(fontSize: 13, color: cs.error),
          ),
        ),
      ],
    );
  }

  // ---------------- banners ----------------

  Widget _blockedBanner(ColorScheme cs, MailSanitizedHtml s) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.visibility_off_outlined, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.blockedImageCount == 1
                    ? '1 externes Bild blockiert'
                    : '${s.blockedImageCount} externe Bilder blockiert',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _imagesAllowed = true),
              child: const Text('Bilder laden'),
            ),
          ],
        ),
      );

  Widget _hiddenBanner(ColorScheme cs, MailSanitizedHtml s) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE0A800).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 17, color: Color(0xFFE0A800)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${s.hiddenCharCount} Zeichen hatte der Absender unsichtbar gemacht.',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

  Widget _truncatedBanner(ColorScheme cs) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.content_cut, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Die Nachricht war zu groß oder zu verschachtelt und wurde gekürzt. '
                'Die Textansicht zeigt sie vollständig.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );

  // ---------------- images ----------------

  Widget? _buildCustom(dom.Element element) {
    if (element.localName?.toLowerCase() != 'img') return null;
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';

    if (src.startsWith('cid:')) {
      final cid = widget.sanitized.cidImages[src];
      if (cid == null || widget.loadInlineImage == null) return _altBox(alt);
      final future = _inlineCache.putIfAbsent(cid, () => widget.loadInlineImage!(cid));
      return FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) return _altBox(alt);
          return Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _altBox(alt),
          );
        },
      );
    }

    if (src.startsWith('blk:')) {
      final url = widget.sanitized.blockedImages[src];
      if (url == null) return _altBox(alt);
      if (!_imagesAllowed) return _placeholder(alt);
      // Nur nach ausdrücklicher Freigabe. Anmerkung: Image.network folgt
      // Redirects — für eine bewusste Nutzeraktion akzeptiert, aber es ist der
      // einzige Punkt im Mailpfad, an dem überhaupt eine Anfrage rausgeht.
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _altBox(alt),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
      );
    }

    // Alles andere hat der Sanitizer schon entfernt; hier bleibt nur alt.
    return _altBox(alt);
  }

  Widget _altBox(String alt) {
    if (alt.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Text('[$alt]', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant));
  }

  Widget _placeholder(String alt) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            alt.isEmpty ? 'Externes Bild' : alt,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ---------------- links ----------------

  Future<bool> _onTapUrl(String token) async {
    final url = widget.sanitized.linkTargets[token];
    if (url == null) return false;
    final go = await _confirmLink(url);
    if (go != true) return true; // behandelt, aber nicht geöffnet
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Der Link konnte nicht geöffnet werden.')),
        );
      }
    }
    return true;
  }

  /// Zeigt das Ziel, bevor etwas geöffnet wird.
  ///
  /// Absichtlich wird die URL VOLLSTÄNDIG und unzerlegt angezeigt, statt einen
  /// "Host" hervorzuheben: Dart zerlegt URLs nach RFC 3986, Browser nach WHATWG
  /// URL, und `https://sparkasse.de\@evil.tld` ergibt dabei verschiedene Hosts.
  /// Ein Dialog, der den einen Host nennt und den anderen öffnet, wäre schlimmer
  /// als keiner.
  Future<bool?> _confirmLink(String url) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link öffnen?'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Das Ziel wird im Browser geöffnet:',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Prüfen Sie die Adresse, bevor Sie Daten eingeben. E-Mails, die '
              'nach Zugangsdaten fragen, sind fast immer gefälscht.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Öffnen')),
        ],
      ),
    );
  }
}

/// Verhindert, dass der Renderer selbst je eine Netzanfrage stellt.
///
/// Verteidigung in der Tiefe: Bilder werden ohnehin über
/// `customWidgetBuilder` gebaut, aber falls je ein `src` daran vorbeikäme,
/// bekommt fwfh hier keinen Provider und lädt nichts.
class _NoNetworkFactory extends WidgetFactory {
  @override
  ImageProvider? imageProviderFromNetwork(String url) => null;
}
