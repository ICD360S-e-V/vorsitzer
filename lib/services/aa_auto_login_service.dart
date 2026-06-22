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
  static const String _ssoUrl = 'https://www.arbeitsagentur.de/anmelden/anmeldenstart';

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
    return '''
(() => {
  if (window.__icd_aa_auto_login_running) return;
  window.__icd_aa_auto_login_running = true;
  const EMAIL = $emailJs;
  const PASSWORD = $passwordJs;
  const TOTP = $totpJs;
  const log = (...a) => { try { console.log('[ICD-AutoLogin]', ...a); } catch (_) {} };

  // Setează valoarea propriu-zis cu evenimente input/change ca să satisfacă
  // framework-uri reactive (Angular/React detectează doar prin native setter).
  const setNativeValue = (el, value) => {
    if (!el) return false;
    const proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    if (setter) setter.call(el, value); else el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
    return true;
  };

  // Caută primul input vizibil + interactiv (nu hidden, nu disabled).
  const findInput = (predicates) => {
    const inputs = Array.from(document.querySelectorAll('input,textarea'));
    for (const i of inputs) {
      if (i.disabled || i.readOnly) continue;
      const style = window.getComputedStyle(i);
      if (style.display === 'none' || style.visibility === 'hidden') continue;
      if (i.offsetParent === null && style.position !== 'fixed') continue;
      for (const p of predicates) { if (p(i)) return i; }
    }
    return null;
  };

  const emailPredicates = [
    (i) => i.type === 'email',
    (i) => i.autocomplete === 'username' || i.autocomplete === 'email',
    (i) => /^(username|email|user|login|benutzer|emailaddress|e-mail|userid)\$/i.test(i.name || ''),
    (i) => /^(username|email|user|login|benutzer|emailaddress|e-mail|userid|j_username)\$/i.test(i.id || ''),
    (i) => /(email|user|benutzer|login)/i.test(i.placeholder || ''),
  ];
  const passwordPredicates = [
    (i) => i.type === 'password',
    (i) => i.autocomplete === 'current-password' || i.autocomplete === 'new-password',
    (i) => /password|passwort|kennwort|j_password/i.test(i.name || i.id || ''),
  ];
  const totpPredicates = [
    (i) => i.autocomplete === 'one-time-code',
    (i) => i.inputMode === 'numeric' && (i.maxLength === 6 || i.maxLength === 8),
    (i) => /totp|otp|code|2fa|einmalcode|tan|verification/i.test(i.name || i.id || i.placeholder || ''),
    (i) => /^[0-9]\$/.test((i.placeholder || '').trim()) && (i.maxLength === 1 || i.maxLength === 6),
  ];

  // Click pe primul buton de submit / login vizibil.
  const clickSubmit = () => {
    const btns = Array.from(document.querySelectorAll('button,input[type=submit],a[role=button]'));
    for (const b of btns) {
      if (b.disabled) continue;
      const txt = (b.innerText || b.value || b.textContent || '').toLowerCase().trim();
      const style = window.getComputedStyle(b);
      if (style.display === 'none' || style.visibility === 'hidden') continue;
      if (b.offsetParent === null && style.position !== 'fixed') continue;
      if (/anmelden|einloggen|sign[\\s-]*in|log[\\s-]*in|weiter|bestätigen|absenden|continue/i.test(txt)) {
        log('clicking submit:', txt);
        b.click();
        return true;
      }
      // Fallback: typul submit fără text relevant — îl luăm dacă nu găsim cu text.
      if (b.type === 'submit') {
        // marcheaza ca rezerva
        if (!window.__icd_fallback_submit) window.__icd_fallback_submit = b;
      }
    }
    if (window.__icd_fallback_submit) {
      log('clicking fallback submit');
      window.__icd_fallback_submit.click();
      return true;
    }
    return false;
  };

  // Polling state-machine: așteaptă să apară câmpurile, le completează, dă submit,
  // apoi așteaptă pagina TOTP. Max 90 sec total ca să nu rulăm la nesfârșit.
  let stage = 'login'; // 'login' → 'totp' → 'done'
  let loginAttempted = false;
  let totpAttempted = false;
  const startedAt = Date.now();
  const MAX_MS = 90_000;

  const tick = () => {
    if (Date.now() - startedAt > MAX_MS) { log('timeout, giving up'); return; }
    try {
      if (stage === 'login') {
        const emailInput = findInput(emailPredicates);
        const passwordInput = findInput(passwordPredicates);
        if (emailInput && passwordInput) {
          if (!loginAttempted) {
            log('filling email + password');
            setNativeValue(emailInput, EMAIL);
            setNativeValue(passwordInput, PASSWORD);
            loginAttempted = true;
            setTimeout(() => { clickSubmit(); stage = 'totp'; }, 350);
          }
        } else if (emailInput && !passwordInput) {
          // Unele portaluri arată email pe pagina 1, parola pe pagina 2 după click.
          if (!loginAttempted) {
            log('filling email only (two-step page)');
            setNativeValue(emailInput, EMAIL);
            loginAttempted = true;
            setTimeout(() => { clickSubmit(); loginAttempted = false; }, 350);
          }
        }
      } else if (stage === 'totp') {
        if (!TOTP) { log('no TOTP code available — stopping'); stage = 'done'; return; }
        const totpInput = findInput(totpPredicates);
        if (totpInput && !totpAttempted) {
          // Variante UI: un singur input sau 6 box-uri separate.
          const splitBoxes = Array.from(document.querySelectorAll('input[maxlength="1"]'))
            .filter(i => !i.disabled && i.offsetParent !== null);
          if (splitBoxes.length >= TOTP.length && splitBoxes.length >= 6) {
            log('filling TOTP into', splitBoxes.length, 'boxes');
            for (let k = 0; k < TOTP.length && k < splitBoxes.length; k++) {
              setNativeValue(splitBoxes[k], TOTP[k]);
              splitBoxes[k].focus();
            }
          } else {
            log('filling TOTP into single input');
            setNativeValue(totpInput, TOTP);
          }
          totpAttempted = true;
          setTimeout(() => { clickSubmit(); stage = 'done'; }, 350);
        }
      }
    } catch (e) {
      log('tick error:', e.message);
    }
    setTimeout(tick, 600);
  };
  tick();
})();
''';
  }
}
