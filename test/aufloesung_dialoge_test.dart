// Öffnet die Dialoge und misst sie — bisher hat sie kein Test je gezeichnet.
//
// ⚠️ Das größte verbliebene Loch: 900 `AlertDialog` und 1103 `showDialog`
// stehen **inline** in `showDialog(builder: …)`. Sie lassen sich nicht
// einzeln instanziieren, also kam keiner der bisherigen Harnesse an sie
// heran. Dabei ist ein Dialog der engste Ort der ganzen App: der
// Standardrand nimmt 2 × 40 dp, auf einem 448-dp-Telefon bleiben 368.
//
// Der Weg dorthin: jeden Knopf antippen, der einen Dialog öffnen könnte,
// und messen, was erscheint. Danach den Dialog wieder schließen und zum
// nächsten. Das ist grob, findet aber genau das, was sonst niemand sieht.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icd360sev_vorsitzer/models/user.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/services/ticket_service.dart';
import 'package:icd360sev_vorsitzer/services/termin_service.dart';
import 'package:icd360sev_vorsitzer/screens/arbeitsagentur_screen.dart';
import 'package:icd360sev_vorsitzer/screens/archiv_screen.dart';
import 'package:icd360sev_vorsitzer/screens/behoerden_screen.dart';
import 'package:icd360sev_vorsitzer/screens/deutschepost_screen.dart';
import 'package:icd360sev_vorsitzer/screens/einstellungen_screen.dart';
import 'package:icd360sev_vorsitzer/screens/gericht_screen.dart';
import 'package:icd360sev_vorsitzer/screens/github_screen.dart';
import 'package:icd360sev_vorsitzer/screens/google_nonprofit_screen.dart';
import 'package:icd360sev_vorsitzer/screens/handelsregister_screen.dart';
import 'package:icd360sev_vorsitzer/screens/inwx_screen.dart';
import 'package:icd360sev_vorsitzer/screens/jasmina_screen.dart';
import 'package:icd360sev_vorsitzer/screens/microsoft_nonprofit_screen.dart';
import 'package:icd360sev_vorsitzer/screens/notar_screen.dart';
import 'package:icd360sev_vorsitzer/screens/paypal_screen.dart';
import 'package:icd360sev_vorsitzer/screens/postcard.dart';
import 'package:icd360sev_vorsitzer/screens/sendungsverfolgung.dart';
import 'package:icd360sev_vorsitzer/screens/servdiscount_screen.dart';
import 'package:icd360sev_vorsitzer/screens/simplefax_screen.dart';
import 'package:icd360sev_vorsitzer/screens/statistik_screen.dart';
import 'package:icd360sev_vorsitzer/screens/stifter_helfen_screen.dart';
import 'package:icd360sev_vorsitzer/screens/vereinregister_screen.dart';
import 'package:icd360sev_vorsitzer/screens/vereinverwaltung_behorde_finanzamt.dart';
import 'package:icd360sev_vorsitzer/screens/vesperkirche_screen.dart';
import 'package:icd360sev_vorsitzer/screens/vr_bank_screen.dart';
import 'package:icd360sev_vorsitzer/widgets/arbeitgeber_behorde_content.dart';
import 'package:icd360sev_vorsitzer/widgets/arbeitgeber_bewerbungsuebersicht.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_deutschlandticket.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_familienkasse.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_finanzamt_steuerklarung.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_fruehfoerderung.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_jobcenter.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_jugendamt.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_kindergarten.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_konsulat.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_polizei.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_tab_content.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_vermieter.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_versorgungsamt.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_wbs.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_wohngeldstelle.dart';
import 'package:icd360sev_vorsitzer/widgets/deo.dart';
import 'package:icd360sev_vorsitzer/widgets/deutschlandticket_einstellung.dart';
import 'package:icd360sev_vorsitzer/widgets/einkaufen_tab_content.dart';
import 'package:icd360sev_vorsitzer/widgets/empfehlung.dart';
import 'package:icd360sev_vorsitzer/widgets/finanzen_tab_content.dart';
import 'package:icd360sev_vorsitzer/widgets/forgot_password_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/freizeit_tab_content.dart';
import 'package:icd360sev_vorsitzer/widgets/gesundheit_tab_content.dart';
import 'package:icd360sev_vorsitzer/widgets/gesundheits_profil.dart';
import 'package:icd360sev_vorsitzer/widgets/github_korrespondenz_tab.dart';
import 'package:icd360sev_vorsitzer/widgets/grundfreibetrag_einstellung.dart';
import 'package:icd360sev_vorsitzer/widgets/hilfsmittel_rezept_section.dart';
import 'package:icd360sev_vorsitzer/widgets/jobcenter_einstellung.dart';
import 'package:icd360sev_vorsitzer/widgets/kindergeld_einstellung.dart';
import 'package:icd360sev_vorsitzer/widgets/korrespondenz_attachments_widget.dart';
import 'package:icd360sev_vorsitzer/widgets/korrespondenz_message_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/member_devices_widget.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_augenarzt.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_hno.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_krankenhaus.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_md.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_rheumatologie.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_behorde_deutschebahn.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_behorde_krankenkasse_pflegegrad.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_benachrichtigung.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_karten.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_unterschriften.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_vertraege.dart';
import 'package:icd360sev_vorsitzer/widgets/pfandung_grenze.dart';
import 'package:icd360sev_vorsitzer/widgets/polizei_vorfall_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/reparatur.dart';
import 'package:icd360sev_vorsitzer/widgets/rettungsdienst.dart';
import 'package:icd360sev_vorsitzer/widgets/reziprozitaet.dart';
import 'package:icd360sev_vorsitzer/widgets/sanitaetshaus.dart';
import 'package:icd360sev_vorsitzer/widgets/stellenangeboten.dart';
import 'package:icd360sev_vorsitzer/widgets/termin_dialogs.dart';
import 'package:icd360sev_vorsitzer/widgets/user_details_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/visitenkarte.dart';
import 'package:icd360sev_vorsitzer/widgets/wasser.dart';
import 'package:icd360sev_vorsitzer/widgets/wasser_trinken.dart';
import 'package:icd360sev_vorsitzer/widgets/wasser_trinken_filter.dart';

