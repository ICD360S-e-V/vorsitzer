/// Jobcenter ▸ Termin ▸ Fahrkosten — die Arten der hochgeladenen Unterlagen.
///
/// ⚠️ NICHT ZU VERWECHSELN mit `kJcFahrtkosten` in `jc_termin_gruende.dart`.
/// Das dort ist der Gründe-Katalog des SCHREIBENS „Reisekosten beantragen",
/// das wir selbst erzeugen (ÖPNV, Pkw, Begleitperson, Vorabzahlung …). Hier
/// geht es um Dateien: den Vordruck, den das Amt ausgibt, und die Belege dazu.
///
/// Beides gehört zum selben Termin und keines ersetzt das andere: viele
/// Jobcenter bearbeiten nur ihren eigenen Vordruck, aber erst das Schreiben
/// trägt die Begründung und die Berufung auf die Vollmacht (§ 13 Abs. 1 SGB X).
library;

/// ⚠️ Zeichengleich mit `JCFK_TYPEN` in
/// `api/admin/jobcenter_av_termin_fahrkosten.php`. Der Server weist alles
/// andere mit HTTP 400 ab — und das sieht auf dem Schirm wie ein Fehler der
/// App aus. Das PHP liegt in keinem Repo, deshalb pinnt
/// `test/jc_fahrkosten_dok_test.dart` die Liste: es ist die einzige Stelle im
/// Baum, an der ein Auseinanderlaufen überhaupt auffallen kann.
const Map<String, String> kJcFahrkostenDokTypen = {
  'antrag': 'Antrag (Vordruck des Jobcenters)',
  'beleg': 'Beleg (Fahrschein, Quittung)',
  'anlage': 'Anlage (Vollmacht, Bescheinigung)',
};

/// Kurzform für die Karte in der Liste — der lange Name sprengt dort die Zeile.
const Map<String, String> kJcFahrkostenDokKurz = {
  'antrag': 'Antrag',
  'beleg': 'Beleg',
  'anlage': 'Anlage',
};

/// Was hochgeladen werden darf.
///
/// ⚠️ Dieselbe Liste für BEIDE Wege — Gerät und Cloud. Zwei Listen bekämen mit
/// der Zeit zwei Inhalte, und dann lässt der eine Knopf einen Typ durch, den
/// der Server mit 400 abweist.
const List<String> kJcFahrkostenEndungen = ['pdf', 'jpg', 'jpeg', 'png'];

/// Höchstzahl je Termin — wie `JCFK_MAX_DOCS` auf dem Server.
const int kJcFahrkostenMaxDokumente = 20;

/// Ist dieses Dokument beim Jobcenter herausgegangen?
///
/// ⚠️ NUR das Datum zählt, und das setzt der Server ausschließlich nach einer
/// angenommenen Übergabe an sipgate. Ein Fehlversuch hat `versand_status`, aber
/// KEIN `versand_datum` — wer beides zusammen abfragt, hält einen Fehlschlag
/// für eine Zustellung.
bool jcFahrkostenVersandt(Map<String, dynamic> d) =>
    (d['versand_datum'] ?? '').toString().isNotEmpty;

/// War der letzte Versuch ein Fehlschlag?
///
/// ⚠️ Diese Frage ist von [jcFahrkostenVersandt] UNABHÄNGIG und muss ZUERST
/// gestellt werden. Sonst fällt ein gescheiterter Versuch — der kein Datum
/// trägt — in denselben Topf wie „noch gar nicht versucht", und niemand
/// erfährt, dass es ihn gab.
///
/// Die Zeichenkette kommt vom Server: `'Fehler: ' . meldung`, auf 40 Zeichen
/// gekürzt.
bool jcFahrkostenFehler(Map<String, dynamic> d) =>
    (d['versand_status'] ?? '').toString().startsWith('Fehler');
