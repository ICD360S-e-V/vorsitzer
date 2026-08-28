import 'package:flutter/material.dart';

import '../utils/mail_virenscan.dart';

/// Grün nur dort, wo wirklich geprüft wurde. Der Ton ist derselbe wie bei der
/// Cloud-Sicherung eine Zeile darüber, damit „erledigt" überall gleich aussieht.
///
/// ⚠️ Zwei Töne, und das ist keine Kosmetik: gemessen gegen die
/// Material-3-Flächen ergibt `2E7D32` auf hell **5,00:1**, auf dunkel aber nur
/// **3,63:1**. Für ein SYMBOL reicht das (WCAG 1.4.11 verlangt 3:1), für den
/// 12-px-TEXT der Plakette nicht (1.4.3 verlangt 4,5:1). `81C784` bringt auf
/// dunkel **9,24:1** — und wäre auf hell mit 1,96:1 unlesbar. Wer einen Ton
/// ändert, rechnet beide Zahlen neu.
///
/// Aufgefallen ist das erst beim ANSEHEN der gerenderten Zeile; im Quelltext
/// sah die eine feste Farbe völlig unauffällig aus.
Color _gruen(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);

/// Das Zeichen neben EINEM Anhang.
///
/// ⚠️ Es steht bewusst immer mit Datum da. Ein nacktes grünes Häkchen würde
/// „diese Datei ist sicher" behaupten; wahr ist nur „am 28.08. war nichts
/// bekannt". Der Unterschied ist der ganze Punkt.
class MailVirenscanPlakette extends StatelessWidget {
  final MailScanBefund befund;

  /// Der Dateiname — nur für die Überschrift beim langen Antippen.
  final String? name;

  /// Erneut prüfen, mit den Signaturen von heute. Fehlt der Rückruf, wird der
  /// Knopf gar nicht erst angeboten.
  final Future<void> Function()? erneutPruefen;

  const MailVirenscanPlakette({
    super.key,
    required this.befund,
    this.name,
    this.erneutPruefen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Noch nie geprüft heißt: nichts zu sagen. Ein Fragezeichen an jeder Datei
    // wäre Lärm, der das eine rote Zeichen unsichtbar macht.
    if (befund.wert == MailScanWert.unbekannt) return const SizedBox.shrink();

    if (befund.wert == MailScanWert.laeuft) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.8)),
          const SizedBox(width: 5),
          Text('Wird auf Viren geprüft…',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      );
    }

    final (IconData zeichen, Color farbe, String text) = switch (befund.wert) {
      MailScanWert.sauber => (
          Icons.verified_user,
          _gruen(context),
          'Virengeprüft ${mailScanDatumKurz(befund.geprueftAm)}',
        ),
      MailScanWert.befallen => (
          Icons.gpp_bad,
          cs.error,
          'Schadsoftware: ${befund.signatur ?? 'Treffer'}',
        ),
      _ => (
          Icons.gpp_maybe,
          cs.onSurfaceVariant,
          'Nicht prüfbar',
        ),
    };

    return InkWell(
      onTap: () => _erklaeren(context),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(zeichen, size: 14, color: farbe),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: farbe,
                  fontWeight: befund.wert == MailScanWert.befallen
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _erklaeren(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name == null ? 'Virenprüfung' : 'Virenprüfung · $name',
            style: const TextStyle(fontSize: 17)),
        content: SingleChildScrollView(
          child: Text(mailScanErklaerung(befund),
              style: const TextStyle(fontSize: 14, height: 1.4)),
        ),
        actions: [
          if (erneutPruefen != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                erneutPruefen!();
              },
              child: const Text('Erneut prüfen'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen')),
        ],
      ),
    );
  }
}

/// Das kleine Zeichen in der NACHRICHTENLISTE, direkt neben der Büroklammer.
///
/// ⚠️ Zeigt ausschließlich Ergebnisse, die schon gespeichert sind. Die Liste
/// löst nie eine Prüfung aus — sonst würde jedes Aufziehen der Liste fünfzig
/// Nachrichten vom Mailserver ziehen.
class MailVirenscanListenZeichen extends StatelessWidget {
  final MailScanWert wert;

  const MailVirenscanListenZeichen({super.key, required this.wert});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (wert) {
      MailScanWert.sauber => Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Icon(Icons.verified_user, size: 13, color: _gruen(context)),
        ),
      MailScanWert.befallen => Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Icon(Icons.gpp_bad, size: 15, color: cs.error),
        ),
      MailScanWert.fehler => Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Icon(Icons.gpp_maybe, size: 13, color: cs.onSurfaceVariant),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
