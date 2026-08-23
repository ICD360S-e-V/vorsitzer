@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:icd360sev_vorsitzer/utils/privater_temp.dart';

/// Beweist die Temp-Umleitung auf Linux: getTemporaryDirectory() liegt danach
/// in einem privaten 0700-Verzeichnis unter dem Cache (nicht /tmp), und der
/// Start-Sweep löscht Reste der letzten Sitzung.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getTemporaryDirectory zeigt nach der Umleitung NICHT mehr auf /tmp', () async {
    await privaterTempEinrichten();
    final tmp = await getTemporaryDirectory();
    expect(tmp.path, isNot(equals('/tmp')));
    expect(tmp.path, isNot(startsWith('/tmp/')));
    expect(tmp.path, endsWith('/tmp-privat'));
    expect(tmp.path, contains('/.cache/'));
    expect(tmp.existsSync(), isTrue);
  });

  test('das Elternverzeichnis hat Modus 0700', () async {
    await privaterTempEinrichten();
    final tmp = await getTemporaryDirectory();
    final stat = await Process.run('stat', ['-c', '%a', tmp.path]);
    expect((stat.stdout as String).trim(), '700');
  });

  test('der Start-Sweep löscht Reste der letzten Sitzung', () async {
    await privaterTempEinrichten();
    final tmp = await getTemporaryDirectory();
    // Ein "übrig gebliebenes Dokument" hinlegen …
    final rest = File('${tmp.path}/rest_von_gestern.pdf')
      ..writeAsStringSync('geheim');
    expect(rest.existsSync(), isTrue);
    // … erneuter Start räumt es weg.
    await privaterTempEinrichten();
    expect(rest.existsSync(), isFalse);
  });
}
