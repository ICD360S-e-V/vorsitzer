# ICD360S e.V - Vorsitzer Portal (Cross-Platform: Windows, macOS, Linux, Mobile)

**Current Version:** 1.0.28+29 (from pubspec.yaml)

**Supported Platforms:**
- ✅ **Windows** - Primary platform, fully tested
- ✅ **macOS** - Active development, camera capture + crop support
- ⚠️ **Linux** - Desktop features supported (not extensively tested)
- ⚠️ **Android/iOS** - Mobile support via cross-platform packages (not primary focus)

**Development Environment:**
- **Windows**: `c:\Users\icd_U\Documents\icd360sev_vorsitzer`
- **macOS**: `/Users/ionut-claudiuduinea/Documents/icd360sev_vorsitzer`
- **Server**: `ssh -i "vps_icd360sev_icd360s.de" -p 36000 root@icd360sev.icd360s.de`
- **Database**: MySQL - `icd360sev_user:SecureDB2026@localhost/icd360sev_db`

---

## REGULA DE AUR - BACKUP OBLIGATORIU

**ÎNAINTE de a modifica ORICE fișier, TREBUIE să faci backup la fișierul original!**

```bash
# Backup individual file (macOS)
cp lib/screens/fisier_original.dart lib/screens/fisier_original.dart.bak

# Restore dacă ceva merge prost
cp lib/screens/fisier_original.dart.bak lib/screens/fisier_original.dart
```

**Reguli:**
1. Fă `.bak` la FIECARE fișier ÎNAINTE de prima modificare
2. Backup-ul se face în același folder cu extensia `.bak`
3. DOAR fișierele care se modifică, nu tot proiectul
4. După ce totul funcționează corect, backup-urile `.bak` pot fi șterse manual

---

## Format Benutzernummer

| Rol | Prefix | Format |
|-----|--------|--------|
| Vorsitzer | V | V00001 |
| Schatzmeister | S | S00001 |
| Kassierer | K | K00001 |
| Mitgliedergrunder | MG | MG00001 |

## Funcționalități

### Start Screen (Tabs)

#### Tab 1: Anmelden (Login)
- Login cu Benutzernummer și parolă
- **Anmeldedaten speichern** - salvează credențialele criptat (Windows Credential Manager)
- **Automatisch anmelden** - auto-login la pornirea aplicației
- **Mit Windows starten** - pornire automată la login Windows
- **Passwort vergessen?** - recuperare parolă cu Benutzernummer + Wiederherstellungscode
- **Single Instance** - aplicația poate rula doar o singură dată

#### Tab 2: Registrieren
- Formular: Name, Email, Passwort, Wiederherstellungscode (6 cifre)
- După succes: Benutzernummer generată random (10000-99999)
- Limitare: max 1 cont per IP per zi

### Dashboard
Accesibil pentru: vorsitzer, schatzmeister, kassierer, mitgliedergrunder

**Sidebar Navigation:**
- Benutzerverwaltung (User management)
- Ticketverwaltung (Ticket system)
- Terminverwaltung (Appointments)
- Vereinverwaltung (Organization admin)
- Finanzverwaltung (Financial management)
- Notar (Notary services)
- Behörden (Government authorities)
- Handelsregister (Trade register)
- Vereinsregister (Association register)
- Stadtverwaltung (City administration)
- Deutsche Post (Postal services & tracking)
- Sendungsverfolgung (DHL Tracking)
- Finanzamt (Tax office)
- Gericht (Court)
- Arbeitsagentur (Employment agency)
- Ordnungsmaßnahmen (Disciplinary measures)
- Statistik (Statistics)
- Reiseplanung (Travel planning)
- DB Mobilitätsunterstützung (Deutsche Bahn)
- Netzwerk (Network)
- VR Bank / GLS Bank (Banking)
- Stifter-helfen / Google Nonprofit / Microsoft Nonprofit
- Archiv (Document archive)
- PDF Manager / JPG2PDF
- Dienste (Services)
- Routinenaufgaben (Routine tasks)
- Einstellungen (Settings)
- Postcard (Postcard creation)
- Jasmina (AI Assistant)

**User Management:**
- Lista toți utilizatorii cu culori per rol
- Statistici: Total Benutzer, Aktiv, Gesperrt
- Activează/Suspendă/Șterge conturi
- **Click pe utilizator** → Dialog cu:
  - Tab 1: Edit Name, Email, Parolă, Rol
  - Tab 2: Device/Session management cu force logout per device
- **Protecție cont propriu** - nu poți modifica propriul cont

### Terminverwaltung (NEW - v1.0.57+)
**Weekly Calendar System:**
- 📅 Grid 7 coloane: Montag → Sonntag
- 🔢 KW number + date range navigation (< >)
- 🕐 Time slots: 11:00, 🍽️ Mittagspause (12:00-14:00), 14:00-17:00
- 🎨 Color coding: Vorstandssitzung (purple), Mitgliederversammlung (blue), Schulung (green), Sonstiges (amber)
- 🏖️ **Urlaub** în roșu - blochează programări
- ✏️ Click pe termin → Edit dialog (change all fields)
- 🗑️ Delete termine
- 👥 Multi-select participanți cu checkboxes
- 🔗 Optional link la ticket

**Urlaub Management:**
- ➕ Buton "Urlaub" roșu → Create vacation period
- 🏖️ Display în calendar (zilele roșii cu beach icon)
- ✏️ Click pe urlaub → Smart edit:
  - Single day → Delete
  - First day → Remove first OR delete all
  - Last day → Remove last OR delete all
  - Middle day → Delete all only

**Time Restrictions:**
- Termine doar: 11:00-12:00 și 14:00-18:00
- Validare automată la create/edit

### Behördenverwaltung (Government Authorities)
**Features:**
- Contact information for various government authorities
- Forms and document templates
- Application tracking (Anträge)
- Appointment scheduling with authorities
- Document upload/download

### Handelsregister (Trade Register)
**Client-Side Scraping (handelsregister.de):**
- Company search by name or registration number
- Extract company data (name, address, directors, capital)
- View company documents (annual reports, registration certificates)
- HTML parsing with `html` package (client-side, no backend proxy)
- Caching of search results

**Implementation:**
- `lib/services/handelsregister_client_service.dart` - HTTP client + HTML parsing
- `lib/screens/handelsregister_screen.dart` - Search UI + results display

### Vereinsregister (Association Register)
**Features:**
- Search associations by name or registration number
- View association details (name, address, board members, purpose)
- Track association registration status
- Document management (statutes, membership lists)

### Stadtverwaltung (City Administration)
**Features:**
- Municipal services overview
- Contact information for city departments
- Appointment scheduling (Bürgeramt, Standesamt, etc.)
- Document requests (Gewerbeschein, Anmeldung, etc.)
- Forms and applications

### Deutsche Post (Postal Services)
**DHL Tracking & Services:**
- Package tracking (Sendungsverfolgung) via DHL API
- Shipping label creation
- Postage calculator
- Pickup scheduling
- Address validation

**Implementation:**
- `lib/screens/deutschepost_screen.dart` - Tracking UI + shipping services
- Integration with DHL API for real-time tracking

### Device Management (v1.0.56+)
**Max 3 Devices:**
- Login verifică sesiuni active
- >3 devices → Dialog cu lista pentru selecție
- Auto-logout device selectat + retry login
- Prevent duplicate sessions per device

**User Self-Service:**
- Tab "Meine Geräte" în profil
- Vezi device name, platform, IP
- Self-service logout per device

### Ticket Notification System (v1.0.58+)
**Cross-Platform Notifications pentru Tickete:**
- Polling la fiecare **10 secunde** pentru notificări noi
- Notificări când:
  - Membri creează tickete noi
  - Membri răspund la tickete existente
  - Adminii răspund (notifică membrii)
- Dual system: WebSocket (real-time) + HTTP Polling (fallback)
- Notificări marcate automat ca trimise după afișare

**Implementare:**
- `lib/services/ticket_notification_service.dart` - Polling service (60s)
- `lib/screens/dashboard_screen.dart` - Start/stop în initState/dispose
- `/api/tickets/poll_notifications.php` - Backend endpoint

**Database:**
- `ticket_notifications` table cu `is_sent` flag
- Notificări create automat la ticket create/comment
- Polling marchează `is_sent = 1` după afișare

### Ticket Camera & Crop Feature (v1.0.24+) - macOS Support
**macOS Camera Capture + Image Cropping pentru Ticket Attachments:**
- **Camera nativă macOS**: `camera_macos` package (AVFoundation)
- **Image cropping**: `crop_your_image` package (pure Dart, cross-platform)
- **3-step flow**: Camera → Crop/Edit → Preview → Upload

**Implementare:**
- `lib/widgets/ticket_details_dialog.dart` - `_MacOSCameraDialog` widget (lines ~1233-1531)
- **Camera capture** → PNG conversion via `dart:ui` codec for crop compatibility
- **Crop UI** → Interactive crop with corner dots, rotation, zoom
- **Preview** → Final preview before upload with retake/back options

**Technical Details:**
- `camera_macos` outputs JPEG by default (set `pictureFormat: PictureFormat.jpg`)
- Convert camera bytes to PNG using `ui.instantiateImageCodec()` before crop
- `crop_your_image` uses `image` Dart package for decoding (not Flutter native codec)
- All photos saved as `.png` on server for consistency

**API Endpoint:**
- `/api/tickets/attachments/upload.php` - Supports image/png, image/jpeg, image/tiff, image/bmp

**Permissions:**
- macOS: `com.apple.security.device.camera` in `macos/Runner/DebugProfile.entitlements`
- macOS: `com.apple.security.device.camera` in `macos/Runner/Release.entitlements`

### Live Chat & Voice Call

**WebSocket Server:** `wss://icd360sev.icd360s.de/wss/`

| Feature | Descriere |
|---------|-----------|
| Live Chat | Mesaje real-time, typing indicator, istoric |
| Voice Call | WebRTC cu STUN servers, mute/unmute, call timer |
| Auto-reject | După 30 secunde fără răspuns |
| **Auto-Reconnect** | **Exponential backoff: 2s, 4s, 8s, 16s, 32s, 60s (max 10 încercări)** |

**Auto-Reconnect System (v1.0.58+):**
- Reconnectare automată când conexiunea cade (network issues, server restart)
- **Exponential backoff**: 2s → 4s → 8s → 16s → 32s → 60s (max)
- Max 10 încercări de reconnectare
- Reset automat la reconnectare cu succes
- Oprire automată la disconnect manual
- Store credentials pentru reconnectare automată

### Native Notifications (Cross-Platform)
**Notification Types:**
- Mesaj nou în chat
- Apel incoming (voice call)
- Update disponibil
- Status conexiune
- Ticket nou creat
- Ticket comment nou

**Implementation:**
- `lib/services/notification_service.dart` - Uses `flutter_local_notifications` (cross-platform)
- **Windows**: Toast notifications via Windows Notification API
- **macOS**: Native macOS notification center
- **Linux**: D-Bus notifications (FreeDesktop specification)
- **Mobile**: Push notifications (Android/iOS native)

### ntfy Push Notifications (Self-Hosted)
**No Google/FCM dependency** - uses self-hosted ntfy server.

**Architecture:**
- **Server**: ntfy v2.11.0 on port 2586, proxied via nginx at `/ntfy/`
- **Topic pattern**: `vorsitzer_{mitgliedernummer}` (e.g., `vorsitzer_v00001`)
- **Auth**: Anonymous read-only on `vorsitzer_*` topics; admin write via `icd360s_admin`
- **App**: HTTP NDJSON streaming (long-poll), auto-reconnect 5s

**Server Services (3 separate services per portal):**
| Service | Topic Prefix | Portal |
|---------|-------------|--------|
| `NtfyService.php` | `icd360s_` | Mitglieder |
| `NtfySchatzmeisterService.php` | `schatzmeister_` | Schatzmeister |
| `NtfyVorsitzerService.php` | `vorsitzer_` | Vorsitzer |

**Notification Methods:**
- `notifyNewMessage($mitgliedernummer, $senderName, $preview)` - priority 4
- `notifyIncomingCall($mitgliedernummer, $callerName)` - priority 5
- `notifyTicketUpdate($mitgliedernummer, $ticketId, $status)` - priority 3
- `notifyTerminReminder($mitgliedernummer, $terminTitle, $time)` - priority 4

**chat/send.php Routing:**
- Recipient role `vorsitzer` → NtfyVorsitzerService
- Recipient role `schatzmeister` → NtfySchatzmeisterService
- Otherwise → NtfyService (Mitglieder)

**Flutter Implementation:**
- `lib/services/ntfy_service.dart` - Singleton, HTTP GET `/{topic}/json` stream
- Started in `dashboard_screen.dart` initState, stopped in dispose
- Notifications displayed via `NotificationService().show()`

### Certificate Pinning (ISRG Root X1)
**Protects against MITM attacks** - all HTTP clients only accept Let's Encrypt certificates.

**Implementation:**
- `lib/services/http_client_factory.dart` - Factory with embedded ISRG Root X1 PEM
- **Debug mode**: pinning disabled (for development)
- **Release mode**: ONLY Let's Encrypt accepted
- **Valid until 2035** - zero maintenance on cert renewal

**Coverage:**
- All REST API services (14 services) → `HttpClientFactory.createPinnedHttpClient()`
- External sites (handelsregister.de) → `HttpClientFactory.createDefaultHttpClient()` (no pinning)
- WebSocket (chat) → system SSL validation (adequate, pinning would require global HttpOverrides)
- ntfy stream → pinned via IOClient wrapper

### Auto-Update System (v1.0.20+)

**Verificare automată:** La fiecare 5 minute (Timer în LegalFooter)

**Flux update silențios:**
1. User apasă "Jetzt aktualisieren" în UpdateDialog
2. App descarcă installer în `%TEMP%` cu progress bar
3. App afișează "Installation wird gestartet..."
4. App lansează installer cu flags: `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`
5. App se închide (`exit(0)`)
6. Installer rulează silențios (fără UI)
7. Installer pornește automat aplicația actualizată (flag `postinstall` fără `skipifsilent`)

**Inno Setup flags pentru silent install:**
```
/VERYSILENT      - Fără interfață grafică
/SUPPRESSMSGBOXES - Fără dialog boxes
/NORESTART       - Nu restarta Windows
```

