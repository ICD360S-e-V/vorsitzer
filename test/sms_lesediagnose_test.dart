import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sms_service.dart';

/// Die Lesediagnose beantwortet auf dem Vereins-Tablet die einzige Frage, an
/// der das Nachlesen eingehender SMS scheitern kann: **darf diese Installation
/// auf diesem Gerät überhaupt lesen?**
///
/// ⚠️ Warum das eine eigene Zustandsmaschine ist: Android liefert ohne
/// READ_SMS **null Zeilen, ohne zu scheitern**. Von aussen ist das nicht von
/// „es hat niemand geschrieben" zu unterscheiden — und genau so blieb der
/// SMS-Verlauf monatelang leer, ohne dass irgendwo ein Fehler stand.
///
/// Die vier Lagen sehen an der Oberfläche gleich aus und brauchen völlig
/// verschiedene Handgriffe:
///
/// | Lage | was hilft |
/// |---|---|
/// | `fragenMoeglich` | der Systemdialog |
/// | `dialogBleibtAus` + Android ≥ 15 | **ein Tipp in der App-Info** (ECM) |
/// | `dialogBleibtAus` + Android < 15 | nur ein anderer Installationsweg |
/// | `vomInstallerBlockiert` | nur ein anderer Installationsweg |
void main() {
  SmsReadDiagnose diag({
    bool permission = false,
    String appOp = 'allowed',
    bool cursorOk = false,
    int rowCount = -1,
    int sdkInt = 36,
    bool dialogBliebAus = false,
    String? fehler,
  }) =>
      SmsReadDiagnose(
        permission: permission,
        appOp: appOp,
        cursorOk: cursorOk,
        rowCount: rowCount,
        hasActivity: true,
        sdkInt: sdkInt,
        fehler: fehler,
        dialogBliebAus: dialogBliebAus,
      );

  group('Lage', () {
    test('kein Android / zu alte App-Version', () {
      expect(diag(sdkInt: 0).lage, SmsReadLage.nichtUnterstuetzt);
      expect(const SmsReadDiagnose.nichtUnterstuetzt().lage,
          SmsReadLage.nichtUnterstuetzt);
    });

    test('nicht erteilt und noch nie gefragt — der Dialog kann helfen', () {
      expect(diag().lage, SmsReadLage.fragenMoeglich);
    });

    test('gefragt, kein Dialog erschienen — der Knopf „Anfragen" hilft nicht mehr',
        () {
      // Vor der Reparatur blieb es bei `fragenMoeglich`: die Seite bot weiter
      // „Anfragen" an, und jeder Tipp tat wieder nichts.
      expect(diag(dialogBliebAus: true).lage, SmsReadLage.dialogBleibtAus);
    });

    test('erteilt, App-Op offen, Abfrage lief — es geht wirklich', () {
      expect(diag(permission: true, cursorOk: true, rowCount: 812).lage,
          SmsReadLage.bereit);
    });

    test('erteilt, aber App-Op ignored — die stille Falle', () {
      // checkSelfPermission meldet GRANTED, die Abfrage gibt null Zeilen
      // zurück und wirft nichts. Ohne den App-Op-Wert wäre das von „keine SMS
      // vorhanden" nicht zu unterscheiden.
      for (final op in ['ignored', 'errored']) {
        expect(diag(permission: true, appOp: op, cursorOk: true).lage,
            SmsReadLage.vomInstallerBlockiert,
            reason: 'appOp=$op');
      }
    });

    test('erteilt, App-Op offen, Abfrage scheitert trotzdem', () {
      expect(diag(permission: true, fehler: 'security: denied').lage,
          SmsReadLage.lesefehler);
    });

    test('nur `bereit` gilt als funktionierend', () {
      expect(diag(permission: true, cursorOk: true).funktioniert, isTrue);
      expect(diag().funktioniert, isFalse);
      expect(diag(dialogBliebAus: true).funktioniert, isFalse);
      expect(diag(permission: true, appOp: 'ignored', cursorOk: true).funktioniert,
          isFalse);
    });
  });

  group('Enhanced Confirmation Mode ab Android 15', () {
    // ECM ist neu in API 35 und prüft eine Allowlist aus dem Werksabbild
    // (/system/etc/sysconfig). Unser eigenes F-Droid-Repo steht dort nie
    // darauf, also erscheint gar kein Dialog — behebbar mit einem Tipp in der
    // App-Info. Darunter gibt es ECM nicht, dort bleibt nur der
    // Installationsweg.
    test('die Schwelle liegt genau bei API 35', () {
      expect(diag(sdkInt: 34).ecmMoeglich, isFalse, reason: 'Android 14');
      expect(diag(sdkInt: 35).ecmMoeglich, isTrue, reason: 'Android 15');
      expect(diag(sdkInt: 36).ecmMoeglich, isTrue, reason: 'Android 16');
      expect(diag(sdkInt: 37).ecmMoeglich, isTrue, reason: 'Android 17');
    });

    test('ab Android 15 nennt der Text den begehbaren Weg', () {
      final u = diag(sdkInt: 35, dialogBliebAus: true).urteil;
      expect(u, contains('App-Info'));
      expect(u, contains('Android 15'));
    });

    test('⚠️ REGRESSION: unter Android 15 darf NICHT auf die App-Info verwiesen '
        'werden — dort gibt es die Freigabe gar nicht', () {
      final u = diag(sdkInt: 34, dialogBliebAus: true).urteil;
      expect(u, isNot(contains('App-Info')));
      expect(u, contains('Installation'));
    });

    test('⚠️ REGRESSION: ab Android 15 darf es NICHT „aussichtslos" heissen', () {
      // Genau das stand vorher da — und schickte den Vorsitzer nach Hause,
      // obwohl ein einziger Tipp gereicht hätte.
      final u = diag(sdkInt: 36, dialogBliebAus: true).urteil;
      expect(u, isNot(contains('darf READ_SMS nicht erhalten')));
    });
  });

  group('copyWith', () {
    test('trägt den belegten Fehlschlag über ein Neuladen hinweg', () {
      // Ohne das würde jedes Neuladen der Seite wieder „Anfragen" anbieten.
      final frisch = diag();
      expect(frisch.lage, SmsReadLage.fragenMoeglich);
      expect(frisch.copyWith(dialogBliebAus: true).lage,
          SmsReadLage.dialogBleibtAus);
    });

    test('lässt alles andere unangetastet', () {
      final d = diag(permission: true, cursorOk: true, rowCount: 42, appOp: 'allowed');
      final k = d.copyWith(dialogBliebAus: true);
      expect(k.permission, d.permission);
      expect(k.appOp, d.appOp);
      expect(k.cursorOk, d.cursorOk);
      expect(k.rowCount, d.rowCount);
      expect(k.sdkInt, d.sdkInt);
    });
  });
}
