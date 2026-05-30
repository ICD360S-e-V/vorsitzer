<?php
/**
 * API Endpoint: Generate a Vollmacht (power of attorney) PDF and persist it.
 *
 * URL:    /api/admin/vollmacht_create.php
 * Method: POST  (application/json)
 * Body:
 *   {
 *     "user_id":      <int>,
 *     "behoerde":     "arbeitsagentur",
 *     "valid_from":   "YYYY-MM-DD",
 *     "valid_until":  null | "YYYY-MM-DD",
 *     "options": {
 *       "umfang": {
 *         "antraege": true, "bescheide": true, "widerspruch": true,
 *         "klage": true, "akteneinsicht": true, "termine": true,
 *         "egv": true, "erklaerungen": true, "online": true
 *       },
 *       "digital": {
 *         "konto_zugriff": true, "antraege_online": true,
 *         "postfach": true, "veraenderungen": true
 *       },
 *       "zugang": {
 *         "verein_to_member": true, "member_to_verein": true
 *       }
 *     }
 *   }
 *
 * Returns: { success: true, data: { id, pdf_url, generated_at } }
 */
define('API_ACCESS', true);
require_once '../config.php';
require_once '../lib/fpdf186/fpdf.php';

// Same crypto as arbeitsagentur_data_manage.php
define('EK', hash('sha256', 'ICD360S_BehoerdeData_2026_SecureKey!', true));
define('EM', 'aes-256-cbc');
function dv($e) {
    if (empty($e)) return '';
    $d = base64_decode($e);
    if (!$d || strlen($d) < 17) return $e;
    $r = openssl_decrypt(substr($d, 16), EM, EK, OPENSSL_RAW_DATA, substr($d, 0, 16));
    return $r !== false ? $r : $e;
}

validateApiKey();
blockBrowserAccess();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    jsonResponse(false, [], 'Method not allowed');
}

$callerId = requireAuth();
requireAdminRole();

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) jsonResponse(false, [], 'Invalid JSON');

$userId    = (int)($input['user_id'] ?? 0);
$behoerde  = $input['behoerde'] ?? 'arbeitsagentur';
$validFrom = $input['valid_from'] ?? date('Y-m-d');
$validUntil= $input['valid_until'] ?? null;
$options   = $input['options'] ?? [];
$allowed   = ['arbeitsagentur'];
if (!in_array($behoerde, $allowed, true)) jsonResponse(false, [], 'Unsupported behoerde');
if ($userId <= 0) jsonResponse(false, [], 'user_id required');

// Encode for the PDF (FPDF uses ISO-8859-1; convert UTF-8 to it lossily but
// safely for German characters).
function p($s) { return iconv('UTF-8', 'ISO-8859-1//TRANSLIT', (string)$s); }

