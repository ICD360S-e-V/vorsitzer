/// Dateinamen aus Serverantworten, bevor sie einen Pfad berühren.
///
/// Der Anlass: an rund 30 Stellen stand
/// `File(verzeichnis + '/' + d['datei_name'])` — der Name kam ungeprüft aus
/// Serverantwort. Ein `datei_name` wie `../../../.bashrc` schreibt damit
/// außerhalb des vorgesehenen Verzeichnisses. Auf dem Desktop läuft die App mit
/// den Rechten des Benutzers; eine überschriebene Startdatei der Shell ist
/// Codeausführung beim nächsten Terminal.
///
/// **Zwei Schichten, nach der Empfehlung von Android und OWASP.** Beide raten
/// ausdrücklich davon ab, sich allein auf das Säubern des Namens zu verlassen —
/// Filter lassen sich über Kodierung, Normalisierung und NUL-Bytes umgehen.
/// Verlässlich ist nur eine Aussage über das *Ergebnis*:
///
///  1. **Strukturelle Angriffe werden abgelehnt, nicht geglättet.** Ein
///     Dateiname hat nie einen legitimen Grund, einen Pfadtrenner, `..` oder
///     ein NUL-Byte zu enthalten. Wer das schickt, schickt keinen Namen.
///     [DateinameAbgelehnt] fliegt, der Download bricht ab. Stillschweigend
///     zurechtbiegen hieße: ein angegriffener Server sieht aus wie ein Server
///     mit schlecht benannten Dateien.
///  2. **Plattformeigenheiten werden still bereinigt** — verbotene Zeichen,
///     Windows-Gerätenamen, Punkt oder Leerzeichen am Ende. Das sind keine
///     Angriffe, nur Namen, die nicht überall funktionieren.
///
/// Darüber liegt in [sichereDatei] die eigentliche Zusicherung: der fertige
/// Pfad wird kanonisiert und muss unterhalb des Zielverzeichnisses liegen.
/// Greift diese Prüfung je, ist ein Fehler in Schicht 1 — deshalb wirft sie,
/// statt zu korrigieren.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;

/// Der Server hat etwas geschickt, das kein Dateiname ist.
///
/// Die [nachricht] ist für die Anzeige gedacht; der rohe Wert steht in [roh]
/// und gehört ins Log, nicht auf den Bildschirm.
class DateinameAbgelehnt implements Exception {
  const DateinameAbgelehnt(this.nachricht, this.roh);

  final String nachricht;
  final String roh;

  @override
  String toString() => nachricht;
}

/// Auf Windows reservierte Gerätenamen.
///
/// ⚠️ Sie gelten **auch mit Endung**: `NUL.txt` und `NUL.tar.gz` sind laut
/// Microsoft beide gleichbedeutend mit `NUL`. Ein `datei_name: "NUL.pdf"` aus
/// der Serverantwort schriebe also ins Nichts, und der Betrachter öffnete eine
/// leere Datei — das sähe nach einer kaputten Funktion aus, nicht nach einem
/// Fehler im Namen. `COM1.pdf` kann sogar blockieren.
///
/// ⚠️ Die hochgestellten Ziffern sind kein Tippfehler: Windows erkennt ¹ ² ³
/// (ISO/IEC 8859-1) als Ziffern und behandelt `COM¹` als Gerätenamen.
const Set<String> _windowsGeraete = {
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'com¹', 'com²', 'com³',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  'lpt¹', 'lpt²', 'lpt³',
};

/// Auf Windows in Dateinamen verbotene Zeichen, dazu die Steuerzeichen.
///
/// ⚠️ `/` steht bewusst nicht hier, sondern führt zur Ablehnung: auf Windows
/// wird **auch der Schrägstrich** als Pfadtrenner akzeptiert, nicht nur der
/// Backslash. Ein Filter, der auf Windows nur `\` behandelt, hat ein Loch.
final RegExp _verboteneZeichen = RegExp(r'[<>:"|?*\x00-\x1f]');

/// Maximale Länge des bereinigten Namens.
///
/// Weit unter MAX_PATH (260 auf Windows vor 1607), damit auch ein tiefes
/// Zielverzeichnis nicht über die Grenze schiebt.
const int _maxLaenge = 120;