const _groessen = <String, ({Size groesse, double schrift})>{
  'Pixel 8 Pro (448 dp)': (groesse: Size(448, 997.3), schrift: 1.0),
  'Pixel 8 Pro, Schrift 2,0': (groesse: Size(448, 997.3), schrift: 2.0),
};

const _langerText = 'Gemeinschaftsunterkunft Musterfrau-Schmidt Alexandra';

final _zeile = <String, dynamic>{
  'id': 1, 'user_id': 13, 'name': _langerText, 'titel': _langerText,
  'subject': _langerText, 'bezeichnung': _langerText, 'notiz': _langerText,
  'beschreibung': _langerText, 'message': _langerText, 'status': 'offen',
  'datum': '2026-08-08', 'created_at': '2026-08-08 10:00:00',
  'betrag': '1234.56', 'kosten': '1234.56',
  'mitgliedernummer': 'M68650', 'telefon_mobil': '+4915112345678',
};

final _zeilen = List.generate(3, (_) => Map<String, dynamic>.from(_zeile));

final _user = User(
  id: 13,
  mitgliedernummer: 'M68650',
  email: 'alexandra.musterfrau-schmidt@icd360s.de',
  name: 'Alexandra Katharina Musterfrau-Schmidt',
  vorname: 'Alexandra Katharina',
  nachname: 'Musterfrau-Schmidt',
  status: 'aktiv',
  role: 'mitglied',
  preferredLanguage: 'de',
);