try {
    $pdo = getDBConnection();
    $pdo->beginTransaction();

    // ── Gather data ─────────────────────────────────────────────────────
    $stmt = $pdo->prepare('
        SELECT id, vorname, nachname, geburtsdatum, geburtsort,
               strasse, hausnummer, plz, ort
        FROM users WHERE id = ?
    ');
    $stmt->execute([$userId]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) { $pdo->rollBack(); jsonResponse(false, [], 'User not found'); }

    $stmt = $pdo->prepare("SELECT id, vorname, nachname FROM users WHERE role='vorsitzer' ORDER BY mitgliedernummer ASC LIMIT 1");
    $stmt->execute();
    $vorsitzer = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$vorsitzer) { $pdo->rollBack(); jsonResponse(false, [], 'No Vorsitzer found'); }

    $verein = $pdo->query('SELECT * FROM vereineinstellungen ORDER BY id ASC LIMIT 1')->fetch(PDO::FETCH_ASSOC);
    if (!$verein) { $pdo->rollBack(); jsonResponse(false, [], 'Verein not configured'); }

    $dienststelle = '';
    $kundennummer = '';
    if ($behoerde === 'arbeitsagentur') {
        $stmt = $pdo->prepare("SELECT feld_name, feld_wert FROM arbeitsagentur_data WHERE user_id=? AND feld_name IN ('dienststelle','kundennummer')");
        $stmt->execute([$userId]);
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if ($r['feld_name'] === 'dienststelle') $dienststelle = dv($r['feld_wert']);
            if ($r['feld_name'] === 'kundennummer') $kundennummer = dv($r['feld_wert']);
        }
    }

    // ── Helper to render an Umfang bullet only if option is enabled ─────
    $umfang  = $options['umfang']  ?? [];
    $digital = $options['digital'] ?? [];
    $zugang  = $options['zugang']  ?? [];
    $bullet = function ($enabled, $text) { return $enabled ? "[X] $text" : "[ ] $text"; };

    // ── PDF ─────────────────────────────────────────────────────────────
    $pdf = new FPDF('P', 'mm', 'A4');
    $pdf->SetMargins(20, 15, 20);
    $pdf->SetAutoPageBreak(true, 15);
    $pdf->AddPage();

    // Title
    $pdf->SetFont('Helvetica', 'B', 16);
    $pdf->Cell(0, 8, p('VOLLMACHT'), 0, 1, 'C');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->Cell(0, 5, p('gem. § 13 Abs. 1 SGB X i.V.m. § 38 SGB III'), 0, 1, 'C');
    $pdf->Cell(0, 5, p('zur Vertretung vor der Agentur für Arbeit'), 0, 1, 'C');
    $pdf->Ln(4);
    $pdf->SetDrawColor(150, 150, 150);
    $pdf->Line(20, $pdf->GetY(), 190, $pdf->GetY());
    $pdf->Ln(3);

    // Section helper
    $section = function ($title) use ($pdf) {
        $pdf->Ln(2);
        $pdf->SetFont('Helvetica', 'B', 10);
        $pdf->SetFillColor(230, 230, 240);
        $pdf->Cell(0, 6, p('  ' . $title), 0, 1, 'L', true);
        $pdf->SetFont('Helvetica', '', 9);
        $pdf->Ln(1);
    };
    $line = function ($label, $value) use ($pdf) {
        $pdf->SetFont('Helvetica', '', 9);
        $pdf->Cell(45, 5, p($label), 0, 0);
        $pdf->SetFont('Helvetica', 'B', 9);
        $pdf->MultiCell(0, 5, p($value));
        $pdf->SetFont('Helvetica', '', 9);
    };

    // ── Vollmachtgeber ──────────────────────────────────────────────────
    $section('VOLLMACHTGEBER (das Mitglied)');
    $line('Name, Vorname:', ($user['vorname'] ?? '') . ' ' . ($user['nachname'] ?? ''));
    $line('Geburtsdatum:', $user['geburtsdatum'] ?? '');
    $line('Geburtsort:', $user['geburtsort'] ?? '');
    $line('Anschrift:', trim(($user['strasse'] ?? '') . ' ' . ($user['hausnummer'] ?? '')));
    $line('', trim(($user['plz'] ?? '') . ' ' . ($user['ort'] ?? '')));
    if ($kundennummer !== '') $line('Kundennummer BA:', $kundennummer);
    if ($dienststelle !== '') $line('Zustaendige Agentur:', $dienststelle);

    // ── Bevollmächtigter ────────────────────────────────────────────────
    $section('BEVOLLMAECHTIGTER (der Verein, vertreten durch den Vorstand)');
    $line('Verein:', $verein['vereinsname'] ?? '');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->Cell(45, 5, p('Anschrift / Sitz:'), 0, 0);
    $pdf->MultiCell(0, 5, p($verein['adresse'] ?? ''));
    $line('Registergericht:', $verein['registergericht'] ?? '');
    $line('Vereinsregister-Nr.:', $verein['registernummer'] ?? '');
    $line('Vertreten durch:', ($vorsitzer['vorname'] ?? '') . ' ' . ($vorsitzer['nachname'] ?? ''));
    $line('Funktion:', '1. Vorsitzender (§ 26 BGB i.V.m. Vereinssatzung)');

    // ── Postanschrift ───────────────────────────────────────────────────
    $section('POSTANSCHRIFT');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->MultiCell(0, 5, p(
        'Saemtliche Bescheide, Mitteilungen, Aufforderungen, Termineinladungen und sonstige ' .
        'Schreiben der Agentur fuer Arbeit sind ausschliesslich an die folgende Anschrift ' .
        'des Bevollmaechtigten zu senden:'
    ));
    $pdf->Ln(1);
    $pdf->SetFont('Helvetica', 'B', 9);
    $pdf->MultiCell(0, 5, p(
        '   ' . ($verein['vereinsname'] ?? '') . "\n" .
        '   z. Hd. ' . ($vorsitzer['vorname'] ?? '') . ' ' . ($vorsitzer['nachname'] ?? '') . "\n" .
        '   ' . ($verein['adresse'] ?? '')
    ));
    $pdf->SetFont('Helvetica', 'I', 9);
    $pdf->MultiCell(0, 5, p('Die Zustellung an die Wohnanschrift des Vollmachtgebers wird hiermit ausdruecklich ausgeschlossen.'));

    // ── Umfang ──────────────────────────────────────────────────────────
    $section('UMFANG DER VOLLMACHT');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->MultiCell(0, 5, p(
        'Der Vollmachtgeber bevollmaechtigt den Bevollmaechtigten, ihn ausschliesslich gegenueber der ' .
        'Agentur fuer Arbeit in allen Angelegenheiten nach dem SGB III zu vertreten. Dies umfasst:'
    ));
    $pdf->Ln(1);
    $items = [
        'antraege'      => 'Stellen, Aendern und Zuruecknehmen von Antraegen (ALG I, Bildungsgutschein, Reha-Antraege, EGL)',
        'bescheide'     => 'Empfang von Bescheiden, Mitteilungen und saemtlicher Korrespondenz',
        'widerspruch'   => 'Unterstuetzung beim Verfassen und Einreichen von Widerspruechen (Hilfestellung, keine Rechtsdienstleistung i.S.d. RDG)',
        'klage'         => 'Unterstuetzung bei Klage vor dem Sozialgericht nach § 73 Abs. 2 Satz 2 Nr. 9 SGG (keine anwaltliche Vertretung)',
        'akteneinsicht' => 'Akteneinsicht und Erhalt von Auskuenften',
        'termine'       => 'Teilnahme an Beratungs- und Vermittlungsgespraechen',
        'egv'           => 'Abschluss, Aenderung und Aufhebung von Eingliederungsvereinbarungen (EGV)',
        'erklaerungen'  => 'Erklaerungen zur Arbeitssuche, Verfuegbarkeit und Mitwirkung',
        'online'        => 'Nutzung der Online-Angebote der BA (eVollmacht-Funktion)',
    ];
    foreach ($items as $k => $label) {
        $pdf->MultiCell(0, 5, p('  ' . $bullet(!empty($umfang[$k]), $label)));
    }
    $pdf->Ln(1);
    $pdf->SetFont('Helvetica', 'I', 8);
    $pdf->MultiCell(0, 4, p(
        'Hinweis 1: Diese Vollmacht gilt NICHT fuer das Jobcenter (SGB II). Fuer Angelegenheiten beim ' .
        'Jobcenter ist eine gesonderte Vollmacht erforderlich.'
    ));
    $pdf->Ln(0.5);
    $pdf->MultiCell(0, 4, p(
        'Hinweis 2: Diese Vollmacht umfasst KEINE Geldangelegenheiten. Saemtliche Leistungen der Agentur ' .
        'fuer Arbeit werden ausschliesslich auf das vom Vollmachtgeber benannte Bankkonto ueberwiesen ' .
        '(§ 337 SGB III). Der Bevollmaechtigte ist weder berechtigt noch verpflichtet, Geldbetraege in ' .
        'Empfang zu nehmen.'
    ));

    // ── Digitale Vertretung ─────────────────────────────────────────────
    $pdf->AddPage();
    $section('DIGITALE VERTRETUNG / ONLINE-HANDELN');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->MultiCell(0, 5, p(
        'eVollmacht gem. § 13 SGB X i.V.m. § 36a SGB I, "Vertretung online" der BA (Stand 2026). ' .
        'Diese Vollmacht umfasst ausdruecklich die Berechtigung zum Online-Handeln im BA-Kundenkonto:'
    ));
    $pdf->Ln(1);
    $digItems = [
        'konto_zugriff'    => 'Online-Zugriff auf das vollstaendige BA-Kundenkonto des Vollmachtgebers',
        'antraege_online'  => 'Stellen, Aendern und Zuruecknehmen von Online-Antraegen',
        'postfach'         => 'Einsicht in Bescheide, Postfachnachrichten und Termineinladungen; Versand von Postfachnachrichten',
        'veraenderungen'   => 'Meldung von Veraenderungen (Adresse, Beschaeftigung, Krankheit etc.)',
    ];
    foreach ($digItems as $k => $label) {
        $pdf->MultiCell(0, 5, p('  ' . $bullet(!empty($digital[$k]), $label)));
    }
    $pdf->Ln(1);
    $pdf->MultiCell(0, 5, p(
        'Die Bundesagentur fuer Arbeit wird angewiesen, dem Bevollmaechtigten den vollen Online-' .
        'Zugriff auf das BA-Konto zu gewaehren, sobald dieser sich im BA-Online-Portal authentifiziert ' .
        'und diese Vollmacht hochlaedt.'
    ));

    // ── Wechselseitige Zugangsgewährung ─────────────────────────────────
    $section('WECHSELSEITIGE ZUGANGSGEWAEHRUNG');
    $pdf->SetFont('Helvetica', '', 9);
    if (!empty($zugang['verein_to_member'])) {
        $pdf->MultiCell(0, 5, p(
            '[X] Der Verein gewaehrt dem Mitglied bei Inkrafttreten dieser Vollmacht VOLLEN Zugriff ' .
            'auf das interne Vereinssystem (Vorsitzer-Plattform). Die Zugangsdaten (E-Mail-Adresse, ' .
            'Passwort, 2FA-Schluessel / KeyAccess-Pass) werden dem Mitglied vollstaendig uebergeben.'
        ));
    } else {
        $pdf->MultiCell(0, 5, p('[ ] Der Verein gewaehrt dem Mitglied Zugang zur Vorsitzer-Plattform.'));
    }
    $pdf->Ln(1);
    if (!empty($zugang['member_to_verein'])) {
        $pdf->MultiCell(0, 5, p(
            '[X] Das Mitglied gewaehrt dem Verein den vollstaendigen Online-Zugriff auf sein ' .
            'BA-Kundenkonto bei der Agentur fuer Arbeit (ueber die offizielle Vertretung online-' .
            'Funktion oder, falls technisch noch nicht freigeschaltet, durch Uebergabe der ' .
            'Login-Daten).'
        ));
    } else {
        $pdf->MultiCell(0, 5, p('[ ] Das Mitglied gewaehrt dem Verein Zugang zum BA-Kundenkonto.'));
    }

    // ── Legitimationspflicht ────────────────────────────────────────────
    $section('LEGITIMATIONSPFLICHT (NUR BEI PERSOENLICHER VORSPRACHE)');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->MultiCell(0, 5, p(
        'Bei jeder physischen Vorsprache des Bevollmaechtigten ist die Identitaet durch Vorlage eines ' .
        'gueltigen amtlichen Lichtbildausweises zu pruefen (Personalausweis oder Reisepass). Die ' .
        'Agentur fuer Arbeit darf KEINE Auskunft erteilen, KEINE Akteneinsicht gewaehren und KEINE ' .
        'Erklaerungen entgegennehmen, solange die Identitaet nicht verifiziert ist — auch dann nicht, ' .
        'wenn die schriftliche Vollmacht im Original vorgelegt wird. Bei Fernkommunikation (Brief, ' .
        'Fax, E-Mail, BA-Online-Portal) entfaellt diese Pflicht.'
    ));
    $pdf->Ln(1);
    $pdf->MultiCell(0, 5, p(
        'Diese Vollmacht legitimiert nur die natuerliche Person, die zum Zeitpunkt des Vorsprechens ' .
        'als 1. Vorsitzender im Vereinsregister ' . ($verein['registernummer'] ?? '') . ' (' .
        ($verein['registergericht'] ?? '') . ') eingetragen ist.'
    ));
    $pdf->SetFont('Helvetica', 'B', 9);
    $pdf->MultiCell(0, 5, p(
        'Aktuell legitimiert: ' . ($vorsitzer['vorname'] ?? '') . ' ' . ($vorsitzer['nachname'] ?? '') .
        '  (Stand: ' . date('d.m.Y', strtotime($validFrom)) . ')'
    ));

    // ── Beschränkungen ─────────────────────────────────────────────────
    $section('BESCHRAENKUNGEN');
    $line('Gueltig ab:', date('d.m.Y', strtotime($validFrom)));
    $line('Gueltig bis:', $validUntil ? date('d.m.Y', strtotime($validUntil)) : 'bis auf schriftlichen Widerruf');
    $line('Untervollmacht:', 'nicht erlaubt');

    // ── Datenschutz ─────────────────────────────────────────────────────
    $section('DATENSCHUTZHINWEIS');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->MultiCell(0, 5, p(
        'Schweigepflichtentbindung gem. § 35 SGB I und §§ 67 ff. SGB X. Datenverarbeitung durch den ' .
        'Verein nach Art. 6 Abs. 1 lit. e DSGVO sowie BDSG, ausschliesslich zur Erfuellung der ' .
        'bevollmaechtigten Aufgaben.'
    ));

    // ── Widerruf ────────────────────────────────────────────────────────
    $pdf->AddPage();
    $section('WIDERRUF');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->MultiCell(0, 5, p(
        'Diese Vollmacht — einschliesslich der wechselseitigen Zugangsgewaehrung — kann jederzeit ' .
        'schriftlich gegenueber dem Bevollmaechtigten und der Agentur fuer Arbeit widerrufen werden, ' .
        'ohne Angabe von Gruenden und ohne Wirkung auf bereits durchgefuehrte Handlungen.'
    ));
    $pdf->Ln(1);
    $pdf->MultiCell(0, 5, p('Widerruf an den Bevollmaechtigten:'));
    $pdf->SetFont('Helvetica', 'B', 9);
    $pdf->MultiCell(0, 5, p(
        '  E-Mail:  widerruf@icd360s.de' . "\n" .
        '  Post:    ' . ($verein['vereinsname'] ?? '') . ' — Widerruf-Vollmacht — ' . ($verein['adresse'] ?? '')
    ));
    $pdf->Ln(1);

    $section('VERANTWORTUNG NACH WIDERRUF');
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->MultiCell(0, 5, p(
        'Der Verein verpflichtet sich, ALLE vom Mitglied erhaltenen Zugangsdaten zum BA-Kundenkonto ' .
        'unverzueglich aus saemtlichen Vereinssystemen zu LOESCHEN und keinen weiteren Zugriff auf ' .
        'das BA-Konto auszuueben.'
    ));
    $pdf->Ln(1);
    $pdf->MultiCell(0, 5, p(
        'Das Mitglied traegt die ALLEINIGE Verantwortung fuer die Sicherung seines BA-Kundenkontos ' .
        'nach Widerruf. Insbesondere obliegt es ausschliesslich dem Mitglied — als rechtmaessigem ' .
        'Inhaber des Kontos — die folgenden Massnahmen eigenverantwortlich durchzufuehren: Aenderung ' .
        'des Passworts, Neueinrichtung / Sperrung des 2FA-Schluessels, Beendigung aller Online-' .
        'Sitzungen und ggf. Sperrung der "Vertretung online"-Funktion bei der BA. Diese Schritte ' .
        'kann und darf der Verein nach Widerruf NICHT mehr durchfuehren.'
    ));

    // ── Signatures ──────────────────────────────────────────────────────
    $pdf->Ln(8);
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->Cell(0, 5, p('Ort, Datum: ____________________________________'), 0, 1);
    $pdf->Ln(10);
    $pdf->Cell(0, 5, p('Vollmachtgeber (Mitglied):'), 0, 1);
    $pdf->Ln(6);
    $pdf->Cell(0, 5, p('____________________________________________________'), 0, 1);
    $pdf->SetFont('Helvetica', 'B', 9);
    $pdf->Cell(0, 5, p(($user['vorname'] ?? '') . ' ' . ($user['nachname'] ?? '')), 0, 1);
    $pdf->Ln(8);
    $pdf->SetFont('Helvetica', '', 9);
    $pdf->Cell(0, 5, p('Bevollmaechtigter (Vorstand ' . ($verein['vereinsname'] ?? '') . '):'), 0, 1);
    $pdf->Ln(6);
    $pdf->Cell(0, 5, p('____________________________________________________'), 0, 1);
    $pdf->SetFont('Helvetica', 'B', 9);
    $pdf->Cell(0, 5, p(($vorsitzer['vorname'] ?? '') . ' ' . ($vorsitzer['nachname'] ?? '') . ', 1. Vorsitzender'), 0, 1);
    $pdf->Ln(4);
    $pdf->SetFont('Helvetica', 'I', 8);
    $pdf->MultiCell(0, 4, p(
        'Hinweis: Ein Vereinsstempel ist gem. § 167 Abs. 2 BGB nicht erforderlich; die Unterschrift ' .
        'des vertretungsberechtigten Vorstands genuegt.'
    ));

    // ── Save PDF ────────────────────────────────────────────────────────
    $storageDir = __DIR__ . '/../../../uploads/vollmachten';
    if (!is_dir($storageDir)) mkdir($storageDir, 0750, true);
    $filename = sprintf('vollmacht_%s_user%d_%s.pdf', $behoerde, $userId, date('Ymd_His'));
    $absPath = $storageDir . '/' . $filename;
    $pdf->Output('F', $absPath);
    $sha256 = hash_file('sha256', $absPath);

    // ── Persist record ──────────────────────────────────────────────────
    $stmt = $pdo->prepare('
        INSERT INTO member_vollmachten
            (user_id, behoerde, vorsitzer_id, valid_from, valid_until,
             status, options_json, pdf_filename, pdf_sha256, created_by)
        VALUES (?, ?, ?, ?, ?, "draft", ?, ?, ?, ?)
    ');
    $stmt->execute([
        $userId, $behoerde, $vorsitzer['id'],
        $validFrom, $validUntil,
        json_encode($options, JSON_UNESCAPED_UNICODE),
        $filename, $sha256, $callerId,
    ]);
    $newId = (int)$pdo->lastInsertId();
    $pdo->commit();

    jsonResponse(true, [
        'id'           => $newId,
        'pdf_filename' => $filename,
        'pdf_sha256'   => $sha256,
        'pdf_url'      => '/api/admin/vollmacht_pdf.php?id=' . $newId,
        'generated_at' => date('c'),
    ]);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    error_log('vollmacht_create error: ' . $e->getMessage());
    jsonResponse(false, [], 'Server error: ' . $e->getMessage());
}
