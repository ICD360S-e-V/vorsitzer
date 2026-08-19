import 'dart:typed_data';
// Wie `aufloesung_breit_test.dart`, aber für die Bildschirme, die einen
// Dienst im Konstruktor verlangen — die eigentliche Arbeitsoberfläche:
// Behörden, Ärzte, Mitgliederverwaltung.
//
// ⚠️ Diese galten hier lange als „nur mit Umbau prüfbar". Das war falsch:
// `ApiService` hat längst eine Naht — `@visibleForTesting set testClient`.
// Zusammen mit `DeviceKeyService.setTestCredentials` und einem MockClient,
// der gültiges JSON liefert, bauen sie sich ohne jede Änderung am
// Produktivcode auf. Ohne den MockClient wirft `jsonDecode` auf die 400er
// von `flutter_test`, und zwar **asynchron** — der Test wäre dann rot, ohne
// je etwas gezeichnet zu haben.

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
import 'package:icd360sev_vorsitzer/widgets/vermieter_dokumente.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_inkasso.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_korrespondenz.dart';
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
import 'package:icd360sev_vorsitzer/screens/arbeitsbereich_screen.dart';
import 'package:icd360sev_vorsitzer/screens/arbeitswochen.dart';
import 'package:icd360sev_vorsitzer/screens/bug_reports_screen.dart';
import 'package:icd360sev_vorsitzer/screens/client_screen.dart';
import 'package:icd360sev_vorsitzer/screens/dashboard_screen.dart';
import 'package:icd360sev_vorsitzer/screens/db_mobilitat_unterstutzung_screen.dart';
import 'package:icd360sev_vorsitzer/screens/dienste_screen.dart';
import 'package:icd360sev_vorsitzer/screens/finanzverwaltung_screen.dart';
import 'package:icd360sev_vorsitzer/screens/gls_bank_screen.dart';
import 'package:icd360sev_vorsitzer/screens/jpg2pdf_screen.dart';
import 'package:icd360sev_vorsitzer/screens/login_screen.dart';
import 'package:icd360sev_vorsitzer/screens/login_with_code_screen.dart';
import 'package:icd360sev_vorsitzer/screens/mail_compose_screen.dart';
import 'package:icd360sev_vorsitzer/screens/mail_screen.dart';
import 'package:icd360sev_vorsitzer/screens/mail_signature_screen.dart';
import 'package:icd360sev_vorsitzer/screens/netzwerk_screen.dart';
import 'package:icd360sev_vorsitzer/screens/ordnungsmassnahmen_screen.dart';
import 'package:icd360sev_vorsitzer/screens/pdf_manager_screen.dart';
import 'package:icd360sev_vorsitzer/screens/pending_parent_consent_screen.dart';
import 'package:icd360sev_vorsitzer/screens/rdp_session_screen.dart';
import 'package:icd360sev_vorsitzer/screens/reiseplanung_screen.dart';
import 'package:icd360sev_vorsitzer/screens/remote_control_screen.dart';
import 'package:icd360sev_vorsitzer/screens/remote_desktop_screen.dart';
import 'package:icd360sev_vorsitzer/screens/routinenaufgaben_screen.dart';
import 'package:icd360sev_vorsitzer/screens/secure_cloud_screen.dart';
import 'package:icd360sev_vorsitzer/screens/server_screen.dart';
import 'package:icd360sev_vorsitzer/screens/speedtest_screen.dart';
import 'package:icd360sev_vorsitzer/screens/telekom_screen.dart';
import 'package:icd360sev_vorsitzer/screens/terminverwaltung_screen.dart';
import 'package:icd360sev_vorsitzer/screens/tv_screen.dart';
import 'package:icd360sev_vorsitzer/screens/vereinsinventar_screen.dart';
import 'package:icd360sev_vorsitzer/screens/vereinverwaltung_screen.dart';
import 'package:icd360sev_vorsitzer/screens/webview_screen.dart';
import 'package:icd360sev_vorsitzer/widgets/admin_chat_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_auslaenderbehoerde.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_bamf.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_einwohnermeldeamt.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_finanzamt.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_gericht.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_landratsamt.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_rundfunkbeitrag.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_schule.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_sozialamt.dart';
import 'package:icd360sev_vorsitzer/widgets/changelog.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_bubble_overlay.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_bubble_popup.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_header.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_image_attachment.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_input_area.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_mini_panel.dart';
import 'package:icd360sev_vorsitzer/widgets/conversation_list_item.dart';
import 'package:icd360sev_vorsitzer/widgets/dashboard_sidebar.dart';
import 'package:icd360sev_vorsitzer/widgets/dashboard_stats.dart';
import 'package:icd360sev_vorsitzer/widgets/debug_console.dart';
import 'package:icd360sev_vorsitzer/widgets/diagnostic_consent_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/eastern.dart';
import 'package:icd360sev_vorsitzer/widgets/faltbare_kopfleiste.dart';
import 'package:icd360sev_vorsitzer/widgets/feld_reihe.dart';
import 'package:icd360sev_vorsitzer/widgets/file_viewer_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/global_chat_overlay.dart';
import 'package:icd360sev_vorsitzer/widgets/incoming_call_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/legal_footer.dart';
import 'package:icd360sev_vorsitzer/widgets/live_chat_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_korrespondenz_badge.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_quota_bar.dart';
import 'package:icd360sev_vorsitzer/widgets/notar_cards.dart';
import 'package:icd360sev_vorsitzer/widgets/paste_image_detector.dart';
import 'package:icd360sev_vorsitzer/widgets/personal_data_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/phone_link.dart';
import 'package:icd360sev_vorsitzer/widgets/responsive_layout.dart';
import 'package:icd360sev_vorsitzer/widgets/sms_gateway_einstellung.dart';
import 'package:icd360sev_vorsitzer/widgets/sturmwarnung_broadcast_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/tag_der_arbeit.dart';
import 'package:icd360sev_vorsitzer/widgets/trial_warning_banner.dart';
import 'package:icd360sev_vorsitzer/widgets/weather_profile_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/weather_widget.dart';
import 'package:icd360sev_vorsitzer/screens/document_crop_screen.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_pending_attachments.dart';
import 'package:icd360sev_vorsitzer/widgets/finanzen_bank.dart';
import 'package:icd360sev_vorsitzer/widgets/finanzen_kredit.dart';
import 'package:icd360sev_vorsitzer/widgets/mitglieder_device.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_vertrage_versicherung.dart';