**Fișiere implicate:**
- `lib/services/update_service.dart` - `launchInstaller(path, silent: true)`
- `lib/widgets/update_dialog.dart` - UI pentru download + progress
- `installer/icd360sev_setup.iss` - `[Run]` section cu `postinstall` flag

### Auto-Recovery Launcher (v1.0.37+)

**Problemă rezolvată:** Dacă o actualizare are un DLL lipsă sau altă eroare fatală, aplicația nu poate porni și utilizatorul rămâne blocat.

**Soluție:** Un launcher VBS care monitorizează pornirea aplicației și oferă rollback automat.

**Flux Auto-Recovery:**
1. Shortcut-urile (Desktop + Start Menu) pornesc `Launcher.vbs`, nu EXE-ul direct
2. Launcher-ul pornește `ICD360S_eV.exe` și monitorizează procesul
3. Dacă aplicația se închide în mai puțin de 5 secunde (crash):
   - Afișează dialog: "Die Anwendung konnte nicht gestartet werden. Möchten Sie zur vorherigen Version zurückkehren?"
   - Dacă utilizatorul apasă **Ja**: restaurează automat din `backup\` și repornește
   - Dacă nu există backup: afișează link pentru download manual
4. Dacă aplicația rulează > 5 secunde: launcher-ul se închide silențios

**Backup automat la instalare:**
- Înainte de fiecare update, installer-ul salvează versiunea curentă în `{app}\backup\`
- Se salvează: EXE + toate DLL-urile
- Se creează `Restore_Previous_Version.bat` pentru restaurare manuală

**Fișiere create de installer:**
```
C:\Program Files\ICD360S e.V\
├── ICD360S_eV.exe           # Aplicația principală
├── Launcher.vbs             # Launcher cu auto-recovery
├── *.dll                    # DLL-uri Flutter
└── backup\
    ├── ICD360S_eV.exe       # Backup versiune anterioară
    ├── *.dll                # Backup DLL-uri
    ├── Restore_Previous_Version.bat  # Script restaurare manuală
    └── info.txt             # Info despre backup
```

**Start Menu entries:**
- `ICD360S e.V` → pornește prin Launcher.vbs
- `Vorherige Version wiederherstellen` → rulează Restore_Previous_Version.bat

### Diagnostic Service
- Trimite starea aplicației la fiecare 120 secunde (optimizat de la 15s)
- Include: battery_level, battery_state, platform, memory, connection status
- Endpoint: `/api/diagnostic/log.php`
- `setUser()` se apelează din dashboard initState (nu din consent dialog)

### Battery Monitoring (battery_plus)
- Package: `battery_plus: ^6.0.0`
- Trimite battery_level (0-100%) și battery_state (charging/discharging/full) în diagnostic payload
- Vizibil pentru Vorsitzer în Live Chat: bara de status arată bateria membrului lângă conexiune
- Server: `user_details.php` face subquery pe `diagnostic_logs` pentru ultimul battery info
- Color coding: verde >30%, portocaliu 16-30%, roșu ≤15%, ⚡ la charging

### Battery Optimization
- **Timer intervals reduse**: Heartbeat 15s→60s, Diagnostic 15s→120s, Tickets 10s→60s, Transit 30s→60s
- **WidgetsBindingObserver** pe dashboard: oprește timer-uri UI în background, le repornește la resume
- **Requests/min**: ~17 → ~3 (foreground), ~1.3 (background)
- NU se opresc în background: WebSocket, ntfy, heartbeat (notificările trebuie să funcționeze)

### Heartbeat Service (v1.0.1+)
**Real-time Online Status Updates:**
- Trimite heartbeat la fiecare 60 secunde pentru actualizare `last_seen`
- Endpoint: `/api/auth/heartbeat.php`
- Permite membrilor să vadă când vorsitzerul este online în timp real
- Automatic start/stop când utilizatorul se loghează/deloghează
- Rulează în background fără să întrerupă aplicația

**Implementare:**
- `lib/services/heartbeat_service.dart` - HeartbeatService cu Timer periodic
- `lib/services/api_service.dart` - `sendHeartbeat()` method
- `lib/screens/dashboard_screen.dart` - Start în `initState()`, stop în `dispose()`

**Rezolvă problema:**
- Membrii vedeau "Zuletzt aktiv vor 35 Minuten" când vorsitzerul era de fapt online
- Acum status-ul se actualizează automat la fiecare 60 secunde

### Log Upload System (v1.0.21+)
**Automatic Real-time Log Upload pentru Debugging:**
- Upload automat la fiecare **30 secunde** către server
- Upload **IMEDIAT** pentru toate error-urile
- Re-queue automat dacă upload eșuează
- Buffer max 500 logs în memorie
- **AVANTAJ MAJOR:** Testare locală pe PC fără nevoie de VM sau device remote!

**Implementare:**
- `lib/services/logger_service.dart` - `startUpload()`, `stopUpload()`, `_uploadLogsToServer()`
- `lib/screens/dashboard_screen.dart` - Start în `initState()`, stop în `dispose()`
- **Endpoint:** `/api/logs/vorsitzer_logs.php` (Vorsitzer Windows)
- **Logs salvate:** `/logs/vorsitzer/logs_YYYY-MM-DD.json`

**Payload JSON:**
```json
{
  "mitgliedernummer": "V00001",
  "device_id": "WIN_ABC123...",
  "machine_name": "DESKTOP-XYZ",
  "platform": "windows \"Windows 10 Pro\" 10.0",
  "logs": [
    {
      "timestamp": "2026-02-03T10:30:00.000Z",
      "message": "✓✓✓ Remote stream attached - AUDIO PLAYBACK ENABLED!",
      "level": "info",
      "tag": "CALL-UI"
    }
  ]
}
```

**Monitoring Real-time:**
```bash
# Vezi logs CALL în timp real
tail -f /var/www/icd360sev.icd360s.de/logs/vorsitzer/logs_$(date +%Y-%m-%d).json | \
  jq -r '.logs[] | select(.tag == "CALL" or .tag == "CALL-UI") | "\(.timestamp) [\(.tag)] \(.message)"'
```

**Beneficii pentru Testing:**
- ✅ **NU mai ai nevoie de VM/device remote** - testezi local pe PC-ul tău!
- ✅ Logs apar AUTOMAT pe server la 30s
- ✅ Debugging în timp real fără acces la device
- ✅ Persistență logs pentru analiza ulterioară
- ✅ Tracking probleme pe device-uri remote (Germania, etc.)

## API Endpoints (~175 PHP files pe server)

### Autentificare (/api/auth/ - 27 endpoints)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/auth/login_vorsitzer.php` | POST | Login Vorsitzer (admin roles only) |
| `/api/auth/login_mitglied.php` | POST | Login Mitglied (member) |
| `/api/auth/login_schatzmeister.php` | POST | Login Schatzmeister |
| `/api/auth/register.php` | POST | Registrare |
| `/api/auth/recover.php` | POST | Recuperare parolă |
| `/api/auth/change_password.php` | POST | Schimbă parola |
| `/api/auth/change_email.php` | POST | Schimbă email |
| `/api/auth/refresh.php` | POST | Refresh JWT token |
| `/api/auth/validate.php` | POST | Validează token |
| `/api/auth/get_profile.php` | GET | Obține profil utilizator |
| `/api/auth/update_profile.php` | POST | Actualizează profil |
| `/api/auth/update_personal_data.php` | POST | Actualizează date personale |
| `/api/auth/update_mitgliedsart.php` | POST | Schimbă tipul de membru |
| `/api/auth/update_zahlungsmethode.php` | POST | Schimbă metoda de plată |
| `/api/auth/account_status.php` | GET | Status cont |
| `/api/auth/check_email.php` | POST | Verifică dacă email există |
| `/api/auth/delete_account.php` | POST | Șterge cont |
| `/api/auth/heartbeat.php` | POST | Update last_seen Vorsitzer (15s) |
| `/api/auth/heartbeat_app.php` | POST | Update last_seen App (15s) |
| `/api/auth/accept_document.php` | POST | Accept document/terms |
| `/api/auth/my_sessions.php` | GET | My active sessions |
| `/api/auth/revoke_my_session.php` | POST | Self-service logout |
| `/api/auth/logout_device.php` | POST | Logout before login (max 3) |
| `/api/auth/my_dokumente.php` | GET | My uploaded documents |
| `/api/auth/my_dokumente_download.php` | GET | Download my document |
| `/api/auth/my_verifizierung.php` | GET | My verification status |
| `/api/auth/my_verwarnungen.php` | GET | My warnings |

### Admin - User Management (/api/admin/)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/users.php` | GET | Lista utilizatori |
| `/api/admin/user_status.php` | POST | Schimbă status |
| `/api/admin/user_delete.php` | POST | Șterge user |
| `/api/admin/user_details.php` | POST | Get user + sessions + devices |
| `/api/admin/user_update.php` | POST | Update name/email/password/rol |
| `/api/admin/session_revoke.php` | POST | Force logout device |
| `/api/admin/admin_register.php` | POST | Admin register user |
| `/api/admin/status_message.php` | POST | Set admin status message |
| `/api/admin/user_qualifikationen.php` | GET/POST | User qualifications |
| `/api/admin/user_schulbildung.php` | GET/POST | User education |

### Admin - Termine & Urlaub
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/termine_create.php` | POST | Create termin cu participanți |
| `/api/admin/termine_list.php` | GET | Lista termine (weekly filter) |
| `/api/admin/termine_details.php` | POST | Termin + participants |
| `/api/admin/termine_update.php` | POST | Update termin fields |
| `/api/admin/termine_delete.php` | POST | Delete termin |
| `/api/admin/urlaub_create.php` | POST | Create vacation period |
| `/api/admin/urlaub_list.php` | GET | Lista urlaub periods |
| `/api/admin/urlaub_update.php` | POST | Update start/end dates |
| `/api/admin/urlaub_delete.php` | POST | Delete urlaub period |
| `/api/termine/my_termine.php` | GET | My termine (member) |
| `/api/termine/respond.php` | POST | Confirm/Decline/Reschedule |
| `/api/termine/calendar.php` | GET | Calendar view data |

### Admin - Dokumente & Archiv
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/dokumente_upload.php` | POST | Upload document |
| `/api/admin/dokumente_download.php` | GET | Download document |
| `/api/admin/dokumente_list.php` | GET | Lista documente |
| `/api/admin/dokumente_delete.php` | POST | Delete document |
| `/api/admin/archiv_upload.php` | POST | Upload to archive |
| `/api/admin/archiv_download.php` | GET | Download from archive |
| `/api/admin/archiv_list.php` | GET | Lista archive |
| `/api/admin/archiv_delete.php` | POST | Delete from archive |

### Admin - Behörden & Befreiungen
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/behoerde_get.php` | GET | Get Behörde data for user |
| `/api/admin/behoerde_save.php` | POST | Save Behörde data |
| `/api/admin/behoerden_standorte.php` | GET | Behörden locations/addresses |
| `/api/admin/behoerde_antrag_upload.php` | POST | Upload Behörde application doc |
| `/api/admin/behoerde_antrag_download.php` | GET | Download Behörde application doc |
| `/api/admin/behoerde_antrag_docs.php` | GET | List Behörde application docs |
| `/api/admin/befreiung_upload.php` | POST | Upload exemption document |
| `/api/admin/befreiung_download.php` | GET | Download exemption document |
| `/api/admin/befreiung_list.php` | GET | List exemptions |
| `/api/admin/befreiung_update.php` | POST | Update exemption |
| `/api/admin/befreiung_delete.php` | POST | Delete exemption |
| `/api/admin/ermaessigung_list.php` | GET | List discounts |
| `/api/admin/ermaessigung_update.php` | POST | Update discount |
| `/api/admin/ermaessigung_delete.php` | POST | Delete discount |
| `/api/admin/ermaessigung_download.php` | GET | Download discount doc |
| `/api/admin/ermaessigung_poll.php` | GET | Poll discount status |
| `/api/admin/ermaessigung_remind.php` | POST | Send discount reminder |

### Admin - Arbeitgeber & Berufserfahrung
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/arbeitgeber_create.php` | POST | Create employer |
| `/api/admin/arbeitgeber_list.php` | GET | List employers |
| `/api/admin/arbeitgeber_update.php` | POST | Update employer |
| `/api/admin/arbeitgeber_delete.php` | POST | Delete employer |
| `/api/admin/arbeitgeber_docs_upload.php` | POST | Upload employer doc |
| `/api/admin/arbeitgeber_docs_download.php` | GET | Download employer doc |
| `/api/admin/arbeitgeber_docs_list.php` | GET | List employer docs |
| `/api/admin/arbeitgeber_docs_delete.php` | POST | Delete employer doc |
| `/api/admin/arbeitsvermittler_manage.php` | GET/POST | Manage Arbeitsvermittler |
| `/api/admin/berufserfahrung_save.php` | POST | Save work experience |
| `/api/admin/berufserfahrung_list.php` | GET | List work experience |
| `/api/admin/berufserfahrung_delete.php` | POST | Delete work experience |
| `/api/admin/berufserfahrung_dok_upload.php` | POST | Upload work exp. doc |
| `/api/admin/berufserfahrung_dok_download.php` | GET | Download work exp. doc |
| `/api/admin/berufserfahrung_dok_list.php` | GET | List work exp. docs |
| `/api/admin/berufserfahrung_dok_delete.php` | POST | Delete work exp. doc |
| `/api/admin/berufsbezeichnungen_list.php` | GET | List job titles |

### Admin - Gesundheit (Health)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/gesundheit_get.php` | GET | Get health data |
| `/api/admin/gesundheit_save.php` | POST | Save health data |
| `/api/admin/gesundheit_doc_upload.php` | POST | Upload health doc |
| `/api/admin/gesundheit_doc_download.php` | GET | Download health doc |
| `/api/admin/gesundheit_doc_list.php` | GET | List health docs |
| `/api/admin/gesundheit_doc_delete.php` | POST | Delete health doc |
| `/api/admin/gesundheit_medikamente_list.php` | GET | List medications |
| `/api/admin/gesundheit_medikamente_save.php` | POST | Save medications |
| `/api/admin/gesundheit_termine_list.php` | GET | List medical appointments |
| `/api/admin/gesundheit_termine_save.php` | POST | Save medical appointment |
| `/api/admin/aerzte_manage.php` | GET/POST | Manage doctors database |
| `/api/admin/medikamente_search.php` | GET | Search medications database |
| `/api/admin/krankenkassen_list.php` | GET | List health insurance companies (~55) |

