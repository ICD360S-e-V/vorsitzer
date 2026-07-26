import 'package:flutter/material.dart';

import '../services/phone_call_service.dart';

/// Icons, hinter denen in diesem Projekt eine Rufnummer steht.
/// Nicht `const`: IconData überschreibt `==`, das lässt Dart in Konstanten-Sets
/// nicht zu.
final _phoneIcons = <IconData>{
  Icons.phone,
  Icons.phone_in_talk,
  Icons.phone_callback,
  Icons.phone_forwarded,
  Icons.phone_android,
  Icons.phone_iphone,
  Icons.local_phone,
  Icons.contact_phone,
  Icons.call,
  Icons.smartphone,
  Icons.support_agent,
};

bool isPhoneIcon(IconData icon) => _phoneIcons.contains(icon);

/// Drop-in-Ersatz für `Text(value, style: …)` in den vielen
/// `_infoRow(IconData icon, String value)`-Helfern der Behörden- und
/// Arzt-Widgets.
///
/// Steht das Icon für ein Telefon **und** enthält [value] eine wählbare
/// Nummer, wird daraus eine Wählfläche; sonst bleibt es exakt der Text, der
/// vorher da stand. Damit werden Zeilen wie `_detailRow(Icons.phone, 'Art',
/// 'telefonisch')` nicht versehentlich zu toten Links.
Widget phoneAwareText(
  IconData icon,
  String? value, {
  TextStyle? style,
  String? label,
  Color? color,
}) {
  if (!isPhoneIcon(icon) || !PhoneCallService.isDialable(value)) {
    return Text(value ?? '', style: style);
  }
  return PhoneText(value, style: style, label: label, color: color);
}

/// Macht ein beliebiges Widget zur Wählfläche.
///
/// Gedacht für die vielen `_infoRow`/`_kvRow`/`_detailRow`-Helfer in den
/// Behörden- und Arzt-Widgets: dort steht die Nummer schon in einer fertig
/// gestylten Zeile, die nur noch tippbar werden soll.
///
/// Enthält [number] keine wählbare Rufnummer (leeres Feld, `-`, „auf Anfrage"),
/// wird [child] unverändert und ohne Tap-Verhalten durchgereicht — die Zeile
/// sieht dann aus wie vorher.
class PhoneTapTarget extends StatelessWidget {
  const PhoneTapTarget({
    super.key,
    required this.number,
    required this.child,
    this.label,
    this.borderRadius = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 2),
  });

  /// Anzeigetext, aus dem die Nummer gelesen wird. Darf Beiwerk wie
  /// `Tel: 0711 / 123 456-78` enthalten.
  final String? number;

  /// Wird in der Bestätigung angezeigt („Ruft an: Jobcenter …"), damit bei
  /// einem versehentlichen Tipp sofort klar ist, wer angerufen wird.
  final String? label;

  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (!PhoneCallService.isDialable(number)) return child;

    return Tooltip(
      message: label == null ? 'Anrufen' : 'Anrufen: $label',
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => PhoneCallService.call(context, number!, label: label),
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Zeigt eine Rufnummer als tippbaren Text an.
///
/// Ersetzt die vielen `Text('Tel: ${x['telefon']}')`-Stellen. Die Nummer wird
/// unterstrichen und in [color] gesetzt, damit erkennbar ist, dass ein Tipp
/// tatsächlich anruft. Ist nichts Wählbares vorhanden, bleibt es einfacher
/// Text in der Originalfarbe.
class PhoneText extends StatelessWidget {
  const PhoneText(
    this.number, {
    super.key,
    this.prefix,
    this.label,
    this.style,
    this.icon,
    this.iconSize,
    this.color,
    this.showIcon = false,
    this.emptyPlaceholder = '-',
  });

  final String? number;

  /// Text vor der Nummer, etwa `Tel: ` oder `Service: `.
  final String? prefix;

  final String? label;
  final TextStyle? style;

  /// Nur wirksam mit [showIcon].
  final IconData? icon;
  final double? iconSize;

  /// Farbe der wählbaren Nummer. Ohne Angabe die Primärfarbe des Themes.
  final Color? color;

  final bool showIcon;

  /// Anzeige, wenn [number] leer ist.
  final String emptyPlaceholder;

  @override
  Widget build(BuildContext context) {
    final raw = number?.trim() ?? '';
    final dialable = PhoneCallService.isDialable(raw);
    final shown = raw.isEmpty ? emptyPlaceholder : raw;
    final linkColor = color ?? Theme.of(context).colorScheme.primary;

    final text = Text(
      prefix == null ? shown : '$prefix$shown',
      style: (style ?? const TextStyle()).copyWith(
        color: dialable ? linkColor : style?.color,
        decoration: dialable ? TextDecoration.underline : null,
        decorationColor: dialable ? linkColor : null,
      ),
    );

    if (!showIcon) {
      return PhoneTapTarget(number: raw, label: label, child: text);
    }

    return PhoneTapTarget(
      number: raw,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.phone,
            size: iconSize ?? (style?.fontSize == null ? 14 : style!.fontSize! + 2),
            color: dialable ? linkColor : style?.color,
          ),
          const SizedBox(width: 4),
          Flexible(child: text),
        ],
      ),
    );
  }
}

/// Runder Anruf-Button für Kartenköpfe und Listen-Trailing.
///
/// Wird ausgeblendet, wenn keine wählbare Nummer vorliegt, damit keine toten
/// Buttons in den Behörden-Karten stehen.
class PhoneCallButton extends StatelessWidget {
  const PhoneCallButton({
    super.key,
    required this.number,
    this.label,
    this.size = 20,
    this.color,
    this.tooltip,
  });

  final String? number;
  final String? label;
  final double size;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (!PhoneCallService.isDialable(number)) return const SizedBox.shrink();

    return IconButton(
      icon: Icon(Icons.phone, size: size),
      color: color ?? Theme.of(context).colorScheme.primary,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(6),
      tooltip: tooltip ?? (label == null ? 'Anrufen' : 'Anrufen: $label'),
      onPressed: () => PhoneCallService.call(context, number!, label: label),
    );
  }
}
