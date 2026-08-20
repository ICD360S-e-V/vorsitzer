import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_inkasso.dart';

/// Die Karte der zuständigen Inkasso-Firma.
///
/// ⚠️ Warum ein eigener Test und nicht die Auflösungstests: dort antwortet
/// der gemeinsame Mock leer, also wird immer nur der LEERE Zustand
/// gemessen. Die Karte mit Daten — die längste und damit gefährlichste
/// Ansicht — bekäme dort nie jemand zu Gesicht. Genau diese Lücke hat
/// vorher schon dreimal Überläufe durchgelassen.
void main() {
  /// ⚠️ `http.Response(String, …)` kodiert ohne Angabe in LATIN-1. Der
  /// Gedankenstrich im Zahlungshinweis existiert dort nicht, und der Mock
  /// warf „Contains invalid characters" — was wie ein Fehler des Widgets
  /// aussah. Mit charset=utf-8 kodiert dieselbe Zeile korrekt.
  http.Response alsJson(Object body, int code) => http.Response(
        body as String,
        code,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  http.Client mandant({required bool mitFirma}) => MockClient((anfrage) async {
        final koerper = anfrage.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(anfrage.body) as Map<String, dynamic>);
        final aktion = koerper['action']?.toString() ?? '';

        if (aktion == 'get_inkasso') {
          if (!mitFirma) {
            return alsJson(jsonEncode({'success': true, 'exists': false}), 200);
          }
          return alsJson(
              jsonEncode({
                'success': true,
                'exists': true,
                // ⚠️ `exists` gehört auf die WURZEL, nicht in `data` — die
                // erste Fassung des Servers hat genau das verwechselt und
                // die Karte blieb leer, obwohl gespeichert war.
                'data': {
                  'id': 1,
                  'inkasso_id': 2,
                  'inkasso_lookup': _coeo,
                },
              }),
              200);
        }
        if (aktion == 'list_inkasso_datenbank') {
          return alsJson(
              jsonEncode({'success': true, 'items': [_coeo, _ohneBank]}), 200);
        }
        return alsJson(jsonEncode({'success': true, 'items': const []}), 200);
      });

  Future<List<String>> zeigen(WidgetTester tester,
      {required bool mitFirma, Size groesse = const Size(411, 915)}) async {
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = mandant(mitFirma: mitFirma);
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      DeviceKeyService().setTestCredentials(null);
    });

    final gesammelt = <String>[];
    final vorher = FlutterError.onError;
    FlutterError.onError = (details) {
      final t = details.exception.toString();
      if (t.contains('overflowed')) gesammelt.add(t.split('\n').first);
    };
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      home: Scaffold(
        body: VermieterInkassoTab(
          apiService: ApiService(),
          userId: 13,
          mietvertragId: 1,
          vertragBezeichnung: 'Musterstraße 1',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = vorher;
    tester.takeException();
    return gesammelt;
  }

  testWidgets('ohne Firma: die Lupe steht da, kein Überlauf', (tester) async {
    final ueberlauf = await zeigen(tester, mitFirma: false);
    expect(ueberlauf, isEmpty, reason: ueberlauf.join('\n'));
    expect(find.text('Inkasso suchen'), findsOneWidget);
    expect(find.text('Keine Inkasso-Firma zugeordnet'), findsOneWidget);
  });

  testWidgets('mit Firma: die Karte trägt IBAN und BIC, kein Überlauf', (tester) async {
    final ueberlauf = await zeigen(tester, mitFirma: true);
    expect(ueberlauf, isEmpty, reason: ueberlauf.join('\n'));
    // Zweimal: als Firmenname und als Kontoinhaber. Beides gewollt.
    expect(find.text('coeo Inkasso GmbH'), findsNWidgets(2));
    // ⚠️ In Vierergruppen — so steht sie auf dem Schreiben, mit dem
    // verglichen werden soll, und so bricht sie auf dem Telefon um.
    expect(find.text('DE23 3601 0043 0999 6844 38'), findsOneWidget);
    expect(find.text('PBNKDEFFXXX'), findsOneWidget);
    expect(find.text('Postbank Essen'), findsOneWidget);
    // Die RDG-Erlaubnis ist der Grund, warum das Büro überhaupt fordern
    // darf — sie muss auf der Karte stehen, nicht in einer Fußnote.
    expect(find.textContaining('RDG-Erlaubnis'), findsOneWidget);
  });

  testWidgets('der Zahlungshinweis steht sichtbar an der IBAN', (tester) async {
    await zeigen(tester, mitFirma: true);
    // ⚠️ Ohne diesen Satz sieht eine im Netz kursierende, ebenfalls
    // prüfsummen-gültige IBAN genauso richtig aus wie die echte.
    expect(find.textContaining('unterschiedliche Konten'), findsOneWidget);
    expect(find.textContaining('mit dem Original-Schreiben abgleichen'), findsOneWidget);
  });

  testWidgets('der Block „Unser Ansprechpartner dort" ist fort', (tester) async {
    await zeigen(tester, mitFirma: true);
    expect(find.textContaining('Ansprechpartner'), findsNothing);
    expect(find.text('Unser Zeichen'), findsNothing);
    expect(find.text('Durchwahl'), findsNothing);
    // Kein Speichern-Knopf mehr: Auswählen IST das Speichern.
    expect(find.text('Speichern'), findsNothing);
  });

  testWidgets('auch bei Schrift 2,0 läuft nichts über', (tester) async {
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = mandant(mitFirma: true);
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      DeviceKeyService().setTestCredentials(null);
    });
    final gesammelt = <String>[];
    final vorher = FlutterError.onError;
    FlutterError.onError = (d) {
      final t = d.exception.toString();
      if (t.contains('overflowed')) gesammelt.add(t.split('\n').first);
    };
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: Scaffold(
          body: VermieterInkassoTab(
            apiService: ApiService(),
            userId: 13,
            mietvertragId: 1,
            vertragBezeichnung: 'Musterstraße 1',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = vorher;
    tester.takeException();
    expect(gesammelt, isEmpty, reason: gesammelt.join('\n'));
  });
}

const _coeo = {
  'id': 2,
  'firmenname': 'coeo Inkasso GmbH',
  'strasse': 'Kieler Straße 16',
  'plz_ort': '41540 Dormagen',
  'telefon': '+49 2133 2463-0',
  'fax': '',
  'email': 'info@coeo-inkasso.de',
  'website': 'https://www.coeo-inkasso.de',
  'hrb': 'HRB 12345 (Amtsgericht Neuss)',
  'ust_id': 'DE123456789',
  'geschaeftsfuehrer': 'Muster, Beispiel',
  'rdg_lizenz': '2025 0000 0607 (Bundesamt für Justiz)',
  'bank_inhaber': 'coeo Inkasso GmbH',
  'iban': 'DE23360100430999684438',
  'bic': 'PBNKDEFFXXX',
  'bank_name': 'Postbank Essen',
  'zahlungshinweis': 'Verwendungszweck: Aktenzeichen aus dem Schreiben. ACHTUNG: coeo '
      'verwendet je Mandat unterschiedliche Konten — im Netz kursiert eine zweite '
      'gueltige IBAN (Postbank Dortmund). Nur die IBAN aus dem eigenen Schreiben verwenden.',
  'notizen': '',
};

const _ohneBank = {
  'id': 3,
  'firmenname': 'Bad Homburger Inkasso GmbH (BHI)',
  'strasse': 'Konrad-Adenauer-Allee 1-11',
  'plz_ort': '61118 Bad Vilbel',
  'telefon': '+49 6101 98911-0',
  'iban': null,
  'bic': null,
  'bank_name': null,
};
