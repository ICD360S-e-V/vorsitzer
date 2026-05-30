<?php
/**
 * API Endpoint: List Vollmachten for a member / behoerde.
 *
 * URL:    /api/admin/vollmacht_list.php
 * Method: GET
 * Params: ?user_id=<int>&behoerde=arbeitsagentur (both optional)
 */
define('API_ACCESS', true);
require_once '../config.php';

validateApiKey();
blockBrowserAccess();
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    jsonResponse(false, [], 'Method not allowed');
}

$callerId = requireAuth();
requireAdminRole();

$userId   = $_GET['user_id']  ?? null;
$behoerde = $_GET['behoerde'] ?? null;

try {
    $pdo = getDBConnection();
    $sql = '
        SELECT mv.id, mv.user_id, mv.behoerde, mv.vorsitzer_id,
               mv.generated_at, mv.valid_from, mv.valid_until,
               mv.status, mv.revoked_at, mv.revoked_reason,
               mv.options_json, mv.pdf_filename, mv.pdf_sha256, mv.signed_at,
               mv.created_at, mv.created_by,
               u.vorname AS user_vorname, u.nachname AS user_nachname,
               v.vorname AS vorsitzer_vorname, v.nachname AS vorsitzer_nachname
        FROM member_vollmachten mv
        JOIN users u ON u.id = mv.user_id
        JOIN users v ON v.id = mv.vorsitzer_id
        WHERE 1=1
    ';
    $params = [];
    if ($userId !== null && $userId !== '') {
        $sql .= ' AND mv.user_id = ?';
        $params[] = (int)$userId;
    }
    if ($behoerde !== null && $behoerde !== '') {
        $sql .= ' AND mv.behoerde = ?';
        $params[] = $behoerde;
    }
    $sql .= ' ORDER BY mv.generated_at DESC LIMIT 200';

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($rows as &$r) {
        $r['id']           = (int)$r['id'];
        $r['user_id']      = (int)$r['user_id'];
        $r['vorsitzer_id'] = (int)$r['vorsitzer_id'];
        $r['options']      = json_decode($r['options_json'] ?? '{}', true);
        unset($r['options_json']);
        $r['pdf_url']      = '/api/admin/vollmacht_pdf.php?id=' . $r['id'];
    }
    jsonResponse(true, ['vollmachten' => $rows]);
} catch (Throwable $e) {
    error_log('vollmacht_list error: ' . $e->getMessage());
    jsonResponse(false, [], 'Server error');
}
