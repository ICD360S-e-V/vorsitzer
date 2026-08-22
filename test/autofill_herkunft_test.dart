import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/autofill_herkunft.dart';

void main() {
  group('autofillHerkunft', () {
    test('gibt den Host im Format von location.host zurück', () {
      expect(autofillHerkunft('https://portal.firma.de/login'), 'portal.firma.de');
    });

    test('schreibt den Host klein — location.host tut das auch', () {
      expect(autofillHerkunft('https://Portal.FIRMA.de'), 'portal.firma.de');
    });

    test('lässt den Standardport weg, auch wenn er dasteht', () {
      // `location.host` zeigt bei :443 nichts an. Stünde er hier, verglichen
      // wir 'a.de:443' gegen 'a.de' und das Auto-Ausfüllen bliebe für immer aus.
      expect(autofillHerkunft('https://a.de:443/x'), 'a.de');
    });

    test('behält einen abweichenden Port', () {
      expect(autofillHerkunft('https://a.de:8443/x'), 'a.de:8443');
    });

    test('verweigert http — auf dem Desktop greift der Manifest-Schalter nicht',
        () {
      expect(autofillHerkunft('http://portal.firma.de'), isNull);
    });

    test('verweigert Unsinn statt zu raten', () {
      expect(autofillHerkunft(null), isNull);
      expect(autofillHerkunft(''), isNull);
      expect(autofillHerkunft('   '), isNull);
      expect(autofillHerkunft('portal.firma.de'), isNull); // ohne Schema
      expect(autofillHerkunft('https://'), isNull); // ohne Host
      expect(autofillHerkunft('javascript:alert(1)'), isNull);
      expect(autofillHerkunft('file:///etc/passwd'), isNull);
    });

    test('ein Unterdomain ist NICHT dieselbe Herkunft', () {
      // Das ist die Entscheidung „exakter Host". Wenn ein Portal zum Anmelden
      // wirklich umleitet, fällt das hier auf — und zwar als bewusste Wahl,
      // nicht als Zufall.
      expect(autofillHerkunft('https://portal.firma.de'),
          isNot(autofillHerkunft('https://login.firma.de')));
    });
  });

  group('jsLiteral', () {
    test('erzeugt ein gültiges, gequotetes JS-Literal', () {
      expect(jsLiteral('abc'), '"abc"');
    });

    test('überlebt Anführungszeichen und Backslashes', () {
      for (final wert in [
        "a'b",
        'a"b',
        r'a\b',
        r"'; alert(1); var x='",
        r'\"; alert(1); //',
      ]) {
        // Rundlauf: was als JSON hineingeht, muss unverändert herauskommen.
        expect(jsonDecode(jsLiteral(wert)), wert, reason: 'bei: $wert');
      }
    });

    test('überlebt einen Zeilenumbruch im Passwort', () {
      // Genau daran zerbrach die Vorgängerfassung: sie maskierte nur \\ und ',
      // ein \n zerriss das Literal und das Skript starb am Syntaxfehler.
      const pass = 'zeile1\nzeile2';
      final lit = jsLiteral(pass);
      expect(lit.contains('\n'), isFalse,
          reason: 'ein roher Umbruch im Literal zerreißt das Skript');
      expect(jsonDecode(lit), pass);
    });

    test('maskiert U+2028/U+2029, die vor ES2019 Zeilenenden sind', () {
      // ⚠️ Die Zeichen werden hier aus dem Codepunkt gebaut, nicht getippt.
      // Ein unsichtbares Zeichen im Quelltext eines Tests ist genau die Falle,
      // die dieser Test bewachen soll — beim Schreiben dieser Datei hat ein
      // Editor sie zweimal still in Leerzeichen verwandelt.
      final ls = String.fromCharCode(0x2028);
      final ps = String.fromCharCode(0x2029);

      expect(jsLiteral('a${ls}b'), r'"a\u2028b"');
      expect(jsLiteral('a${ps}b'), r'"a\u2029b"');
      expect(jsLiteral('a${ls}b').contains(ls), isFalse,
          reason: 'das rohe Zeichen darf nicht stehen bleiben');
      expect(jsonDecode(jsLiteral('a${ls}b')), 'a${ls}b',
          reason: 'maskiert, aber inhaltlich unverändert');
    });

    test('ein Leerzeichen bleibt ein Leerzeichen', () {
      // Wachhund gegen genau den Unfall, der beim Schreiben dieser Datei
      // passiert ist: stünde in der Maskierung ein Leerzeichen statt U+2028,
      // würde hier jedes Leerzeichen zu \\u2028 — und jedes Passwort mit
      // Leerzeichen wäre still kaputt.
      expect(jsonDecode(jsLiteral('mein passwort mit leerzeichen')),
          'mein passwort mit leerzeichen');
      expect(jsLiteral('a b').contains('u2028'), isFalse,
          reason: 'ein Leerzeichen ist kein Zeilentrenner');
    });
  });

  group('autofillSkript', () {
    String skript({
      String herkunft = 'portal.firma.de',
      String benutzer = 'nutzer',
      String passwort = 'geheim',
    }) =>
        autofillSkript(
            herkunft: herkunft, benutzer: benutzer, passwort: passwort);

    test('prüft die Herkunft, BEVOR es irgendetwas einträgt', () {
      // Der Kern der Reparatur. Beide Prüfungen müssen vor dem ersten
      // setNativeValue stehen, sonst ist die Reihenfolge wirkungslos.
      final js = skript();
      final tls = js.indexOf("location.protocol !== 'https:'");
      final host = js.indexOf('location.host');
      final ersterSchreibzugriff = js.indexOf('setNativeValue(userField');

      expect(tls, greaterThanOrEqualTo(0));
      expect(host, greaterThanOrEqualTo(0));
      expect(tls, lessThan(ersterSchreibzugriff));
      expect(host, lessThan(ersterSchreibzugriff));
    });

    test('vergleicht gegen genau die übergebene Herkunft', () {
      expect(skript(herkunft: 'portal.firma.de'),
          contains('!== "portal.firma.de"'));
    });

    test('trägt nichts ein, wenn kein Passwortfeld da ist', () {
      final js = skript();
      final wache = js.indexOf('if (!passField) return');
      expect(wache, greaterThanOrEqualTo(0));
      expect(wache, lessThan(js.indexOf('setNativeValue(userField')),
          reason: 'ohne Anmeldeformular landet der Benutzername im Suchfeld');
    });

    test('ein Anführungszeichen in der Herkunft bricht nicht aus', () {
      // Die Herkunft stammt aus einem Datensatz auf dem Server, ist also
      // nicht vertrauenswürdiger als der Rest.
      final js = skript(herkunft: 'a.de" || true || "');
      expect(js, isNot(contains('|| true ||   ')));
      expect(js, contains(r'a.de\" || true || \"'));
    });

    test('Zugangsdaten mit Sonderzeichen brechen nicht aus dem Literal aus',
        () {
      final js = skript(
        benutzer: "'; alert('user'); //",
        passwort: r'p"a\s;s',
      );
      // Beide Werte müssen als JSON-Literale dastehen, nicht als Code.
      expect(js, contains(jsLiteral("'; alert('user'); //")));
      expect(js, contains(jsLiteral(r'p"a\s;s')));
    });

    test('die Rückgabecodes stimmen mit den Konstanten überein', () {
      // Die Zahlen stehen im JS und werden in Dart ausgewertet — sie dürfen
      // nicht auseinanderlaufen.
      final js = skript();
      expect(js, contains('return ${AutofillErgebnis.keinTls};'));
      expect(js, contains('return ${AutofillErgebnis.falscheHerkunft};'));
      expect(js, contains('return ${AutofillErgebnis.keinFormular};'));
      expect(AutofillErgebnis.keinTls, lessThan(0));
      expect(AutofillErgebnis.falscheHerkunft, lessThan(0));
      expect(AutofillErgebnis.keinFormular, 0);
    });
  });
}
