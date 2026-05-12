<div align="center">

# ICD360S e.V. — Vorsitzer Portal

**Administrationsportal für den Vorstand des gemeinnützigen Vereins ICD360S e.V.**

Verwaltung von Mitgliederdaten, Behördenschriftverkehr, Arztterminen,
Pflegehilfsmitteln, Live-Chat und vielem mehr — auf allen Plattformen.

[![Flutter](https://img.shields.io/badge/Flutter-3.38-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.6-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-blue)](#-plattformen)
[![Release](https://img.shields.io/github/v/release/ICD360S-e-V/vorsitzer?include_prereleases&sort=semver)](https://github.com/ICD360S-e-V/vorsitzer/releases/latest)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-green)](LICENSE)

[![Download APK](https://img.shields.io/badge/Download-Android%20APK-brightgreen?style=for-the-badge&logo=android&logoColor=white)](https://github.com/ICD360S-e-V/vorsitzer/releases/latest)

</div>

---

## 📋 Übersicht

Das **Vorsitzer-Portal** ist die zentrale Admin-Oberfläche für den Vorstand des
gemeinnützigen Vereins [ICD360S e.V.](https://icd360s.de) (Deutschland). Es
bündelt die komplette Vereinsverwaltung in **einer plattformübergreifenden
App** — statt Excel-Tabellen, gestreuten PDFs und drei verschiedenen Web-Tools.

Die App kommuniziert mit einem selbst gehosteten PHP-/MySQL-Backend, das nur
nach Registrierung eines gerätespezifischen Schlüssels (`X-Device-Key`) +
JWT-Authentifizierung Zugriff gewährt.

---

## ✨ Features

### 👥 Mitgliederverwaltung
- Stammdaten, Mitgliedsbeiträge, Familienangehörige, Beitrittsdatum
- Pro Mitglied: komplette **Behörden-Akte** mit verschlüsselter Dateiablage
- Mehrsprachige Oberfläche (DE / RO / UK / RU / EN / TR / AR)

### 🏛️ Behörden-Integration (14 Typen)

| Behörde | Funktionen |
|---|---|
| **Krankenkasse** | eGK, EHIC, Befreiungsausweis, Pflegegrad, Pflegebox, Lieferscheine mit Tracking-ID |
| **Versorgungsamt** | SB-Ausweis, GdB + Nachteilsausgleiche (2025/2026), Merkzeichen |
| **Finanzamt** | Steuerklasse, Steuererklärung-Workflow, ELSTER-Integration |
| **Jobcenter** | Bescheide, Termine, Widerspruchsfristen |
| **Agentur für Arbeit** | Arbeitssuche, Weiterbildungen |
| **Rentenversicherung** | Versicherungsnummer, Bescheide |
| **Familienkasse** | Kindergeld |
| **Einwohnermeldeamt** | Anmeldung, Ummeldung |
| **Ausländerbehörde / BAMF** | Aufenthaltstitel, Fristen |
| **Jugendamt / Sozialamt** | Leistungsbescheide |
| **Wohngeldstelle / Vermieter / Gericht** | Schriftverkehr, Mietverträge, Akten |

Jede Behörde mit eigenen Registerkarten: **Amt** · **Termine** · **Korrespondenz** · behördenspezifische Felder.

### 🩺 Gesundheit
- Ärzte-Datenbank (Allgemeinmedizin / Fachärzte / Kliniken / Apotheken)
- Termin-Tracking pro Arzt, Rezept-Historie, AU-Bescheinigungen

### 📅 Terminverwaltung
- Zentraler Kalender über alle Behörden + Ärzte + interne Termine
- Push-Benachrichtigungen via [ntfy](https://ntfy.sh) (selbst gehostet)

### 💬 Live-Chat
- Echtzeit-Chat Vorstand ⇄ Mitglieder (WebSocket)
- Sprachanrufe via WebRTC (STUN/TURN)

### 🎫 Ticket-System
- Erinnerungen mit Fälligkeitsdatum (z. B. „Befreiungsausweis 2027 beantragen"
  automatisch ab erstem Montag im November)

### 🔐 Sicherheit
- Dateien Ende-zu-Ende verschlüsselt (AES-256-CBC) auf dem Server
- Pro-Gerät-Auth + JWT Access-/Refresh-Tokens
- Biometrische Entsperrung (Face ID / Touch ID / Windows Hello)
- Zertifikats-Pinning (ISRG Root X1)

---

## 📱 Plattformen

| Plattform | Format | Vertrieb |
|---|---|---|
| **Android** | `.apk` universal + ABI-splits | Google Play (AAB) · Samsung Galaxy Store · Huawei AppGallery · F-Droid |
| **iOS** | `.ipa` (unsigned) | Sideload via Enterprise / TestFlight geplant |
| **macOS** | `.dmg` (signed + notarized) | Direkt-Download |
| **Windows** | `.zip` portable | Direkt-Download |
| **Linux** | `.tar.gz` | Direkt-Download |
| **Web** | statisches `build/web/` | – |

**Alle Binaries:** [github.com/ICD360S-e-V/vorsitzer/releases/latest](https://github.com/ICD360S-e-V/vorsitzer/releases/latest)

---

## 🛠️ Tech Stack

- **Frontend:** Flutter 3.38 · Dart 3.6 · Material 3
- **Backend:** PHP 8 · MySQL / MariaDB · nginx
- **Auth:** JWT (Access 1h / Refresh 30d) + gerätespezifische Keys
- **Push:** [ntfy](https://ntfy.sh)
- **WebRTC:** `flutter_webrtc` + eigener coturn-Server
- **CI/CD:** GitHub Actions (auto semver-bump · Multi-Plattform-Build · Releases)

---

## 🚀 Build

Dies ist eine **vereinsinterne** App — Backend-Zugang ist auf registrierte
Geräte beschränkt. Forks können kompilieren, aber ohne passendes Backend
keine Verbindung aufbauen.

```bash
# Voraussetzungen: Flutter 3.38, Android SDK / Xcode je nach Zielplattform
flutter pub get

# Debug-Build
flutter run

# Release-Build (Beispiel: Android universal APK)
flutter build apk --release \
  --dart-define=TURN_HOST=turn.example.org \
  --dart-define=TURN_USER=turnuser \
  --dart-define=TURN_CRED=*** \
  --dart-define=HAFAS_AID=***
```

### Build-Variablen (`--dart-define`)

| Variable | Zweck | Optional |
|---|---|---|
| `TURN_HOST` · `TURN_USER` · `TURN_CRED` | Eigener TURN-Server für Sprachanrufe | ✅ (Fallback: nur STUN) |
| `HAFAS_AID` | saarVV-Fahrplanabfrage Saarland | ✅ (leer → Provider deaktiviert) |

Das Backend-URL (`baseUrl`) ist in `lib/services/*.dart` hartkodiert. Für
Fork-Deployments bitte dort anpassen.

---

## 🧪 Release-Pipeline

`.github/workflows/build.yml` läuft bei Push auf `main` und bei Tag-Push `v*`:

1. **Auto-Bump** — Aus dem Git-Diff seit letztem Tag wird `patch` / `minor` /
   `major` abgeleitet (neue Datei → minor; sonst patch).
2. **Parallel-Build** — 11 Artefakte auf GitHub-Hosted Runners (Ubuntu · macOS · Windows).
3. **Create Release** — GitHub Release mit allen Installern.
4. **Deploy** — Update-Metadaten werden auf den eigenen Server gepusht.

Die gleichzeitigen Pushes werden über eine `concurrency`-Gruppe serialisiert,
damit keine Tag-Kollisionen entstehen.

---

## 🤝 Beitragen

Pull Requests sind willkommen — bitte erst ein Issue öffnen, damit wir
Doppelarbeit vermeiden. Security-Meldungen: siehe unten.

### Commit-Konvention

[Conventional Commits](https://www.conventionalcommits.org/):

- `feat(...)` — neue Funktion → **minor bump**
- `fix(...)` — Bugfix → **patch bump**
- `BREAKING CHANGE:` im Body → **major bump**
- `chore:` · `docs:` · `refactor:` · `style:` · `test:` — kein Release-Bump

---

## 🛡️ Sicherheit

Bitte melde Schwachstellen **nicht** via öffentlichem Issue, sondern per
E-Mail an `security@icd360s.de`.

Die App enthält **keine** hartkodierten Credentials. Alle sensiblen Werte
werden zur Build-Zeit via `--dart-define` injiziert oder vom Server geladen.

---

## 📄 Lizenz

Lizenziert unter **AGPL-3.0** — siehe [LICENSE](LICENSE).

> Für abgeleitete Werke, die über ein Netzwerk bereitgestellt werden, muss der
> Quellcode den Nutzer:innen offen zur Verfügung gestellt werden.

---

<div align="center">

© 2026 [ICD360S e.V.](https://icd360s.de) · Mit ❤️ in Deutschland gebaut

</div>
