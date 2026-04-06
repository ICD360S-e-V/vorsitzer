import 'package:flutter/material.dart';

/// ============================================================
/// Rollen in einem eingetragenen Verein (e.V.) nach deutschem Recht
/// Basierend auf BGB §§ 21-79 und gängiger Vereinspraxis
/// ============================================================
///
/// VORSTAND (Pflichtorgan §26 BGB):
///   - vorsitzer          = 1. Vorsitzender
///   - stellvertreter     = 2. Vorsitzender / Stellvertreter
///   - schatzmeister      = Schatzmeister (Kassenwart)
///   - schriftfuehrer     = Schriftführer
///   - beisitzer          = Beisitzer (erweiterter Vorstand)
///
/// FINANZKONTROLLE:
///   - kassierer          = Kassierer
///   - kassenprufer       = Kassenprüfer (Rechnungsprüfer)
///
/// EHRENAMT:
///   - ehrenamtlich       = Ehrenamtlicher Mitarbeiter
///
/// MITGLIEDERTYPEN:
///   - mitglied           = Ordentliches Mitglied
///   - mitgliedergrunder  = Gründungsmitglied
///   - ehrenmitglied      = Ehrenmitglied
///   - foerdermitglied    = Fördermitglied
/// ============================================================

/// Returns the display text for a user role
String getRoleText(String role) {
  switch (role) {
    case 'vorsitzer':
      return 'Vorsitzender';
    case 'stellvertreter':
      return 'Stellvertreter';
    case 'schatzmeister':
      return 'Schatzmeister';
    case 'schriftfuehrer':
      return 'Schriftführer';
    case 'beisitzer':
      return 'Beisitzer';
    case 'kassierer':
      return 'Kassierer';
    case 'kassenprufer':
      return 'Kassenprüfer';
    case 'ehrenamtlich':
      return 'Ehrenamtlich';
    case 'mitglied':
      return 'Mitglied';
    case 'mitgliedergrunder':
      return 'Gründungsmitglied';
    case 'ehrenmitglied':
      return 'Ehrenmitglied';
    case 'foerdermitglied':
      return 'Fördermitglied';
    default:
      return role;
  }
}

/// Returns the color associated with a user role
Color getRoleColor(String role) {
  switch (role) {
    // Vorstand
    case 'vorsitzer':
      return Colors.purple;
    case 'stellvertreter':
      return Colors.purple.shade300;
    case 'schatzmeister':
      return Colors.indigo;
    case 'schriftfuehrer':
      return Colors.deepPurple;
    case 'beisitzer':
      return Colors.purple.shade200;
    // Finanzkontrolle
    case 'kassierer':
      return Colors.teal;
    case 'kassenprufer':
      return Colors.teal.shade300;
    // Ehrenamt
    case 'ehrenamtlich':
      return Colors.orange;
    // Mitgliedertypen
    case 'mitgliedergrunder':
      return Colors.amber.shade800;
    case 'ehrenmitglied':
      return Colors.amber;
    case 'foerdermitglied':
      return Colors.lime.shade700;
    default:
      return Colors.blue; // mitglied
  }
}

/// Returns the display text for a user status
String getStatusText(String status) {
  switch (status) {
    case 'nicht_verifiziert':
      return 'Nicht verifiziert';
    case 'neu':
      return 'Neu (Antrag)';
    case 'active':
      return 'Aktiv';
    case 'passiv':
      return 'Passiv';
    case 'ruhend':
      return 'Ruhend';
    case 'gesperrt':
      return 'Gesperrt';
    case 'gekuendigt_selbst':
      return 'Gekündigt (selbst)';
    case 'gekuendigt_verein':
      return 'Gekündigt (Verein)';
    case 'ausgeschlossen':
      return 'Ausgeschlossen';
    case 'verstorben':
      return 'Verstorben';
    // Legacy statuses (backward compatibility)
    case 'suspended':
      return 'Gesperrt';
    case 'deleted':
      return 'Gelöscht';
    case 'gekuendigt':
      return 'Gekündigt';
    default:
      return status;
  }
}

