import 'dart:convert';

import 'anredeform.dart';

/// Vorbefüllung des ZBFS-Kontaktformulars
/// (`formularserver-bp.bayern.de/.../kontaktformular_zbfs`).
///
/// Das Formular ist ein IntelliForm-Assistent: mehrere Seiten hintereinander,
/// jede Seite ein eigener Server-Roundtrip, und die Auswahlfelder auf der Seite
/// „Themenbereich" bauen aufeinander auf — das nächste Feld erscheint erst,
/// nachdem der Server die Seite neu geliefert hat. Deshalb wird das Skript
/// **auf jeder Seite erneut** ausgeführt und füllt jeweils das, was gerade da
/// ist. Es klickt nie „Weiter" und nie „Absenden".
///
/// Die Feldnamen unten sind nicht geraten, sondern am 22.08.2026 am echten
/// Formular abgelaufen worden. Wichtig ist der Zweig auf der Seite
/// „Themenbereich" → „Ich wende mich an das ZBFS":
///
/// | Zweig                       | Feldnamen                                  |
/// |-----------------------------|--------------------------------------------|
/// | In eigener Sache            | `input.vorname`, `input.telefon_sgbix`, …  |
/// | als Vertreter/Betreuer      | `input.as_*` (betroffene Person) **und**   |
/// |                             | `input.ab_*` (Absender, hier der Verein)   |
///
/// ⚠️ Die Endung des Feldnamens hängt am Themenbereich (`telefon_sgbix`,
/// `aktenzeichen_bess`, …). Deshalb wird nach dem Stamm verglichen und nicht
/// nach dem vollen Namen.
///
/// ⚠️ „Ich wende mich an das ZBFS" wird **bewusst nicht** vorbelegt: ob der
/// Verein in eigener Sache oder als Bevollmächtigter schreibt, ist eine
/// rechtliche Aussage und keine Bequemlichkeit.
class ZbfsFormularDaten {
  /// Betroffene Person (Mitglied) — Verifizierung Stufe 1.
  final String vorname;
  final String nachname;

  /// `M`/`W`/… aus `users.geschlecht`; leer heißt „nicht hinterlegt".
  final String geschlecht;
  final String strasseHausnummer;
  final String plz;
  final String ort;
  final String land;

  /// Geburtsdatum in beliebiger Schreibweise; wird zu `dd.mm.yyyy`.
  final String geburtsdatum;

  /// Aktenzeichen des ZBFS aus dem Amt-Tab (bei uns als `1234-5678` gespeichert).
  final String aktenzeichen;

  /// Absender-Seite: Festnetz und Anschrift des Vereins.
  final String vereinName;
  final String vereinTelefon;
  final String vereinStrasseHausnummer;
  final String vereinPlz;
  final String vereinOrt;

  /// Antragsart-Schlüssel aus [kVaAntragsarten], z. B. `wertmarke`.
  final String antragsart;

  /// Vorgeschlagener Text für „Ihre Mitteilung an uns". Leer = nichts eintragen.
  final String mitteilung;

  const ZbfsFormularDaten({
    this.vorname = '',
    this.nachname = '',
    this.geschlecht = '',
    this.strasseHausnummer = '',
    this.plz = '',
    this.ort = '',
    this.land = '',
    this.geburtsdatum = '',
    this.aktenzeichen = '',
    this.vereinName = '',
    this.vereinTelefon = '',
    this.vereinStrasseHausnummer = '',
    this.vereinPlz = '',
    this.vereinOrt = '',
    this.antragsart = '',
    this.mitteilung = '',
  });
}

/// `1|Herr` / `2|Frau` / `9|keine Angabe` — die Optionswerte des Formulars.
///
/// Ohne hinterlegtes Geschlecht wird `9|keine Angabe` gewählt und **nicht**
/// geraten: die Anrede geht an eine Behörde und steht anschließend in deren
/// Akte.
String zbfsAnredeOption(String? geschlecht) {
  switch (anredeform(geschlecht)) {
    case Anredeform.herr:
      return '1|Herr';
    case Anredeform.frau:
      return '2|Frau';
    case Anredeform.neutral:
      return '9|keine Angabe';
  }
}

