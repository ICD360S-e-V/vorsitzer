import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'external_browser_service.dart';
import 'api_service.dart';

/// Auto-login flow pentru contul Online al membrului pe sso.arbeitsagentur.de.
///
/// Folosește credențialele stocate (email + parolă criptate + TOTP secret)
/// pentru a injecta un script JavaScript în Chromium-ul extern care:
///   1. Detectează inputul email/username + parola (selector fallbacks),
///      completează-le și apasă submit.
///   2. Detectează inputul TOTP (autocomplete=one-time-code / inputmode=numeric)
///      pe pagina următoare şi completează codul de 6 cifre.
///   3. Submit final → utilizatorul aterizează logged-in.
///
/// Tot flow-ul rulează în Chromium-ul host (via CDP) — nu trimite credențialele
/// niciodată în afara serverului propriu + browserului local. JS-ul polling
/// rulează în pagina vizată direct, fără relay extern.
class AaAutoLoginService {
  /// Timer pentru reîmprospătarea sistem-clipboard cu cod TOTP fresh.
  /// User-ul poate face Ctrl+V în câmpul TOTP din Chromium ca fallback dacă
  /// JS-ul nostru de auto-fill nu match-uiește selectorul.
  static Timer? _clipboardRefreshTimer;

  /// Pornește timer care la fiecare 5 secunde:
  /// 1. Cere serverului codul TOTP curent
  /// 2. Îl copiază în system-clipboard (Clipboard.setData)
  /// 3. User poate face Ctrl+V în pagina BA TOTP
  /// Timer-ul se oprește după 2 minute sau la apel cancel.
  static void _startClipboardRefresh(ApiService apiService, int userId) {
    _clipboardRefreshTimer?.cancel();
    int ticks = 0;
    _clipboardRefreshTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      ticks++;
      if (ticks > 24) { // 2 min max
        t.cancel();
        return;
      }
      try {
        final res = await apiService.getArbeitsagenturTotpCode(userId);
        if (res['success'] == true) {
          final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
          final code = (data['code'] ?? '').toString();
          if (code.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: code));
          }
        }
      } catch (_) {}
    });
  }

  /// Oprește timer-ul de clipboard refresh (apelat la cleanup sau succes).
  static void stopClipboardRefresh() {
    _clipboardRefreshTimer?.cancel();
    _clipboardRefreshTimer = null;
  }

  // Entry-point pentru flow-ul BA Online. Navigarea la web.arbeitsagentur.de/profil
  // forțează redirect-ul către Keycloak SSO (sso.arbeitsagentur.de/auth/realms/OCP/...).
  // BA folosește Keycloak ca identity broker — selectoarele formularului sunt
  // standard Keycloak (#username, #password, #kc-login, #otp).
  static const String _ssoUrl = 'https://web.arbeitsagentur.de/profil/profil-ui/pd/';

  /// Lansează auto-login pentru [userId]. Returnează `null` la succes sau
  /// mesaj de eroare german pentru SnackBar.
  static Future<String?> autoLogin({
    required ApiService apiService,
    required int userId,
  }) async {
    Map<String, dynamic> res = await apiService.getArbeitsagenturLoginCredentials(userId);
    if (res['success'] != true) {
      return res['message']?.toString() ?? 'Anmeldedaten konnten nicht geladen werden';
    }
    Map<String, dynamic> data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
    // Dacă codul TOTP curent are < 15s rămase din fereastra de 30s,
    // auto-login-ul (Chromium start + form fill + validate + navigate)
    // va lua mai mult decât asta → codul expiră înainte de submit.
    // Așteaptă următoarea fereastră TOTP și re-cere credentials cu cod fresh.
    final secondsRemaining = (data['totp_seconds_remaining'] is num)
        ? (data['totp_seconds_remaining'] as num).toInt()
        : 30;
    final totpConfigured0 = data['totp_configured'] == true;
    if (totpConfigured0 && secondsRemaining < 15) {
      // ignore: avoid_print
      // Așteaptă până la următoarea fereastră (+ 1s buffer ca să nu prinzi limit-ul).
      await Future.delayed(Duration(seconds: secondsRemaining + 1));
      // Re-cere credentials cu cod proaspăt (full 30s fereastră).
      res = await apiService.getArbeitsagenturLoginCredentials(userId);
      if (res['success'] != true) {
        return res['message']?.toString() ?? 'Anmeldedaten konnten nicht geladen werden';
      }
      data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
    }
    final email    = (data['email']     ?? '').toString();
    final password = (data['password']  ?? '').toString();
    final totpCode = (data['totp_code'] ?? '').toString();
    final totpConfigured = data['totp_configured'] == true;
    if (email.isEmpty || password.isEmpty) {
      return 'E-Mail oder Passwort nicht hinterlegt';
    }
    final js = _buildAutoFillJs(
      email: email,
      password: password,
      totpCode: totpConfigured ? totpCode : '',
    );
    // CRITICAL fallback: dacă JS-ul de auto-fill TOTP nu match-uiește selectorul
    // pe BA custom theme, user-ul oricum poate face Ctrl+V în câmpul TOTP.
    // Pornim timer care reîmprospătează clipboard-ul cu cod TOTP fresh la
    // fiecare 5 secunde pentru 2 minute. Triplu fallback: JS auto-detect +
    // JS focus-listener + system clipboard Ctrl+V manual.
    if (totpConfigured && totpCode.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: totpCode));
        _startClipboardRefresh(apiService, userId);
      } catch (_) {
        // Clipboard nu e critic — auto-fill JS rămâne strategia principală
      }
    }
    return ExternalBrowserService.openWithAutoFill(
      url: _ssoUrl,
      autoFillJs: js,
      // CRITICAL: golește cookie-urile browser-ului înainte de navigare.
      // Sesiunile vechi cu tab_id Keycloak expirat cauzează "Ihre Anmeldung
      // ist nicht mehr aktiv" la prima încărcare — fără ca JS-ul nostru să
      // fi rulat. Curățarea totală e acceptabilă: browserul nostru CDP nu
      // păstrează sesiuni utile între auto-login-uri.
      clearCookies: true,
    );
  }

  static String _buildAutoFillJs({
    required String email,
    required String password,
    required String totpCode,
  }) {
    // Encode prin JSON ca să scăpăm de escape-ul manual al apostrofului etc.
    final emailJs    = jsonEncode(email);
    final passwordJs = jsonEncode(password);
    final totpJs     = jsonEncode(totpCode);
    // language=js
    // BA Online folosește Keycloak SSO (sso.arbeitsagentur.de/auth/realms/OCP).
    // Pagina de login Keycloak are HTML standard:
    //   <form id="kc-form-login">
    //     <input id="username" name="username" type="text" autocomplete="username">
    //     <input id="password" name="password" type="password" autocomplete="current-password">
    //     <input id="kc-login" type="submit">
    //   </form>
    // Pagina TOTP Keycloak:
    //   <form id="kc-otp-login-form">
    //     <input id="otp" name="otp" type="text">
    //     <input id="kc-login" type="submit">
    //   </form>
    // Selectoare hardcodate pentru fiabilitate maximă, cu generic-fallback la final.
    return '''
(() => {
  // CRITICAL: imediat log la injectare ca să vedem că JS-ul rulează,
  // chiar dacă user-ul deschide F12 după. Folosim console.warn pentru
  // a apărea evidențiat în consolă.
  try {
    console.warn('[ICD-AutoLogin] INJECTED url=' + location.href + ' time=' + new Date().toISOString());
  } catch (_) {}
  // Curăță cookie-urile Keycloak/SSO de pe domeniul curent (sso/web/www).
  // evaluateOnNewDocument rulează la document_start, deci înainte ca pagina
  // să facă XHR-uri folosind cookie-urile vechi. Asta ajută cu "Ihre Anmeldung
  // ist nicht mehr aktiv" cauzat de sesiuni Keycloak vechi.
  try {
    const host = location.hostname || '';
    if (/arbeitsagentur\\.de\$/.test(host)) {
      const all = document.cookie.split(';');
      let cleared = 0;
      for (const c of all) {
        const eq = c.indexOf('=');
        const name = (eq > -1 ? c.substr(0, eq) : c).trim();
        if (!name) continue;
        // KEYCLOAK_*, KC_*, AUTH_*, JSESSIONID — sesiunile potențial expirate.
        if (/^(KEYCLOAK_|KC_|AUTH_|kc-|JSESSION)/i.test(name)) {
          for (const d of ['', '.' + host, host, '.arbeitsagentur.de']) {
            const domain = d ? '; domain=' + d : '';
            document.cookie = name + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/' + domain;
          }
          cleared++;
        }
      }
      if (cleared > 0) console.warn('[ICD-AutoLogin] cleared ' + cleared + ' stale Keycloak cookies on ' + host);
    }
  } catch (_) {}
  if (window.__icd_aa_auto_login_running) {
    try { console.warn('[ICD-AutoLogin] already running on this document — skip re-init'); } catch (_) {}
    return;
  }
  window.__icd_aa_auto_login_running = true;
  const EMAIL = $emailJs;
  const PASSWORD = $passwordJs;
  const TOTP = $totpJs;
  const log = (...a) => { try { console.warn('[ICD-AutoLogin]', ...a); } catch (_) {} };

  // CRITICAL: sessionStorage persistă peste navigări în acelaşi tab.
  // Folosit ca să nu re-submit login form după redirect (cauza erorii
  // "Ihre Anmeldung ist nicht mehr aktiv" — Keycloak invalid token la al 2-lea submit).
  const ss = (k, v) => {
    try {
      if (v === undefined) return window.sessionStorage.getItem(k);
      window.sessionStorage.setItem(k, v);
    } catch (_) {}
  };

  // Detectează pagini de eroare BA Keycloak şi opreşte tot.
  const detectError = () => {
    const body = (document.body && document.body.innerText) || '';
    if (/ihre anmeldung ist nicht mehr aktiv|anmeldung abgelaufen|session expired|invalid_grant/i.test(body)) {
      log('!!! ERROR PAGE detected on url=' + location.href);
      log('!!! body snippet:', body.substring(0, 300));
      window.__icd_aa_done = true;
      return true;
    }
    return false;
  };

  // Setează valoarea propriu-zis cu evenimente input/change/blur ca să
  // satisfacă Angular/React/Keycloak's own JS validators.
  const setNativeValue = (el, value) => {
    if (!el) return false;
    const proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    if (setter) setter.call(el, value); else el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  };

  // Verifică că un element e vizibil şi interactiv.
  const isUsable = (el) => {
    if (!el || el.disabled || el.readOnly) return false;
    const style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden') return false;
    if (el.offsetParent === null && style.position !== 'fixed') return false;
    return true;
  };

  // Keycloak primary: caută EXACT după id-urile standard #username, #password, #otp.
  // Dacă lipsesc, fallback la pattern-uri generice.
  const findUsername = () => {
    const k = document.getElementById('username');
    if (isUsable(k)) return k;
    const inputs = Array.from(document.querySelectorAll('input')).filter(isUsable);
    return inputs.find(i =>
      i.type === 'email' ||
      i.autocomplete === 'username' ||
      i.autocomplete === 'email' ||
      /^(username|email|user|login|benutzer|userid)\$/i.test(i.name || i.id || '')
    ) || null;
  };
  const findPassword = () => {
    const k = document.getElementById('password');
    if (isUsable(k)) return k;
    const inputs = Array.from(document.querySelectorAll('input')).filter(isUsable);
    return inputs.find(i =>
      i.type === 'password' ||
      i.autocomplete === 'current-password' ||
      /password|passwort|kennwort/i.test(i.name || i.id || '')
    ) || null;
  };
  const findTotp = () => {
    // Primary: standard Keycloak #otp
    const k = document.getElementById('otp');
    if (isUsable(k)) return k;
    const allInputs = Array.from(document.querySelectorAll('input'));
    const inputs = allInputs.filter(isUsable);
    // 1) autocomplete one-time-code (WebAuthn / OS-suggested)
    let hit = inputs.find(i => i.autocomplete === 'one-time-code');
    if (hit) return hit;
    // 2) inputMode numeric + short maxLength (typical 6-digit input)
    hit = inputs.find(i =>
      (i.inputMode === 'numeric' || i.inputMode === 'decimal') &&
      (i.maxLength === 6 || i.maxLength === 8)
    );
    if (hit) return hit;
    // 3) name/id/placeholder/aria/class match
    const otpRegex = /\\botp\\b|\\btotp\\b|einmalcode|einmal[_-]?code|verification[_-]?code|2fa|two[_-]?factor|6[-_ ]?stellig|six[-_ ]?digit|authenticator|\\bcode\\b/i;
    hit = inputs.find(i => {
      const blob = (i.name || '') + ' ' + (i.id || '') + ' ' + (i.placeholder || '') +
                   ' ' + (i.getAttribute('aria-label') || '') + ' ' + (i.className || '');
      return otpRegex.test(blob);
    });
    if (hit) return hit;
    // 4) Label-text scan: <label for=ID>6-stelliger Code</label> + <input id=ID>
    //    BA pune label vizibil deasupra input-ului. Match-uim input prin asociere.
    const labels = Array.from(document.querySelectorAll('label'));
    for (const lab of labels) {
      const labTxt = (lab.innerText || lab.textContent || '').trim();
      if (otpRegex.test(labTxt)) {
        const forId = lab.getAttribute('for');
        if (forId) {
          const linked = document.getElementById(forId);
          if (linked && linked.tagName === 'INPUT' && isUsable(linked)) return linked;
        }
        // Sau input direct înăuntrul label-ului
        const nested = lab.querySelector('input');
        if (nested && isUsable(nested)) return nested;
      }
    }
    // 5) document.activeElement — Keycloak typically autofocus-uiește input-ul OTP
    //    când pagina se încarcă. Dacă post-login şi activeEl e un input non-password
    //    empty → e TOTP (independent de selector).
    if (ss(SS_LOGIN_SUBMITTED)) {
      const ae = document.activeElement;
      if (ae && ae.tagName === 'INPUT' && isUsable(ae) &&
          ae.type !== 'password' && ae.type !== 'hidden' &&
          ae.type !== 'checkbox' && ae.type !== 'radio' &&
          ae.type !== 'submit' && ae.type !== 'button' &&
          (ae.value || '').length === 0) {
        log('  ↳ TOTP found via document.activeElement (id=' + (ae.id || '?') + ' name=' + (ae.name || '?') + ')');
        return ae;
      }
    }
    // 6) Single text input on page (TOTP page de obicei are doar 1 input vizibil
    //    care nu e parolă) — aplicabil DOAR post-login ca să nu false-match pe alte pagini
    if (ss(SS_LOGIN_SUBMITTED)) {
      const textInputs = inputs.filter(i =>
        i.type !== 'password' && i.type !== 'hidden' && i.type !== 'checkbox' &&
        i.type !== 'radio' && i.type !== 'submit' && i.type !== 'button'
      );
      if (textInputs.length === 1) {
        log('  ↳ TOTP found via single-text-input fallback');
        return textInputs[0];
      }
      // Sau primul empty cu maxLength 6-8
      const filtered = textInputs.find(i =>
        (i.maxLength === 6 || i.maxLength === 7 || i.maxLength === 8) &&
        (i.value || '').length === 0);
      if (filtered) {
        log('  ↳ TOTP found via maxLength 6-8 fallback');
        return filtered;
      }
      // Last resort: primul empty input vizibil (post-login putem fi agresivi)
      const first = textInputs.find(i => (i.value || '').length === 0);
      if (first) {
        log('  ↳ TOTP found via first-empty-input last-resort fallback');
        return first;
      }
    }
    return null;
  };

  // Logger pentru când avem otpForm dar nu găsim input — listă toate inputurile.
  const logInputsForDiagnostic = () => {
    const inputs = Array.from(document.querySelectorAll('input'));
    log('=== DIAGNOSTIC: ' + inputs.length + ' inputs on page ===');
    inputs.forEach((i, idx) => {
      log('  [' + idx + ']',
        'type=' + i.type,
        'id=' + (i.id || '?'),
        'name=' + (i.name || '?'),
        'maxLength=' + i.maxLength,
        'inputMode=' + (i.inputMode || '?'),
        'autocomplete=' + (i.autocomplete || '?'),
        'placeholder=' + (i.placeholder || '?').substring(0, 40),
        'visible=' + isUsable(i));
    });
    const forms = Array.from(document.querySelectorAll('form'));
    log('=== ' + forms.length + ' forms on page ===');
    forms.forEach((f, idx) => {
      log('  form[' + idx + ']', 'id=' + (f.id || '?'), 'action=' + (f.action || '?').substring(0, 80));
    });
  };

  // Keycloak submit: primary #kc-login. Fallback: form.submit() sau primul button[type=submit].
  // Verifică că butonul nu e disabled (Keycloak îl disable-uiește cât timp form-ul nu e valid).
  const submitForm = (formEl) => {
    const kc = document.getElementById('kc-login');
    if (kc && !kc.disabled && isUsable(kc)) { log('clicking #kc-login'); kc.click(); return true; }
    if (formEl) {
      try { log('formEl.requestSubmit()'); formEl.requestSubmit(); return true; }
      catch (_) { try { formEl.submit(); return true; } catch (_) {} }
    }
    const btn = Array.from(document.querySelectorAll('button[type=submit],input[type=submit],button')).find(b => {
      if (!isUsable(b) || b.disabled) return false;
      const txt = (b.innerText || b.value || b.textContent || '').toLowerCase().trim();
      return /anmelden|einloggen|sign[\\s-]*in|log[\\s-]*in|weiter|bestätigen|absenden|continue/i.test(txt) || b.type === 'submit';
    });
    if (btn) { log('clicking fallback submit:', btn.innerText || btn.value); btn.click(); return true; }
    return false;
  };

  // Polling state-machine — folosește sessionStorage ca să nu re-submit
  // pe redirect-uri (cauza erorii "Ihre Anmeldung ist nicht mehr aktiv").
  const SS_LOGIN_SUBMITTED = '__icd_aa_login_submitted_at';
  const SS_TOTP_SUBMITTED  = '__icd_aa_totp_submitted_at';
  const SS_STARTED         = '__icd_aa_started_at';
  if (!ss(SS_STARTED)) ss(SS_STARTED, String(Date.now()));

  let loginFilling = false;
  let totpFilling = false;
  const localStart = Date.now();
  const MAX_MS = 120_000;

  let tickCount = 0;
  const tick = () => {
    tickCount++;
    if (Date.now() - localStart > MAX_MS) { log('timeout, giving up after', tickCount, 'ticks'); return; }
    if (window.__icd_aa_done) return;
    if (detectError()) return;
    try {
      const loginForm = document.getElementById('kc-form-login');
      const otpForm = document.getElementById('kc-otp-login-form') || document.querySelector('form[action*="otp"]');
      // Diagnostic tick log la primul tick + la fiecare 5 ticks ca să nu spam-uim.
      if (tickCount === 1 || tickCount % 5 === 0) {
        log('tick #' + tickCount,
          'url=' + location.pathname,
          'title=' + (document.title || '?').substring(0, 60),
          'loginForm=' + !!loginForm,
          'otpForm=' + !!otpForm,
          'u=' + !!findUsername(),
          'p=' + !!findPassword(),
          'totp=' + !!findTotp(),
          'login_submitted=' + !!ss(SS_LOGIN_SUBMITTED),
          'totp_submitted=' + !!ss(SS_TOTP_SUBMITTED));
      }
      // Dacă suntem post-login dar nu găsim TOTP input, dump full diagnostic pe tick #3
      // ca user-ul să vadă exact ce există pe pagină.
      if (tickCount === 3 && ss(SS_LOGIN_SUBMITTED) && !findTotp()) {
        log('!!! POST-LOGIN dar TOTP input NEDETECTAT — dump diagnostic complet');
        logInputsForDiagnostic();
        log('=== HEADERS / LABELS ===');
        Array.from(document.querySelectorAll('label, h1, h2, h3, h4, legend')).forEach((el, idx) => {
          const txt = (el.innerText || el.textContent || '').trim().substring(0, 100);
          if (txt) log('  [' + idx + ']', el.tagName.toLowerCase(),
            el.getAttribute('for') ? 'for=' + el.getAttribute('for') : '',
            'text="' + txt + '"');
        });
      }

      // STAGE TOTP — semnale:
      //   a) form explicit Keycloak default (#kc-otp-login-form sau action*=otp)
      //   b) un input ce match-uiește findTotp ŞI login-ul a fost deja submitted
      //      (BA custom theme nu folosește ID-uri Keycloak standard pentru TOTP)
      const totpInput = findTotp();
      const isTotpStage = otpForm || (totpInput && ss(SS_LOGIN_SUBMITTED));
      if (isTotpStage) {
        if (ss(SS_TOTP_SUBMITTED)) {
          if (tickCount === 1 || tickCount % 5 === 0) log('totp already submitted — skip');
          return;
        }
        if (!TOTP) {
          if (tickCount === 1) log('no TOTP code in payload — user must enter manually');
          return;
        }
        if (!totpInput) {
          // Diagnostic: vedem ce inputuri sunt pe pagină dacă nu match-uiește nimic
          if (tickCount === 1 || tickCount === 5) {
            log('!!! TOTP context detected but no input matched any predicate');
            logInputsForDiagnostic();
          }
          return;
        }
        if (!totpFilling) {
          totpFilling = true;
          log('filling TOTP — input.id=' + (totpInput.id || '?') + ' name=' + (totpInput.name || '?') + ' code=' + TOTP);
          // Type per character cu keydown/keyup pentru Keycloak validators
          const typeChar = (el, ch) => {
            el.focus();
            el.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true }));
            setNativeValue(el, (el.value || '') + ch);
            el.dispatchEvent(new KeyboardEvent('keyup', { key: ch, bubbles: true }));
          };
          const splitBoxes = Array.from(document.querySelectorAll('input[maxlength="1"]')).filter(isUsable);
          if (splitBoxes.length >= 6) {
            log('detected', splitBoxes.length, 'split boxes — using per-box fill');
            for (let k = 0; k < TOTP.length && k < splitBoxes.length; k++) {
              setNativeValue(splitBoxes[k], '');
              typeChar(splitBoxes[k], TOTP[k]);
            }
          } else {
            setNativeValue(totpInput, '');
            for (const ch of TOTP) typeChar(totpInput, ch);
            totpInput.dispatchEvent(new Event('blur', { bubbles: true }));
          }
          // Așteaptă Keycloak să activeze submit + extra retry dacă disabled
          setTimeout(() => {
            const formEl = otpForm || totpInput.closest('form');
            const kc = document.getElementById('kc-login');
            if (kc && kc.disabled) {
              log('kc-login încă disabled după 1.5s — așteptăm încă 1.5s');
              setTimeout(() => {
                if (submitForm(formEl)) {
                  ss(SS_TOTP_SUBMITTED, String(Date.now()));
                  log('TOTP submitted (after extra wait) — done');
                  window.__icd_aa_done = true;
                } else {
                  log('!!! TOTP submit FAILED definitiv');
                  totpFilling = false;
                }
              }, 1500);
              return;
            }
            if (submitForm(formEl)) {
              ss(SS_TOTP_SUBMITTED, String(Date.now()));
              log('TOTP submitted — done');
              window.__icd_aa_done = true;
            } else {
              log('!!! TOTP submit FAILED — form?');
              totpFilling = false;
            }
          }, 1500);
        }
        return; // pe TOTP page nu mai încercăm login
      }

      // STAGE LOGIN
      if (ss(SS_LOGIN_SUBMITTED)) {
        // Login a fost submited într-o navigare anterioară — aşteptăm pagina TOTP
        if (tickCount === 1 || tickCount % 10 === 0) log('login deja submitted — waiting for TOTP page');
        return;
      }
      // STAGE METHOD-PICKER: BA Keycloak arată o pagină cu 3 butoane:
      // "Mit BundID anmelden" / "Mit Passkey anmelden" / "Bundesagentur für Arbeit"
      // (sau "Mit Benutzername und Passwort"). Click-uim "Bundesagentur für Arbeit"
      // ca să mergem la formul username+password.
      let u = findUsername();
      let p = findPassword();
      if (!u && !p && !ss('__icd_aa_method_picked')) {
        const candidates = Array.from(document.querySelectorAll('button,a,div[role=button],input[type=button],input[type=submit]'))
          .filter(isUsable);
        const methodBtn = candidates.find(b => {
          const txt = (b.innerText || b.value || b.textContent || '').toLowerCase().trim();
          // Match pe denumiri tipice BA: "Bundesagentur für Arbeit", "Mit Benutzername und Passwort"
          return /bundesagentur\\s+f[üu]r\\s+arbeit|benutzername.*passwort|mit benutzername/i.test(txt);
        });
        if (methodBtn) {
          log('method picker detected — clicking:', (methodBtn.innerText || methodBtn.value || '').substring(0, 60));
          ss('__icd_aa_method_picked', String(Date.now()));
          methodBtn.click();
          // After click, page may navigate — wait next tick to re-detect form
          return;
        }
      }
      if (u && p && !loginFilling) {
        loginFilling = true;
        log('filling username + password — u.id=' + (u.id || '?') + ' p.id=' + (p.id || '?'));
        // Tipare simulată: dispatch keydown/input/keyup pentru fiecare char,
        // ca BA să declanşeze validatorii async (verificare pre-existenţă user etc.).
        const typeChar = (el, ch) => {
          el.focus();
          el.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true }));
          setNativeValue(el, (el.value || '') + ch);
          el.dispatchEvent(new KeyboardEvent('keyup', { key: ch, bubbles: true }));
        };
        // Username
        setNativeValue(u, '');
        for (const ch of EMAIL) typeChar(u, ch);
        u.dispatchEvent(new Event('blur', { bubbles: true }));
        // Password
        setNativeValue(p, '');
        for (const ch of PASSWORD) typeChar(p, ch);
        p.dispatchEvent(new Event('blur', { bubbles: true }));
        // Așteaptă MAI MULT — BA poate face pre-validare username via fetch().
        // 3000ms acoperă majoritatea timpilor async, dar e încă << TTL tab_id.
        setTimeout(() => {
          const kc = document.getElementById('kc-login');
          if (kc && kc.disabled) {
            log('kc-login încă disabled după 3s — așteptăm încă 2s');
            setTimeout(() => {
              if (submitForm(loginForm || u.closest('form'))) {
                ss(SS_LOGIN_SUBMITTED, String(Date.now()));
                log('login submitted (after extra wait)');
              } else {
                log('!!! login submit FAILED definitiv — kc-login still disabled');
                loginFilling = false;
              }
            }, 2000);
            return;
          }
          if (submitForm(loginForm || u.closest('form'))) {
            ss(SS_LOGIN_SUBMITTED, String(Date.now()));
            log('login submitted — waiting for next page');
          } else {
            log('!!! login submit FAILED — kc-login not found?');
            loginFilling = false;
          }
        }, 3000);
      } else if (u && !p && !loginFilling) {
        // Two-step layout (rar la Keycloak BA, dar posibil).
        loginFilling = true;
        log('two-step? filling username only');
        setNativeValue(u, EMAIL);
        setTimeout(() => {
          submitForm(loginForm || u.closest('form'));
          loginFilling = false;
        }, 800);
      }
    } catch (e) {
      log('tick error:', e.message);
    }
    setTimeout(tick, 700);
  };
  // FOCUS LISTENER fallback — dacă cele 6 strategii findTotp nu match-uiesc,
  // user-ul poate clica MANUAL pe câmpul TOTP din pagină. Acest listener
  // detectează focus pe orice input non-password empty post-login și-l
  // completează automat cu codul TOTP. Independent de selector.
  document.addEventListener('focusin', (e) => {
    try {
      if (!ss(SS_LOGIN_SUBMITTED)) return; // doar post-login
      if (ss(SS_TOTP_SUBMITTED)) return;   // deja completat
      if (!TOTP) return;                    // n-avem cod
      const el = e.target;
      if (!el || el.tagName !== 'INPUT') return;
      if (el.type === 'password' || el.type === 'hidden' ||
          el.type === 'checkbox' || el.type === 'radio' ||
          el.type === 'submit' || el.type === 'button') return;
      if ((el.value || '').length > 0) return; // deja are conținut
      log('FOCUS listener: filling input.id=' + (el.id || '?') + ' name=' + (el.name || '?') + ' cu cod TOTP');
      el.focus();
      for (const ch of TOTP) {
        el.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true }));
        setNativeValue(el, (el.value || '') + ch);
        el.dispatchEvent(new KeyboardEvent('keyup', { key: ch, bubbles: true }));
      }
      el.dispatchEvent(new Event('blur', { bubbles: true }));
      ss(SS_TOTP_SUBMITTED, String(Date.now()));
      // Submit dacă găsim buton Bestätigen
      setTimeout(() => {
        try { submitForm(el.closest('form')); } catch (_) {}
      }, 600);
    } catch (err) {
      log('focus listener err:', err.message);
    }
  }, true);

  log('starting Auto-Login polling (Keycloak BA Online), url=' + location.href);
  // Wait 800ms initial ca Keycloak SPA să-şi rendereze form-ul.
  setTimeout(tick, 800);
})();
''';
  }
}
