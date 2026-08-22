import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mobilfunk_anbieter.dart';

void main() {
  group('Suche', () {
    test('leere Eingabe zeigt alle Anbieter', () {
      expect(mobilfunkAnbieterSuchen('').length, kMobilfunkAnbieter.length);
      expect(mobilfunkAnbieterSuchen('   ').length, kMobilfunkAnbieter.length);
    });

    test('Name getippt: der Anbieter steht an erster Stelle', () {
      for (final gesucht in ['telekom', 'vodafone', 'o2', 'congstar', 'aldi talk']) {
        final t = mobilfunkAnbieterSuchen(gesucht);
        expect(t, isNotEmpty, reason: '„$gesucht“ findet nichts');
        expect(mobilfunkSchluessel(t.first.name).contains(mobilfunkSchluessel(gesucht)) ||
               t.first.alias.any((a) => mobilfunkSchluessel(a).contains(mobilfunkSchluessel(gesucht))),
            isTrue,
            reason: 'Erster Treffer für „$gesucht“ ist ${t.first.name}');
      }
    });

    test('Schreibweise ist egal', () {
      // Genau die Formen, die jemand von seiner Rechnung abtippt.
      for (final e in ['Telekom', 'TELEKOM', 't-mobile', 'Deutsche Telekom', 'D1']) {
        expect(mobilfunkAnbieterFinden(e)?.name, 'Telekom', reason: e);
      }
      for (final e in ['o2', 'O2', 'O₂', 'Telefónica', 'o2 telefonica']) {
        expect(mobilfunkAnbieterFinden(e)?.name, 'O2', reason: e);
      }
      for (final e in ['1&1', '1und1', '1 und 1', 'Drillisch']) {
        expect(mobilfunkAnbieterFinden(e)?.name, '1&1', reason: e);
      }
    });

    test('Suche nach dem Netz zeigt auch die Zweitmarken', () {
      final namen = mobilfunkAnbieterSuchen('vodafone').map((a) => a.name).toSet();
      expect(namen, containsAll(['Vodafone', 'otelo', 'LIDL Connect', 'SIMon mobile']));

      final telekom = mobilfunkAnbieterSuchen('telekom').map((a) => a.name).toSet();
      expect(telekom, containsAll(['Telekom', 'congstar', 'fraenk']));
    });

    test('unbekannter Anbieter bleibt unbekannt', () {
      expect(mobilfunkAnbieterFinden('Irgendein Laden GmbH'), isNull);
      expect(mobilfunkAnbieterFinden(''), isNull);
      expect(mobilfunkAnbieterFinden(null), isNull);
    });

    test('kein Treffer über eine bloße Teilzeichenkette', () {
      // „sim“ steckt in winSIM, PremiumSIM, sim.de, Mega SIM, SIM 24, Black SIM,
      // CyberSIM. Würde finden() per contains arbeiten, bekäme ein Vertrag den
      // Kündigungsknopf eines fremden Anbieters.
      expect(mobilfunkAnbieterFinden('sim'), isNull);
      expect(mobilfunkAnbieterFinden('mobil'), isNull);
    });
  });

  group('Datenbestand', () {
    test('keine doppelten Namen', () {
      final schluessel = kMobilfunkAnbieter.map((a) => mobilfunkSchluessel(a.name)).toList();
      expect(schluessel.toSet().length, schluessel.length,
          reason: 'Doppelter Anbietername in der Liste');
    });

    test('kein Alias zeigt auf zwei Anbieter', () {
      // Sonst hinge das Ergebnis von finden() an der Reihenfolge der Liste —
      // und die ändert sich beim nächsten Einsortieren stillschweigend.
      // Sammelt ALLE Kollisionen und meldet sie zusammen. Ein Abbruch beim
      // ersten Treffer hieße: für jede Dublette ein eigener Testlauf.
      final gesehen = <String, String>{};
      final klagen = <String>[];
      for (final a in kMobilfunkAnbieter) {
        for (final al in [a.name, ...a.alias]) {
          final k = mobilfunkSchluessel(al);
          if (gesehen.containsKey(k)) {
            klagen.add(gesehen[k] == a.name
                ? '„$al“ ist bei ${a.name} überflüssig — die Normalisierung deckt es schon ab'
                : '„$al“ gehört zu ${a.name} und zu ${gesehen[k]}');
          }
          gesehen[k] = a.name;
        }
      }
      expect(klagen, isEmpty, reason: klagen.join('\n'));
    });

    test('jeder Kündigungslink ist eine https-Adresse', () {
      for (final a in kMobilfunkAnbieter.where((x) => x.hatKuendigungOnline)) {
        final u = Uri.tryParse(a.kuendigungUrl!);
        expect(u, isNotNull, reason: a.name);
        expect(u!.scheme, 'https', reason: '${a.name}: ${a.kuendigungUrl}');
        expect(u.host, isNotEmpty, reason: a.name);
      }
    });

    test('die vier Netzbetreiber haben eine Online-Kündigung', () {
      // Genau die drei, nach denen im Alltag gefragt wird — plus 1&1.
      for (final n in ['Telekom', 'Vodafone', 'O2', '1&1']) {
        final a = mobilfunkAnbieterFinden(n);
        expect(a, isNotNull, reason: n);
        expect(a!.hatKuendigungOnline, isTrue, reason: '$n ohne Kündigungslink');
      }
    });

    test('jeder Anbieter trägt Netz und Art', () {
      for (final a in kMobilfunkAnbieter) {
        expect(a.name.trim(), isNotEmpty);
        expect(a.netz.trim(), isNotEmpty, reason: a.name);
        expect(a.art.trim(), isNotEmpty, reason: a.name);
      }
    });

    test('die alte fest verdrahtete Liste wird weiter erkannt', () {
      // Genau diese 16 Zeichenketten stehen in bereits gespeicherten Verträgen,
      // weil sie bis zur Umstellung die Vorschlagsliste im Formular waren.
      // Werden sie nicht mehr erkannt, verlieren Altverträge stillschweigend
      // Netzanzeige und Kündigungsknopf.
      const alt = [
        'Telekom', 'Vodafone', 'O2 / Telefónica', '1&1', 'congstar', 'ALDI TALK',
        'LIDL Connect', 'Blau', 'Drillisch', 'Lebara', 'Lycamobile', 'simplytel',
        'PremiumSIM', 'winSIM', 'fraenk', 'freenet',
      ];
      for (final e in alt) {
        expect(mobilfunkAnbieterFinden(e), isNotNull, reason: 'Altwert „$e“ wird nicht erkannt');
      }
    });

    test('Namensliste und Datenbank bleiben deckungsgleich', () {
      expect(kMobilfunkAnbieterNamen.length, kMobilfunkAnbieter.length);
      expect(kMobilfunkAnbieterNamen.first, kMobilfunkAnbieter.first.name);
    });
  });
}