/// Prüft den rohen Namen und gibt einen benutzbaren zurück.
///
/// Wirft [DateinameAbgelehnt], wenn der Name strukturell unzulässig ist.
/// Alles andere wird still bereinigt; ist danach nichts Brauchbares übrig,
/// kommt [fallback] zum Zug.
String gepruefterDateiname(Object? roh, {String fallback = 'datei'}) {
  final s = roh?.toString() ?? '';

  // ── Schicht 1: strukturelle Angriffe → ablehnen ────────────────────────────
  if (s.contains('\x00')) {
    throw DateinameAbgelehnt(
        'Der Server hat einen unzulässigen Dateinamen geschickt '
        '(NUL-Byte im Namen).',
        s);
  }
  if (s.contains('/') || s.contains('\\')) {
    // Ein Dateiname enthält nie einen Pfadtrenner — auf keiner Plattform.
    throw DateinameAbgelehnt(
        'Der Server hat einen unzulässigen Dateinamen geschickt '
        '(Pfadtrenner im Namen).',
        s);
  }
  if (s == '.' || s == '..') {
    throw DateinameAbgelehnt(
        'Der Server hat einen unzulässigen Dateinamen geschickt '
        '(Verzeichnisverweis statt Name).',
        s);
  }
  // "C:datei.pdf" ist auf Windows ein Pfad relativ zum aktuellen Verzeichnis
  // von Laufwerk C: — also ebenfalls kein Dateiname.
  if (RegExp(r'^[A-Za-z]:').hasMatch(s)) {
    throw DateinameAbgelehnt(
        'Der Server hat einen unzulässigen Dateinamen geschickt '
        '(Laufwerksangabe im Namen).',
        s);
  }

  // ── Schicht 2: Plattformeigenheiten → still bereinigen ─────────────────────
  var n = s.replaceAll(_verboteneZeichen, '_');

  // Punkte und Leerzeichen am Ende: „Do not end a file or directory name with
  // a space or a period" (Microsoft). Windows schneidet sie sonst still ab —
  // aus `bericht.pdf.` würde `bericht.pdf`, aus `bericht ` etwas anderes als
  // gedacht.
  n = n.replaceAll(RegExp(r'[. ]+$'), '');
  n = n.trim();

  // Gerätename? Der Vergleich läuft über den Stamm vor dem ersten Punkt,
  // weil die Endung nichts daran ändert (NUL.pdf ist NUL).
  final stamm = n.contains('.') ? n.substring(0, n.indexOf('.')) : n;
  if (_windowsGeraete.contains(stamm.toLowerCase())) {
    n = '_$n';
  }

  if (n.length > _maxLaenge) {
    // Die Endung entscheidet, womit der Betrachter die Datei öffnet — sie
    // bleibt erhalten, gekürzt wird davor.
    final punkt = n.lastIndexOf('.');
    if (punkt > 0 && n.length - punkt <= 12) {
      final endung = n.substring(punkt);
      n = n.substring(0, _maxLaenge - endung.length) + endung;
    } else {
      n = n.substring(0, _maxLaenge);
    }
  }

  n = n.trim();
  return n.isEmpty ? fallback : n;
}

/// Datei unterhalb von [basis], deren Name aus einer Serverantwort stammt.
///
/// Verbindet beide Schichten: [gepruefterDateiname] für den Namen, danach die
/// von Android und OWASP empfohlene Zusicherung über das Ergebnis — der fertige
/// Pfad wird kanonisiert und muss unterhalb von [basis] liegen.
///
/// ⚠️ Diese zweite Prüfung soll nie greifen. Wenn doch, ist Schicht 1 undicht,
/// und dann ist Abbrechen die einzig richtige Antwort — nicht Korrigieren.
///
/// ⚠️ `p.canonicalize` löst **keine** Symlinks auf, anders als `getCanonicalPath`
/// aus dem Android-Beispiel. Ein im Zielverzeichnis untergeschobener Symlink
/// würde hier also nicht auffallen. Das Zielverzeichnis ist auf Android
/// app-privat und auf dem Desktop das des Benutzers — wer dort schreiben kann,
/// braucht diesen Umweg nicht. Festgehalten, damit die Grenze bekannt ist.
File sichereDatei(Directory basis, Object? rohName, {String fallback = 'datei'}) {
  final name = gepruefterDateiname(rohName, fallback: fallback);
  final ziel = p.join(basis.path, name);

  final basisKanonisch = p.canonicalize(basis.path);
  final zielKanonisch = p.canonicalize(ziel);
  if (!p.isWithin(basisKanonisch, zielKanonisch)) {
    throw DateinameAbgelehnt(
        'Der Server hat einen unzulässigen Dateinamen geschickt '
        '(Ziel läge außerhalb des Ordners).',
        rohName?.toString() ?? '');
  }
  return File(ziel);
}

/// Meldet einen fehlgeschlagenen Download, statt ihn zu verschlucken.
///
/// Gedacht als Ersatz für `catch (_) {}` an den Stellen, die eine Datei
/// herunterladen und anzeigen. Ein abgelehnter Dateiname ist das einzige
/// Anzeichen dafür, dass der Server etwas schickt, was er nicht schicken
/// sollte — verschluckt sieht ein echter Angriff genauso aus wie ein Server,
/// der gerade nicht erreichbar ist.
void dateiFehlerMelden(BuildContext context, Object fehler) {
  final text = fehler is DateinameAbgelehnt
      ? fehler.nachricht
      : 'Datei konnte nicht geöffnet werden: $fehler';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: Colors.red.shade700,
    duration: const Duration(seconds: 6),
  ));
}