/// Returns the color associated with a user status
Color getStatusColor(String status) {
  switch (status) {
    case 'nicht_verifiziert':
      return Colors.red.shade300;
    case 'active':
      return Colors.green;
    case 'neu':
      return Colors.amber;
    case 'passiv':
      return Colors.blueGrey;
    case 'ruhend':
      return Colors.indigo;
    case 'gesperrt':
    case 'suspended':
      return Colors.orange;
    case 'gekuendigt_selbst':
      return Colors.brown.shade400;
    case 'gekuendigt_verein':
    case 'gekuendigt':
      return Colors.brown;
    case 'ausgeschlossen':
      return Colors.red.shade800;
    case 'verstorben':
      return Colors.grey.shade700;
    case 'deleted':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

/// All available statuses for dropdowns (ordered by lifecycle)
const allStatuses = [
  {'value': 'nicht_verifiziert', 'label': 'Nicht verifiziert', 'description': 'Konto erstellt, Identität noch nicht bestätigt (30 Tage Frist)'},
  {'value': 'neu', 'label': 'Neu (Antrag)', 'description': 'Aufnahmeantrag eingegangen'},
  {'value': 'active', 'label': 'Aktiv', 'description': 'Ordentliches Mitglied'},
  {'value': 'passiv', 'label': 'Passiv', 'description': 'Zahlt Beitrag, nimmt nicht aktiv teil'},
  {'value': 'ruhend', 'label': 'Ruhend', 'description': 'Mitgliedschaft vorübergehend ruhend'},
  {'value': 'gesperrt', 'label': 'Gesperrt', 'description': 'Mitgliedschaftsrechte vorübergehend entzogen'},
  {'value': 'gekuendigt_selbst', 'label': 'Gekündigt (selbst)', 'description': 'Austritt durch Mitglied'},
  {'value': 'gekuendigt_verein', 'label': 'Gekündigt (Verein)', 'description': 'Kündigung durch den Verein'},
  {'value': 'ausgeschlossen', 'label': 'Ausgeschlossen', 'description': 'Vereinsausschluss nach Satzung'},
  {'value': 'verstorben', 'label': 'Verstorben', 'description': 'Mitglied verstorben'},
];

/// Returns the role prefix for Benutzernummer
String getRolePrefix(String role) {
  switch (role) {
    case 'vorsitzer':
      return 'V';
    case 'stellvertreter':
      return 'SV';
    case 'schatzmeister':
      return 'S';
    case 'schriftfuehrer':
      return 'SF';
    case 'beisitzer':
      return 'B';
    case 'kassierer':
      return 'K';
    case 'kassenprufer':
      return 'KP';
    case 'ehrenamtlich':
      return 'E';
    case 'mitgliedergrunder':
      return 'MG';
    case 'ehrenmitglied':
      return 'EM';
    case 'foerdermitglied':
      return 'FM';
    default:
      return 'M'; // mitglied
  }
}

/// Checks if a role is an admin role (Vorstand + Finanzkontrolle)
bool isAdminRole(String role) {
  return [
    'vorsitzer',
    'stellvertreter',
    'schatzmeister',
    'schriftfuehrer',
    'beisitzer',
    'kassierer',
    'kassenprufer',
    'mitgliedergrunder',
  ].contains(role);
}

/// Checks if a role is a Vorstand (board) role
bool isVorstandRole(String role) {
  return [
    'vorsitzer',
    'stellvertreter',
    'schatzmeister',
    'schriftfuehrer',
    'beisitzer',
  ].contains(role);
}

/// All available roles for dropdowns
const allRoles = [
  {'value': 'mitglied', 'label': 'Mitglied'},
  {'value': 'vorsitzer', 'label': 'Vorsitzender'},
  {'value': 'stellvertreter', 'label': 'Stellvertreter'},
  {'value': 'schatzmeister', 'label': 'Schatzmeister'},
  {'value': 'schriftfuehrer', 'label': 'Schriftführer'},
  {'value': 'beisitzer', 'label': 'Beisitzer'},
  {'value': 'kassierer', 'label': 'Kassierer'},
  {'value': 'kassenprufer', 'label': 'Kassenprüfer'},
  {'value': 'ehrenamtlich', 'label': 'Ehrenamtlich'},
  {'value': 'mitgliedergrunder', 'label': 'Gründungsmitglied'},
  {'value': 'ehrenmitglied', 'label': 'Ehrenmitglied'},
  {'value': 'foerdermitglied', 'label': 'Fördermitglied'},
];

/// ✅ SECURITY FIX (2026-02-10): Input sanitization to prevent SQL injection
/// Sanitizes Mitgliedernummer by allowing only alphanumeric characters
/// Valid formats: V00001, S00001, K00001, MG00001, SV00001, etc.
String sanitizeMitgliedernummer(String input) {
  // Remove all non-alphanumeric characters
  final sanitized = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // Validate format
  if (sanitized.isEmpty) return '';

  // Check if it matches valid patterns:
  // - V/S/K/MG/SV/SF/B/KP/E/EM/FM/M + 5 digits (role prefixes)
  // - 10000-99999 (5-digit numbers for legacy accounts)
  final validPattern = RegExp(r'^(V|SV|S|SF|K|KP|MG|B|E|EM|FM|M)\d{5}$|^\d{5}$');

  if (validPattern.hasMatch(sanitized)) {
    return sanitized;
  }

  // Return original if doesn't match (UI validation will catch it)
  return sanitized;
}

/// Validates Mitgliedernummer format
bool isValidMitgliedernummer(String mitgliedernummer) {
  final sanitized = sanitizeMitgliedernummer(mitgliedernummer);

  // Must match: role prefix + 5 digits, or legacy 5-digit number
  final validPattern = RegExp(r'^(V|SV|S|SF|K|KP|MG|B|E|EM|FM|M)\d{5}$|^[1-9]\d{4}$');

  return validPattern.hasMatch(sanitized);
}

/// Sanitizes email input (basic validation)
String sanitizeEmail(String email) {
  return email.trim().toLowerCase();
}

/// Validates email format
bool isValidEmail(String email) {
  final sanitized = sanitizeEmail(email);
  final emailPattern = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
  return emailPattern.hasMatch(sanitized);
}
