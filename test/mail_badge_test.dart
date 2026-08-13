import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/mail_badge_service.dart';

/// Das Abzeichen am Briefsymbol im Kopf zählt ungelesene Post im Eingang.
/// Die Zahl kommt aus `mail/folders.php`; hier steht fest, wie sie gelesen
/// wird — inklusive der Fälle, in denen sie NICHT auf null fallen darf.
void main() {
  group('mailUngeleseneAusAntwort', () {
    test('liest den Eingang, nicht den ersten Ordner', () {
      final antwort = {
        'success': true,
        'folders': [
          {'box': 'Drafts', 'total': 2, 'unseen': 2},
          {'box': 'INBOX', 'total': 8, 'unseen': 3},
          {'box': 'Junk', 'total': 40, 'unseen': 40},
        ],
      };
      expect(mailUngeleseneAusAntwort(antwort), 3);
    });

    test('Spam und Entwürfe zählen nicht mit', () {
      // Sonst leuchtet das Abzeichen dauerhaft wegen Werbung, und dann fällt
      // die eine echte Mail auch nicht mehr auf.
      final antwort = {
        'success': true,
        'folders': [
          {'box': 'INBOX', 'total': 8, 'unseen': 0},
          {'box': 'Junk', 'total': 40, 'unseen': 40},
          {'box': 'Drafts', 'total': 2, 'unseen': 2},
        ],
      };
      expect(mailUngeleseneAusAntwort(antwort), 0);
    });

    test('ohne Eingang in der Antwort: null, nicht 0', () {
      // null heisst „unbekannt". Eine 0 würde ein zu Recht stehendes
      // Abzeichen löschen, obwohl der Server nichts dergleichen gesagt hat.
      expect(mailUngeleseneAusAntwort({'success': true, 'folders': []}), isNull);
      expect(mailUngeleseneAusAntwort({'success': true}), isNull);
    });

    test('versteht auch eine nach Ordnernamen geschlüsselte Map', () {
      final antwort = {
        'success': true,
        'folders': {
          'INBOX': {'box': 'INBOX', 'total': 8, 'unseen': 5},
        },
      };
      expect(mailUngeleseneAusAntwort(antwort), 5);
    });

    test('fehlendes oder unsinniges unseen wird nicht negativ', () {
      expect(
        mailUngeleseneAusAntwort({
          'folders': [
            {'box': 'INBOX', 'total': 8}
          ]
        }),
        0,
      );
      expect(
        mailUngeleseneAusAntwort({
          'folders': [
            {'box': 'INBOX', 'unseen': -1}
          ]
        }),
        0,
      );
    });
  });

  group('MailBadgeService', () {
    test('setzeAusOrdnern hält den Zähler bei 0 oder darüber', () {
      final dienst = MailBadgeService();
      dienst.setzeAusOrdnern(4);
      expect(dienst.unreadCount.value, 4);
      dienst.setzeAusOrdnern(0);
      expect(dienst.unreadCount.value, 0);
      dienst.setzeAusOrdnern(-3);
      expect(dienst.unreadCount.value, 0);
    });

    test('ist ein Singleton — Kopf und Mail-Bildschirm teilen den Zähler', () {
      // Sonst schreibt der Mail-Bildschirm in eine eigene Instanz und das
      // Abzeichen im Kopf bleibt stehen, obwohl alles gelesen ist.
      expect(identical(MailBadgeService(), MailBadgeService()), isTrue);
    });
  });
}