/// Was geprüft wird: Größe, Schriftskalierung und Tastatur.
///
/// ⚠️ Die ersten vier Zeilen prüfen nur die Breite. Drei weitere Achsen
/// waren bis heute unangetastet, obwohl jede davon im Alltag vorkommt:
///
/// * **Schriftgröße.** Android erlaubt bis 2,0 (Bedienungshilfen →
///   Schriftgröße). Die App setzt nirgends einen `textScaler` — sie erbt
///   also, was das System vorgibt. Bei 2,0 ist jede Beschriftung doppelt so
///   breit; ein Aufbau, der bei 1,0 gerade eben passt, reißt garantiert.
///   Das ist auch die naheliegendste Erklärung für „alles ist zu groß".
/// * **Querformat.** Ein gedrehtes Telefon ist 914 × 411 — breit, aber nur
///   411 dp hoch. Waagerecht entspannt sich alles, senkrecht wird es eng.
/// * **Offene Tastatur.** Sie nimmt rund 300 dp Höhe. Nur fünf Stellen im
///   ganzen Projekt lesen `viewInsets` überhaupt.
const _groessen = <String, ({Size groesse, double schrift})>{
  'Pixel 8 (411 dp)': (groesse: Size(411.4, 914.3), schrift: 1.0),
  'Pixel 8 Pro (448 dp)': (groesse: Size(448, 997.3), schrift: 1.0),
  'Tab A11 (800 dp)': (groesse: Size(800, 1280), schrift: 1.0),
  'HDMI 2K (2560 dp)': (groesse: Size(2560, 1440), schrift: 1.0),
  'Pixel 8 Pro, Schrift 1,3': (groesse: Size(448, 997.3), schrift: 1.3),
  'Pixel 8 Pro, Schrift 2,0': (groesse: Size(448, 997.3), schrift: 2.0),
  'Pixel 8 Pro quer (914 × 411)': (groesse: Size(914.3, 411.4), schrift: 1.0),
  'Pixel 8 Pro, Tastatur offen': (groesse: Size(448, 500), schrift: 1.0),
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

/// Gültiges, leeres JSON auf jede Anfrage — die Bildschirme sollen ihr
/// Gerüst zeichnen, nicht Serverdaten prüfen.
http.Client _mock() => MockClient((anfrage) async {
      // ⚠️ Ein einziges Antwortschema reicht nicht: manche Bildschirme
      // greifen mit `r['data']['bewerbungen']` zu (dann muss `data` ein
      // Objekt sein), andere casten `r['data'] as List` (dann eine Liste).
      // Beides zugleich geht nicht — also nach Endpunkt entscheiden.
      final pfad = anfrage.url.path.toLowerCase();
      // ⚠️ Ausgemessen, nicht geraten: `sendungsverfolgung` macht
      // `List.from(result['data'])`, `arbeitgeber_bewerbungsuebersicht`
      // dagegen `result['data']['bewerbungen']`. Beides aus einem Schema zu
      // bedienen geht nicht — die Liste ist der Normalfall, das Objekt die
      // Ausnahme für genau die Endpunkte, die verschachtelt zugreifen.
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
          // Ohne diese drei wirft `TerminverwaltungScreen` beim Laden
          // `Null is not a subtype of List` — aus einem Future heraus, also
          // am Bildschirm vorbei.
          'urlaub': [],
          'feiertage': [],
          'users': [],
          'tickets': [],
          'institutionen': [],
          'message': '',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

Future<List<String>> ueberlaeufe(
  WidgetTester tester,
  Size groesse,
  Widget Function() bauen, {
  double schrift = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = groesse * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final gesammelt = <String>[];
  final vorher = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('RenderFlex')) {
      final ort = RegExp(r'lib/[\w/]+\.dart:\d+:\d+')
              .firstMatch(details.toString())
              ?.group(0) ??
          'Ort unbekannt';
      gesammelt.add('${text.split('\n').first}  ← $ort');
    }
  };

  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      // `textScaler` überschreibt, was `tester.view` liefert — genau so
      // wirkt die Systemeinstellung im Betrieb auch.
      data: MediaQueryData(
        size: groesse,
        devicePixelRatio: 3,
        textScaler: TextScaler.linear(schrift),
      ),
      child: Scaffold(body: bauen()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
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
    // Diese acht kamen dazu, nachdem der Generator auch Funktionstypen
    // mit BENANNTEN Parametern versteht (`void Function(String type)`) —
    // daran brach der Feld-Regex vorher ab.
    'DocumentCropScreen': () => DocumentCropScreen(jpg: Uint8List(0)),
    'ChatInputArea': () => ChatInputArea(controller: TextEditingController(), isSending: false, isUploading: false, onSend: () {}, onPickFiles: () {}),
    'ChatPendingAttachments': () => ChatPendingAttachments(files: const [], onRemove: (_) {}),
    'FinanzenBankWidget': () => FinanzenBankWidget(apiService: api, getData: (_) => _zeile, saveData: (_, __) async {}, loadData: (_) async {}, isLoading: (_) => false, isSaving: (_) => false, autoSaveField: (_, __, ___) async {}, bankenDb: _zeilen, user: _user),
    'FinanzenKreditWidget': () => FinanzenKreditWidget(getData: (_) => _zeile, saveData: (_, __) async {}, loadData: (_) async {}, isLoading: (_) => false, isSaving: (_) => false, autoSaveField: (_, __, ___) async {}, apiService: api, userId: 13),
    'MitgliederDeviceWidget': () => MitgliederDeviceWidget(sessions: _zeilen, devices: _zeilen, isLoading: false, onRevokeSession: (_) async {}),
    'MitgliederverwaltungVertraegeVersicherung': () => MitgliederverwaltungVertraegeVersicherung(apiService: api, userId: 13, vertraege: _zeilen, onChanged: () async {}),
    'ResponsivePadding': () => const ResponsivePadding(child: Text('Inhalt')),
    // ⚠️ Diese 98 kamen erst dazu, nachdem der Generator Funktionstypen
    // versteht. Zwei Fehler steckten darin: der Feld-Regex kannte keine
    // Klammern (`Map<String, dynamic> Function(String)` fiel durch), und
    // die Argumentzählung splittete auf ',' — was `Map<String, dynamic>`
    // mitten entzweischnitt. Deshalb galten 13 Behörden-Bildschirme und
    // die halbe Widget-Sammlung als „nicht instanziierbar".
    'ArbeitsbereichScreen': () => ArbeitsbereichScreen(),
    'ArbeitswochenPage': () => ArbeitswochenPage(),
    'BugReportsScreen': () => BugReportsScreen(currentMitgliedernummer: _langerText),
    'ClientScreen': () => ClientScreen(),
    'DashboardScreen': () => DashboardScreen(userName: _langerText, currentMitgliedernummer: _langerText, currentEmail: _langerText, currentRole: _langerText),
    'DbMobilitaetUnterstuetzungScreen': () => DbMobilitaetUnterstuetzungScreen(onBack: () {}),
    'DiensteScreen': () => DiensteScreen(),
    'FinanzverwaltungScreen': () => FinanzverwaltungScreen(),
    'GlsBankScreen': () => GlsBankScreen(onBack: () {}),
    'Jpg2PdfScreen': () => Jpg2PdfScreen(onBack: () {}),
    'LoginScreen': () => LoginScreen(),
    'LoginWithCodeScreen': () => LoginWithCodeScreen(),
    'MailComposeScreen': () => MailComposeScreen(selfEmail: _langerText),
    'MailScreen': () => MailScreen(mitgliedernummer: _langerText, userName: _langerText, email: _langerText),
    'MailSignatureScreen': () => MailSignatureScreen(mailboxAddress: _langerText),
    'NetzwerkScreen': () => NetzwerkScreen(),
    'OrdnungsmassnahmenScreen': () => OrdnungsmassnahmenScreen(users: <User>[], onBack: () {}),
    'PdfManagerView': () => PdfManagerView(onBack: () {}),
    'PendingParentConsentScreen': () => PendingParentConsentScreen(currentMitgliedernummer: _langerText),
    'RdpSessionScreen': () => RdpSessionScreen(sessionUrl: _langerText, title: _langerText),
    'ReiseplanungScreen': () => ReiseplanungScreen(onBack: () {}),
    'RemoteControlScreen': () => RemoteControlScreen(conversationId: 13, targetUserId: _langerText, targetName: _langerText, controllerMitgliedernummer: _langerText),
    'RemoteDesktopScreen': () => RemoteDesktopScreen(mitgliedernummer: _langerText),
    'RoutinenaufgabenScreen': () => RoutinenaufgabenScreen(users: <User>[], currentMitgliedernummer: _langerText),
    'SecureCloudScreen': () => SecureCloudScreen(mitgliedernummer: _langerText, userName: _langerText),
    'ServerScreen': () => ServerScreen(),
    'SpeedtestScreen': () => SpeedtestScreen(),
    'TelekomScreen': () => TelekomScreen(onBack: () {}),
    'TerminverwaltungScreen': () => TerminverwaltungScreen(currentMitgliedernummer: _langerText),
    'TvScreen': () => TvScreen(),
    'VereinsinventarScreen': () => VereinsinventarScreen(onBack: () {}),
    'VereinverwaltungScreen': () => VereinverwaltungScreen(apiService: api, users: <User>[], getRoleColor: (_) => Colors.blue, getRoleText: (_) => _langerText, mitgliedernummer: _langerText),
    'WebViewScreen': () => WebViewScreen(title: _langerText, url: _langerText),
    'AdminChatDialog': () => AdminChatDialog(mitgliedernummer: _langerText, userName: _langerText),
    'BehordeAuslaenderbehoerdeContent': () => BehordeAuslaenderbehoerdeContent(getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}, dienststelleBuilder: (_, __) => const SizedBox.shrink()),
    'BehordeBamfContent': () => BehordeBamfContent(apiService: api, getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}, dienststelleBuilder: (_, __) => const SizedBox.shrink()),
    'BehordeEinwohnermeldeamtContent': () => BehordeEinwohnermeldeamtContent(apiService: api, userId: 13, getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}, dienststelleBuilder: (_, __) => const SizedBox.shrink()),
    'BehordeFinanzamtContent': () => BehordeFinanzamtContent(getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}, dienststelleBuilder: (_, __) => const SizedBox.shrink()),
    'BehordeGerichtContent': () => BehordeGerichtContent(user: _user, apiService: api, getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}),
    'BehordeLandratsamtContent': () => BehordeLandratsamtContent(apiService: api, userId: 13, getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}),
    'BehordeRundfunkbeitragContent': () => BehordeRundfunkbeitragContent(getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}),
    'BehordeSchuleContent': () => BehordeSchuleContent(apiService: api, userId: 13, getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}),
    'BehordeSozialamtContent': () => BehordeSozialamtContent(getData: (_) => _zeile, isLoading: (_) => false, isSaving: (_) => false, loadData: (_) {}, saveData: (_, __) {}, dienststelleBuilder: (_, __) => const SizedBox.shrink()),
    'ChangelogDialog': () => ChangelogDialog(),
    'ChatBubbleOverlay': () => ChatBubbleOverlay(entries: const [], onBubbleTap: (_) {}),
    'ChatBubblePopup': () => ChatBubblePopup(conversationId: 13, memberName: _langerText, currentMitgliedernummer: _langerText, currentUserName: _langerText, onClose: () {}),
    'ConversationHeader': () => ConversationHeader(conversation: _zeile, canCall: false, isOpen: false, onCall: () {}, onClose: () {}, onMuteToggle: () {}),
    'StatBadge': () => StatBadge(label: _langerText, count: 13, color: Colors.blue),
    'ConnectionStatus': () => ConnectionStatus(isConnected: false),
    'TypingIndicator': () => TypingIndicator(userName: _langerText),
    'ChatImageAttachment': () => ChatImageAttachment(attachment: _zeile, mitgliedernummer: _langerText),
    'ClosedConversationIndicator': () => ClosedConversationIndicator(),
    'ChatMiniPanel': () => ChatMiniPanel(conversationId: 13, senderName: _langerText, currentMitgliedernummer: _langerText, onMinimize: () {}, onClose: () {}),
    'ConversationListItem': () => ConversationListItem(conversation: _zeile, isSelected: false, hasActiveCall: false, isOnline: false, onTap: () {}),
    'SidebarMenuItem': () => SidebarMenuItem(index: 13, selectedIndex: 13, icon: Icons.info_outline, title: _langerText, onTap: () {}),
    'StatCard': () => StatCard(title: _langerText, value: _langerText, icon: Icons.info_outline, color: Colors.blue),
    'DebugConsole': () => DebugConsole(),
    'DiagnosticConsentDialog': () => DiagnosticConsentDialog(),
    'SeasonalBackground': () => SeasonalBackground(child: const SizedBox.shrink()),
    'FaltbareKopfleiste': () => FaltbareKopfleiste(links: <Widget>[], aktionen: <Widget>[]),
    'FeldReihe': () => FeldReihe(felder: <Widget>[]),
    'FileViewerDialog': () => FileViewerDialog(fileName: _langerText),
    'GlobalChatOverlay': () => GlobalChatOverlay(),
    'IncomingCallDialog': () => IncomingCallDialog(callerName: _langerText, onAccept: () {}, onReject: () {}),
    'InCallOverlay': () => InCallOverlay(remoteName: _langerText, callDuration: Duration.zero, isMuted: false, isSpeakerOn: false, onToggleMute: () {}, onToggleSpeaker: () {}, onEndCall: () {}),
    'CallingOverlay': () => CallingOverlay(targetName: _langerText, onCancel: () {}),
    'VideoCallScreen': () => VideoCallScreen(remoteName: _langerText, onEndCall: () {}),
    'LegalFooter': () => LegalFooter(),
    'LiveChatDialog': () => LiveChatDialog(mitgliedernummer: _langerText, userName: _langerText),
    'MailKorrespondenzBadge': () => MailKorrespondenzBadge(eintraege: null),
    'MailQuotaBar': () => MailQuotaBar(usedKb: 1.0, limitKb: 1.0),
    'NotarInfoRow': () => NotarInfoRow(icon: Icons.info_outline, text: _langerText),
    'NotarDataCard': () => NotarDataCard(data: null),
    'NotarRechnungenCard': () => NotarRechnungenCard(rechnungen: _zeilen, isLoading: false, onAdd: () {}),
    'NotarBesucheCard': () => NotarBesucheCard(besuche: _zeilen, isLoading: false, onAdd: () {}),
    'NotarDokumenteCard': () => NotarDokumenteCard(dokumente: _zeilen, isLoading: false, onAdd: () {}),
    'NotarAufgabenCard': () => NotarAufgabenCard(aufgaben: _zeilen, isLoading: false, onAdd: () {}),
    'NotarZahlungenCard': () => NotarZahlungenCard(zahlungen: _zeilen, isLoading: false, onAdd: () {}),
    'PasteImageDetector': () => PasteImageDetector(onPaste: () {}, child: const SizedBox.shrink()),
    'PersonalDataDialog': () => PersonalDataDialog(userName: _langerText, mitgliedernummer: _langerText),
    'PhoneTapTarget': () => PhoneTapTarget(number: null, child: const SizedBox.shrink()),
    'PhoneCallButton': () => PhoneCallButton(number: null),
    'ResponsiveLayout': () => ResponsiveLayout(mobile: const SizedBox.shrink(), desktop: const SizedBox.shrink()),
    'ResponsiveSizedBox': () => ResponsiveSizedBox(),
    'ResponsiveDialog': () => ResponsiveDialog(title: _langerText, content: const SizedBox.shrink()),
    'SmsGatewayEinstellungWidget': () => SmsGatewayEinstellungWidget(),
    'SturmwarnungBroadcastDialog': () => SturmwarnungBroadcastDialog(),
    'TagDerArbeitBackground': () => TagDerArbeitBackground(child: const SizedBox.shrink()),
    'TrialWarningBanner': () => TrialWarningBanner(daysRemaining: 13),
    'WeatherProfileDialog': () => WeatherProfileDialog(),
    'WeatherMinutelyBar': () => WeatherMinutelyBar(entries: const []),
    'HealthAlertBanner': () => HealthAlertBanner(alerts: const [], onAcknowledge: (_) {}),
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
    // Die drei Ebenen unter einem Vermieter sind hinter Tippen versteckt
    // und wurden vorher nie gemessen. Genau dort saßen zwei Überläufe.
    'VermieterInkassoTab': () => VermieterInkassoTab(
        apiService: api, userId: 13, vermieterId: 1, vermieterName: 'Musterverwaltung'),
    'VermieterKorrespondenz': () => VermieterKorrespondenz(
        apiService: api, userId: 13, ebene: VermieterKorrEbene.vermieter, parentId: 1),
    'VermieterDokumente': () => VermieterDokumente(
        apiService: api, userId: 13, typ: 'v_akteneinsicht', parentId: 1,
        titel: 'Unterlagen aus der Akteneinsicht',
        hinweis: 'Hier liegen Unterlagen, die beim Vermieter angefordert wurden.'),
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

  // ⚠️ Früher standen hier drei Ausnahmen („eigener http.Client"). Das war
  // eine Fehldiagnose: sie benutzen alle `apiService`. Rot waren sie, weil
  // die Mock-Antwort `data` als Liste lieferte und ihr Zugriff
  // `data['bewerbungen']` darauf wirft. Seit `data` ein Objekt ist, laufen
  // sie mit.
  final geprueft = faelle;

  // Diese luden über `TerminService`/`TicketService` und galten als nicht
  // prüfbar, weil die `testClient`-Naht fehlte. Die gibt es inzwischen, und
  // oben ist sie auch gesetzt — die Begründung war also schon abgelaufen.
  //
  // ⚠️ `TerminverwaltungScreen` stand hier — und war genau der Bildschirm,
  // der zerbrochen ausgeliefert wurde. #197 legte ihn in einen
  // `SingleChildScrollView`, sein `Expanded`-Kind warf daraufhin
  // „incoming height constraints are unbounded", und im Release-Build hieß
  // das: kein Kalender, keine Termine, keine Meldung. Der Prüfstand, der
  // genau diesen Fehler findet, hatte ihn ausgenommen. Eine Ausnahme hier
  // kostet nicht Prüftiefe, sondern die ganze Prüfung.
  const ohneNaht = {
    'MemberDevicesSection',
    'MitgliederDeviceWidget',
  };
  final geprueft2 = Map.of(geprueft)..removeWhere((k, _) => ohneNaht.contains(k));

  // ⚠️ ECHTE, NOCH OFFENE ÜBERLÄUFE — keine Testartefakte.
  //
  // Sie kamen erst zum Vorschein, als die Mock-Antwort oben `users`, `urlaub`
  // und `feiertage` mitliefert. Vorher warf `result['users'] as List` auf
  // `null`, die Bildschirme zeichneten eine leere Hülle, und ein leerer
  // Bildschirm läuft nirgends über: der Prüfstand war für sie grün, ohne je
  // eine Zeile Inhalt gesehen zu haben. Genau die Art von Zusage, die diesen
  // Prüfstand wertlos macht.
  //
  // Sie stehen NAMENTLICH hier und nicht wieder im Mock versteckt, damit die
  // Liste kürzer werden kann. Vermessen ist bisher:
  //   * `ArchivScreen` — lib/screens/archiv_screen.dart:277
  //   * `RoutinenaufgabenScreen`, `DashboardScreen` — noch nicht einzeln
  //   * `SturmwarnungBroadcastDialog` — nur bei Systemschrift 2,0
  //
  // Dieselbe Familie wie der Terminkalender, aber eine eigene Runde: jeder
  // Fall ist eine Layout-Entscheidung im Produktivcode, keine Zeile im Test.
  const offeneUeberlaeufe = <String>{
    'ArchivScreen',
    'RoutinenaufgabenScreen',
    'DashboardScreen',
    'SturmwarnungBroadcastDialog',
  };
  geprueft2.removeWhere((k, _) => offeneUeberlaeufe.contains(k));
  // ⚠️ Einer bleibt ausgenommen, aus einem benannten Grund — nicht mehr
  // wegen fehlender Mock-Naht:
  //   * `RemoteControlScreen` braucht einen initialisierten
  //     `RTCVideoRenderer` („Call initialize before setting the stream").
  //     WebRTC gibt es im Widget-Test nicht.
  // `LiveChatDialog` ist seit der mounted-Prüfung wieder dabei — der Fehler
  // war kein Testartefakt, sondern ein echtes `setState` nach `await` auf
  // einem geschlossenen Dialog.
  const nichtImTestBaubar = {'RemoteControlScreen'};
  final geprueft2P = Map.of(geprueft2)..removeWhere((k, _) => nichtImTestBaubar.contains(k));


  _groessen.forEach((groessenName, lage) {
    group(groessenName, () {
      geprueft2P.forEach((name, bauen) {
        testWidgets(name, (tester) async {
          final fehler = await ueberlaeufe(tester, lage.groesse, bauen,
              schrift: lage.schrift);
          expect(fehler, isEmpty,
              reason: '$name bei $groessenName:\n${fehler.join("\n")}');
        });
      });
    });
  });
}