### Admin - Finanzen & Finanzamt
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/finanzen_get.php` | GET | Get financial data |
| `/api/admin/finanzen_save.php` | POST | Save financial data |
| `/api/admin/finanzaemter_list.php` | GET | List Finanzämter (tax offices) |
| `/api/admin/finanzamt/dokumente.php` | GET | List Finanzamt documents |
| `/api/admin/finanzamt/download.php` | GET | Download Finanzamt doc |
| `/api/admin/finanzamt_korrespondenz_upload.php` | POST | Upload Finanzamt correspondence |
| `/api/admin/finanzamt_korrespondenz_download.php` | GET | Download Finanzamt correspondence |
| `/api/admin/finanzamt_korrespondenz_list.php` | GET | List Finanzamt correspondence |
| `/api/admin/finanzamt_korrespondenz_delete.php` | POST | Delete Finanzamt correspondence |
| `/api/admin/grundfreibetrag.php` | GET | Get Grundfreibetrag (tax-free allowance) |
| `/api/admin/pkonto_freibetrag.php` | GET | Get P-Konto Freibetrag |
| `/api/admin/banken_manage.php` | GET/POST | Manage banks |

### Admin - Finanzverwaltung (Verein)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/finanzverwaltung/beitragszahlungen.php` | GET/POST | Membership fee payments |
| `/api/admin/finanzverwaltung/spenden.php` | GET/POST | Donations management |
| `/api/admin/finanzverwaltung/transaktionen.php` | GET/POST | Bank transactions |

### Admin - Korrespondenz (Correspondence)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/aa_korr_upload.php` | POST | Upload Arbeitsagentur correspondence |
| `/api/admin/aa_korr_download.php` | GET | Download AA correspondence |
| `/api/admin/aa_korr_list.php` | GET | List AA correspondence |
| `/api/admin/aa_korr_delete.php` | POST | Delete AA correspondence |
| `/api/admin/aa_korr_update_widerspruch.php` | POST | Update AA Widerspruch status |
| `/api/admin/kk_korrespondenz_upload.php` | POST | Upload Krankenkasse correspondence |
| `/api/admin/kk_korrespondenz_download.php` | GET | Download KK correspondence |
| `/api/admin/kk_korrespondenz_list.php` | GET | List KK correspondence |
| `/api/admin/kk_korrespondenz_delete.php` | POST | Delete KK correspondence |
| `/api/admin/kredit_korr_upload.php` | POST | Upload credit correspondence |
| `/api/admin/kredit_korr_download.php` | GET | Download credit correspondence |
| `/api/admin/kredit_korr_list.php` | GET | List credit correspondence |
| `/api/admin/kredit_korr_delete.php` | POST | Delete credit correspondence |

### Admin - Freizeit, Bildung & Routinen
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/freizeit_get.php` | GET | Get leisure data |
| `/api/admin/freizeit_save.php` | POST | Save leisure data |
| `/api/admin/freizeit_datenbank.php` | GET | Leisure activities database |
| `/api/admin/schulen_manage.php` | GET/POST | Manage schools |
| `/api/admin/schulabschluesse_list.php` | GET | List school degrees |
| `/api/admin/schulbildung_dok.php` | GET/POST | Education documents |
| `/api/admin/schulbildung_dok_download.php` | GET | Download education doc |
| `/api/admin/routine_create.php` | POST | Create routine task |
| `/api/admin/routine_list.php` | GET | List routine tasks |
| `/api/admin/routine_update.php` | POST | Update routine task |
| `/api/admin/routine_delete.php` | POST | Delete routine task |
| `/api/admin/routine_executions.php` | GET/POST | Routine execution log |

### Admin - Diverse
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/admin/handelsregister.php` | GET | Server-side Handelsregister search |
| `/api/admin/handelsregister_document.php` | GET | Download Handelsregister document |
| `/api/admin/verwarnungen_create.php` | POST | Create warning |
| `/api/admin/verwarnungen_list.php` | GET | List warnings |
| `/api/admin/verwarnungen_delete.php` | POST | Delete warning |
| `/api/admin/verifizierung_list.php` | GET | List verifications |
| `/api/admin/verifizierung_update.php` | POST | Update verification |
| `/api/admin/versorgungsamt_manage.php` | GET/POST | Manage Versorgungsamt |
| `/api/admin/vereineinstellungen.php` | GET/POST | Vereineinstellungen |
| `/api/admin/notizen_create.php` | POST | Create note |
| `/api/admin/notizen_list.php` | GET | List notes |
| `/api/admin/notizen_delete.php` | POST | Delete note |
| `/api/admin/ocr_lohnsteuerbescheinigung.php` | POST | OCR Lohnsteuerbescheinigung |
| `/api/admin/feiertage_list.php` | GET | List holidays |
| `/api/admin/sprachen_list.php` | GET | List languages |
| `/api/admin/staatsangehoerigkeiten_list.php` | GET | List nationalities |
| `/api/admin/fuehrerscheinklassen_list.php` | GET | List driving license classes |
| `/api/admin/deutschlandticket_saetze.php` | GET | Deutschlandticket prices |
| `/api/admin/jobcenter_regelsaetze.php` | GET | Jobcenter standard rates |
| `/api/admin/kindergeld_saetze.php` | GET | Kindergeld rates |
| `/api/admin/kurs_traeger_manage.php` | GET/POST | Manage course providers |

### Device Management
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/device/register.php` | POST | Înregistrează device nou |
| `/api/device/validate.php` | POST | Validează device key |

### Chat (Live Chat - 13 endpoints)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/chat/start.php` | POST | Pornește conversație (member) |
| `/api/chat/admin_start.php` | POST | Pornește conversație (admin) |
| `/api/chat/close.php` | POST | Închide conversație |
| `/api/chat/conversations.php` | GET | Lista conversații |
| `/api/chat/messages.php` | GET | Istoric mesaje |
| `/api/chat/send.php` | POST | Trimite mesaj |
| `/api/chat/mark_read.php` | POST | Marchează mesaje ca citite |
| `/api/chat/mute.php` | POST | Mute/unmute conversație |
| `/api/chat/upload.php` | POST | Upload fișier atașat |
| `/api/chat/download.php` | GET | Download atașament |
| `/api/chat/support_status.php` | GET | Get support availability status |
| `/api/chat/scheduled_messages.php` | GET/POST | Scheduled messages management |
| `/api/chat/conversation_scheduled.php` | GET | Get scheduled messages for conversation |

### Tickets (Ticketverwaltung - 20+ endpoints)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/tickets/create.php` | POST | Creează ticket |
| `/api/tickets/admin_create.php` | POST | Admin creează ticket |
| `/api/tickets/list.php` | GET | Lista tickete utilizator |
| `/api/tickets/admin_list.php` | GET | Lista toate ticketele (admin) |
| `/api/tickets/update.php` | POST | Actualizează status ticket |
| `/api/tickets/mark_viewed.php` | POST | Mark ticket as viewed |
| `/api/tickets/poll_notifications.php` | POST | Poll notificări (Vorsitzer, 60s) |
| `/api/tickets/poll_notifications_member.php` | POST | Poll notificări (Member) |
| `/api/tickets/comments/add.php` | POST | Adaugă comentariu |
| `/api/tickets/comments/list.php` | GET | Lista comentarii |
| `/api/tickets/attachments/upload.php` | POST | Upload attachment |
| `/api/tickets/attachments/download.php` | GET | Download attachment |
| `/api/tickets/attachments/delete.php` | POST | Delete attachment |
| `/api/tickets/aufgaben/create.php` | POST | Create ticket task |
| `/api/tickets/aufgaben/list.php` | GET | List ticket tasks |
| `/api/tickets/aufgaben/update.php` | POST | Update ticket task |
| `/api/tickets/aufgaben/delete.php` | POST | Delete ticket task |
| `/api/tickets/aufgaben/toggle.php` | POST | Toggle task completion |
| `/api/tickets/categories/list.php` | GET | List ticket categories |
| `/api/tickets/history/list.php` | GET | Ticket status history |
| `/api/tickets/time/start.php` | POST | Start time tracking |
| `/api/tickets/time/stop.php` | POST | Stop time tracking |
| `/api/tickets/time/add.php` | POST | Add manual time entry |
| `/api/tickets/time/delete.php` | POST | Delete time entry |
| `/api/tickets/time/list.php` | GET | List time entries |
| `/api/tickets/time/running.php` | GET | Get running timer |
| `/api/tickets/time/sync.php` | POST | Sync time entries |
| `/api/tickets/time/user_summary.php` | GET | User time summary |
| `/api/tickets/time/weekly.php` | GET | Weekly time report |

### Notar (Notariatsverwaltung)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/notar/besuche.php` | GET | Lista vizite notar |
| `/api/notar/dokumente.php` | GET | Lista documente notar |
| `/api/notar/rechnungen.php` | GET | Lista facturi notar |
| `/api/notar/zahlungen.php` | GET | Lista plăți notar |
| `/api/notar/aufgaben.php` | GET/POST | Notar tasks management |

### Vereinverwaltung
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/vereinverwaltung/get.php` | GET | Obține date asociație |
| `/api/vereinverwaltung/update.php` | POST | Actualizează date asociație |
| `/api/vereinverwaltung/board_members.php` | GET | Board members list |

### Stadtverwaltung
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/stadtverwaltung/behoerden.php` | GET | Lista Behörden |
| `/api/stadtverwaltung/drogerien.php` | GET | Lista Drogerien |
| `/api/stadtverwaltung/krankenhaeuser.php` | GET | Lista Krankenhäuser |
| `/api/stadtverwaltung/krankenkassen.php` | GET | Lista Krankenkassen |
| `/api/stadtverwaltung/maerkte.php` | GET | Lista Märkte |
| `/api/stadtverwaltung/praxen.php` | GET | Lista Praxen |

### DHL Tracking
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/tracking/dhl.php` | GET/POST | DHL package tracking |
| `/api/tracking/dhl_settings.php` | GET/POST | DHL tracking settings |
| `/api/tracking/filialfinder.php` | GET | DHL Filialfinder |

### Platform (Postcard, Tasks, Notes, Credentials)
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/platform/postcard_create.php` | POST | Create postcard |
| `/api/platform/postcard_list.php` | GET | List postcards |
| `/api/platform/postcard_update.php` | POST | Update postcard |
| `/api/platform/postcard_delete.php` | POST | Delete postcard |
| `/api/platform/postcard_account_get.php` | GET | Get postcard account |
| `/api/platform/postcard_account_save.php` | POST | Save postcard account |
| `/api/platform/aufgaben_create.php` | POST | Create platform task |
| `/api/platform/aufgaben_list.php` | GET | List platform tasks |
| `/api/platform/aufgaben_update.php` | POST | Update platform task |
| `/api/platform/aufgaben_delete.php` | POST | Delete platform task |
| `/api/platform/notizen_create.php` | POST | Create note |
| `/api/platform/notizen_list.php` | GET | List notes |
| `/api/platform/notizen_delete.php` | POST | Delete note |
| `/api/platform/get_credentials.php` | GET | Get stored credentials |
| `/api/platform/save_credentials.php` | POST | Save credentials |

### Member Endpoints
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/member/update_personal_data.php` | POST | Update personal data |
| `/api/member/update_finanzielle_situation.php` | POST | Update financial situation |
| `/api/member/update_mitgliedschaftsbeginn.php` | POST | Update membership start |
| `/api/member/update_zahlungsdaten.php` | POST | Update payment data |
| `/api/member/upload_leistungsbescheid.php` | POST | Upload benefit notice |
| `/api/member/verifizierung_list.php` | GET | List verifications |

### FCM Push Notifications
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/fcm/register.php` | POST | Register FCM token |
| `/api/fcm/unregister.php` | POST | Unregister FCM token |

