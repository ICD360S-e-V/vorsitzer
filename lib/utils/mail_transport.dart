/// War die LEITUNG zu, auf der diese Nachricht unterwegs war?
///
/// ⚠️ Das ist eine andere Frage als die in `mail_echtheit.dart`, und die beiden
/// dürfen nie zu einer Aussage verschmelzen:
///
/// * **Echtheit** (DKIM/SPF/DMARC) sagt, ob der Absender der ist, der er zu
///   sein behauptet.
/// * **Transport** (TLS) sagt, ob unterwegs jemand mitlesen konnte.
///
/// Eine Nachricht kann echt und offen lesbar unterwegs gewesen sein, und eine
/// gefälschte kann tadellos verschlüsselt ankommen. „Sicher" allein ist
/// deshalb kein zulässiges Wort für beides zusammen.
///
/// Zwei Quellen, je nach Richtung:
///
/// * **Eingang** — die `Received`-Zeile unseres eigenen annehmenden Servers.
///   `with ESMTPS` heißt TLS, `with ESMTP` heißt Klartext. Der Server liefert
///   das ausgewertet als `transport` mit.
/// * **Ausgang** — das Postfix-Log, je Empfänger. Dort steht auch, ob das
///   Zertifikat der Gegenstelle überhaupt überprüfbar war.
library;

/// Wie die Leitung war.
enum MailTransportWert {
  /// TLS stand.
  verschluesselt,

  /// Offen lesbar unterwegs.
  klartext,

  /// Nie über das Netz gegangen — selbst erzeugte Post, Zustellung im Haus.
  intern,

  /// Nichts Belegbares. ⚠️ Ausdrücklich NICHT dasselbe wie [klartext]: eine
  /// Vermutung als Befund auszugeben wäre hier die schlimmere Antwort.
  unbekannt,
}

/// Wie gut die Gegenstelle beim Senden ausgewiesen war (nur Ausgang).
enum MailZertifikatWert {
  /// Zertifikat gegen die Vertrauensliste geprüft.
  geprueft,

  /// Zusätzlich der Name festgenagelt (DANE/Fingerabdruck).
  festgenagelt,

  /// TLS stand, aber das Zertifikat war nicht überprüfbar.
  ungeprueft,

  /// Keine Angabe.
  unbekannt,
}

class MailTransportBefund {
  final MailTransportWert wert;

  /// `ESMTPS`, `UTF8SMTPS`, … (Eingang) — sonst leer.
  final String protokoll;

  /// `TLSv1.3` (Ausgang) — sonst leer.
  final String version;

  /// Die ausgehandelte Chiffre (Ausgang) — sonst leer.
  final String cipher;

  final MailZertifikatWert zertifikat;

  const MailTransportBefund({
    this.wert = MailTransportWert.unbekannt,
    this.protokoll = '',
    this.version = '',
    this.cipher = '',
    this.zertifikat = MailZertifikatWert.unbekannt,
  });

  bool get istWarnung =>
      wert == MailTransportWert.klartext ||
      (wert == MailTransportWert.verschluesselt &&
          zertifikat == MailZertifikatWert.ungeprueft);

  /// Nur der ruhige Normalfall — dann genügt eine unauffällige Zeile.
  bool get istSauber =>
      wert == MailTransportWert.verschluesselt && !istWarnung;
}

MailTransportWert _wert(String roh) {
  switch (roh.trim().toLowerCase()) {
    case 'verschluesselt':
      return MailTransportWert.verschluesselt;
    case 'klartext':
      return MailTransportWert.klartext;
    case 'intern':
      return MailTransportWert.intern;
    default:
      return MailTransportWert.unbekannt;
  }
}

MailZertifikatWert _zert(String roh) {
  switch (roh.trim().toLowerCase()) {
    case 'verified':
      return MailZertifikatWert.festgenagelt;
    case 'trusted':
      return MailZertifikatWert.geprueft;
    case 'untrusted':
    case 'anonymous':
      return MailZertifikatWert.ungeprueft;
    default:
      return MailZertifikatWert.unbekannt;
  }
}

/// Der Befund für eine EMPFANGENE Nachricht, aus dem `transport`-Block.
///
/// ⚠️ Nimmt beide Formen entgegen. PHP reicht die Antwort der mailapi
/// unverändert durch, und was dort ein Objekt ist, kann anderswo als leere
/// Liste ankommen — ein `as Map` darauf wirft, statt null zu liefern.
MailTransportBefund mailTransportLesen(dynamic roh) {
  if (roh is! Map) return const MailTransportBefund();
  final m = Map<String, dynamic>.from(roh);
  return MailTransportBefund(
    wert: _wert('${m['status'] ?? ''}'),
    protokoll: '${m['protokoll'] ?? ''}',
  );
}