/// Bringt ein Datum auf `dd.mm.yyyy` — die Schreibweise, die das Formular im
/// Platzhalter verlangt. Versteht `yyyy-mm-dd` (so liefert es die API) und
/// `dd.mm.yyyy`. Alles andere kommt unverändert zurück, damit nie ein falsches
/// Datum entsteht.
String zbfsDatumDe(String? roh) {
  final s = (roh ?? '').trim();
  if (s.isEmpty) return '';
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (iso != null) {
    return '${iso.group(3)!.padLeft(2, '0')}.${iso.group(2)!.padLeft(2, '0')}.${iso.group(1)}';
  }
  final de = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(s);
  if (de != null) {
    return '${de.group(1)!.padLeft(2, '0')}.${de.group(2)!.padLeft(2, '0')}.${de.group(3)}';
  }
  return s;
}

/// Bringt das Aktenzeichen auf die Schreibweise des ZBFS: vier Ziffern,
/// Bindestrich, vier Ziffern — `1234-5678`.
///
/// ⚠️ Der Bindestrich gehört dazu und ist **nicht** bloß die Darstellung
/// unserer zweigeteilten Eingabemaske. Er wurde zwischenzeitlich entfernt, weil
/// das nach einer eigenen Zutat aussah; das war falsch.
///
/// ⚠️ Der ZBFS-Server prüft die Nummer gegen den **eigenen Bestand**, nicht
/// gegen ein Muster: er lehnt jede erfundene Nummer ab („Das Aktenzeichen ist
/// ungültig."), gleich in welcher Schreibweise. Weist das Feld die Eingabe
/// zurück, ist also die Nummer zu prüfen, nicht die Formatierung.
///
/// Was nicht acht Ziffern hat, wird unverändert durchgereicht — lieber
/// unformatiert als umgebaut.
String zbfsAktenzeichen(String? roh) {
  final s = (roh ?? '').trim();
  final ziffern = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (ziffern.length != 8) return s;
  return '${ziffern.substring(0, 4)}-${ziffern.substring(4)}';
}

/// Zerlegt das mehrzeilige Adressfeld aus `vereineinstellungen.adresse` in
/// Straße, PLZ und Ort.
///
/// ⚠️ Gibt bei unklarem Aufbau leere Werte zurück statt zu raten. Eine falsche
/// Absenderanschrift auf einem Behördenformular ist schlimmer als ein leeres
/// Feld, das jemand ausfüllt.
({String strasse, String plz, String ort}) zbfsAdresseZerlegen(String? adresse) {
  final zeilen = (adresse ?? '')
      .split(RegExp(r'[\r\n]+'))
      .map((z) => z.trim())
      .where((z) => z.isNotEmpty)
      .toList();
  for (var i = zeilen.length - 1; i >= 0; i--) {
    final m = RegExp(r'^(\d{5})\s+(.+)$').firstMatch(zeilen[i]);
    if (m != null) {
      return (
        strasse: i > 0 ? zeilen[i - 1] : '',
        plz: m.group(1)!,
        ort: m.group(2)!.trim(),
      );
    }
  }
  return (strasse: '', plz: '', ort: '');
}

/// Der Themenbereich, unter dem das ZBFS den Antrag führt.
///
/// Rückgabe ist das Wertepaar der beiden Auswahlfelder `input.themenbereich`
/// und `input.behinderung` — genau in der Schreibweise der `<option value=…>`.
({String themenbereich, String unterpunkt}) zbfsThemenzuordnung(String antragsart) {
  const schwerbehinderung =
      '1|Schwerbehindertenfeststellungsverfahren (GdB, Ausweis, Wertmarke, etc.)';
  switch (antragsart) {
    case 'landesblindengeld':
      return (
        themenbereich: '2|Menschen mit Behinderung',
        unterpunkt: '2|Bayerisches Blindengeld',
      );
    case 'soziale_entschaedigung':
      // Eigener Themenbereich — nicht das Schwerbehindertenrecht.
      return (themenbereich: '4|Soziale Entschädigung', unterpunkt: '');
    default:
      return (themenbereich: '2|Menschen mit Behinderung', unterpunkt: schwerbehinderung);
  }
}

