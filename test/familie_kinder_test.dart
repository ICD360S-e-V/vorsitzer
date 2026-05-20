// Tests for the Familie/Kinder feature foundation:
// - jugendmitglied role plumbing in role_helpers.dart
// - vormundUserId field on User model
// - calculateAge / isMinor helpers
//
// Phase 1: foundation only. UI dialog tested manually via flutter run.

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/user.dart';
import 'package:icd360sev_vorsitzer/utils/role_helpers.dart';

void main() {
  group('jugendmitglied role plumbing', () {
    test('getRoleText returns Jugendmitglied', () {
      expect(getRoleText('jugendmitglied'), 'Jugendmitglied');
    });

    test('getRolePrefix returns J', () {
      expect(getRolePrefix('jugendmitglied'), 'J');
    });

    test('isJugendmitglied identifies the role', () {
      expect(isJugendmitglied('jugendmitglied'), isTrue);
      expect(isJugendmitglied('mitglied'), isFalse);
      expect(isJugendmitglied('vorsitzer'), isFalse);
    });

    test('jugendmitglied is NOT an admin or Vorstand role', () {
      expect(isAdminRole('jugendmitglied'), isFalse,
          reason: 'Children must not be granted admin permissions');
      expect(isVorstandRole('jugendmitglied'), isFalse,
          reason: 'Children cannot serve on the Vorstand');
    });

    test('jugendmitglied appears in allRoles dropdown', () {
      final values = allRoles.map((e) => e['value']).toList();
      expect(values, contains('jugendmitglied'));
    });

    test('isValidMitgliedernummer accepts J + 5 digits', () {
      expect(isValidMitgliedernummer('J12345'), isTrue);
      expect(isValidMitgliedernummer('J00001'), isTrue);
      expect(isValidMitgliedernummer('J123'), isFalse, reason: 'too short');
      expect(isValidMitgliedernummer('J123456'), isFalse, reason: 'too long');
    });
  });

  group('age + minor helpers', () {
    test('calculateAge from a known birth date', () {
      // Person born exactly 25 years and 1 day ago is 25
      final twentyFiveYearsAgo = DateTime.now().subtract(const Duration(days: 25 * 365 + 7));
      final iso = '${twentyFiveYearsAgo.year}-${twentyFiveYearsAgo.month.toString().padLeft(2, '0')}-${twentyFiveYearsAgo.day.toString().padLeft(2, '0')}';
      final age = calculateAge(iso);
      expect(age, anyOf(equals(25), equals(24)),
          reason: 'should be 25 or 24 depending on month/day rollover');
    });

    test('calculateAge returns null for empty/null/garbage', () {
      expect(calculateAge(null), isNull);
      expect(calculateAge(''), isNull);
      expect(calculateAge('   '), isNull);
      expect(calculateAge('not-a-date'), isNull);
    });

    test('isMinor true for 10-year-old', () {
      final tenYearsAgo = DateTime.now().subtract(const Duration(days: 10 * 365 + 3));
      final iso = '${tenYearsAgo.year}-${tenYearsAgo.month.toString().padLeft(2, '0')}-${tenYearsAgo.day.toString().padLeft(2, '0')}';
      expect(isMinor(iso), isTrue);
    });

    test('isMinor false for 30-year-old', () {
      final thirtyYearsAgo = DateTime.now().subtract(const Duration(days: 30 * 365 + 8));
      final iso = '${thirtyYearsAgo.year}-${thirtyYearsAgo.month.toString().padLeft(2, '0')}-${thirtyYearsAgo.day.toString().padLeft(2, '0')}';
      expect(isMinor(iso), isFalse);
    });

    test('isMinor false when birth date is missing (cannot determine)', () {
      expect(isMinor(null), isFalse);
      expect(isMinor(''), isFalse);
    });
  });

  group('User model vormundUserId', () {
    test('fromJson parses vormund_user_id when present', () {
      final u = User.fromJson({
        'id': 100,
        'mitgliedernummer': 'J12345',
        'email': 'kind@example.de',
        'name': 'Anna Mueller',
        'status': 'active',
        'role': 'jugendmitglied',
        'vormund_user_id': 42,
      });
      expect(u.vormundUserId, 42);
    });

    test('fromJson handles string vormund_user_id from JSON', () {
      final u = User.fromJson({
        'id': 100,
        'mitgliedernummer': 'J12345',
        'email': 'k@e.de',
        'name': 'A',
        'status': 'active',
        'role': 'jugendmitglied',
        'vormund_user_id': '42',
      });
      expect(u.vormundUserId, 42);
    });

    test('fromJson sets null when vormund_user_id missing', () {
      final u = User.fromJson({
        'id': 100,
        'mitgliedernummer': 'V12345',
        'email': 'parent@example.de',
        'name': 'Parent',
        'status': 'active',
        'role': 'vorsitzer',
      });
      expect(u.vormundUserId, isNull);
    });

    test('toJson round-trips vormund_user_id', () {
      final u = User.fromJson({
        'id': 1,
        'mitgliedernummer': 'J00001',
        'email': 'a@b.de',
        'name': 'X',
        'status': 'active',
        'role': 'jugendmitglied',
        'vormund_user_id': 99,
      });
      expect(u.toJson()['vormund_user_id'], 99);
    });

    test('copyWith preserves vormundUserId by default and can override', () {
      final u = User.fromJson({
        'id': 1, 'mitgliedernummer': 'J00001', 'email': 'a@b.de',
        'name': 'X', 'status': 'active', 'role': 'jugendmitglied',
        'vormund_user_id': 99,
      });
      expect(u.copyWith().vormundUserId, 99);
      expect(u.copyWith(vormundUserId: 100).vormundUserId, 100);
    });
  });
}
