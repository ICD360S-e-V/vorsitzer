import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/ra_antwort.dart';

/// Test gegen die **echten**, ungekürzten Antworten von
/// `api/admin/vertrag_rechtsanwalt_manage.php`.
///
/// ⚠️ Warum echte Antworten und keine nachgebauten: die Form der Antwort ist
/// ein Nebeneffekt von `jsonResponse()` (`array_merge` in die Wurzel) und
/// davon, ob PHP ein Array als Liste oder als Objekt kodiert. Beides kann
/// man sich falsch merken, und ein Test gegen eine ausgedachte Antwort
/// prüft dann nur, ob man konsequent falsch liegt.
///
/// Genau das ist am 05.08.2026 im Speedtest-Bildschirm passiert: eine
/// PHP-Liste wurde als Map gelesen, `as Map?` gab **nicht** `null` zurück
/// sondern warf, und im Release-Build blieb eine graue Fläche ohne jede
/// Meldung übrig — an der weder `flutter analyze` noch 514 Tests etwas
/// auszusetzen hatten, weil keiner davon die echte Serverantwort anfasste.
///
/// Abgenommen am 14.08.2026 mit `_server_rechtsanwalt/ra_antwort_dump.php`.
/// Wird der Endpunkt geändert, wird dieses Skript erneut ausgeführt und die
/// Zeichenketten hier ersetzt — nicht von Hand angepasst.
void main() {
  // ── Echte Antworten, Wort für Wort vom Server ────────────────────────

  const listAktenzeichen = r'''
{"success":true,"items":[{"id":5,"status":"mahnverfahren","eroeffnet_am":"2026-07-05","geschlossen_am":null,"naechste_frist":null,"aktenzeichen":"DUMP 42\/26","bezeichnung":"Probeakte","gegenseite":"Musterstrom AG","gegner_anwalt":null,"gegner_aktenzeichen":null,"gericht":null,"gericht_aktenzeichen":null,"streitwert":"1234,56","notizen":null,"created_at":"2026-08-14 13:38:18","mahn_stufe":"vb_zugestellt","hat_mahnverfahren":true,"fristen_offen":2,"vollmacht_aktiv":false}]}
''';

  const getMandat = r'''
{"success":true,"exists":true,"data":{"id":5,"rechtsanwalt_id":5,"status":"mandat_erteilt","mandat_seit":"2026-07-01","mandat_bis":null,"ansprechpartner":"Frau Muster","telefon_durchwahl":null,"email_ansprechpartner":null,"ra_aktenzeichen":"142\/26 MU","gegenstand":null,"rechtsschutz":null,"rsv_name":null,"rsv_schadennummer":null,"notizen":null,"kanzlei":{"firmenname":"DUMP Kanzlei Muster PartG mbB","anwalt_name":"Dr. Erika Muster","strasse":"Musterstrasse 12","plz_ort":"89073 Ulm","telefon":"+49 731 0000000","fax":null,"email":"kanzlei@example.invalid","website":null,"rechtsanwaltskammer":"RAK Tuebingen","bea_safe_id":"DE.DUMP.0001","fachgebiete":"Fachanwaeltin fuer Zivilrecht"}}}
''';

  const getMahnverfahren = r'''
{"success":true,"exists":true,"data":{"id":6,"rolle":"antragsgegner","stufe":"vb_zugestellt","mb_beantragt_am":null,"mb_erlassen_am":null,"mb_zugestellt_am":"2026-06-01","widerspruch_am":null,"widerspruch_umfang":"kein","vb_beantragt_am":null,"vb_erlassen_am":"2026-07-20","vb_zugestellt_am":"2026-08-03","einspruch_am":null,"abgabe_am":null,"vollstreckung_am":null,"zustellung_ausland":0,"erledigt":0,"mahngericht":"Amtsgericht Stuttgart","gz_mahngericht":null,"antragsteller":null,"antragsteller_vertreter":null,"hauptforderung":"987,65","zinsen":null,"kosten":null,"widerspruch_begruendung":null,"notizen":null},"stufen":{"kein":{"label":"Kein Mahnverfahren","norm":""},"mb_beantragt":{"label":"Mahnbescheid beantragt","norm":"§ 690 ZPO"},"mb_zugestellt":{"label":"Mahnbescheid zugestellt","norm":"§ 693 ZPO"},"widerspruch":{"label":"Widerspruch eingelegt","norm":"§ 694 ZPO"},"vb_beantragt":{"label":"Vollstreckungsbescheid beantragt","norm":"§ 699 ZPO"},"vb_zugestellt":{"label":"Vollstreckungsbescheid zugestellt","norm":"§ 700 ZPO"},"einspruch":{"label":"Einspruch eingelegt","norm":"§ 700 i.V.m. § 338 ZPO"},"streitverfahren":{"label":"Abgabe an das Streitgericht","norm":"§ 696 ZPO"},"vollstreckung":{"label":"Zwangsvollstreckung","norm":"§ 794 Abs. 1 Nr. 4 ZPO"},"erledigt":{"label":"Erledigt","norm":""}},"fristen":[{"schluessel":"einspruch","titel":"Einspruch gegen den Vollstreckungsbescheid","norm":"§ 700 Abs. 1 ZPO i.V.m. § 339 Abs. 1 ZPO","ab":"2026-08-03","ab_label":"Zustellung des Vollstreckungsbescheids","datum":"2026-08-17","notfrist":true,"erledigt":false,"hinweis":"Notfrist. Sie kann nicht verlaengert werden (§ 224 Abs. 2 ZPO).","tage":3,"dringlichkeit":"bald"},{"schluessel":"mb_wirkung","titel":"Wirkung des Mahnbescheids entfaellt","norm":"§ 701 ZPO","ab":"2026-06-01","ab_label":"Zustellung des Mahnbescheids","datum":"2026-12-01","notfrist":false,"erledigt":false,"hinweis":"Wird bis dahin kein Vollstreckungsbescheid beantragt, verliert der Mahnbescheid seine Wirkung — auch die Hemmung der Verjaehrung endet dann (§ 204 Abs. 2 BGB). Das ist eine Frist zugunsten des Mitglieds.","tage":109,"dringlichkeit":"offen"},{"schluessel":"widerspruch","titel":"Widerspruch gegen den Mahnbescheid","norm":"§ 692 Abs. 1 Nr. 3 ZPO","ab":"2026-06-01","ab_label":"Zustellung des Mahnbescheids","datum":"2026-06-15","notfrist":false,"erledigt":false,"hinweis":"Der Vollstreckungsbescheid ist bereits erlassen — ein Widerspruch ist nach § 694 Abs. 1 ZPO nicht mehr moeglich. Was bleibt, ist der Einspruch.","tage":-60,"dringlichkeit":"abgelaufen"}],"vorbehalt":"Berechnet nach §§ 187 Abs. 1, 188 BGB i.V.m. § 222 ZPO; ein Fristende an einem Samstag, Sonntag oder gesetzlichen Feiertag ist auf den naechsten Werktag geschoben (§ 222 Abs. 2 ZPO). Beruecksichtigt sind die bundeseinheitlichen Feiertage — landesrechtliche Feiertage am Sitz des Gerichts koennen das Ende weiter nach hinten schieben. Massgeblich bleiben Zustellungsurkunde und Kanzlei; diese Uebersicht ist eine Erinnerungshilfe, keine Fristenberechnung im Rechtssinne."}
''';

  const listKorrespondenz = r'''
{"success":true,"items":[{"id":4,"datum":"2026-07-10","richtung":"eingehend","medium":"bea","erledigt":0,"betreff":"Sachstand","text":"Text mit Umlauten: äöüß","gespraechspartner":null,"notizen":null,"created_at":"2026-08-14 13:38:18","anhaenge":0}]}
''';

  const listVollmachtenLeer = r'''{"success":true,"items":[]}''';

  const fehlerEnum = r'''
{"success":false,"message":"Ungueltiger Wert \"gibt_es_nicht\" — erlaubt sind: kein_mandat, mandat_erteilt, in_bearbeitung, aussergerichtlich, mahnverfahren, klageverfahren, vergleich, ruht, beendet, mandat_niedergelegt"}
''';

  Map<String, dynamic> j(String s) => jsonDecode(s.trim()) as Map<String, dynamic>;

  group('Antwortform: Nutzdaten stehen in der Wurzel', () {
    test('list_aktenzeichen liefert items OHNE data-Dach', () {
      final res = j(listAktenzeichen);
      // Der Fehler, den es zu verhindern gilt: erst res['data'] auspacken.
      expect(res.containsKey('data'), isFalse,
          reason: 'jsonResponse() mischt in die Wurzel — es gibt kein data-Dach');
      final items = raListe(res);
      expect(items, hasLength(1));
      expect(items.first['aktenzeichen'], 'DUMP 42/26');
    });

    test('get_mandat hat exists in der Wurzel UND ein echtes data', () {
      final res = j(getMandat);
      expect(res['exists'], isTrue, reason: 'exists steht oben, nicht unter data');
      final daten = raKarte(res, 'data');
      expect(daten['ra_aktenzeichen'], '142/26 MU');
      // Die Kanzlei hängt eine Ebene tiefer und wird direkt gelesen.
      final kanzlei = Map<String, dynamic>.from(daten['kanzlei'] as Map);
      expect(kanzlei['firmenname'], 'DUMP Kanzlei Muster PartG mbB');
      expect(kanzlei['bea_safe_id'], 'DE.DUMP.0001');
    });

    test('raListe und raKarte lesen BEIDE Formen', () {
      // Wurzel …
      expect(raListe({'items': [{'a': 1}]}), hasLength(1));
      // … und Dach, falls ein Endpunkt es je so schickt.
      expect(raListe({'data': {'items': [{'a': 1}, {'b': 2}]}}), hasLength(2));
      expect(raKarte({'k': {'x': 1}}, 'k')['x'], 1);
      expect(raKarte({'data': {'k': {'x': 2}}}, 'k')['x'], 2);
    });

    test('eine leere Liste ist kein Absturz und kein null', () {
      expect(raListe(j(listVollmachtenLeer)), isEmpty);
      expect(raListe({'success': true}), isEmpty);
      expect(raKarte({'success': true}, 'data'), isEmpty);
    });

    test('eine Liste, wo eine Map erwartet wird, wirft NICHT', () {
      // Genau der Speedtest-Fehler: PHP kodiert ein lückenloses Array als
      // Liste, der Client las es als Map, `as Map?` warf statt null zu
      // geben, und im Release-Build blieb eine graue Fläche.
      expect(raKarte({'stufen': <dynamic>[]}, 'stufen'), isEmpty);
      expect(raListe({'stufen': <String, dynamic>{}}, 'stufen'), isEmpty);
    });
  });

  group('Mahnverfahren und Fristen', () {
    test('stufen ist ein Objekt, fristen eine Liste', () {
      final res = j(getMahnverfahren);
      expect(res['stufen'], isA<Map>(), reason: 'String-Schlüssel → PHP kodiert als Objekt');
      expect(res['fristen'], isA<List>());
      expect((res['stufen'] as Map), hasLength(10));
    });

    test('die drei Fristen tragen Norm, Datum und Dringlichkeit', () {
      final fristen = raListe(j(getMahnverfahren), 'fristen');
      expect(fristen.map((f) => f['schluessel']),
          containsAll(['widerspruch', 'einspruch', 'mb_wirkung']));

      final einspruch = fristen.firstWhere((f) => f['schluessel'] == 'einspruch');
      expect(einspruch['datum'], '2026-08-17');
      expect(einspruch['notfrist'], isTrue);
      expect(einspruch['norm'], contains('§ 339 Abs. 1 ZPO'));

      final widerspruch = fristen.firstWhere((f) => f['schluessel'] == 'widerspruch');
      expect(widerspruch['dringlichkeit'], 'abgelaufen');
      // Bei erlassenem Vollstreckungsbescheid ist der Widerspruch nach
      // § 694 Abs. 1 ZPO endgültig weg — das muss der Hinweis auch sagen.
      expect(widerspruch['hinweis'], contains('§ 694 Abs. 1 ZPO'));
    });

    test('nur der Einspruch ist Notfrist', () {
      final fristen = raListe(j(getMahnverfahren), 'fristen');
      final notfristen = fristen.where((f) => f['notfrist'] == true).map((f) => f['schluessel']);
      expect(notfristen, ['einspruch'],
          reason: '§ 701 und § 692 sind keine Notfristen — wer sie so kennzeichnet, '
              'macht die Kennzeichnung wertlos');
    });

    test('die Reihenfolge stellt das Dringende nach vorn, nicht das Älteste', () {
      // ⚠️ Reine Datumssortierung wäre falsch, und man sieht es erst am
      // gerenderten Bild: die am 15.06. abgelaufene Widerspruchsfrist, gegen
      // die es nichts mehr zu tun gibt, stand über der Notfrist, die in drei
      // Tagen abläuft. Das Wichtigste stand an zweiter Stelle.
      final fristen = raListe(j(getMahnverfahren), 'fristen');
      expect(fristen.map((f) => f['schluessel']).toList(),
          ['einspruch', 'mb_wirkung', 'widerspruch']);
      expect(fristen.first['dringlichkeit'], 'bald');
      expect(fristen.last['dringlichkeit'], 'abgelaufen',
          reason: 'was vorbei und keine Notfrist ist, gehört ans Ende');
    });

    test('der Vorbehalt zur Fristenrechnung fehlt nie', () {
      final res = j(getMahnverfahren);
      expect(raWert(res['vorbehalt']), contains('§ 222 Abs. 2 ZPO'));
      expect(raWert(res['vorbehalt']), contains('landesrechtliche Feiertage'));
    });

    test('Wahrheitswerte kommen als 0/1, nicht als true/false', () {
      // Deshalb prüft die Oberfläche überall `== 1 || == true` — ein reiner
      // `as bool` läge hier daneben.
      final d = raKarte(j(getMahnverfahren), 'data');
      expect(d['zustellung_ausland'], 0);
      expect(d['erledigt'], 0);
      expect(d['zustellung_ausland'] is bool, isFalse);
    });
  });

  group('Listeneinträge tragen die Zusammenfassung für die Akte', () {
    test('Mahnstufe, offene Fristen und Vollmacht stehen am Eintrag', () {
      final a = raListe(j(listAktenzeichen)).first;
      expect(a['mahn_stufe'], 'vb_zugestellt');
      expect(a['hat_mahnverfahren'], isTrue);
      expect(a['fristen_offen'], 2);
      expect(a['vollmacht_aktiv'], isFalse);
    });

    test('fristen_offen zählt nur, was drängt', () {
      // Drei Fristen, aber nur zwei sind heute/bald/abgelaufen — die dritte
      // läuft erst im Dezember. Eine Zahl, die auch ferne Termine mitzählt,
      // wird nach einer Woche ignoriert.
      final fristen = raListe(j(getMahnverfahren), 'fristen');
      final draengend = fristen
          .where((f) => ['heute', 'bald', 'abgelaufen'].contains(f['dringlichkeit']))
          .length;
      expect(fristen, hasLength(3));
      expect(draengend, 2);
      expect(raListe(j(listAktenzeichen)).first['fristen_offen'], draengend);
    });
  });

  group('Verschlüsselte Felder überleben den Weg', () {
    test('Umlaute kommen unversehrt zurück', () {
      final k = raListe(j(listKorrespondenz)).first;
      expect(k['text'], 'Text mit Umlauten: äöüß');
      expect(k['betreff'], 'Sachstand');
    });
  });

  group('ENUM-Kopplung Client ↔ Server', () {
    test('der Server nennt bei Ablehnung genau unsere Mandatsstatus', () {
      // ⚠️ Das PHP liegt in keinem Repository. Diese Prüfung ist die einzige
      // Stelle, an der ein Auseinanderlaufen von Datenbankspalte, `ENUMS`
      // im Endpunkt und der Liste im Client überhaupt auffallen kann.
      final message = raWert(j(fehlerEnum)['message']);
      expect(j(fehlerEnum)['success'], isFalse);
      for (final wert in RaEnums.mandatStatus) {
        expect(message, contains(wert),
            reason: '$wert fehlt in der Serverliste — Client und Server '
                'sind auseinandergelaufen');
      }
      // Und andersherum: der Server nennt nichts, was der Client nicht kennt.
      final serverListe = message.split('erlaubt sind:').last.split(',').map((e) => e.trim()).toList();
      expect(serverListe.toSet(), RaEnums.mandatStatus.toSet());
    });

    test('gelieferte Werte liegen alle in den bekannten Mengen', () {
      final a = raListe(j(listAktenzeichen)).first;
      expect(RaEnums.aktenzeichenStatus, contains(a['status']));
      expect(RaEnums.mahnStufe, contains(a['mahn_stufe']));

      final m = raKarte(j(getMahnverfahren), 'data');
      expect(RaEnums.mahnRolle, contains(m['rolle']));
      expect(RaEnums.mahnStufe, contains(m['stufe']));
      expect(RaEnums.widerspruchUmfang, contains(m['widerspruch_umfang']));

      final k = raListe(j(listKorrespondenz)).first;
      expect(RaEnums.korrRichtung, contains(k['richtung']));
      expect(RaEnums.korrMedium, contains(k['medium']));

      expect(RaEnums.mandatStatus, contains(raKarte(j(getMandat), 'data')['status']));
    });

    test('die Stufenliste des Servers deckt sich mit RaEnums.mahnStufe', () {
      final stufen = (j(getMahnverfahren)['stufen'] as Map).keys.map((e) => e.toString()).toList();
      expect(stufen.toSet(), RaEnums.mahnStufe.toSet());
    });
  });

  group('Datumsformate', () {
    test('ISO wird deutsch angezeigt', () {
      expect(raDatumDe('2026-08-14'), '14.08.2026');
      expect(raDatumDe('2026-08-03'), '03.08.2026');
      expect(raDatumDe('2026-08-14 13:38:18'), '14.08.2026');
    });

    test('leer bleibt leer — kein erfundenes Datum auf einem Fristenblatt', () {
      expect(raDatumDe(null), '');
      expect(raDatumDe(''), '');
      expect(raDatumDe('0000-00-00'), '');
      expect(raDatumDe('   '), '');
    });

    test('Unlesbares verschwindet nicht still', () {
      expect(raDatumDe('demnächst'), 'demnächst');
    });

    test('raIso liefert genau das, was der Server annimmt', () {
      expect(raIso(DateTime(2026, 8, 14)), '2026-08-14');
      expect(raIso(DateTime(2026, 1, 2)), '2026-01-02');
      expect(raIso(null), '');
      // ⚠️ Der Server weist alles andere mit HTTP 400 ab, auch das deutsche
      // Format: '01.07.2026' würde in MariaDB zu 0000-00-00 und sähe dann
      // aus wie „kein Datum erfasst".
      expect(raIso(DateTime(2026, 7, 1)), isNot('01.07.2026'));
    });
  });

  group('raWert / raHat', () {
    test('null, Zahlen und Leerraum', () {
      expect(raWert(null), '');
      expect(raWert('  x  '), 'x');
      expect(raWert(2), '2');
      expect(raHat(null), isFalse);
      expect(raHat('   '), isFalse);
      expect(raHat(0), isTrue, reason: 'die Zahl 0 ist ein Wert, kein leeres Feld');
    });
  });
}