/// Der Befund für eine GESENDETE Nachricht, aus `per_recipient`.
///
/// ⚠️ Der schlechteste Empfänger gewinnt — genauso, wie der Server schon den
/// Zustellstatus zusammenfasst. Eine Nachricht an drei Empfänger, von denen
/// einer im Klartext beliefert wurde, ist nicht „verschlüsselt versendet".
MailTransportBefund mailTransportAusEmpfaengern(dynamic roh) {
  if (roh is! List || roh.isEmpty) return const MailTransportBefund();
  final zeilen = roh.whereType<Map>().map((e) => Map<String, dynamic>.from(e));
  if (zeilen.isEmpty) return const MailTransportBefund();

  const rang = {
    MailTransportWert.klartext: 3,
    MailTransportWert.unbekannt: 2,
    MailTransportWert.intern: 1,
    MailTransportWert.verschluesselt: 0,
  };
  // ⚠️ Rang ausgeschrieben und NICHT `enum.index` benutzt. Die Reihenfolge in
  // der Aufzählung ist die des Lesens, nicht die von gut nach schlecht:
  // `festgenagelt` steht dort hinter `geprueft`, ist aber der bessere Ausweis.
  // Mit dem Index als Rang hätte ein geprüftes Zertifikat ein festgenageltes
  // nie ablösen können — der Test hat genau das gefunden.
  const zRang = {
    MailZertifikatWert.festgenagelt: 0,
    MailZertifikatWert.geprueft: 1,
    MailZertifikatWert.unbekannt: 2,
    MailZertifikatWert.ungeprueft: 3,
  };
  var schlimmster = MailTransportWert.verschluesselt;
  MailZertifikatWert? zert;
  var version = '';
  var cipher = '';
  var etwasGesehen = false;

  for (final z in zeilen) {
    final w = _wert('${z['tls_status'] ?? ''}');
    if ((rang[w] ?? 2) > (rang[schlimmster] ?? 0)) schlimmster = w;
    final t = z['tls'];
    if (t is Map) {
      etwasGesehen = true;
      final tm = Map<String, dynamic>.from(t);
      final zz = _zert('${tm['stufe'] ?? ''}');
      // Auch hier gewinnt der schwächste Ausweis.
      if (zert == null || (zRang[zz] ?? 2) > (zRang[zert] ?? 2)) zert = zz;
      if (version.isEmpty) version = '${tm['version'] ?? ''}';
      if (cipher.isEmpty) cipher = '${tm['cipher'] ?? ''}';
    }
  }
  return MailTransportBefund(
    wert: schlimmster,
    version: version,
    cipher: cipher,
    zertifikat: (etwasGesehen && zert != null) ? zert : MailZertifikatWert.unbekannt,
  );
}

/// Eine Zeile Klartext für den Bildschirm und den Ausdruck — dieselbe für
/// beide, aus demselben Grund wie bei `deliveryReportRows`.
String mailTransportText(MailTransportBefund b, {required bool gesendet}) {
  switch (b.wert) {
    case MailTransportWert.verschluesselt:
      final teile = <String>[
        gesendet ? 'Verschlüsselt zugestellt' : 'Verschlüsselt empfangen',
        if (b.version.isNotEmpty) b.version,
        if (b.protokoll.isNotEmpty) b.protokoll,
      ];
      final satz = teile.length > 1
          ? '${teile.first} (${teile.skip(1).join(', ')})'
          : teile.first;
      switch (b.zertifikat) {
        case MailZertifikatWert.ungeprueft:
          return '$satz — das Zertifikat der Gegenstelle war aber nicht '
              'überprüfbar';
        case MailZertifikatWert.festgenagelt:
          return '$satz, Zertifikat festgenagelt';
        case MailZertifikatWert.geprueft:
          return '$satz, Zertifikat geprüft';
        case MailZertifikatWert.unbekannt:
          return satz;
      }
    case MailTransportWert.klartext:
      return gesendet
          ? 'Unverschlüsselt zugestellt — unterwegs offen lesbar'
          : 'Unverschlüsselt empfangen — unterwegs offen lesbar';
    case MailTransportWert.intern:
      return 'Nicht über das Netz gegangen — im Haus erzeugt und zugestellt';
    case MailTransportWert.unbekannt:
      return 'Verschlüsselung nicht belegt';
  }
}