/// Entwurf für „Ihre Mitteilung an uns".
///
/// Bewusst ein *Entwurf*: er wird nur in ein leeres Feld geschrieben und ist
/// gedacht zum Überschreiben. Er benennt die Antragsart mit ihrer Rechtsgrundlage
/// und den Stand, den unsere Akte kennt — mehr weiß das Formular nicht, und
/// mehr soll es an dieser Stelle auch nicht behaupten.
///
/// [unterzeichner] ist der Vor- und Nachname des Mitglieds: die Sache ist seine,
/// und die Personendaten des Formulars sind ebenfalls seine.
///
/// [vereinName] trägt den Schlussvermerk. Fehlt er, entfällt der Vermerk ganz —
/// ein „Diese Nachricht wurde automatisch erstellt durch" ohne Absender wäre
/// schlechter als keiner.
String zbfsMitteilung({
  required String antragsart,
  String antragDatum = '',
  String wertmarkeBis = '',
  String ausweisGueltigBis = '',
  String unterzeichner = '',
  String vereinName = '',
}) {
  final datum = zbfsDatumDe(antragDatum);
  String satz;
  switch (antragsart) {
    case 'erstantrag':
      satz = 'beantrage ich die Feststellung eines Grades der Behinderung '
          '(§ 152 Absatz 1 SGB IX).';
      break;
    case 'neufeststellung':
      satz = 'beantrage ich die Neufeststellung des Grades der Behinderung '
          'wegen Verschlimmerung (§ 48 SGB X).';
      break;
    case 'ausweis_verlaengerung':
      satz = 'beantrage ich die Verlängerung meines Schwerbehindertenausweises'
          '${ausweisGueltigBis.isNotEmpty ? '. Der Ausweis ist gültig bis ${zbfsDatumDe(ausweisGueltigBis)}' : ''}.';
      break;
    case 'ausweis_neu':
      satz = 'beantrage ich die Neuausstellung meines Schwerbehindertenausweises.';
      break;
    case 'wertmarke':
      // ⚠️ „Verlängerung" wäre falsch: eine Wertmarke wird nicht verlängert,
      // sondern nach Ablauf neu ausgegeben — das ZBFS schreibt selbst „Nach
      // Ablauf der Gültigkeitsdauer können Sie eine neue Wertmarke erwerben",
      // und § 228 Absatz 5 SGB IX spricht von der „Ausgabe der Wertmarken … auf
      // Antrag".
      satz = 'beantrage ich die Ausgabe eines Beiblatts mit einer neuen '
          'Wertmarke (§ 228 Absatz 5 SGB IX)'
          '${wertmarkeBis.isNotEmpty ? '. Die derzeitige Wertmarke gilt bis einschließlich $wertmarkeBis' : ''}.';
      break;
    case 'parkausweis':
      satz = 'beantrage ich einen Parkausweis für schwerbehinderte Menschen.';
      break;
    case 'merkzeichen':
      satz = 'beantrage ich die Feststellung eines Merkzeichens.';
      break;
    case 'soziale_entschaedigung':
      satz = 'beantrage ich Leistungen der Sozialen Entschädigung nach dem SGB XIV.';
      break;
    case 'landesblindengeld':
      satz = 'beantrage ich Bayerisches Blindengeld nach dem BayBlindG.';
      break;
    default:
      satz = 'wende ich mich in der oben genannten Angelegenheit an Sie.';
  }
  final einleitung = datum.isNotEmpty ? 'mit Antrag vom $datum ' : 'hiermit ';
  final gruss = unterzeichner.trim().isNotEmpty
      ? 'Mit freundlichen Grüßen\n${unterzeichner.trim()}'
      : 'Mit freundlichen Grüßen';
  final vermerk = vereinName.trim().isNotEmpty
      ? '\n\n---\nDiese Nachricht wurde automatisch erstellt durch den '
          '${vereinName.trim()}, einen gemeinnützigen Verein. '
          'Die Mitarbeit erfolgt ehrenamtlich und unentgeltlich.'
      : '';
  return 'Sehr geehrte Damen und Herren,\n\n$einleitung$satz\n\n$gruss$vermerk';
}

