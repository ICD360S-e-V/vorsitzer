import 'package:flutter/material.dart';

/// Legt Tastaturkürzel über einen Bildschirm — aber nur, solange nicht gerade
/// jemand tippt.
///
/// ⚠️ Die Prüfung auf ein aktives Textfeld ist der ganze Punkt. `Shortcuts`
/// greift sonst auch im Suchfeld, und ein Postfach, in dem man nicht nach
/// „Rechnung" suchen kann, weil das „c" ein neues Fenster öffnet, ist kaputt.
///
/// ⚠️ Und die Hülle muss sich den Fokus ZURÜCKHOLEN. `CallbackShortcuts` hört
/// nur, solange der Fokus innerhalb liegt; wer ins Suchfeld tippt und es dann
/// verlässt, hinterlässt gar keinen Fokus — die Kürzel wären danach still tot,
/// bis man irgendwohin klickt. Ein Test hat genau das gefunden, das Lesen des
/// Codes nicht.
class MailTastaturhuelle extends StatefulWidget {
  final bool aktiv;
  final Map<ShortcutActivator, VoidCallback> aktionen;
  final Widget child;

  const MailTastaturhuelle({
    super.key,
    required this.aktiv,
    required this.aktionen,
    required this.child,
  });

  /// Steht die Schreibmarke gerade in einem Textfeld?
  static bool jemandTippt() {
    final f = FocusManager.instance.primaryFocus;
    if (f == null) return false;
    final ctx = f.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  State<MailTastaturhuelle> createState() => _MailTastaturhuelleState();
}

class _MailTastaturhuelleState extends State<MailTastaturhuelle> {
  final _knoten = FocusNode(debugLabel: 'MailTastatur');

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_fokusGewandert);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_fokusGewandert);
    _knoten.dispose();
    super.dispose();
  }

  /// Holt den Fokus zurück, wenn ihn sonst niemand hat.
  ///
  /// ⚠️ NUR dann. Läge hier ein unbedingtes `requestFocus()`, risse die Hülle
  /// den Fokus aus jedem Dialog, jedem Menü und jedem Textfeld heraus — und
  /// aus einer Bequemlichkeit würde ein Bildschirm, den man nicht mehr
  /// bedienen kann.
  void _fokusGewandert() {
    if (!mounted || !widget.aktiv) return;
    final f = FocusManager.instance.primaryFocus;
    // Kein Fokus, oder nur noch der Wurzel-Bereich: dann ist niemand zuständig.
    final niemand = f == null || f.context == null || f is FocusScopeNode;
    if (niemand && _knoten.canRequestFocus && !_knoten.hasFocus) {
      _knoten.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.aktiv) return widget.child;
    return CallbackShortcuts(
      bindings: {
        for (final e in widget.aktionen.entries)
          e.key: () {
            if (MailTastaturhuelle.jemandTippt()) return;
            e.value();
          },
      },
      child: Focus(
        focusNode: _knoten,
        autofocus: true,
        // Nicht in der Tab-Reihenfolge: die Hülle ist kein Bedienelement, sie
        // hört nur zu. Sonst hielte Tab jedes Mal hier an.
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}

/// Was die Tastatur kann — für den Hilfedialog.
const List<({String taste, String was})> kMailTasten = [
  (taste: 'J  /  Strg+↓', was: 'nächste Nachricht (mit Lesebereich)'),
  (taste: 'K  /  Strg+↑', was: 'vorige Nachricht (mit Lesebereich)'),
  (taste: 'C', was: 'neue E-Mail'),
  (taste: 'R', was: 'Ordner neu laden'),
  (taste: 'U', was: 'gelesen / ungelesen'),
  (taste: 'S', was: 'markieren (Stern)'),
  (taste: 'E', was: 'ins Archiv'),
  (taste: 'Entf', was: 'in den Papierkorb'),
  (taste: '/', was: 'in die Suche springen'),
  (taste: 'Esc', was: 'Suche oder Auswahl beenden'),
];