### System & Diagnostics
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/version_vorsitzer.php` | GET | Version check Vorsitzer (Device Key required) |
| `/api/version_mitglieder.php` | GET | Version check Mitglieder |
| `/api/version_schatzmeister.php` | GET | Version check Schatzmeister |
| `/api/changelog_vorsitzer.php` | GET | Changelog Vorsitzer (Device Key required) |
| `/api/changelog_mitglieder.php` | GET | Changelog Mitglieder |
| `/api/changelog_schatzmeister.php` | GET | Changelog Schatzmeister |
| `/api/diagnostic/log.php` | POST | Log diagnostic app (120s interval) + battery |
| `/api/logs/debug.php` | POST | Log debug messages |
| `/api/logs/store.php` | POST | Store app logs |
| `/api/logs/vorsitzer_logs.php` | POST | Real-time log upload Vorsitzer (30s) |
| `/api/logs/mitglieder_windows.php` | POST | Log upload Mitglieder Windows |
| `/api/logs/mitglieder_android.php` | POST | Log upload Mitglieder Android |
| `/api/logs/schatzmeister_logs.php` | POST | Log upload Schatzmeister |
| `/api/pauschalen.php` | GET | Pauschalen (allowances) data |
| `/api/debug_messages.php` | GET | Debug messages |

### Cron Jobs
| Endpoint | Method | Descriere |
|----------|--------|-----------|
| `/api/cron/auto_suspend.php` | GET | Auto-suspend inactive users |
| `/api/cron/cleanup_chat.php` | GET | Cleanup old chat data |
| `/api/cron/cleanup_old_scheduled_messages.php` | GET | Cleanup expired scheduled messages |
| `/api/cron/send_scheduled_messages.php` | GET | Send pending scheduled messages |
| `/api/cron/auto_delete_expired_docs.php` | GET | Auto-delete expired documents |
| `/api/cron/update_pauschalen.php` | GET | Update Pauschalen data |

### Config & Helpers
| File | Descriere |
|------|-----------|
| `/api/config.php` | Configurație DB + constante |
| `/api/helpers.php` | Funcții helper (JWT, auth, etc.) |
| `/api/helpers/TranslationHelper.php` | NLLB-200 translation helper |
| `/api/helpers/FcmService.php` | Firebase Cloud Messaging service |
| `/api/helpers/NtfyService.php` | ntfy push notifications (Mitglieder, prefix: icd360s_) |
| `/api/helpers/NtfySchatzmeisterService.php` | ntfy push notifications (Schatzmeister, prefix: schatzmeister_) |
| `/api/helpers/NtfyVorsitzerService.php` | ntfy push notifications (Vorsitzer, prefix: vorsitzer_) |
| `/api/helpers/WebSocketNotifier.php` | WebSocket notification helper |
| `/api/helpers/ip_helper.php` | IP detection helper |

## Structura Proiect

```
lib/
├── main.dart                        # App entry point + window initialization
├── services/                        # Business logic layer (25 services)
│   ├── api_service.dart             # HTTP requests + token management
│   ├── chat_service.dart            # WebSocket chat + call signaling + online status
│   ├── voice_call_service.dart      # WebRTC voice call
│   ├── termin_service.dart          # Termine + Urlaub management
│   ├── ticket_service.dart          # Ticket system
│   ├── ticket_notification_service.dart  # Ticket notification polling (60s)
│   ├── device_key_service.dart      # Device registration + validation
│   ├── update_service.dart          # Auto-update checker + silent installer
│   ├── diagnostic_service.dart      # App diagnostics (120s interval) + battery monitoring
│   ├── notification_service.dart    # Cross-platform notifications (flutter_local_notifications)
│   ├── logger_service.dart          # Debug logging + real-time upload
│   ├── tray_service.dart            # System tray management (desktop)
│   ├── startup_service.dart         # Auto-start with OS (desktop)
│   ├── heartbeat_service.dart       # Real-time last_seen updates (15s)
│   ├── dokumente_service.dart       # Document management service
│   ├── handelsregister_client_service.dart  # Handelsregister.de client-side scraping
│   ├── verwarnung_service.dart      # Warning/penalty management
│   ├── platform_service.dart        # Platform detection + capabilities
│   ├── news_service.dart            # News/RSS feed service
│   ├── radio_service.dart           # Live radio streaming service
│   ├── routine_service.dart         # Routine tasks management (encrypted)
│   ├── transit_service.dart         # Public transit / nearby stops
│   ├── weather_service.dart         # Weather data service
│   ├── ntfy_service.dart            # ntfy push notifications (self-hosted, no FCM)
│   └── http_client_factory.dart     # Certificate pinning factory (ISRG Root X1)
├── models/                          # Data models
│   └── user.dart                    # User model (id, mitgliedernummer, role, status)
├── screens/                         # Full-page views (34 screens)
│   ├── login_screen.dart            # Login/Register tabs
│   ├── dashboard_screen.dart        # Admin dashboard (Vorsitzer)
│   ├── terminverwaltung_screen.dart # Weekly calendar + urlaub
│   ├── ticketverwaltung_screen.dart # Ticket management
│   ├── vereinverwaltung_screen.dart # Organization admin
│   ├── finanzverwaltung_screen.dart # Financial management (Beitragszahlungen, Spenden, Transaktionen)
│   ├── notar_screen.dart            # Notary functions
│   ├── webview_screen.dart          # Embedded browser
│   ├── behoerden_screen.dart        # Government authorities screen
│   ├── deutschepost_screen.dart     # Deutsche Post services
│   ├── sendungsverfolgung.dart      # DHL package tracking (Sendungsverfolgung)
│   ├── postcard.dart                # Postcard creation and management
│   ├── handelsregister_screen.dart  # Trade register (Handelsregister.de)
│   ├── vereinregister_screen.dart   # Association register
│   ├── finanzamt_screen.dart        # Tax office (Finanzamt) - ELSTER, Steuererklarung
│   ├── gericht_screen.dart          # Court (Gericht) - legal proceedings
│   ├── arbeitsagentur_screen.dart   # Employment agency (Arbeitsagentur)
│   ├── ordnungsmassnahmen_screen.dart # Disciplinary measures
│   ├── statistik_screen.dart        # Statistics and analytics
│   ├── reiseplanung_screen.dart     # Travel planning
│   ├── db_mobilitat_unterstutzung_screen.dart # Deutsche Bahn mobility support
│   ├── netzwerk_screen.dart         # Network management
│   ├── vr_bank_screen.dart          # VR Bank integration
│   ├── gls_bank_screen.dart         # GLS Bank integration
│   ├── stifter_helfen_screen.dart   # Stifter-helfen nonprofit portal
│   ├── google_nonprofit_screen.dart # Google for Nonprofits
│   ├── microsoft_nonprofit_screen.dart # Microsoft for Nonprofits
│   ├── archiv_screen.dart           # Document archive management
│   ├── pdf_manager_screen.dart      # PDF management and compression
│   ├── jpg2pdf_screen.dart          # JPG to PDF converter
│   ├── dienste_screen.dart          # Services overview
│   ├── routinenaufgaben_screen.dart # Routine tasks (encrypted)
│   ├── einstellungen_screen.dart    # Settings (Grundfreibetrag, Kindergeld, etc.)
│   └── jasmina_screen.dart          # AI Assistant (Jasmina)
├── widgets/                         # Reusable UI components (63 widgets)
│   ├── dashboard_sidebar.dart       # Navigation sidebar
│   ├── dashboard_stats.dart         # Statistics cards
│   ├── user_data_table.dart         # User list table
│   ├── user_details_dialog.dart     # Edit user + device/session management
│   ├── profile_dialog.dart          # User profile view
│   ├── personal_data_dialog.dart    # Edit personal info
│   ├── login_tab.dart               # Login form
│   ├── register_tab.dart            # Register form (Vorsitzer only)
│   ├── forgot_password_dialog.dart  # Password recovery
│   ├── admin_chat_dialog.dart       # Admin chat interface
│   ├── live_chat_dialog.dart        # Member chat interface
│   ├── chat_header.dart             # Chat dialog header
│   ├── chat_message_bubble.dart     # Message display
│   ├── chat_input_area.dart         # Message input
│   ├── chat_attachment_item.dart    # File attachment display
│   ├── conversation_list_item.dart  # Chat list item + online status
│   ├── incoming_call_dialog.dart    # Voice call UI
│   ├── termin_dialogs.dart          # Create/Edit termine
│   ├── ticket_dialogs.dart          # Create/View tickets
│   ├── ticket_details_dialog.dart   # View ticket details + camera capture + crop
│   ├── notar_dialogs.dart           # Notar-specific dialogs
│   ├── notar_cards.dart             # Notar info cards
│   ├── confirm_dialogs.dart         # Generic confirmations
│   ├── legal_footer.dart            # Footer + version + changelog + update checker
│   ├── changelog.dart               # Changelog viewer dialog
│   ├── update_dialog.dart           # Update notification + download
│   ├── debug_console.dart           # Debug output console
│   ├── diagnostic_consent_dialog.dart # Diagnostic opt-in
│   ├── file_viewer_dialog.dart      # File preview dialog (PDF, images)
│   ├── responsive_layout.dart       # Responsive layout wrapper
│   ├── visitenkarte.dart            # Business card widget
│   ├── lebenslauf.dart              # CV/Resume (Lebenslauf) generator
│   ├── moon.dart                    # Moon phase widget
│   ├── pfandung_grenze.dart         # Pfandungsfreigrenze calculator
│   ├── finanzen_tab_content.dart    # Finance tab content
│   ├── finanzen_bank.dart           # Bank account management
│   ├── finanzen_kredit.dart         # Credit/loan management
│   ├── gesundheit_tab_content.dart  # Health tab content (doctors, medications, appointments)
│   ├── freizeit_tab_content.dart    # Leisure tab content
│   ├── behorde_tab_content.dart     # Government authority tab content (orchestrator)
│   ├── behorde_jobcenter.dart       # Jobcenter widget
│   ├── behorde_arbeitsagentur.dart  # Employment agency widget
│   ├── behorde_auslaenderbehoerde.dart # Immigration office widget
│   ├── behorde_bamf.dart            # BAMF (asylum office) widget
│   ├── behorde_deutschlandticket.dart # Deutschlandticket widget
│   ├── behorde_einwohnermeldeamt.dart # Residents registration widget
│   ├── behorde_familienkasse.dart   # Family benefits office widget
│   ├── behorde_finanzamt.dart       # Tax office widget
│   ├── behorde_finanzamt_steuerklarung.dart # Tax declaration widget
│   ├── behorde_gericht.dart         # Court widget
│   ├── behorde_jugendamt.dart       # Youth welfare office widget
│   ├── behorde_konsulat.dart        # Consulate widget
│   ├── behorde_krankenkasse.dart    # Health insurance widget
│   ├── behorde_rentenversicherung.dart # Pension insurance widget
│   ├── behorde_schule.dart          # School/education widget
│   ├── behorde_sozialamt.dart       # Social welfare office widget
│   ├── behorde_vermieter.dart       # Landlord/tenant widget
│   ├── behorde_wohngeldstelle.dart  # Housing benefit office widget
│   ├── arbeitgeber_behorde_content.dart # Employer management widget
│   ├── grundfreibetrag_einstellung.dart # Tax-free allowance settings
│   ├── jobcenter_einstellung.dart   # Jobcenter rate settings
│   ├── kindergeld_einstellung.dart  # Child benefit settings
│   └── deutschlandticket_einstellung.dart # Deutschlandticket settings
└── utils/                           # Helper functions
    └── role_helpers.dart            # Role colors, prefixes, status helpers

installer/
├── icd360sev_setup.iss              # Inno Setup installer script
├── vc_redist.x64.exe                # Visual C++ redistributable
└── MicrosoftEdgeWebView2RuntimeInstallerX64.exe  # WebView2 runtime

assets/
├── app_icon.ico                     # Windows app icon
├── badges/                          # Notification badge icons
├── tray_icons/                      # System tray icons
├── card_logos/                      # Bank/card logos
└── fonts/                           # Custom fonts