http.Client _mock() => MockClient((anfrage) async {
      final pfad = anfrage.url.path.toLowerCase();
      final alsObjekt =
          pfad.contains('bewerbung') || pfad.contains('korrespondenz');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': alsObjekt
              ? <String, dynamic>{
                  'bewerbungen': [],
                  'eintraege': [],
                  'message': <String, dynamic>{'body_html': '', 'body_text': ''},
                }
              : [],
          'items': [],
          'vorfaelle': [],
          'termine': [],
          'tickets': [],
          'institutionen': [],
          'message': '',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

/// Tippt der Reihe nach jeden Knopf an und misst, was sich öffnet.
Future<List<String>> dialogeOeffnen(
  WidgetTester tester,
  Size groesse,
  double schrift,
  Widget Function() bauen,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = groesse * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final gesammelt = <String>[];
  var wo = 'Grundzustand';
  final vorher = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('RenderFlex')) {
      final ort = RegExp(r'lib/[\w/]+\.dart:\d+:\d+')
              .firstMatch(details.toString())
              ?.group(0) ??
          'Ort unbekannt';
      final zeile = '${text.split('\n').first}  ← $ort  [$wo]';
      if (!gesammelt.contains(zeile)) gesammelt.add(zeile);
    }
  };

  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: groesse,
        devicePixelRatio: 3,
        textScaler: TextScaler.linear(schrift),
      ),
      child: Scaffold(body: bauen()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));

  // ⚠️ Zuerst die Aufklapper: 48 `ExpansionTile` im Projekt zeigen ihren
  // Inhalt standardmäßig NICHT. Das ist dasselbe Loch wie bei den Reitern —
  // was eingeklappt ist, hat noch nie ein Test gezeichnet.
  final aufklapper = find.byType(ExpansionTile);
  for (var i = 0; i < aufklapper.evaluate().length && i < 6; i++) {
    wo = 'Aufklapper Nr. $i';
    try {
      await tester.tap(aufklapper.at(i), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    } catch (_) {}
  }

  // Knöpfe, die typischerweise einen Dialog öffnen. Bewusst begrenzt:

  for (final finder in [
    find.byIcon(Icons.add),
    find.byIcon(Icons.edit),
    find.byIcon(Icons.edit_outlined),
    find.byIcon(Icons.info_outline),
    find.byIcon(Icons.search),
    find.byIcon(Icons.upload_file),
    find.byType(FilledButton),
    find.byType(ElevatedButton),
  ]) {
    final anzahl = finder.evaluate().length;
    for (var i = 0; i < anzahl && i < 2; i++) {
      wo = 'nach Tipp Nr. $i';
      try {
        await tester.tap(finder.at(i), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      } catch (_) {
        continue;
      }
      // ⚠️ NICHT mit `nav.pop()` schließen. Das hinterlässt den Baum in
      // einem Zustand, den Flutter beim nächsten Aufbau mit
      // „renderObject.child == child is not true" quittiert — ein
      // Framework-Fehler, den ich mir selbst gebaut hatte. Stattdessen den
      // Bildschirm frisch aufbauen: teurer, aber sauber.
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: groesse,
            devicePixelRatio: 3,
            textScaler: TextScaler.linear(schrift),
          ),
          child: Scaffold(body: bauen()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  await tester.pump(const Duration(seconds: 16));
  FlutterError.onError = vorher;
  tester.takeException();
  return gesammelt;
}

void main() {
  setUpAll(() {
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = _mock();
    // ⚠️ Neu: dieselbe Naht für die beiden anderen Dienste. Ohne sie gingen
    // ihre Aufrufe wirklich hinaus und warfen asynchron aus der Zone — daran
    // hingen `DiensteScreen`, `LiveChatDialog` und `RemoteControlScreen`.
    TicketService().testClient = _mock();
    TerminService().testClient = _mock();
  });
  tearDownAll(() => DeviceKeyService().setTestCredentials(null));

  final api = ApiService();
  final tickets = TicketService();
  final termine = TerminService();

  final faelle = <String, Widget Function()>{
    'ArbeitsagenturScreen': () => ArbeitsagenturScreen(apiService: api, onBack: () {}),
    'ArchivScreen': () => ArchivScreen(apiService: api, users: <User>[]),
    'BehoerdenScreen': () => BehoerdenScreen(apiService: api, mitgliedernummer: _langerText, onBack: () {}),
    'DeutschePostScreen': () => DeutschePostScreen(apiService: api, onBack: () {}),
    'EinstellungenScreen': () => EinstellungenScreen(apiService: api),
    'GerichtScreen': () => GerichtScreen(apiService: api, onBack: () {}),
    'GitHubScreen': () => GitHubScreen(onBack: () {}, apiService: api),
    'GoogleNonprofitScreen': () => GoogleNonprofitScreen(apiService: api, onBack: () {}),
    'HandelsregisterScreen': () => HandelsregisterScreen(apiService: api, onBack: () {}),
    'InwxScreen': () => InwxScreen(apiService: api, onBack: () {}),
    'JasminaScreen': () => JasminaScreen(apiService: api, onBack: () {}),
    'MicrosoftNonprofitScreen': () => MicrosoftNonprofitScreen(apiService: api, onBack: () {}),
    'NotarScreen': () => NotarScreen(apiService: api, onBack: () {}),
    'PayPalScreen': () => PayPalScreen(onBack: () {}, apiService: api),
    'PostcardView': () => PostcardView(apiService: api),
    'SendungsverfolgungView': () => SendungsverfolgungView(apiService: api),
    'ServdiscountScreen': () => ServdiscountScreen(apiService: api, onBack: () {}),
    'SimpleFaxScreen': () => SimpleFaxScreen(onBack: () {}, apiService: api),
    'StatistikScreen': () => StatistikScreen(apiService: api, users: <User>[], currentMitgliedernummer: _langerText),
    'StifterHelfenScreen': () => StifterHelfenScreen(apiService: api, onBack: () {}),
    'VereinregisterScreen': () => VereinregisterScreen(apiService: api, onBack: () {}),
    'FinanzamtScreen': () => FinanzamtScreen(apiService: api, mitgliedernummer: _langerText, onBack: () {}),
    'VesperkircheScreen': () => VesperkircheScreen(apiService: api, onBack: () {}),
    'VrBankScreen': () => VrBankScreen(onBack: () {}, apiService: api),
    'ArbeitgeberBehoerdeContent': () => ArbeitgeberBehoerdeContent(user: _user, apiService: api, dbArbeitgeberListe: _zeilen),
    'ArbeitgeberBewerbungsuebersichtContent': () => ArbeitgeberBewerbungsuebersichtContent(apiService: api, userId: 13, dbArbeitgeberListe: _zeilen),
    'BehordeDeutschlandticketContent': () => BehordeDeutschlandticketContent(apiService: api, userId: 13),
    'BehordeFamilienkasseContent': () => BehordeFamilienkasseContent(apiService: api, userId: 13),
    'FinanzamtSteuerklarungWidget': () => FinanzamtSteuerklarungWidget(apiService: api, user: _user, finanzamtData: _zeile, onBack: () {}),
    'BehordeFruehfoerderungContent': () => BehordeFruehfoerderungContent(apiService: api, userId: 13),
    'BehordeJobcenterContent': () => BehordeJobcenterContent(apiService: api, userId: 13),
    'BehordeJugendamtContent': () => BehordeJugendamtContent(apiService: api, userId: 13),
    'BehordeKindergartenContent': () => BehordeKindergartenContent(apiService: api, userId: 13),
    'BehordeKonsulatContent': () => BehordeKonsulatContent(apiService: api, userId: 13),
    'BehordePolizeiContent': () => BehordePolizeiContent(apiService: api, adminMitgliedernummer: _langerText, clientMitgliedernummer: _langerText, userId: 13),
    'BehoerdeTabContent': () => BehoerdeTabContent(user: _user, apiService: api, ticketService: tickets, terminService: termine, adminMitgliedernummer: _langerText),
    'BehordeVermieterContent': () => BehordeVermieterContent(apiService: api, userId: 13),
    'BehordeVersorgungsamtContent': () => BehordeVersorgungsamtContent(apiService: api, userId: 13, user: _user),
    'BehordeWbsContent': () => BehordeWbsContent(apiService: api, userId: 13),
    'BehordeWohngeldstelleContent': () => BehordeWohngeldstelleContent(apiService: api, userId: 13),
    'DeoTab': () => DeoTab(apiService: api),
    'DeutschlandticketEinstellungWidget': () => DeutschlandticketEinstellungWidget(apiService: api),
    'EinkaufenTabContent': () => EinkaufenTabContent(apiService: api, userId: 13),
    'EmpfehlungContent': () => EmpfehlungContent(apiService: api),
    'FinanzenTabContent': () => FinanzenTabContent(user: _user, apiService: api, ticketService: tickets, adminMitgliedernummer: _langerText),
    'ForgotPasswordDialog': () => ForgotPasswordDialog(apiService: api),
    'FreizeitTabContent': () => FreizeitTabContent(apiService: api, user: _user),
    'GesundheitTabContent': () => GesundheitTabContent(user: _user, apiService: api, ticketService: tickets, terminService: termine, adminMitgliedernummer: _langerText),
    'GesundheitsProfilTab': () => GesundheitsProfilTab(apiService: api, userId: 13, vorname: _langerText, nachname: _langerText, geschlecht: _langerText, geburtsdatum: _langerText),
    'GithubKorrespondenzTab': () => GithubKorrespondenzTab(apiService: api),
    'GrundfreibetragEinstellungWidget': () => GrundfreibetragEinstellungWidget(apiService: api),
    'HilfsmittelTab': () => HilfsmittelTab(apiService: api, userId: 13, arztType: _langerText, arztTitle: _langerText),
    'JobcenterEinstellungWidget': () => JobcenterEinstellungWidget(apiService: api),
    'KindergeldEinstellungWidget': () => KindergeldEinstellungWidget(apiService: api),
    'KorrAttachmentsWidget': () => KorrAttachmentsWidget(apiService: api, modul: _langerText, korrespondenzId: 13),
    'KorrespondenzMessageDialog': () => KorrespondenzMessageDialog(apiService: api, fileId: 13),
    'MemberDevicesSection': () => MemberDevicesSection(apiService: api, userId: 13, mitgliedernummer: _langerText, userName: _langerText),
    'MitgliederverwaltungArztenAugenarzt': () => MitgliederverwaltungArztenAugenarzt(user: _user, apiService: api, ticketService: tickets, terminService: termine, adminMitgliedernummer: _langerText),
    'MitgliederverwaltungArztenHno': () => MitgliederverwaltungArztenHno(user: _user, apiService: api, ticketService: tickets, terminService: termine, adminMitgliedernummer: _langerText),
    'MitgliederverwaltungArztenKrankenhaus': () => MitgliederverwaltungArztenKrankenhaus(user: _user, apiService: api, ticketService: tickets, terminService: termine, adminMitgliedernummer: _langerText),
    'MitgliederverwaltungArztenMd': () => MitgliederverwaltungArztenMd(user: _user, apiService: api, ticketService: tickets, terminService: termine, adminMitgliedernummer: _langerText),
    'MitgliederverwaltungArztenRheumatologie': () => MitgliederverwaltungArztenRheumatologie(user: _user, apiService: api, ticketService: tickets, terminService: termine, adminMitgliedernummer: _langerText),
    'MitgliederverwaltungBehordeDeutscheBahn': () => MitgliederverwaltungBehordeDeutscheBahn(apiService: api, userId: 13, user: _user),
    'MitgliederverwaltungBehordeKrankenkassePflegegrad': () => MitgliederverwaltungBehordeKrankenkassePflegegrad(apiService: api, userId: 13),
    'MitgliederBenachrichtigungWidget': () => MitgliederBenachrichtigungWidget(apiService: api, user: _user),
    'MitgliederKartenContent': () => MitgliederKartenContent(apiService: api, userId: 13),
    'KarteEditDialog': () => KarteEditDialog(apiService: api, userId: 13, karte: null, shops: _zeilen),
    'MitgliederUnterschriftenTab': () => MitgliederUnterschriftenTab(user: _user, adminMitgliedernummer: _langerText),
    'VertraegeContent': () => VertraegeContent(apiService: api, userId: 13),
    'VertragKorrTab': () => VertragKorrTab(apiService: api, vertragId: 13),
    'VertragDokTab': () => VertragDokTab(apiService: api, vertragId: 13, kategorie: _langerText, label: _langerText),
    'PfandungGrenzeWidget': () => PfandungGrenzeWidget(apiService: api),
    'PolizeiVorfallDialog': () => PolizeiVorfallDialog(apiService: api, vorfallId: 13, mitgliedernummer: _langerText, userId: 13, onUpdated: () {}),
    'ReparaturContent': () => ReparaturContent(apiService: api, userId: 13),
    'RettungsdienstContent': () => RettungsdienstContent(apiService: api, userId: 13),
    'ReziprozitaetContent': () => ReziprozitaetContent(apiService: api, userId: 13),
    'SanitaetshausContent': () => SanitaetshausContent(apiService: api, userId: 13),
    'StellenangebotenContent': () => StellenangebotenContent(apiService: api, user: _user),
    'CreateTerminDialog': () => CreateTerminDialog(terminService: termine, users: <User>[], tickets: const [], onTerminCreated: () {}),
    'UserDetailsDialog': () => UserDetailsDialog(user: _user, apiService: api, onUpdated: () {}, adminMitgliedernummer: _langerText),
    'Visitenkarte': () => Visitenkarte(mitgliedernummer: _langerText, apiService: api),
    'WasserTab': () => WasserTab(apiService: api),
    'WasserTrinkenTab': () => WasserTrinkenTab(apiService: api),
    'WasserTrinkenFilterTab': () => WasserTrinkenFilterTab(apiService: api),
  };

  // ⚠️ Diese drei überleben das Neuaufbauen zwischen den Tipps nicht:
  // steht der Fokus in einem Eingabefeld, wirft Flutter beim Verwerfen des
  // Baums `_dependents.isEmpty is not true`. Das ist ein Artefakt DIESES
  // Harnesses, kein Befund an der App — ihre Überläufe sind über die
  // anderen Harnesse abgedeckt.
  const fokusEmpfindlich = {
    'ReziprozitaetContent',
    'MemberDevicesSection',
    'StellenangebotenContent',
  };
  final geprueftD = Map.of(faelle)
    ..removeWhere((k, _) => fokusEmpfindlich.contains(k));
  // ⚠️ Einer bleibt ausgenommen, aus einem benannten Grund — nicht mehr
  // wegen fehlender Mock-Naht:
  //   * `RemoteControlScreen` braucht einen initialisierten
  //     `RTCVideoRenderer` („Call initialize before setting the stream").
  //     WebRTC gibt es im Widget-Test nicht.
  // `LiveChatDialog` ist seit der mounted-Prüfung wieder dabei — der Fehler
  // war kein Testartefakt, sondern ein echtes `setState` nach `await` auf
  // einem geschlossenen Dialog.
  const nichtImTestBaubar = {'RemoteControlScreen'};
  final geprueftDP = Map.of(geprueftD)..removeWhere((k, _) => nichtImTestBaubar.contains(k));
  // jeder Tipp kostet zwei Frames, und ein Bildschirm hat schnell 40 davon.

  _groessen.forEach((groessenName, lage) {
    group('Dialoge bei $groessenName', () {
      geprueftDP.forEach((name, bauen) {
        testWidgets(name, (tester) async {
          final fehler = await dialogeOeffnen(
              tester, lage.groesse, lage.schrift, bauen);
          expect(fehler, isEmpty,
              reason: '$name bei $groessenName:\n${fehler.join("\n")}');
        });
      });
    });
  });
}