/// Baut das JavaScript, das die Felder des Assistenten füllt.
///
/// Die Werte werden als JSON eingebettet und nicht per Hand maskiert — sonst
/// zerlegt der erste Nachname mit Apostroph das Skript.
String zbfsAutofillJs(ZbfsFormularDaten d) {
  final thema = zbfsThemenzuordnung(d.antragsart);
  // Land nur setzen, wenn die Anschrift auch deutsch aussieht — sonst bliebe
  // eine falsche Länderangabe in der Behördenakte stehen.
  final land = d.land.trim().isNotEmpty
      ? d.land.trim()
      : (RegExp(r'^\d{5}$').hasMatch(d.plz.trim()) ? 'Deutschland' : '');

  final werte = <String, String>{
    // In eigener Sache und zugleich die betroffene Person im Vertreter-Zweig.
    'person.anrede': zbfsAnredeOption(d.geschlecht),
    'person.vorname': d.vorname,
    'person.nachname': d.nachname,
    'person.strasse_hausnummer': d.strasseHausnummer,
    'person.plz': d.plz,
    'person.ort': d.ort,
    'person.land': land,
    'person.geburtsdatum': zbfsDatumDe(d.geburtsdatum),
    'person.aktenzeichen': zbfsAktenzeichen(d.aktenzeichen),
    'person.telefon': d.vereinTelefon,
    // Absender im Vertreter-Zweig: der Verein.
    'absender.funktion': '1|bevollmächtigte Vertretung',
    'absender.firma': d.vereinName,
    'absender.strasse_hausnummer': d.vereinStrasseHausnummer,
    'absender.plz': d.vereinPlz,
    'absender.ort': d.vereinOrt,
    'absender.land': d.vereinPlz.isNotEmpty ? 'Deutschland' : '',
    'absender.telefon': d.vereinTelefon,
    // Auswahlfelder des Assistenten.
    'auswahl.themenbereich': thema.themenbereich,
    'auswahl.behinderung': thema.unterpunkt,
    'auswahl.anliegenauswahl': '1|Allgemeine Mitteilung (ggf. mit Dokumenten-Upload)',
    'text.nachricht': d.mitteilung,
  }..removeWhere((_, v) => v.trim().isEmpty);

  final json = jsonEncode(werte);

  return '''
(function () {
  var W = $json;

  // Die beiden Felder, deren Auswahl das nächste Feld erst einblendet. Nur bei
  // ihnen wird ein change-Ereignis ausgelöst — der Assistent schickt darauf die
  // Seite neu. Bei allen übrigen Feldern wäre das ein überflüssiger Roundtrip.
  var KASKADE = { 'themenbereich': 1, 'behinderung': 1 };

  // Notbremse gegen eine Endlosschleife: falls der Server einen gesetzten Wert
  // nicht übernimmt, würde jedes Neuladen erneut ein change auslösen.
  function versuche(schluessel) {
    try {
      var k = 'icdZbfs.' + schluessel;
      var n = parseInt(window.sessionStorage.getItem(k) || '0', 10) + 1;
      window.sessionStorage.setItem(k, String(n));
      return n;
    } catch (e) { return 1; }
  }

  // `input.as_strasse_hausnummer` -> { rolle: 'person', stamm: 'strasse_hausnummer' }
  function zerlegen(name) {
    if (!name || name.indexOf('input.') !== 0) return null;
    var rest = name.substring(6);
    var rolle = 'person';
    if (rest.indexOf('ab_') === 0) { rolle = 'absender'; rest = rest.substring(3); }
    else if (rest.indexOf('as_') === 0) { rest = rest.substring(3); }
    // Die Endung trägt den Themenbereich (telefon_sgbix, aktenzeichen_bess …).
    if (rest.indexOf('telefon') === 0) rest = 'telefon';
    else if (rest.indexOf('aktenzeichen') === 0) rest = 'aktenzeichen';
    return { rolle: rolle, stamm: rest };
  }

  function wert(rolle, stamm) {
    if (W['auswahl.' + stamm] !== undefined) return W['auswahl.' + stamm];
    if (W['text.' + stamm] !== undefined) return W['text.' + stamm];
    return W[rolle + '.' + stamm];
  }

  function setzeText(el, val) {
    if (el.value === val) return false;
    var proto = el.tagName === 'TEXTAREA'
      ? window.HTMLTextAreaElement.prototype
      : window.HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto, 'value');
    if (setter && setter.set) setter.set.call(el, val); else el.value = val;
    // Nur `input`, kein `change`: an `onchange` hängt beim Assistenten der
    // Server-Roundtrip.
    el.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  }

  function setzeAuswahl(el, val, kaskade) {
    if (el.value === val) return false;
    var treffer = -1;
    for (var i = 0; i < el.options.length; i++) {
      if (el.options[i].value === val) { treffer = i; break; }
    }
    if (treffer < 0) {
      // Zweitchance über den sichtbaren Text — der Wert ist „2|Frau", die
      // Beschriftung „Frau".
      var ziel = (val.indexOf('|') >= 0 ? val.split('|')[1] : val).toLowerCase();
      for (var j = 0; j < el.options.length; j++) {
        var t = (el.options[j].text || '').trim().toLowerCase();
        if (t && t === ziel && el.options[j].value) { treffer = j; break; }
      }
    }
    if (treffer < 0) return false;
    el.selectedIndex = treffer;
    if (kaskade) {
      if (versuche(el.name) > 3) return false;
      el.dispatchEvent(new Event('change', { bubbles: true }));
    }
    return true;
  }

  function fuellen() {
    var felder = document.querySelectorAll('input, select, textarea');
    var anzahl = 0;
    for (var i = 0; i < felder.length; i++) {
      var el = felder[i];
      if (el.type === 'hidden' || el.disabled || el.readOnly) continue;
      var teil = zerlegen(el.name || '');
      if (!teil) continue;
      var val = wert(teil.rolle, teil.stamm);
      if (val === undefined || val === null || val === '') continue;
      // Was schon dasteht — vom Nutzer oder vom Server — wird nie überschrieben.
      if (el.tagName === 'SELECT') {
        if (el.value && el.value !== '' && el.value.charAt(0) !== '|') continue;
        if (setzeAuswahl(el, val, KASKADE[teil.stamm] === 1)) anzahl++;
      } else {
        if (el.value && el.value.trim() !== '') continue;
        if (setzeText(el, val)) anzahl++;
      }
    }
    return anzahl;
  }

  function start() {
    if (!document.body) { window.setTimeout(start, 50); return; }
    fuellen();
    // Der Assistent liefert jede Seite serverseitig aus; der Beobachter fängt
    // nur nachgeladene Teile ab und hält sich selbst kurz.
    if (!window.__icdZbfsObs) {
      var t = null;
      window.__icdZbfsObs = new MutationObserver(function () {
        if (t) return;
        t = window.setTimeout(function () { t = null; fuellen(); }, 400);
      });
      window.__icdZbfsObs.observe(document.body, { childList: true, subtree: true });
      window.setTimeout(function () {
        try { window.__icdZbfsObs.disconnect(); } catch (e) {}
        window.__icdZbfsObs = null;
      }, 120000);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
''';
}
