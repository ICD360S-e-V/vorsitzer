import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/app_sperre_service.dart';
import 'package:icd360sev_vorsitzer/widgets/app_sperre_huelle.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Der Fehler, mit dem die erste Fassung im Betrieb ankam.
///
/// `AppSperreHuelle` sitzt im `builder:` der `MaterialApp` und wurde nur neu
/// gebaut, wenn der Sperrdienst etwas meldete. Beim Start ist niemand
/// angemeldet — sie stieg also sofort aus, stiess das Laden nie an, und der
/// Dienst hatte folglich nie etwas zu melden. Henne und Ei.
///
/// Dass danach die Anmeldung durchlief und der Navigator auf das Armaturenbrett
/// wechselte, half nicht: der Navigator verwaltet seine Routen selbst, `builder`
/// läuft dabei NICHT erneut. Im Betrieb hiess das: keine Sperre, und nach dem
/// Update fragte niemand nach einem Passwort.
///
/// ⚠️ Zum Aufbau der Proben: alles, was `SecureStore` anfasst, läuft in
/// `runAsync` und VOR dem Rendern. `SecureStore` reiht seine Zugriffe hinter
/// einer prozessweiten Sperre auf und benutzt `timeout()`; unter der Testuhr
/// löst ein solches Future nie auf, und der erste haengende Zugriff legt alle
/// folgenden lahm — auch die im tearDown.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('huelle_test');
    for (final kanal in [
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/path_provider_linux',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              MethodChannel(kanal), (call) async => tempDir.path);
    }
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget bauen() => MaterialApp(
        builder: (context, child) =>
            AppSperreHuelle(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('Armaturenbrett')),
      );

  testWidgets('Anmeldung NACH dem ersten Bau wird bemerkt', (t) async {
    await t.runAsync(() async {
      await ApiService().clearTokens();
      await AppSperreService().zuruecksetzen();
      await AppSperreService().laden(); // Zustand steht, kein Zugriff beim Bauen
    });

    await t.pumpWidget(bauen());
    await t.pump();
    expect(find.text('Armaturenbrett'), findsOneWidget,
        reason: 'abgemeldet haelt sich die Huelle heraus');

    // Genau der Ablauf im Betrieb: die Anmeldung laeuft durch, nachdem die
    // Huelle schon einmal gebaut wurde.
    await t.runAsync(
        () => ApiService().saveTokens('test-token', 'test-refresh'));
    await t.pump(const Duration(seconds: 2));

    expect(find.text('App-Passwort festlegen'), findsOneWidget,
        reason: 'nach dem Update muss nach einem neuen Passwort gefragt werden');
    // ⚠️ Der Inhalt bleibt im Baum — er MUSS bleiben, sonst faellt der
    // Navigator und mit ihm das `Overlay`, das das Passwortfeld braucht. Er
    // ist verdeckt und unbedienbar, nicht entfernt. Geprueft wird deshalb die
    // Sperrschicht, nicht seine Abwesenheit.
    // ⚠️ DIE Probe zum schwarzen Bildschirm. In 6.137.3 gab die Huelle die
    // Flaeche ANSTELLE des Kindes zurueck; damit fiel der Navigator und mit
    // ihm das Overlay, das jedes EditableText braucht. Das Passwortfeld hat
    // `autofocus`, also flog beim Erscheinen sofort „No Overlay widget found"
    // — im Release-Build heisst das: schwarze Flaeche, keine Meldung.
    //
    // Auf dem Pixel selbst fiel es nicht auf, weil die Huelle dort in der
    // fruehen Rueckgabe feststeckte und die Flaeche nie zeichnete. Am externen
    // Monitor wird neu gebaut, `isLoggedIn` steht da schon — und es flog.
    expect(t.takeException(), isNull,
        reason: 'kein Aufbaufehler — sonst ist die Flaeche im Release schwarz');
    expect(find.byType(AbsorbPointer), findsWidgets,
        reason: 'der Hintergrund darf nicht mehr bedienbar sein');
    expect(find.byType(ExcludeSemantics), findsWidgets,
        reason: 'und Vorlesehilfen sollen ihn nicht mehr anbieten');

    await t.pumpWidget(const SizedBox()); // Zeitgeber abraeumen
    await t.runAsync(() => ApiService().clearTokens());
  });

  testWidgets('mit gesetztem Passwort erscheint die Sperre — und sie fragt '
      'nach dem PASSWORT, nicht nach dem Code', (t) async {
    await t.runAsync(() async {
      await ApiService().clearTokens();
      await AppSperreService().zuruecksetzen();
      await AppSperreService().passwortSetzen('probe-passwort-1');
      await AppSperreService().laden(); // sperrt, weil ein Passwort da ist
      await ApiService().saveTokens('test-token', 'test-refresh');
    });

    await t.pumpWidget(bauen());
    await t.pump(const Duration(seconds: 2));

    expect(t.takeException(), isNull,
        reason: 'auch die Sperrflaeche darf nicht beim Aufbau werfen');
    expect(find.text('Gesperrt'), findsOneWidget);
    expect(find.byType(AbsorbPointer), findsWidgets);
    // Der Navigator MUSS stehenbleiben — er traegt das Overlay.
    expect(find.byType(Navigator), findsWidgets,
        reason: 'ohne Navigator kein Overlay, ohne Overlay kein Textfeld');
    // ⚠️ Der normale Weg ist das PASSWORT. Der Aktivierungscode darf erst
    // erscheinen, wenn man „Passwort vergessen?" ausdruecklich antippt.
    expect(find.text('App-Passwort'), findsOneWidget);
    expect(find.textContaining('Aktivierungscode'), findsNothing);

    await t.tap(find.text('Passwort vergessen?'));
    await t.pump();
    expect(find.textContaining('Aktivierungscode'), findsWidgets,
        reason: 'erst jetzt, und nur auf ausdrueckliches Antippen');

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      await ApiService().clearTokens();
      await AppSperreService().zuruecksetzen();
    });
  });
}
