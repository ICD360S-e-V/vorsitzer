// Wächter gegen die zwei Fehlerklassen, die am 2026-07-30 quer durch die App
// gefunden wurden — beide fielen nur auf Android und Linux auf, also genau
// dort, wo beim Entwickeln auf dem Mac niemand hinschaut:
//
//   1. Drucken/Öffnen über `Process.run('open' | 'rundll32' | …)`. Das sind
//      macOS- bzw. Windows-Befehle; auf Android und Linux tat der Knopf
//      nichts — nicht einmal eine Fehlermeldung.
//   2. Speichern über einen selbst gebauten Pfad („Downloads") oder über
//      `saveFile` ohne Bytes. Auf Android wirft das entweder
//      `ArgumentError: Bytes are required…` oder es landet in einem
//      app-privaten Ordner, den der Nutzer nie wiederfindet — die Meldung
//      sagte trotzdem „Gespeichert".
//
// Der Test liest den Quelltext, weil keine Unit-Test-Umgebung die
// Plattformkanäle von file_picker/printing nachstellt. Grob, aber es fängt
// genau das wieder ein, was hier schon zweimal durchgerutscht ist.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dateien, in denen ein `Process.run('open', …)` legitim ist: dort geht es
/// nicht um Nutzerdateien, sondern um Systemaufgaben (Update-Installer,
/// Sicherheits-Abfragen, Browser-Start).
const _openProcessAllowlist = <String>{
  'lib/services/update_service.dart',
  'lib/services/desktop_security_service.dart',
  'lib/services/device_key_service.dart',
  'lib/services/notification_service.dart',
  'lib/services/external_browser_service.dart',
  'lib/screens/webview_screen.dart', // startet den Host-Browser, keine Datei
  'lib/screens/microsoft_nonprofit_screen.dart', // osascript, kein Dateiöffnen
};

Iterable<File> _dartSources() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

/// Kommentare zählen nicht — dort steht bewusst, was früher falsch war.
List<String> _codeLines(String source) => source
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .toList();

void main() {
  test('keine Nutzerdatei wird über Process.run geöffnet oder gedruckt', () {
    final offenders = <String>[];

    for (final file in _dartSources()) {
      final path = file.path;
      if (_openProcessAllowlist.contains(path)) continue;

      final lines = _codeLines(file.readAsStringSync());
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final hit = RegExp(r"""Process\.(run|start)\(\s*['"](open|xdg-open|rundll32|explorer)['"]""")
            .hasMatch(line);
        if (hit) offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Zum Öffnen gehört OpenFilex.open, zum Drucken Printing.layoutPdf '
          '— beides kennt alle fünf Plattformen:\n${offenders.join('\n')}',
    );
  });

  test('gespeichert wird nur über FilePickerHelper.saveBytes', () {
    final offenders = <String>[];

    for (final file in _dartSources()) {
      final path = file.path;
      // Der Helper selbst ist die eine Stelle, die saveFile aufrufen darf.
      if (path == 'lib/utils/file_picker_helper.dart') continue;

      final lines = _codeLines(file.readAsStringSync());
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('FilePicker.platform.saveFile') ||
            line.contains('FilePickerHelper.saveFile')) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'saveFile liefert auf Android/iOS keinen beschreibbaren Pfad — '
          'FilePickerHelper.saveBytes nehmen:\n${offenders.join('\n')}',
    );
  });

  test('„Downloads" wird nicht von Hand zusammengebaut', () {
    final offenders = <String>[];

    for (final file in _dartSources()) {
      final path = file.path;
      if (path == 'lib/utils/file_picker_helper.dart') continue; // macOS-Zweig

      final lines = _codeLines(file.readAsStringSync());
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // z.B. '${Platform.environment['HOME']}/Downloads'
        if (RegExp(r"""Platform\.environment\[['"](HOME|USERPROFILE)['"]\]""")
                .hasMatch(line) &&
            line.contains('Downloads')) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Der Ablageort gehört in FilePickerHelper.saveBytes, nicht in den '
          'Aufrufer:\n${offenders.join('\n')}',
    );
  });

  test('kein Herunterladen-Knopf reicht die Datei nur weiter', () {
    // Die dritte Variante desselben Fehlers: der Knopf heisst
    // „Herunterladen", schreibt die Datei aber ins Temp-Verzeichnis und
    // uebergibt sie an eine fremde App. Auf dem Desktop sieht das aus wie ein
    // Download, auf Android bleibt nichts uebrig, was der Nutzer wiederfindet.
    //
    // „Mit App oeffnen" ist derselbe Ablauf mit ehrlicher Beschriftung und
    // deshalb erlaubt — geprüft wird nur, was „Herunterladen" verspricht.
    final offenders = <String>[];

    for (final file in _dartSources()) {
      final lines = _codeLines(file.readAsStringSync());
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('OpenFilex.open')) continue;
        final from = i - 25 < 0 ? 0 : i - 25;
        final window = lines.sublist(from, i + 3).join('\n');
        final promisesDownload = window.contains("tooltip: 'Herunterladen'") ||
            window.contains("Text('Herunterladen')") ||
            window.contains("Text('Download')");
        // Ein „Speichern"-Knopf daneben heisst: der Download ist abgedeckt,
        // OpenFilex ist dort nur das zusaetzliche „Oeffnen".
        final hasSaveToo = window.contains('FilePickerHelper.saveBytes') ||
            window.contains("Text('Speichern')");
        if (promisesDownload && !hasSaveToo) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Herunterladen heisst behalten — FilePickerHelper.saveBytes:\n'
          '${offenders.join('\n')}',
    );
  });

  test('der Datei-Viewer druckt plattformneutral', () {
    final source = File('lib/widgets/file_viewer_dialog.dart').readAsStringSync();
    expect(source, contains('Printing.layoutPdf'),
        reason: 'Drucken muss über das printing-Paket laufen');
    expect(source, contains('FilePickerHelper.saveBytes'),
        reason: 'Herunterladen muss über den Helper laufen');
    expect(_codeLines(source).join('\n'), isNot(contains('Process.run')),
        reason: 'Der alte macOS/Windows-Pfad darf nicht zurückkommen');
  });
}