windows/                             # Native Windows integration
├── CMakeLists.txt                   # Windows build config
├── flutter/                         # Flutter Windows wrapper
└── runner/                          # Native Windows runner
```

### Services Directory (lib/services/) - Detailed (25 Services)

| Service | Descriere |
|---------|-----------|
| `api_service.dart` | HTTP client, JWT token management, device key validation, refresh token |
| `chat_service.dart` | WebSocket connection, auto-reconnect, real-time chat, online status tracking, call signaling |
| `voice_call_service.dart` | WebRTC voice calls, ICE candidates, audio codec management |
| `termin_service.dart` | Appointment management, vacation periods, weekly calendar data |
| `ticket_service.dart` | Ticket CRUD operations, status management |
| `ticket_notification_service.dart` | Ticket notification polling (60s interval), native notifications |
| `device_key_service.dart` | Generate unique device keys, device registration |
| `update_service.dart` | Version checking, installer download, silent update launch |
| `notification_service.dart` | Cross-platform notifications (flutter_local_notifications) |
| `diagnostic_service.dart` | App telemetry (120s interval), battery monitoring (battery_plus), performance |
| `heartbeat_service.dart` | Real-time last_seen updates (60s interval), online status tracking |
| `logger_service.dart` | Centralized logging, device ID generation, real-time log upload to server |
| `startup_service.dart` | Auto-start with OS configuration (desktop only) |
| `tray_service.dart` | System tray management, minimize to tray (desktop only) |
| `dokumente_service.dart` | Document management service (upload, download, organize) |
| `handelsregister_client_service.dart` | Client-side handelsregister.de scraping (HTML parsing) |
| `verwarnung_service.dart` | Warning/penalty management system |
| `platform_service.dart` | Platform detection (Windows/macOS/Linux/Android/iOS) and capabilities check |
| `news_service.dart` | News/RSS feed fetching and display |
| `radio_service.dart` | Live radio streaming (just_audio, AVFoundation on macOS) |
| `routine_service.dart` | Routine tasks management with AES-256 encryption (encrypt package) |
| `transit_service.dart` | Public transit nearby stops (geolocator for GPS) |
| `weather_service.dart` | Weather data fetching and display |
| `ntfy_service.dart` | ntfy push notifications - self-hosted, no Google/FCM, HTTP NDJSON stream |
| `http_client_factory.dart` | Certificate pinning factory - ISRG Root X1 (Let's Encrypt), valid until 2035 |

### Screens Directory (lib/screens/) - Detailed (34 Screens)

| Screen | Descriere |
|--------|-----------|
| `login_screen.dart` | Login/Register tabs, credential saving, password recovery |
| `dashboard_screen.dart` | Admin dashboard, user management, statistics, heartbeat start |
| `terminverwaltung_screen.dart` | Weekly calendar, appointment scheduling, vacation management (Urlaub) |
| `ticketverwaltung_screen.dart` | Ticket management system with camera capture + crop support |
| `vereinverwaltung_screen.dart` | Organization/association administration |
| `finanzverwaltung_screen.dart` | Financial management (Beitragszahlungen, Spenden, Transaktionen) |
| `notar_screen.dart` | Notary functions and documents |
| `webview_screen.dart` | Embedded browser for external content |
| `behoerden_screen.dart` | Government authorities (Behörden) - tabbed interface with 18+ Behörden |
| `deutschepost_screen.dart` | Deutsche Post services |
| `sendungsverfolgung.dart` | DHL package tracking (Sendungsverfolgung) with tracking API |
| `postcard.dart` | Postcard creation, management and sending |
| `handelsregister_screen.dart` | Trade register (Handelsregister.de) - client-side scraping, company search |
| `vereinregister_screen.dart` | Association register (Vereinsregister) - search and view associations |
| `finanzamt_screen.dart` | Tax office (Finanzamt) - ELSTER Online, Steuererklarung, Korrespondenz |
| `gericht_screen.dart` | Court (Gericht) - legal proceedings management |
| `arbeitsagentur_screen.dart` | Employment agency (Arbeitsagentur) - Korrespondenz, Arbeitsvermittler |
| `ordnungsmassnahmen_screen.dart` | Disciplinary measures (Verwarnungen) management |
| `statistik_screen.dart` | Statistics and analytics dashboard |
| `reiseplanung_screen.dart` | Travel planning with transit integration |
| `db_mobilitat_unterstutzung_screen.dart` | Deutsche Bahn mobility support |
| `netzwerk_screen.dart` | Network management |
| `vr_bank_screen.dart` | VR Bank integration (online banking) |
| `gls_bank_screen.dart` | GLS Bank integration (online banking) |
| `stifter_helfen_screen.dart` | Stifter-helfen nonprofit portal |
| `google_nonprofit_screen.dart` | Google for Nonprofits management |
| `microsoft_nonprofit_screen.dart` | Microsoft for Nonprofits management |
| `archiv_screen.dart` | Document archive (upload, download, organize) |
| `pdf_manager_screen.dart` | PDF management and compression |
| `jpg2pdf_screen.dart` | JPG to PDF converter |
| `dienste_screen.dart` | Services overview (Radio, News, Weather, Transit) |
| `routinenaufgaben_screen.dart` | Routine tasks with AES-256 encryption |
| `einstellungen_screen.dart` | Settings (Grundfreibetrag, Kindergeld, Jobcenter, Deutschlandticket) |
| `jasmina_screen.dart` | AI Assistant (Jasmina) |

### Widgets Directory (lib/widgets/) - Detailed (63 Widgets)

**Dialog Components:**
- `user_details_dialog.dart` - View/edit user, device/session management
- `profile_dialog.dart` - User profile display and settings
- `forgot_password_dialog.dart` - Password recovery flow
- `personal_data_dialog.dart` - Personal information editor
- `termin_dialogs.dart` - Create/edit appointments with participants
- `ticket_dialogs.dart` - Create/view tickets with attachments
- `ticket_details_dialog.dart` - View ticket details + macOS camera capture + crop/edit photo
- `notar_dialogs.dart` - Notary-specific dialogs
- `confirm_dialogs.dart` - Generic confirmation dialogs
- `update_dialog.dart` - App update notification + download progress
- `incoming_call_dialog.dart` - Incoming voice call UI
- `diagnostic_consent_dialog.dart` - Diagnostic data opt-in
- `file_viewer_dialog.dart` - File preview dialog (PDF, images) with pdfrx

**Chat Components:**
- `admin_chat_dialog.dart` - Admin chat interface with online user list
- `live_chat_dialog.dart` - Member chat interface, message history
- `chat_header.dart` - Chat dialog header with user status
- `chat_message_bubble.dart` - Individual message display
- `chat_input_area.dart` - Message input & send functionality
- `conversation_list_item.dart` - Chat list item with online status indicator
- `chat_attachment_item.dart` - File attachment display

**Dashboard Components:**
- `dashboard_sidebar.dart` - Navigation sidebar with role-based menu
- `dashboard_stats.dart` - Statistics cards (total users, active, suspended)
- `user_data_table.dart` - User list table with sorting/filtering

**Login Components:**
- `login_tab.dart` - Login form with credential save option
- `register_tab.dart` - Registration form (Vorsitzer only)

**Behörden Tab Widgets (18 individual authority widgets):**
- `behorde_tab_content.dart` - Orchestrator for all Behörden tabs
- `behorde_jobcenter.dart` - Jobcenter (Regelsätze, Bescheide)
- `behorde_arbeitsagentur.dart` - Arbeitsagentur (Korrespondenz, Vermittler)
- `behorde_auslaenderbehoerde.dart` - Ausländerbehörde (residence permits)
- `behorde_bamf.dart` - BAMF (asylum office)
- `behorde_deutschlandticket.dart` - Deutschlandticket management
- `behorde_einwohnermeldeamt.dart` - Einwohnermeldeamt (registration)
- `behorde_familienkasse.dart` - Familienkasse (child benefits)
- `behorde_finanzamt.dart` - Finanzamt (tax office)
- `behorde_finanzamt_steuerklarung.dart` - Steuererklärung (tax declaration)
- `behorde_gericht.dart` - Gericht (court)
- `behorde_jugendamt.dart` - Jugendamt (youth welfare)
- `behorde_konsulat.dart` - Konsulat (consulate)
- `behorde_krankenkasse.dart` - Krankenkasse (health insurance)
- `behorde_rentenversicherung.dart` - Rentenversicherung (pension)
- `behorde_schule.dart` - Schule (school/education)
- `behorde_sozialamt.dart` - Sozialamt (social welfare)
- `behorde_vermieter.dart` - Vermieter (landlord/tenant)
- `behorde_wohngeldstelle.dart` - Wohngeldstelle (housing benefit)

**Finance & Settings Widgets:**
- `finanzen_tab_content.dart` - Finance tab orchestrator
- `finanzen_bank.dart` - Bank account management
- `finanzen_kredit.dart` - Credit/loan management
- `pfandung_grenze.dart` - Pfändungsfreigrenze calculator
- `grundfreibetrag_einstellung.dart` - Grundfreibetrag (tax-free allowance) settings
- `jobcenter_einstellung.dart` - Jobcenter Regelsätze settings
- `kindergeld_einstellung.dart` - Kindergeld (child benefit) rate settings
- `deutschlandticket_einstellung.dart` - Deutschlandticket price settings

**Health & Leisure Widgets:**
- `gesundheit_tab_content.dart` - Health tab (doctors, medications, appointments, documents)
- `freizeit_tab_content.dart` - Leisure tab (activities database)

**Employment Widget:**
- `arbeitgeber_behorde_content.dart` - Employer management (Arbeitgeber, Berufserfahrung, Qualifikationen)

**Document & Utility Widgets:**
- `lebenslauf.dart` - CV/Resume (Lebenslauf) generator with PDF export
- `moon.dart` - Moon phase display widget
- `visitenkarte.dart` - Business card widget (contact info display)

**Other Components:**
- `legal_footer.dart` - Footer with version, changelog, update checker (5min timer)
- `changelog.dart` - Changelog viewer dialog (reads from server API)
- `debug_console.dart` - Debug output console
- `notar_cards.dart` - Notary information cards
- `responsive_layout.dart` - Responsive layout wrapper for cross-platform UI

## Pachete Flutter

```yaml
dependencies:
  # ============================================================
  # CORE PACKAGES
  # ============================================================
  http: ^1.2.0                      # HTTP requests
  shared_preferences: ^2.3.0        # Local storage for tokens
  provider: ^6.1.0                  # State management
  flutter_secure_storage: ^10.0.0   # Encrypted credentials (DPAPI/Keychain/libsecret)

  # ============================================================
  # NETWORKING & REAL-TIME
  # ============================================================
  web_socket_channel: ^3.0.1        # WebSocket for real-time chat
  flutter_webrtc: ^1.2.1            # WebRTC for voice/video calls
  html: ^0.15.4                     # HTML parsing for handelsregister.de scraping

  # ============================================================
  # UI & LOCALIZATION
  # ============================================================
  flutter_localizations:            # German date/time pickers (SDK)
    sdk: flutter
  intl: ^0.20.2                     # Date formatting + week number calculation

  # ============================================================
  # ENCRYPTION & SECURITY
  # ============================================================
  encrypt: ^5.0.3                   # AES-256 encryption for routine data (client-side)

  # ============================================================
  # FILE HANDLING & MEDIA
  # ============================================================
  path_provider: ^2.1.0             # Temp directory access
  file_picker: ^8.0.0               # File attachments (chat, tickets)
  image_picker: ^1.1.2              # Image picker for camera capture (mobile)
  camera_macos: ^0.0.9              # Native macOS camera capture (AVFoundation)
  crop_your_image: ^2.0.0           # Image cropping (pure Dart, cross-platform)
  signature: ^6.3.0                 # Handwritten signature capture (pure Dart)
  url_launcher: ^6.2.0              # Open URLs in browser
  open_filex: ^4.5.0                # Open files with default app
  pdfrx: ^2.2.24                    # PDF viewer/renderer
  pdf: ^3.11.0                      # PDF generation (Zuwendungsbestätigung/Spendequittung)
  printing: ^5.13.0                 # PDF printing/sharing/saving
  image: ^4.5.4                     # Image processing for PDF compression (JPEG encoding)
  archive: ^4.0.9                   # Archive extraction (ZIP, TAR)

  # ============================================================
  # LOCATION & AUDIO
  # ============================================================
  geolocator: ^12.0.0               # GPS for transit nearby stops
  battery_plus: ^6.0.0              # Battery level monitoring for diagnostics
  just_audio: ^0.9.43               # Live radio streaming (AVFoundation on macOS)

  # ============================================================
  # NOTIFICATIONS & BADGES
  # ============================================================
  flutter_local_notifications: ^18.0.0  # Cross-platform notifications
  flutter_app_badger: ^1.5.0        # App icon badges for unread count (Android/iOS)

  # ============================================================
  # DEVICE & PLATFORM
  # ============================================================
  device_info_plus: ^12.3.0         # Device identification
  uuid: ^3.0.7                      # UUID generation for device ID

  # ============================================================
  # DESKTOP-ONLY PACKAGES (Windows, macOS, Linux)
  # ============================================================
  windows_single_instance: ^1.0.1   # Single instance - prevent multiple windows
  webview_windows: ^0.4.0           # WebView for Windows (WebView2)
  window_manager: ^0.5.1            # Window control (size, position, maximize)
  system_tray: ^2.0.3               # System tray - minimize to tray
  launch_at_startup: ^0.5.1         # Auto-start with OS login
  windows_taskbar: ^1.1.2           # Windows taskbar flash icon and badge

  # ============================================================
  # MOBILE-ONLY PACKAGES (Android, iOS)
  # ============================================================
  webview_flutter: ^4.10.0          # WebView for mobile (Android/iOS)
  workmanager: ^0.5.2               # Background tasks scheduler (mobile)
```

## Server Architecture

### WebSocket Server
**Location:** `/var/www/icd360sev.icd360s.de/websocket/`
**URL:** `wss://icd360sev.icd360s.de/wss/`
**Framework:** Ratchet PHP WebSocket library

**Files:**
- `server.php` - WebSocket entry point, bootstrapper
- `src/ChatServer.php` - Main WebSocket logic (chat, presence, call signaling)

**Event Types (WebSocket Messages):**
| Type | Direction | Descriere |
|------|-----------|-----------|
| `auth` | Client→Server | Autentificare WebSocket cu token |
| `auth_success` | Server→Client | Auth succes + listă online_users |
| `auth_error` | Server→Client | Auth eșuat |
| `chat_message` | Client→Server | Trimite mesaj chat |
| `message` | Server→Client | Mesaj nou primit |
| `typing` | Client→Server | User scrie mesaj |
| `typing_indicator` | Server→Client | Altcineva scrie |
| `read_receipt` | Server→Client | Mesaj citit de destinatar |
| `online_users` | Server→Client | Lista completă utilizatori online (periodic) |
| `user_joined` | Server→Client | Utilizator intră online |
| `user_left` | Server→Client | Utilizator iese offline |
| `user_disconnected` | Server→Client | Utilizator deconectat neașteptat |
| `call_offer` | Server→Client | Ofertă apel voice (WebRTC SDP) |
| `call_answer` | Server→Client | Răspuns apel (WebRTC SDP) |
| `call_rejected` | Server→Client | Apel respins |
| `call_busy` | Server→Client | Apelat ocupat |
| `call_ended` | Server→Client | Apel închis |
| `ice_candidate` | Server→Client | WebRTC ICE candidate |
| `new_device_login` | Server→Client | Notificare device nou detectat |

**WebSocket Server Management:**
```bash
# Verificare status
ssh -i "vps_icd360sev_icd360s.de" -p 36000 root@icd360sev.icd360s.de \
  "supervisorctl status icd360s-websocket"

# Restart server
ssh -i "vps_icd360sev_icd360s.de" -p 36000 root@icd360sev.icd360s.de \
  "supervisorctl restart icd360s-websocket"

# View logs
ssh -i "vps_icd360sev_icd360s.de" -p 36000 root@icd360sev.icd360s.de \
  "tail -f /var/log/supervisor/icd360s-websocket.log"
```

### API Server Structure (~175 PHP files)
**Location:** `/var/www/icd360sev.icd360s.de/api/`
**Base URL:** `https://icd360sev.icd360s.de/api/`

