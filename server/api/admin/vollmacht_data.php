<?php
/**
 * API Endpoint: Get Vollmacht preview data (member + vorsitzer + verein).
 *
 * URL:    /api/admin/vollmacht_data.php
 * Method: GET
 * Params: ?user_id=<member id>&behoerde=arbeitsagentur
 *
 * Returns the data needed to render the Vollmacht preview / generate the PDF:
 *   - user:               from `users` (vorname, nachname, geburtsdatum,
 *                          geburtsort, strasse, hausnummer, plz, ort) — i.e.
 *                          the fields collected at Verifizierung Stufe 1
 *   - user_behoerde:      decrypted dienststelle + kundennummer from
 *                          `arbeitsagentur_data`
 *   - vorsitzer:          1. Vorsitzender (lowest mitgliedernummer with
 *                          role='vorsitzer') — only vorname + nachname
 *   - verein:             from `vereineinstellungen`
 */
define('API_ACCESS', true);
require_once '../config.php';

// Crypto used by arbeitsagentur_data (same key as arbeitsagentur_data_manage.php)
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

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    jsonResponse(false, [], 'Method not allowed');
}

$callerId = requireAuth();
requireAdminRole();

$userId = (int)($_GET['user_id'] ?? 0);
$behoerde = $_GET['behoerde'] ?? 'arbeitsagentur';
$allowedBehoerden = ['arbeitsagentur', 'jobcenter'];
if (!in_array($behoerde, $allowedBehoerden, true)) {
    jsonResponse(false, [], 'Unsupported behoerde');
}
if ($userId <= 0) {
    jsonResponse(false, [], 'user_id required');
}

try {
    $pdo = getDBConnection();

    // 1. Member (Vollmachtgeber)
    $stmt = $pdo->prepare('
        SELECT id, mitgliedernummer, vorname, nachname, geburtsdatum, geburtsort,
               strasse, hausnummer, plz, ort
        FROM users
        WHERE id = ?
    ');
    $stmt->execute([$userId]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonResponse(false, [], 'User not found');

    // 2. Vorsitzender (Bevollmächtigter) — first by mitgliedernummer
    $stmt = $pdo->prepare("
        SELECT id, vorname, nachname, mitgliedernummer
        FROM users
        WHERE role = 'vorsitzer'
        ORDER BY mitgliedernummer ASC
        LIMIT 1
    ");
    $stmt->execute();
    $vorsitzer = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$vorsitzer) jsonResponse(false, [], 'No Vorsitzer found in system');

    // 3. Verein
    $verein = $pdo->query('SELECT * FROM vereineinstellungen ORDER BY id ASC LIMIT 1')
                  ->fetch(PDO::FETCH_ASSOC);
    if (!$verein) jsonResponse(false, [], 'Verein not configured');

    // 4. Behoerde-specific data
    //   - arbeitsagentur: kundennummer + dienststelle (from arbeitsagentur_data)
    //   - jobcenter:      kundennummer + bg_nummer + selected_amt_name
    //                     (from jobcenter_data, bereich='stammdaten')
    $userBehoerde = ['dienststelle' => '', 'kundennummer' => '', 'bg_nummer' => ''];
    if ($behoerde === 'arbeitsagentur') {
        $stmt = $pdo->prepare("
            SELECT feld_name, feld_wert FROM arbeitsagentur_data
            WHERE user_id = ? AND feld_name IN ('dienststelle', 'kundennummer')
        ");
        $stmt->execute([$userId]);
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $userBehoerde[$row['feld_name']] = dv($row['feld_wert']);
        }
    } elseif ($behoerde === 'jobcenter') {
        $stmt = $pdo->prepare("
            SELECT feld_name, feld_wert FROM jobcenter_data
            WHERE user_id = ? AND bereich = 'stammdaten'
              AND feld_name IN ('kundennummer', 'bg_nummer', 'selected_amt_name')
        ");
        $stmt->execute([$userId]);
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            if ($row['feld_name'] === 'kundennummer')      $userBehoerde['kundennummer'] = dv($row['feld_wert']);
            if ($row['feld_name'] === 'bg_nummer')         $userBehoerde['bg_nummer']    = dv($row['feld_wert']);
            if ($row['feld_name'] === 'selected_amt_name') $userBehoerde['dienststelle'] = dv($row['feld_wert']);
        }
    }

    jsonResponse(true, [
        'user' => [
            'id'              => (int)$user['id'],
            'vorname'         => $user['vorname'] ?? '',
            'nachname'        => $user['nachname'] ?? '',
            'geburtsdatum'    => $user['geburtsdatum'] ?? '',
            'geburtsort'      => $user['geburtsort'] ?? '',
            'strasse'         => $user['strasse'] ?? '',
            'hausnummer'      => $user['hausnummer'] ?? '',
            'plz'             => $user['plz'] ?? '',
            'ort'             => $user['ort'] ?? '',
        ],
        'user_behoerde' => $userBehoerde,
        'vorsitzer' => [
            'id'       => (int)$vorsitzer['id'],
            'vorname'  => $vorsitzer['vorname'] ?? '',
            'nachname' => $vorsitzer['nachname'] ?? '',
        ],
        'verein' => [
            'vereinsname'      => $verein['vereinsname'] ?? '',
            'adresse'          => $verein['adresse'] ?? '',
            'registernummer'   => $verein['registernummer'] ?? '',
            'registergericht'  => $verein['registergericht'] ?? '',
            'email'            => $verein['email'] ?? '',
        ],
    ]);
} catch (Throwable $e) {
    error_log('vollmacht_data error: ' . $e->getMessage());
    jsonResponse(false, [], 'Server error');
}
