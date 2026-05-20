// Tests for the vormund-kinder Termin aggregation feature:
// - Termin.fromJson reads the new participant_* fields from my_termine.php
// - Termin.forKindBadge(selfMnr) returns the right child label
// - isKindTermin reports jugendmitglied role correctly

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/termin_service.dart';

Map<String, dynamic> _baseTerminJson({
  int id = 1,
  String? participantMnr,
  String? participantVorname,
  String? participantNachname,
  String? participantRole,
  int? participantUserId,
}) {
  return {
    'id': id,
    'title': 'Test Termin',
    'category': 'sonstiges',
    'description': '',
    'termin_date': '2026-05-21 13:25:00',
    'duration_minutes': 60,
    'location': '',
    'created_by': 1,
    'status': 'scheduled',
    'created_at': '2026-05-20 10:00:00',
    if (participantUserId != null) 'participant_user_id': participantUserId,
    if (participantVorname != null) 'participant_vorname': participantVorname,
    if (participantNachname != null) 'participant_nachname': participantNachname,
    if (participantMnr != null) 'participant_mitgliedernummer': participantMnr,
    if (participantRole != null) 'participant_role': participantRole,
  };
}

void main() {
  group('Termin.fromJson parses participant_* fields', () {
    test('all participant fields are read when present', () {
      final t = Termin.fromJson(_baseTerminJson(
        participantUserId: 54,
        participantVorname: 'mykhailo',
        participantNachname: 'tsynhalov',
        participantMnr: 'J23960',
        participantRole: 'jugendmitglied',
      ));
      expect(t.participantUserId, 54);
      expect(t.participantVorname, 'mykhailo');
      expect(t.participantNachname, 'tsynhalov');
      expect(t.participantMitgliedernummer, 'J23960');
      expect(t.participantRole, 'jugendmitglied');
    });

    test('participant_user_id parses from string too', () {
      final t = Termin.fromJson(_baseTerminJson(participantUserId: null)..['participant_user_id'] = '99');
      expect(t.participantUserId, 99);
    });

    test('missing participant fields stay null (back-compat)', () {
      final t = Termin.fromJson(_baseTerminJson());
      expect(t.participantUserId, isNull);
      expect(t.participantMitgliedernummer, isNull);
      expect(t.participantRole, isNull);
    });
  });

  group('forKindBadge', () {
    test('returns null when self == participant (own termin, no badge)', () {
      final t = Termin.fromJson(_baseTerminJson(
        participantMnr: 'M82983',
        participantVorname: 'Olha',
        participantNachname: 'Pasichnyk',
        participantRole: 'mitglied',
      ));
      expect(t.forKindBadge('M82983'), isNull);
    });

    test('returns child full name when participant differs from self', () {
      final t = Termin.fromJson(_baseTerminJson(
        participantMnr: 'J23960',
        participantVorname: 'mykhailo',
        participantNachname: 'tsynhalov',
        participantRole: 'jugendmitglied',
      ));
      expect(t.forKindBadge('M82983'), 'mykhailo tsynhalov');
    });

    test('falls back to Mitgliedernummer when name parts missing', () {
      final t = Termin.fromJson(_baseTerminJson(
        participantMnr: 'J23960',
        participantRole: 'jugendmitglied',
      ));
      expect(t.forKindBadge('M82983'), 'J23960');
    });

    test('returns null when no participant info present (legacy server)', () {
      final t = Termin.fromJson(_baseTerminJson());
      expect(t.forKindBadge('M82983'), isNull);
    });
  });

  group('isKindTermin', () {
    test('true for jugendmitglied role', () {
      final t = Termin.fromJson(_baseTerminJson(participantRole: 'jugendmitglied'));
      expect(t.isKindTermin, isTrue);
    });

    test('false for mitglied / vorsitzer / etc', () {
      for (final r in ['mitglied', 'vorsitzer', 'schatzmeister']) {
        final t = Termin.fromJson(_baseTerminJson(participantRole: r));
        expect(t.isKindTermin, isFalse, reason: 'role=$r should not be kind');
      }
    });

    test('false when participant_role absent', () {
      final t = Termin.fromJson(_baseTerminJson());
      expect(t.isKindTermin, isFalse);
    });
  });
}
