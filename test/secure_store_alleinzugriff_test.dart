import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nur `SecureStore` darf das Linux-Schlüsselbund anfassen.
///
/// `flutter_secure_storage_linux` ruft libsecret **synchron** auf
/// (`secret_service_get_sync`, `secret_password_lookupv_sync`), und zwar im
/// Plattformkanal-Handler. Auf dem Linux-Embedder läuft dieser Handler auf dem
/// Thread, der auch die Dart-Ereignisschleife antreibt — ein langsamer Aufruf
/// friert also Zeitgeber, Darstellung und jedes `await` im Prozess ein.
///
/// Gemessen in einer xrdp-Sitzung, deren Sitzungsbus `org.freedesktop.secrets`
/// nur als *aktivierbar* kennt: **25,0 s pro Aufruf**, die D-Bus-Zeitgrenze für
/// Dienststart. Fünf Geheimnis-Lesevorgänge beim Start kosteten so rund 115 s
/// eingefrorene Oberfläche.
///
/// [SecureStore] fängt das ab, indem es **vor** dem Plugin in reinem Dart über
/// D-Bus fragt, ob der Dienst überhaupt einen Eigentümer hat. Diese Sperre
/// wirkt aber nur, solange niemand am Store vorbei greift — und genau das taten
/// sechs Dateien (Logger, Cloud-Wiederaufnahme, Login, Dashboard, RDP-Kiosk,
/// Jasmina). Der Fehler ist unsichtbar: der Code funktioniert überall dort, wo
/// ein Schlüsselbund läuft, und friert nur auf den Geräten ein, auf denen keins
/// erreichbar ist.
///
/// Deshalb dieser Test statt eines Kommentars: er ist die einzige Stelle, an
/// der ein neuer Direktzugriff auffällt, bevor er ausgeliefert wird.
void main() {
  test('nur secure_store.dart bindet flutter_secure_storage ein', () {
    const erlaubt = 'lib/services/secure_store.dart';
    const paket = 'package:flutter_secure_storage/flutter_secure_storage.dart';

    final verstoesse = <String>[];
    final dateien = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    // Der Fund muss von der Datei selbst kommen, nicht vom Suchpfad: liefe der
    // Test aus einem anderen Arbeitsverzeichnis, wäre die Liste leer und der
    // Test grün, ohne etwas geprüft zu haben.
    expect(dateien, isNotEmpty,
        reason: 'kein lib/**.dart gefunden — läuft der Test im Projektwurzel?');

    for (final datei in dateien) {
      final pfad = datei.path.replaceAll(r'\', '/');
      if (pfad == erlaubt) continue;
      if (datei.readAsStringSync().contains(paket)) verstoesse.add(pfad);
    }

    expect(verstoesse, isEmpty,
        reason: 'Diese Dateien greifen am SecureStore vorbei direkt auf das '
            'Schlüsselbund zu und umgehen damit die D-Bus-Vorprüfung. Jeder '
            'solche Aufruf friert die Oberfläche 25 s ein, wenn kein '
            'Secret-Service erreichbar ist (xrdp, Kiosk, minimale Desktops). '
            'Bitte SecureStore verwenden: ${verstoesse.join(", ")}');
  });

  test('secure_store.dart prüft den Dienst, bevor es das Plugin betritt', () {
    final quelle = File('lib/services/secure_store.dart').readAsStringSync();

    // Ohne die Vorprüfung ist die Sperre wieder nur ein `.timeout()`, das auf
    // Linux nie auslösen kann — der Zeitgeber bräuchte genau den Thread, den
    // der Aufruf blockiert.
    expect(quelle, contains('org.freedesktop.secrets'),
        reason: 'die D-Bus-Vorprüfung fehlt');
    expect(quelle, contains('nameHasOwner'),
        reason: 'ohne NameHasOwner wird ein nur aktivierbarer Dienst nicht '
            'von einem laufenden unterschieden — genau das kostet die 25 s');

    // Eine einzige Sonde pro Prozess. Vorher liefen die Startaufrufe gleich-
    // zeitig los, kamen alle an `_linuxKeyringDown == false` vorbei und
    // reihten sich dann nacheinander in denselben blockierenden Aufruf ein.
    expect(quelle, contains('_keyringProbe ??='),
        reason: 'die Sonde muss prozessweit geteilt werden, sonst blockieren '
            'gleichzeitige Leser weiterhin nacheinander');
  });
}