**Directory Structure:**
```
/var/www/icd360sev.icd360s.de/api/
├── config.php                  # DB config + constante
├── helpers.php                 # JWT, auth, utility functions
├── helpers/                    # Helper classes
│   ├── TranslationHelper.php   # NLLB-200 translation
│   ├── FcmService.php          # Firebase Cloud Messaging
│   ├── NtfyService.php         # ntfy Mitglieder (prefix: icd360s_)
│   ├── NtfySchatzmeisterService.php  # ntfy Schatzmeister (prefix: schatzmeister_)
│   ├── NtfyVorsitzerService.php      # ntfy Vorsitzer (prefix: vorsitzer_)
│   ├── WebSocketNotifier.php   # WebSocket notification helper
│   └── ip_helper.php           # IP detection
├── auth/                       # Autentificare (27 endpoints)
│   ├── login_vorsitzer.php, login_mitglied.php, login_schatzmeister.php
│   ├── register.php, recover.php
│   ├── change_password.php, change_email.php
│   ├── refresh.php, validate.php
│   ├── get_profile.php, update_profile.php, update_personal_data.php
│   ├── update_mitgliedsart.php, update_zahlungsmethode.php
│   ├── account_status.php, check_email.php, delete_account.php
│   ├── heartbeat.php, heartbeat_app.php, accept_document.php
│   ├── my_sessions.php, revoke_my_session.php, logout_device.php
│   └── my_dokumente.php, my_dokumente_download.php, my_verifizierung.php, my_verwarnungen.php
├── admin/                      # Admin endpoints (119 endpoints!)
│   ├── users.php, user_*.php   # User management (10 files)
│   ├── termine_*.php           # Termine (5 files)
│   ├── urlaub_*.php            # Urlaub (4 files)
│   ├── dokumente_*.php         # Documents (4 files)
│   ├── archiv_*.php            # Archive (4 files)
│   ├── behoerde_*.php          # Behörden (6 files)
│   ├── befreiung_*.php         # Exemptions (5 files)
│   ├── ermaessigung_*.php      # Discounts (5 files)
│   ├── arbeitgeber_*.php       # Employers (8 files)
│   ├── berufserfahrung_*.php   # Work experience (7 files)
│   ├── gesundheit_*.php        # Health (9 files)
│   ├── finanzamt_*.php         # Tax office (4 files)
│   ├── finanzamt/              # Tax office subdirectory (2 files)
│   ├── finanzen_*.php          # Finance (2 files)
│   ├── finanzverwaltung/       # Financial management (3 files)
│   ├── freizeit_*.php          # Leisure (3 files)
│   ├── routine_*.php           # Routines (5 files)
│   ├── verwarnungen_*.php      # Warnings (3 files)
│   ├── verifizierung_*.php     # Verification (2 files)
│   ├── aa_korr_*.php           # Arbeitsagentur correspondence (5 files)
│   ├── kk_korrespondenz_*.php  # Krankenkasse correspondence (4 files)
│   ├── kredit_korr_*.php       # Credit correspondence (4 files)
│   ├── notizen_*.php           # Notes (3 files)
│   ├── schulen_manage.php, schulabschluesse_list.php, schulbildung_dok*.php
│   ├── handelsregister.php, handelsregister_document.php
│   └── ... (catalog lists: sprachen, staatsangehoerigkeiten, feiertage, etc.)
├── chat/                       # Live Chat (13 endpoints)
│   ├── start.php, admin_start.php, close.php
│   ├── conversations.php, messages.php, send.php
│   ├── mark_read.php, mute.php, upload.php, download.php
│   ├── support_status.php, scheduled_messages.php
│   └── conversation_scheduled.php
├── tickets/                    # Ticket system (20+ endpoints)
│   ├── create.php, admin_create.php, list.php, admin_list.php
│   ├── update.php, mark_viewed.php
│   ├── poll_notifications.php, poll_notifications_member.php
│   ├── attachments/            # upload, download, delete
│   ├── aufgaben/               # create, list, update, delete, toggle
│   ├── categories/             # list
│   ├── comments/               # add, list
│   ├── history/                # list
│   └── time/                   # start, stop, add, delete, list, running, sync, user_summary, weekly
├── termine/                    # Termine (member access)
│   ├── my_termine.php, respond.php, calendar.php
├── device/                     # Device management
│   ├── register.php, validate.php
├── notar/                      # Notary system (5 endpoints)
│   ├── besuche.php, dokumente.php, rechnungen.php, zahlungen.php, aufgaben.php
├── vereinverwaltung/           # Organization admin
│   ├── get.php, update.php, board_members.php
├── stadtverwaltung/            # City administration (6 endpoints)
│   ├── behoerden.php, drogerien.php, krankenhaeuser.php
│   ├── krankenkassen.php, maerkte.php, praxen.php
├── tracking/                   # DHL tracking (3 endpoints)
│   ├── dhl.php, dhl_settings.php, filialfinder.php
├── platform/                   # Platform features (15 endpoints)
│   ├── postcard_*.php          # Postcards (6 files)
│   ├── aufgaben_*.php          # Tasks (4 files)
│   ├── notizen_*.php           # Notes (3 files)
│   └── *_credentials.php       # Stored credentials (2 files)
├── member/                     # Member self-service (6 endpoints)
│   ├── update_personal_data.php, update_finanzielle_situation.php
│   ├── update_mitgliedschaftsbeginn.php, update_zahlungsdaten.php
│   ├── upload_leistungsbescheid.php, verifizierung_list.php
├── fcm/                        # Firebase Push Notifications
│   ├── register.php, unregister.php
├── diagnostic/                 # App diagnostics
│   └── log.php
├── logs/                       # Logging endpoints (6 files)
│   ├── debug.php, store.php, vorsitzer_logs.php
│   ├── mitglieder_windows.php, mitglieder_android.php, schatzmeister_logs.php
├── cron/                       # Scheduled tasks (6 jobs)
│   ├── auto_suspend.php, cleanup_chat.php
│   ├── cleanup_old_scheduled_messages.php, send_scheduled_messages.php
│   ├── auto_delete_expired_docs.php, update_pauschalen.php
├── data/                       # Protected JSON data (chmod 640)
│   ├── version_vorsitzer.json
│   └── changelog_vorsitzer.json
└── version_*.php, changelog_*.php  # Version/changelog API endpoints (6 files)
```

### Database Tables (MySQL) - 96 tables
**Location:** Server MySQL (credentials în `/api/config.php`)

**Core Tables:**
- `users` - User accounts (id, mitgliedernummer, email, password_hash, role, status)
- `sessions` - Active sessions (session_token, user_id, device_key, expires_at)
- `device_keys` - Registered devices (device_key, user_id, device_name, platform, ip_address)
- `login_attempts` - Login attempt tracking
- `registration_limits` - Registration IP limits

**Chat & Communication:**
- `chat_conversations` - Chat conversations
- `chat_messages` - Chat messages
- `chat_attachments` - File attachments
- `chat_scheduled_messages` - Scheduled messages
- `chat_scheduled_messages_log` - Scheduled message delivery log
- `chat_conversation_scheduled` - Conversation scheduled settings

**Tickets:**
- `tickets` - Support tickets
- `ticket_comments` - Ticket comments
- `ticket_replies` - Ticket replies
- `ticket_attachments` - Ticket attachments
- `ticket_notifications` - Ticket notifications
- `ticket_aufgaben` - Ticket tasks/todos
- `ticket_categories` - Ticket categories
- `ticket_history` - Ticket status history
- `ticket_time_entries` - Time tracking entries

**Termine & Urlaub:**
- `termine` - Appointments
- `termin_participants` - Appointment participants
- `urlaub` - Vacation periods

**Behörden & Government:**
- `behoerden` - Government authorities
- `behoerden_standorte` - Authority locations
- `behoerde_antrag_dokumente` - Authority application documents
- `user_behoerde_data` - User-specific authority data

**Finanzen & Banking:**
- `banken` - Banks database
- `bank_transaktionen` - Bank transactions
- `beitragszahlungen` - Membership fee payments
- `spenden` - Donations
- `finanzaemter` - Tax offices database
- `finanzamt_dokumente` - Tax office documents
- `finanzamt_korrespondenz` - Tax office correspondence
- `grundfreibetrag` - Tax-free allowance settings
- `jobcenter_regelsaetze` - Jobcenter standard rates
- `kindergeld_saetze` - Child benefit rates
- `deutschlandticket_saetze` - Deutschlandticket prices
- `pkonto_freibetraege` - P-Konto exemptions
- `kredit_korrespondenz` - Credit correspondence

**Arbeitgeber & Berufserfahrung:**
- `arbeitgeber_db` - Employers database
- `arbeitgeber_dokumente` - Employer documents
- `arbeitsvermittler` - Job placement agents
- `arbeitsagentur_korrespondenz` - Employment agency correspondence
- `berufserfahrung` - Work experience
- `berufserfahrung_dokumente` - Work experience documents
- `berufsbezeichnungen` - Job title catalog
- `kurs_traeger` - Course providers

**Gesundheit (Health):**
- `aerzte_datenbank` - Doctors database
- `medikamente_datenbank` - Medications database
- `mitglied_arzt_medikamente` - Member medications
- `mitglied_arzt_termine` - Member medical appointments
- `gesundheit_dokumente` - Health documents
- `krankenhaeuser` - Hospitals
- `krankenkassen` - Health insurance companies
- `krankenkasse_korrespondenz` - Health insurance correspondence

**Bildung (Education):**
- `schulen` - Schools database
- `schulabschluesse` - School degrees catalog
- `user_schulabschluss` - User school degrees
- `user_schulbildung` - User education
- `user_schulbildung_dokumente` - Education documents

**Befreiungen & Ermäßigungen:**
- `member_befreiung` - Member exemptions
- `ermaessigungsantraege` - Discount applications
- `member_dokumente` - Member documents

**Verein & Administration:**
- `vereinverwaltung` - Association data
- `vereineinstellungen` - Association settings
- `verwarnungen` - Warnings/penalties
- `user_verifizierung` - User verification
- `notar_besuche` - Notary visits
- `notar_dokumente` - Notary documents
- `notar_rechnungen` - Notary invoices
- `notar_zahlungen` - Notary payments
- `notar_aufgaben` - Notary tasks
- `versorgungsaemter` - Welfare offices
- `admin_status_message` - Admin status message

**Platform & Misc:**
- `platform_aufgaben` - Platform tasks
- `platform_credentials` - Stored credentials
- `platform_notizen` - Platform notes
- `postcard_account` - Postcard service account
- `postcard_karten` - Postcards
- `archiv` - Document archive
- `routines` - Routine tasks
- `routine_executions` - Routine execution log
- `fcm_tokens` - Firebase push notification tokens
- `translation_cache` - NLLB-200 translation cache
- `api_logs` - API request logs

**Stadtverwaltung:**
- `drogerien` - Drugstores
- `maerkte` - Markets
- `praxen` - Medical practices

**DHL & Tracking:**
- `dhl_tracking` - DHL tracking entries
- `dhl_settings` - DHL tracking settings

**Sonstige:**
- `feiertage` - Holidays
- `sprachen` - Languages catalog
- `staatsangehoerigkeiten` - Nationalities catalog
- `fuehrerscheinklassen` - Driving license classes
- `freizeit_datenbank` - Leisure activities
- `user_freizeit_data` - User leisure preferences
- `user_fuehrerschein` - User driving license
- `user_sprachen` - User languages
- `user_notizen` - User notes

## DLL Files în Inno Setup

**⚠️ CRITICAL:** După adăugarea unui pachet Flutter nativ în `pubspec.yaml`, TREBUIE să adaugi DLL-ul corespunzător în `installer/icd360sev_setup.iss`!

**Dacă uiți să adaugi un DLL, aplicația NU va porni după update și utilizatorul trebuie să descarce manual de pe site!**

### Verificare DLL-uri după build
```bash
# Listează toate DLL-urile din build (rulează după flutter build windows --release)
ls build/windows/x64/runner/Release/*.dll

# Compară cu cele din icd360sev_setup.iss - toate trebuie să fie prezente!
```

### Lista DLL-uri curente (Windows Build)
| DLL File | Pachet Flutter |
|----------|----------------|
| `flutter_windows.dll` | Flutter core |
| `flutter_secure_storage_windows_plugin.dll` | flutter_secure_storage |
| `flutter_webrtc_plugin.dll` | flutter_webrtc |
| `libwebrtc.dll` | flutter_webrtc |
| `flutter_local_notifications_plugin.dll` | flutter_local_notifications (NEW - replaced local_notifier) |
| `screen_retriever_windows_plugin.dll` | window_manager |
| `system_tray_plugin.dll` | system_tray |
| `webview_windows_plugin.dll` | webview_windows |
| `WebView2Loader.dll` | webview_windows |
| `window_manager_plugin.dll` | window_manager |
| `windows_single_instance_plugin.dll` | windows_single_instance |
| `url_launcher_windows_plugin.dll` | url_launcher |
| `file_selector_windows_plugin.dll` | file_picker |
| `windows_taskbar_plugin.dll` | windows_taskbar (NEW) |

**Removed DLLs** (no longer needed):
- `desktop_audio_capture_plugin.dll` - Package removed from pubspec.yaml
- `local_notifier_plugin.dll` - Replaced with flutter_local_notifications (cross-platform)

## Comenzi Build & Deploy

### Release Flow (NEW — tag-based, fully automated, v1.0.37+)

**TL;DR:** bump 2 files, push 1 tag, CI builds & deploys, then **document the changelog**.

```bash
# ═══════════════════════════════════════════════════════════════
# STEP 1: Bump version in BOTH files (must match — CI guard fails otherwise)
# ═══════════════════════════════════════════════════════════════
#    pubspec.yaml                        → version: X.Y.Z+B
#    lib/services/update_service.dart    → currentVersion = 'X.Y.Z'; currentBuildNumber = B
git add pubspec.yaml lib/services/update_service.dart
git commit -m "chore: bump version to X.Y.Z+B"

# ═══════════════════════════════════════════════════════════════
# STEP 2: Tag and push
# ═══════════════════════════════════════════════════════════════
git tag vX.Y.Z
git push origin main vX.Y.Z

# ═══════════════════════════════════════════════════════════════
# STEP 3: Wait for CI (~15 min) — builds, release, deploy, version.json update
# ═══════════════════════════════════════════════════════════════
# CI does automatically:
#   - 9 builds in parallel: Android (universal/samsung/play/fdroid/huawei), Windows, Linux, macOS, iOS
#   - GitHub Release with all artifacts attached
#   - SCP artifacts to /var/www/icd360sev.icd360s.de/downloads/vorsitzer/{platform}/
#   - Update version_vorsitzer.json on the prod server (version + URLs)
#   - Create STUB entry in changelog_vorsitzer.json (just marks is_latest=true)

# ═══════════════════════════════════════════════════════════════
# STEP 4: ⚠️ OBLIGATORIU — Documentează changelog-ul PE SERVER
# ═══════════════════════════════════════════════════════════════
# CI creează doar un STUB (placeholder). TREBUIE să-l înlocuiești cu
# descrieri REALE ale modificărilor. Fără acest pas, utilizatorii
# văd în changelog doar un link la GitHub — INACCEPTABIL.
#
# Conectează-te la server și rulează scriptul de mai jos:

ssh -i ~/.ssh/icd360sev.icd360s.de -p 36000 root@icd360sev.icd360s.de
python3 << 'PYEOF'
import json

path = "/var/www/icd360sev.icd360s.de/api/data/changelog_vorsitzer.json"
d = json.load(open(path))

# Găsește versiunea nouă (is_latest=True) și înlocuiește changes:
for v in d["versions"]:
    if v.get("is_latest"):
        v["changes"] = [
            # ← SCRIE AICI modificările reale, câte una per linie:
            "Prima modificare descriere",
            "A doua modificare descriere",
            "..."
        ]
        print(f"Updated {v['version']}: {len(v['changes'])} entries")
        break

json.dump(d, open(path, "w"), indent=2, ensure_ascii=False)
print("OK saved")
PYEOF
```

### ⚠️ REGULI CHANGELOG (NU SE NEGOCIAZĂ)

1. **FIECARE versiune TREBUIE să aibă descrieri reale în changelog** — nu linkuri GitHub, nu stubs, nu "see release notes"
2. **Limba: Germană** — changelog-ul este afișat utilizatorilor în app
3. **NICIODATĂ nu pune date sensibile** (Mitgliedernummern reale, parole, IP-uri, chei) — fișierul este public
4. **Format: bullet points scurte** — fiecare schimbare pe o linie separată, max 1-2 propoziții
5. **Verificare:** după editare, deschide changelog-ul din app și confirmă că arată corect

### Required for the flow above to work

