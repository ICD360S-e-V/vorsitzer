/// Wer die JavaScript-Brücken der WebView benutzen darf.
///
/// `WebViewScreen` meldet zwei Kanäle an: `FlutterFilePicker` (öffnet den
/// Dateiauswähler des Geräts) und, im RDP-Bildschirm, `RdpBridge`. Beide waren
/// bisher ungeprüft — wer sie rief, bekam sie.
///
/// ⚠️ **Android reicht solche Kanäle an JEDEN Rahmen weiter, auch an fremde
/// iframes, und sagt uns nicht, wer gerufen hat.** Das steht so im
/// Sicherheitsleitfaden von Android:
///
///   „injects a supplied Java object into every frame of the WebView,
///    including iframes … there is no way to tell the calling frame's origin
///    from the app side"
///
/// Die dort empfohlene Abhilfe — `WebViewCompat.addWebMessageListener` mit
/// erlaubten Herkünften — reicht `webview_flutter_android` nicht durch.
/// Bleibt also das, was wir wissen können: die Adresse des HAUPTrahmens.
///
/// ⚠️ **Was das deckt und was nicht** (Entscheidung des Users, 22.08.2026):
///  * gedeckt — die Seite ist woanders hingewandert als dorthin, wofür der
///    Bildschirm geöffnet wurde: Weiterleitung, Werbe-Zwischenseite, ein Link,
///    der aus dem Portal hinausführt.
///  * NICHT gedeckt — ein fremdes iframe INNERHALB der erlaubten Seite. Dessen
///    Hauptrahmen ist ja der erwartete. Dagegen hülfe nur, die Brücke auf den
///    Bildschirmen gar nicht erst anzumelden, die sie nicht brauchen.
library;

import 'autofill_herkunft.dart';

/// Darf auf der gerade angezeigten Seite eine Brücke benutzt werden?
///
/// [geoeffnetMit] ist der URL, mit dem der Bildschirm gestartet wurde,
/// [aktuell] der zuletzt gemeldete URL des Hauptrahmens.
///
/// Ist die aktuelle Adresse (noch) unbekannt, gilt der Startwert — sonst
/// schlüge die erste Anfrage fehl, bevor `onPageStarted` überhaupt gelaufen ist.
bool brueckeErlaubt(String? geoeffnetMit, String? aktuell) {
  final erwartet = autofillHerkunft(geoeffnetMit);
  if (erwartet == null) return false;
  final jetzt = aktuell == null || aktuell.trim().isEmpty
      ? erwartet
      : autofillHerkunft(aktuell);
  return jetzt != null && jetzt == erwartet;
}

/// Was dem Benutzer gesagt wird, wenn eine Brücke abgewiesen wurde.
///
/// Nicht stillschweigend abweisen: ein Dateiauswähler, der sich nicht öffnet,
/// sieht sonst wie ein kaputter Knopf aus — und ein echter Angriff genauso.
String brueckeAbgelehntText(String? geoeffnetMit) {
  final erwartet = autofillHerkunft(geoeffnetMit) ?? 'die geöffnete Seite';
  return 'Dateiauswahl abgelehnt: Diese Seite gehört nicht zu $erwartet.';
}
