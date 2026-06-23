import 'dart:convert';

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
    final res = await apiService.getArbeitsagenturLoginCredentials(userId);
    if (res['success'] != true) {
      return res['message']?.toString() ?? 'Anmeldedaten konnten nicht geladen werden';
    }
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
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
    return ExternalBrowserService.openWithAutoFill(url: _ssoUrl, autoFillJs: js);
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
  if (window.__icd_aa_auto_login_running) return;
  window.__icd_aa_auto_login_running = true;
  const EMAIL = $emailJs;
  const PASSWORD = $passwordJs;
  const TOTP = $totpJs;
  const log = (...a) => { try { console.log('[ICD-AutoLogin]', ...a); } catch (_) {} };

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
      log('ERROR PAGE detected — stopping');
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
    const k = document.getElementById('otp');
    if (isUsable(k)) return k;
    const inputs = Array.from(document.querySelectorAll('input')).filter(isUsable);
    return inputs.find(i =>
      i.autocomplete === 'one-time-code' ||
      (i.inputMode === 'numeric' && (i.maxLength === 6 || i.maxLength === 8)) ||
      /totp|otp|code|2fa|einmalcode|tan|verification/i.test(i.name || i.id || i.placeholder || '')
    ) || null;
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

  const tick = () => {
    if (Date.now() - localStart > MAX_MS) { log('timeout, giving up'); return; }
    if (window.__icd_aa_done) return;
    if (detectError()) return;
    try {
      const loginForm = document.getElementById('kc-form-login');
      const otpForm = document.getElementById('kc-otp-login-form') || document.querySelector('form[action*="otp"]');

      // STAGE TOTP — dacă vede form-ul OTP, încearcă să-l completeze
      if (otpForm) {
        if (ss(SS_TOTP_SUBMITTED)) { log('totp deja submitted in acest session — skip'); return; }
        if (!TOTP) { log('no TOTP code in payload — user trebuie să introducă manual'); return; }
        const t = findTotp();
        if (t && !totpFilling) {
          totpFilling = true;
          log('filling TOTP into #otp');
          const splitBoxes = Array.from(document.querySelectorAll('input[maxlength="1"]')).filter(isUsable);
          if (splitBoxes.length >= 6) {
            log('detected', splitBoxes.length, 'split boxes for TOTP');
            for (let k = 0; k < TOTP.length && k < splitBoxes.length; k++) {
              setNativeValue(splitBoxes[k], TOTP[k]);
              splitBoxes[k].focus();
            }
          } else {
            setNativeValue(t, TOTP);
          }
          // Așteaptă ca Keycloak să activeze butonul (validatori interni).
          setTimeout(() => {
            if (submitForm(otpForm || t.closest('form'))) {
              ss(SS_TOTP_SUBMITTED, String(Date.now()));
              log('TOTP submitted — done');
              window.__icd_aa_done = true;
            } else {
              log('TOTP submit failed — kc-login encă disabled?');
              totpFilling = false;
            }
          }, 800);
        }
        return; // pe TOTP page nu mai încercăm login
      }

      // STAGE LOGIN
      if (ss(SS_LOGIN_SUBMITTED)) {
        // Login a fost submited într-o navigare anterioară — aşteptăm pagina TOTP
        log('login deja submitted — waiting for TOTP page');
        return;
      }
      const u = findUsername();
      const p = findPassword();
      if (u && p && !loginFilling) {
        loginFilling = true;
        log('filling username + password (Keycloak #username/#password)');
        setNativeValue(u, EMAIL);
        setNativeValue(p, PASSWORD);
        // Așteaptă ca Keycloak să-şi valideze inputurile + activeze submit.
        // 1500ms e un compromis sigur: suficient pentru Keycloak's onkeyup
        // validators, nu prea mult cât să expire tab_id token-ul.
        setTimeout(() => {
          if (submitForm(loginForm || u.closest('form'))) {
            ss(SS_LOGIN_SUBMITTED, String(Date.now()));
            log('login submitted — waiting for next page');
          } else {
            log('login submit failed — kc-login disabled?');
            loginFilling = false;
          }
        }, 1500);
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
  log('starting Auto-Login polling (Keycloak BA Online), url=' + location.href);
  // Wait 800ms initial ca Keycloak SPA să-şi rendereze form-ul.
  setTimeout(tick, 800);
})();
''';
  }
}