**1. `pubspec.yaml` and `lib/services/update_service.dart` MUST be in sync.**
The Version Info job in `.github/workflows/build.yml` greps both and fails the build with a `::error` annotation if they disagree. Footer / changelog dialog read `UpdateService.currentVersion` so a mismatch ships a wrong version to the user.

**2. The tag MUST be on a commit where pubspec.yaml has the same version.**
Tag `v1.0.45` requires `version: 1.0.45+...` in pubspec on that commit.

**3. The CI workflow needs these GitHub Secrets** (already configured, see CI/CD Pipeline section below):
- Android signing: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`
- Deploy: `DEPLOY_SSH_KEY`, `DEPLOY_HOST`, `DEPLOY_PORT`, `DEPLOY_USER`, `DEPLOY_PATH`

### What gets updated on the prod server (automatically)

After the `📤 Deploy to Server` job finishes, two extra workflow steps run:

| Step | What it does | File on server |
|------|--------------|----------------|
| `Update version_vorsitzer.json on server` | Generates a fresh manifest with the current version, fallback set to previous patch, and 5 platform download URLs that point to the artifacts that were just uploaded (`vorsitzer-X.Y.Z-{universal.apk,windows-x64.zip,macos.dmg,linux-x64.tar.gz,ios-unsigned.ipa}`). | `/var/www/icd360sev.icd360s.de/api/data/version_vorsitzer.json` |
| `Update changelog_vorsitzer.json on server` | Remote Python one-liner that clears `is_latest` from every existing entry, prepends a **STUB** entry, and marks it `is_latest=true`. The stub is a **PLACEHOLDER** that **MUST be replaced** with real descriptions in STEP 4 above. | `/var/www/icd360sev.icd360s.de/api/data/changelog_vorsitzer.json` |

**⚠️ CI creează doar un placeholder în changelog. STEP 4 (documentarea manuală a changelog-ului) este OBLIGATORIU după fiecare release. Dacă se sare STEP 4, utilizatorii văd în app doar un link la GitHub în loc de descrieri reale — asta NU este acceptabil.**

### Manual server edits (only when CI is not enough)

If you ever need to touch the manifests by hand (e.g. to fix a typo in a published changelog), the rules are:

- **Never** put real Mitgliedernummern in `changelog_vorsitzer.json` — it is a public file. Use generic phrases like "randomized for security".
- `version_vorsitzer.json.version` MUST equal the `is_latest` entry in `changelog_vorsitzer.json`. Quick consistency check:
  ```bash
  ssh -i ~/.ssh/icd360sev.icd360s.de -p 36000 root@icd360sev.icd360s.de \
    "python3 -c \"
  import json
  v = json.load(open('/var/www/icd360sev.icd360s.de/api/data/version_vorsitzer.json'))
  c = json.load(open('/var/www/icd360sev.icd360s.de/api/data/changelog_vorsitzer.json'))
  latest = next((x['version'] for x in c['versions'] if x.get('is_latest')), None)
  print('version_vorsitzer:', v['version'])
  print('changelog latest :', latest)
  print('OK' if v['version'] == latest else 'MISMATCH')
  \""
  ```
- Backup before editing: `cp file.json file.json.bak.$(date +%Y%m%d_%H%M%S)`

### ⚠️ DEPRECATED — old manual Windows-based release flow

The previous "Pas 1 → Pas 7" checklist (build on Windows + Inno Setup + scp `.exe` + edit JSON manually) is **no longer used** as of v1.0.37. The CI pipeline replaces all of it. If you find yourself running `flutter build windows` locally for a release, you are doing it wrong — push a tag instead.

The legacy installer at `installer/icd360sev_setup.iss` is kept in the repo for reference but is not part of the release flow anymore. Releases ship as a Windows ZIP (`vorsitzer-X.Y.Z-windows-x64.zip`) generated by CI.

### Comenzi Flutter (Bash - pentru Claude)

**Windows (Git Bash):**
```bash
# Navigare la proiect
cd /c/Users/icd_U/Documents/icd360sev_vorsitzer

# Flutter analyze (verificare erori)
/c/flutter/bin/flutter analyze

# Flutter build Windows release
/c/flutter/bin/flutter build windows --release

# Flutter pub get (instalare dependențe)
/c/flutter/bin/flutter pub get

# Flutter pub upgrade (actualizare pachete)
/c/flutter/bin/flutter pub upgrade --major-versions
```

**macOS:**
```bash
# Navigare la proiect
cd /Users/ionut-claudiuduinea/Documents/icd360sev_vorsitzer

# Flutter analyze (verificare erori)
/Users/ionut-claudiuduinea/development/flutter/bin/flutter analyze

# Flutter build macOS release
/Users/ionut-claudiuduinea/development/flutter/bin/flutter build macos --release

# Flutter run (development mode)
/Users/ionut-claudiuduinea/development/flutter/bin/flutter run -d macos

# Flutter pub get (instalare dependențe)
/Users/ionut-claudiuduinea/development/flutter/bin/flutter pub get

# Flutter pub upgrade (actualizare pachete)
/Users/ionut-claudiuduinea/development/flutter/bin/flutter pub upgrade --major-versions
```

### Build & Upload (PowerShell - pentru user)
```powershell
# Build release
cd "c:\Users\icd_U\Documents\icd360sev_vorsitzer"
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat build windows --release

# Compile installer
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "installer\icd360sev_setup.iss"

# Upload to server (Vorsitzer)
scp -o StrictHostKeyChecking=no -i "vps_icd360sev_icd360s.de" -P 36000 "downloads\vorsitzer\windows\version.json" root@icd360sev.icd360s.de:/var/www/icd360sev.icd360s.de/downloads/vorsitzer/windows/

scp -o StrictHostKeyChecking=no -i "vps_icd360sev_icd360s.de" -P 36000 "build\installer\icd360sev_vorsitzer_setup.exe" root@icd360sev.icd360s.de:/var/www/icd360sev.icd360s.de/downloads/vorsitzer/windows/
```

### ⚠️ Backup Stable Version (ÎNAINTE de upload!)
```bash
# IMPORTANT: Rulează înainte de a uploada o nouă versiune!
# Salvează versiunea curentă ca fallback în caz de probleme
ssh -i "vps_icd360sev_icd360s.de" -p 36000 root@icd360sev.icd360s.de \
  "cp /var/www/icd360sev.icd360s.de/downloads/vorsitzer/windows/icd360sev_vorsitzer_setup.exe \
      /var/www/icd360sev.icd360s.de/downloads/vorsitzer/windows/icd360sev_vorsitzer_setup_stable.exe"
```

### Rollback rapid (dacă noua versiune are probleme)
```bash
# Restaurează versiunea stabilă
ssh -i "vps_icd360sev_icd360s.de" -p 36000 root@icd360sev.icd360s.de \
  "cp /var/www/icd360sev.icd360s.de/downloads/vorsitzer/windows/icd360sev_vorsitzer_setup_stable.exe \
      /var/www/icd360sev.icd360s.de/downloads/vorsitzer/windows/icd360sev_vorsitzer_setup.exe"
```

### Paths

**Windows:**
```
c:\Users\icd_U\Documents\icd360sev_vorsitzer\  (Project Root)
├── vps_icd360sev_icd360s.de           # SSH Key (in project folder!)
├── vps_icd360sev_icd360s.de.pub
├── lib/                                # Flutter source code
├── windows/                            # Windows native
├── installer/                          # Inno Setup installer script
│   └── icd360sev_setup.iss
├── build/windows/x64/runner/Release/   # Build output
└── build/installer/                    # Compiled installer
    └── icd360sev_vorsitzer_setup.exe
```

**macOS:**
```
/Users/ionut-claudiuduinea/Documents/icd360sev_vorsitzer/  (Project Root)
├── vps_icd360sev_icd360s.de           # SSH Key (in project folder!)
├── vps_icd360sev_icd360s.de.pub
├── lib/                                # Flutter source code
├── macos/                              # macOS native
│   ├── Runner/
│   │   ├── DebugProfile.entitlements  # Camera permission
│   │   └── Release.entitlements       # Camera permission
├── build/macos/Build/Products/Release/ # Build output
└── build/macos/Build/Products/Release/icd360sev_vorsitzer.app
```

Server:
/var/www/icd360sev.icd360s.de/
├── downloads/vorsitzer/windows/        # Vorsitzer Portal downloads
│   ├── icd360sev_vorsitzer_setup.exe
│   └── icd360sev_vorsitzer_setup_stable.exe  (backup)
├── api/data/                           # Protected JSON files
│   ├── version_vorsitzer.json          # Version info (chmod 640, root:nginx)
│   └── changelog_vorsitzer.json        # Detailed changelog (chmod 640, root:nginx)
├── downloads/mitglieder/windows/       # Mitglieder Portal downloads
│   ├── version.json
│   ├── icd360sev_setup.exe
│   └── icd360sev_setup_stable.exe
├── api/                                # REST API endpoints
│   ├── config.php
│   ├── helpers.php
│   ├── auth/
│   ├── admin/
│   ├── chat/
│   └── ...
└── websocket/                          # WebSocket server
    ├── server.php                      # Entry point
    └── src/ChatServer.php              # Main logic (chat, presence, calls)
```

### version.json Format (Vorsitzer)
```json
{
    "version": "1.0.0",
    "build_number": 1,
    "download_url": "https://icd360sev.icd360s.de/downloads/vorsitzer/windows/icd360sev_vorsitzer_setup.exe",
    "fallback_url": "https://icd360sev.icd360s.de/downloads/vorsitzer/windows/icd360sev_vorsitzer_setup_stable.exe",
    "fallback_version": "1.0.0",
    "changelog": "Version 1.0.0\n\n- Initiale Version für Vorsitzer Portal\n- Nur für Vorsitzer zugänglich\n- Mitgliederverwaltung\n- Terminverwaltung\n- Ticketverwaltung\n- Vereinverwaltung",
    "min_version": null,
    "force_update": false,
    "release_date": "2026-01-23",
    "file_size": "42 MB"
}
```

---

## Version & Changelog Management

**IMPORTANT:** Atât version info cât și changelog-ul sunt stocate pe server în folder protejat, NU în cod!

### ⚠️ Diferența dintre cele 2 JSON-uri:

| Aspect | version_vorsitzer.json | changelog_vorsitzer.json |
|--------|------------------------|---------------------------|
| **Scop** | Trigger update notification în aplicație | Changelog detaliat vizibil în dialog |
| **Accesat de** | UpdateService (automat, la 5 minute) | User manual (click pe "Änderungsprotokoll") |
| **Changelog format** | **SCURT** - 1-2 fraze principale | **DETALIAT** - listă completă modificări per versiune |
| **Exemplu changelog** | `"Version 1.0.3\n\n- Login security improved"` | `["Sicherheit: Login-Endpoint geändert", "Device Key authentication", "Browser blocking"]` |
| **Câte versiuni?** | Doar versiunea CURENTĂ | **TOATE** versiunile (istoric complet) |
| **Când se actualizează?** | **LA FINAL** (după upload .exe) | Înainte de version info |

**Regula de aur:**
1. **changelog_vorsitzer.json** = ce s-a modificat în detaliu (pentru utilizatori curioși)
2. **version_vorsitzer.json** = "există versiune nouă + rezumat scurt" (pentru notificare update)

---

### Version Management (Update Check)

**Fișier Server (PROTECTED):**
```
/var/www/icd360sev.icd360s.de/api/data/version_vorsitzer.json
Permisiuni: chmod 640, root:nginx (doar root write, nginx read)
```

**API Endpoint:**
```
https://icd360sev.icd360s.de/api/version_vorsitzer.php (GET, requires Device Key)
```

**Cum să actualizezi version info:**

1. **Editează fișierul pe server** (SSH):
```bash
ssh -i "vps_icd360sev_icd360s.de" -p 36000 root@icd360sev.icd360s.de \
  "nano /var/www/icd360sev.icd360s.de/api/data/version_vorsitzer.json"
```

2. **Actualizează informațiile versiunii:**
```json
{
    "version": "1.0.3",
    "build_number": 3,
    "download_url": "https://icd360sev.icd360s.de/downloads/vorsitzer/windows/icd360sev_vorsitzer_setup.exe",
    "fallback_url": "https://icd360sev.icd360s.de/downloads/vorsitzer/windows/icd360sev_vorsitzer_setup_stable.exe",
    "fallback_version": "1.0.2",
    "changelog": "Version 1.0.3\n\n- Login security improved with Device Key\n- Version & changelog protected with authentication",
    "min_version": null,
    "force_update": false,
    "release_date": "2026-01-23",
    "file_size": "42 MB"
}
```

**IMPORTANT:** Changelog-ul aici trebuie să fie SCURT (1-2 fraze principale). Pentru detalii complete, utilizatorul va deschide changelog-ul detaliat din aplicație.

**Fișiere în aplicație:**
- [lib/services/update_service.dart](lib/services/update_service.dart) - `checkForUpdate()` method cu Device Key

**Securitate:**
- ✅ **Protected endpoint:** Doar aplicația instalată poate accesa (Device Key required)
- ✅ **Blochează browsere:** User-Agent verification pe server
- ✅ **Legacy fallback:** Suport pentru versiuni vechi cu Legacy API Key

---

### Changelog Management (Detailed Changelog)

**Fișier Server (PROTECTED):**
```
/var/www/icd360sev.icd360s.de/api/data/changelog_vorsitzer.json
Permisiuni: chmod 640, root:nginx (doar root write, nginx read)
```

**API Endpoint:**
```
https://icd360sev.icd360s.de/api/changelog_vorsitzer.php (GET, requires Device Key)
```

### Cum să adaugi o versiune nouă:

1. **Editează fișierul pe server** (SSH):
```bash
ssh -i "vps_icd360sev_icd360s.de" -p 36000 root@icd360sev.icd360s.de \
  "nano /var/www/icd360sev.icd360s.de/api/data/changelog_vorsitzer.json"
```

