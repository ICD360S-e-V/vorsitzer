import 'package:flutter/material.dart';
import '../services/theme_service.dart';

/// Knopf in der Kopfleiste: schaltet System → Hell → Dunkel → System weiter.
///
/// Das Sinnbild zeigt den *eingestellten* Modus, nicht die gerade sichtbare
/// Helligkeit — bei „System" also das Automatik-Zeichen. Der Tooltip nennt
/// beides, weil man dem Sinnbild allein nicht ansieht, wohin der nächste
/// Druck führt.
class ThemeUmschalterKnopf extends StatelessWidget {
  const ThemeUmschalterKnopf({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.modus,
      builder: (context, modus, _) {
        final helligkeit = Theme.of(context).brightness;
        final sichtbar = helligkeit == Brightness.dark ? 'dunkel' : 'hell';
        return IconButton(
          icon: Icon(ThemeService.symbol(modus)),
          tooltip: 'Erscheinungsbild: ${ThemeService.bezeichnung(modus)}'
              '${modus == ThemeMode.system ? ' (zurzeit $sichtbar)' : ''}'
              ' — tippen zum Wechseln',
          onPressed: () => ThemeService.instance.weiterschalten(helligkeit),
        );
      },
    );
  }
}

/// Zeile für Einstellungen und Menüs: die drei Modi als Segmentwahl.
///
/// ⚠️ Hier bewusst KEIN Weiterschalten, sondern die drei Möglichkeiten
/// nebeneinander. Der Knopf oben ist für den schnellen Wechsel; wer die
/// Einstellungen öffnet, will sehen, was es überhaupt gibt — und dass
/// „System" existiert, verrät ein Rundum-Knopf nie.
class ThemeUmschalterZeile extends StatelessWidget {
  const ThemeUmschalterZeile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.modus,
      builder: (context, modus, _) {
        return SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Hell'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Dunkel'),
            ),
          ],
          selected: {modus},
          showSelectedIcon: false,
          onSelectionChanged: (auswahl) =>
              ThemeService.instance.setzen(auswahl.first),
        );
      },
    );
  }
}