2. **Adaugă noua versiune la ÎNCEPUTUL array-ului `versions`**:
```json
{
  "versions": [
    {
      "version": "1.0.3",
      "date": "23.01.2026",
      "changes": [
        "Sicherheit: Version & Changelog protected mit Device Key",
        "Update Check: Nur für installierte Anwendungen (Browser blockiert)",
        "API: Neuer Endpoint /api/version_vorsitzer.php",
        "Changelog: Server-basiert für alle Versionen (changelog_vorsitzer.json)",
        "Fallback: Legacy API Key Support für alte Versionen"
      ],
      "is_latest": true
    },
    {
      "version": "1.0.2",
      "date": "23.01.2026",
      "changes": [
        "Sicherheit: Login-Endpoint zu /auth/login_vorsitzer.php geändert",
        "Zugriffskontrolle: Nur Admin-Rollen erlaubt",
        "Changelog-System: Server-basiert mit geschütztem API-Endpoint"
      ],
      "is_latest": false  // IMPORTANT: Setează false pentru versiunea veche!
    },
    ...
  ]
}
```

**IMPORTANT:** Aici poți adăuga cât de multe detalii dorești - utilizatorul va vedea lista completă în dialog.

3. **Actualizează `last_updated`**:
```json
"last_updated": "2026-01-23T20:00:00Z"
```

**Fișiere în aplicație:**
- [lib/services/api_service.dart](lib/services/api_service.dart) - `getChangelog()` method
- [lib/widgets/changelog.dart](lib/widgets/changelog.dart) - Citește changelog prin API protejat
- [lib/widgets/legal_footer.dart](lib/widgets/legal_footer.dart) - Deschide dialog cu changelog

---

### Avantaje Generale (Version + Changelog):
- ✅ **Securitate maximă:** Ambele endpoint-uri protejate cu Device Key (nu public)
- ✅ **Blochează accesul neautorizat:** Browserele nu pot accesa datele
- ✅ **Flexibilitate:** Nu trebuie rebuild pentru actualizări metadata
- ✅ **Consistență:** Toate versiunile aplicației văd aceleași date actualizate
- ✅ **Corectabilitate:** Poți corecta erori fără deployment
- ✅ **Istoric complet:** Changelog disponibil pentru toate versiunile
- ✅ **Fallback sigur:** Legacy API Key pentru compatibilitate cu versiuni vechi

**Last updated:** 2026-04-03 (PHP 8.5 upgrade, ntfy push, cert pinning, battery monitoring+optimization, Easter theme, 31-category code audit)

### PHP 8.5 Upgrade (2026-04-03)
- **Upgraded from:** PHP 8.4.17 → PHP 8.5.4
- **Remi repo:** php85-php-fpm + all modules (gd, mbstring, mysqlnd, opcache, pdo, redis6, sodium, xml, zip, igbinary, msgpack)
- **FPM socket:** `/var/opt/remi/php85/run/php-fpm/www.sock`
- **PHP CLI symlink:** `/usr/local/bin/php` → `/opt/remi/php85/root/usr/bin/php`
- **Fixes applied:** 2x implicit nullable `?ConnectionInterface` in `ChatServer.php` (lines 591, 601)
- **Fixes applied:** 3x pre-existing syntax errors fixed (debug.php, ermaessigung_remind.php x2)
- **313 PHP files** syntax-checked, **175 endpoints** HTTP-tested, **0 errors**
- **Backup location:** `/root/backup_php84_20260403_221904/`
- **Rollback:** Re-enable php84-php-fpm, update nginx sock path, restore symlink
- **PHP 8.4 packages:** Still installed (not removed), disabled only

---

## Recent Changes & Updates

### v1.0.28+29 (Current - macOS Development)
**New Features (since v1.0.24):**
- ✅ **Behörden System** - 18+ individual authority widgets (Jobcenter, Finanzamt, Arbeitsagentur, Krankenkasse, Ausländerbehörde, BAMF, etc.)
- ✅ **Finanzverwaltung** - Beitragszahlungen, Spenden, Transaktionen management
- ✅ **Gesundheit** - Doctors database, medications, medical appointments, health documents
- ✅ **Arbeitgeber & Berufserfahrung** - Employer management, work experience, qualifications
- ✅ **Finanzamt** - ELSTER Online (Zertifikat-Upload .pfx), Steuererklärung, Korrespondenz
- ✅ **Lebenslauf** - CV/Resume generator with PDF export
- ✅ **Routinenaufgaben** - Encrypted routine tasks (AES-256)
- ✅ **Dienste** - Radio streaming, News, Weather, Transit nearby stops
- ✅ **Einstellungen** - Grundfreibetrag, Kindergeld, Jobcenter Regelsätze, Deutschlandticket
- ✅ **Sendungsverfolgung** - DHL tracking with API + Filialfinder
- ✅ **Postcard** - Postcard creation and management
- ✅ **Archiv** - Document archive system
- ✅ **PDF Manager + JPG2PDF** - PDF management, compression, JPG to PDF
- ✅ **Jasmina** - AI Assistant screen
- ✅ **Banking** - VR Bank, GLS Bank integration
- ✅ **Nonprofit** - Google, Microsoft, Stifter-helfen portals
- ✅ **Statistik** - Analytics dashboard
- ✅ **Reiseplanung** - Travel planning with DB Mobilität
- ✅ **Ticket Time Tracking** - Start/stop timer, manual entries, weekly reports
- ✅ **Ticket Tasks** - Aufgaben (subtasks) within tickets
- ✅ **Scheduled Chat Messages** - Schedule messages for later delivery
- ✅ **FCM Push Notifications** - Firebase Cloud Messaging support
- ✅ **Rentenversicherung** - Brutto/Netto-Rentenrechner
- ✅ **Krankenkassen-Datenbank** - ~55 health insurance companies with rating
- ✅ **ntfy Push Notifications** - Self-hosted push via ntfy (no Google/FCM), topic: vorsitzer_{mitgliedernummer}
- ✅ **Certificate Pinning** - ISRG Root X1 (Let's Encrypt) pinning on all HTTP clients, valid until 2035
- ✅ **Battery Monitoring** - battery_plus, battery_level + battery_state în diagnostic payload
- ✅ **Battery Display in Chat** - Vorsitzer vede bateria membrului în Live Chat (lângă conexiune)
- ✅ **Battery Optimization** - Timer intervals reduse (Heartbeat 60s, Diagnostic 120s, Tickets 60s, Transit 60s)
- ✅ **WidgetsBindingObserver** - oprește UI timers în background, repornește la resume
- ✅ **Eastern Theme** - Tema de Paște (aprilie) cu ouă, iepurași, puișori, fluturi, flori, iarbă

**Code Quality Fixes (2026-04-03):**
- ✅ **~70+ TextEditingController memory leaks** fixed across 10+ Behörden widgets
- ✅ **HTTP timeouts** added to all ~250+ API requests (15s standard, 30s upload)
- ✅ **jsonDecode safety** - wrapped in try/catch across all services
- ✅ **Timer/Stream mounted checks** - prevents setState after dispose
- ✅ **voice_call_service** - proper StreamController disposal + track.stop()
- ✅ **analysis_options.yaml** - stricter lints (cancel_subscriptions, close_sinks, avoid_print)
- ✅ **macOS Release.entitlements** - removed debug-only temporary exception
- ✅ **User model** - added toJson(), copyWith(), safe int parsing

**New Packages (since v1.0.24):**
- `encrypt` ^5.0.3 - AES-256 for routine data
- `signature` ^6.3.0 - Handwritten signature capture
- `pdf` ^3.11.0 + `printing` ^5.13.0 - PDF generation and printing
- `image` ^4.5.4 - Image processing for PDF compression
- `geolocator` ^12.0.0 - GPS for transit
- `just_audio` ^0.9.43 - Radio streaming
- `archive` ^4.0.9 - ZIP/TAR extraction
- `battery_plus` ^6.0.0 - Battery level monitoring

**Architecture Growth:**
- 25 services (+8: news, radio, routine, transit, weather, ntfy_service, http_client_factory, platform_service)
- 34 screens (+22 new screens)
- 63 widgets (+33 new widgets, mostly Behörden + Finance + Health)
- 96 database tables on server
- ~175 API endpoints on server

**Server Version Info:**
- `version_vorsitzer.json`: 1.0.28 (build 29), release date: 2026-03-18
- Fallback version: 1.0.27
- File size: 48 MB

---

## CI/CD Pipeline & Release Flow (v1.0.37+)

### GitHub Actions Workflow
**File:** `.github/workflows/build.yml`

**Triggers:**
- `workflow_dispatch` (manual run, no release)
- Tag push `v*` → full build + GitHub Release + auto-deploy to prod server

**Jobs (10 total, run in parallel):**

| Job | Output | Runner |
|-----|--------|--------|
| 📋 Version Info | Reads version from pubspec.yaml | ubuntu |
| 🤖 Android Universal APK | `vorsitzer-X.Y.Z-universal.apk` (fat APK, all ABIs) | ubuntu |
| 📱 Samsung Galaxy Store | Per-ABI splits: `samsung-arm64-v8a`, `samsung-armeabi-v7a`, `samsung-x86_64` | ubuntu |
| ▶️ Google Play AAB | `vorsitzer-X.Y.Z-googleplay.aab` (signed) | ubuntu |
| 🔓 F-Droid APK | `vorsitzer-X.Y.Z-fdroid.apk` (`--dart-define=STORE=fdroid`) | ubuntu |
| 📲 Huawei AppGallery | `vorsitzer-X.Y.Z-huawei.apk` (`--dart-define=STORE=huawei`) | ubuntu |
| 🪟 Windows | `vorsitzer-X.Y.Z-windows-x64.zip` | windows |
| 🐧 Linux | `vorsitzer-X.Y.Z-linux-x64.tar.gz` (deps: libgtk-3, libsecret, libayatana-appindicator3, libmpv) | ubuntu |
| 🍎 macOS | `vorsitzer-X.Y.Z-macos.dmg` (unsigned, ad-hoc; signing disabled via Release.xcconfig override) | macos (Xcode latest-stable) |
| 📱 iOS | `vorsitzer-X.Y.Z-ios-unsigned.ipa` (Podfile.lock refreshed pre-build) | macos (Xcode latest-stable) |
| 🚀 Create Release | GitHub Release with all artifacts attached | ubuntu |
| 📤 Deploy to Server | SCP artifacts to prod, organized by platform | ubuntu |

### Release Process
```bash
# 1. Bump version in pubspec.yaml (e.g. 1.0.40+41 → 1.0.41+42)
# 2. Tag and push
git tag v1.0.41
git push origin v1.0.41
# 3. GitHub Actions runs everything automatically:
#    - 9 builds in parallel (~10-15 min)
#    - Creates GitHub Release at https://github.com/ICD360S-e-V/vorsitzer/releases/tag/v1.0.41
#    - SCPs all artifacts to prod under /var/www/icd360sev.icd360s.de/downloads/vorsitzer/{platform}/
```

### Public Download URLs (after deploy)
```
https://icd360sev.icd360s.de/downloads/vorsitzer/windows/vorsitzer-X.Y.Z-windows-x64.zip
https://icd360sev.icd360s.de/downloads/vorsitzer/linux/vorsitzer-X.Y.Z-linux-x64.tar.gz
https://icd360sev.icd360s.de/downloads/vorsitzer/macos/vorsitzer-X.Y.Z-macos.dmg
https://icd360sev.icd360s.de/downloads/vorsitzer/ios/vorsitzer-X.Y.Z-ios-unsigned.ipa
https://icd360sev.icd360s.de/downloads/vorsitzer/android/vorsitzer-X.Y.Z-{universal,fdroid,huawei,googleplay,samsung-*}.{apk,aab}
```

### GitHub Secrets Required
**Android signing (configured):**
- `KEYSTORE_BASE64` — base64-encoded `.jks` keystore
- `KEYSTORE_PASSWORD`, `KEY_PASSWORD` — same complex password
- `KEY_ALIAS` — `vorsitzer-icd360sev`

Keystore details: RSA 2048, 10000 days validity, CN=ICD360S e.V., L=Neu-Ulm, C=DE.
**Backup file:** `/root/upload-keystore.jks` on alma-8gb-fsn1-1 (DO NOT LOSE — only copy).

**Auto-deploy SSH (configured):**
- `DEPLOY_SSH_KEY` — private key `icd360sev.icd360s.de`
- `DEPLOY_HOST=icd360sev.icd360s.de`, `DEPLOY_PORT=36000`, `DEPLOY_USER=root`
- `DEPLOY_PATH=/var/www/icd360sev.icd360s.de/downloads/vorsitzer`

**Apple signing (NOT configured — builds are unsigned):**
- `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_PROVISIONING_PROFILE`
- `MACOS_CERTIFICATE_BASE64`, `MACOS_CERTIFICATE_PASSWORD`
- Workflow auto-detects: if present → signs; if absent → unsigned (current state).

### Known limitations on unsigned macOS builds
**`flutter_secure_storage` -34018 errSecMissingEntitlement**
- macOS Sequoia/Tahoe (26.x) refuses Keychain access for binaries without ANY code signature.
- CI builds use `CODE_SIGNING_ALLOWED = NO` (no Apple Developer cert) → no signature → keychain blocked.
- **Mitigation in code** (`api_service.dart`, `login_screen.dart`): try/catch around `_secureStorage.read/write/delete`, **memory-only fallback**. NO plaintext disk fallback (security).
- **Consequence:** "Remember me" / auto-login is a no-op on macOS unsigned builds. Tokens kept in RAM only — user re-logs in on each app start. Login itself works fine.
- **Real fix (not yet applied):** ad-hoc or self-signed code signing in CI workflow, OR Apple Developer ID ($99/year).
- iOS unsigned builds: same flow but `flutter_secure_storage` works without entitlements via fallback.

### iOS code-level fix (also in v1.0.39+)
`ios/Runner/AppDelegate.swift` `checkForkExecution()` resolves `fork()` symbol via `dlsym(RTLD_DEFAULT, "fork")` instead of calling it directly. This bypasses the Xcode 16 SDK `unavailable` annotation while preserving the runtime jailbreak-detection behaviour. Required imports: `import MachO; import Darwin`.

### Last release
- **v1.0.40** (2026-04-08) — keychain fallback (memory-only, no plaintext disk), Vorsitzer credentials reset

## Vorsitzer Account (production)
| Field | Value |
|-------|-------|
| Mitgliedernummer | `V27655` (was `V00001`, randomized 2026-04-08 for security) |
| Password | `12345678901` |
| Role | `vorsitzer` |
| User ID | `2` |
| Email | `icd@icd360s.de` |
| Name | Ionut Duinea |

**Second vorsitzer:** `V75715` (Michaela-Christine Weber) — already had random ID, untouched.
