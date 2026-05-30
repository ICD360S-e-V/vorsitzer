<?php
/**
 * API Endpoint: Record that a Vollmacht has been submitted to the BA.
 *
 * URL:    /api/admin/vollmacht_submit.php
 * Method: POST  (application/json)
 * Body:
 *   {
 *     "vollmacht_id":  <int>,
 *     "submitted_at":  "YYYY-MM-DD" | null,  // null = clear submission
 *     "method":        "online|fax|persoenlich|post",
 *     "reference":     "<Aktenzeichen / Sendungsnummer>",
 *     "notes":         "<freitext>"
 *   }
 *
 * On submission: status transitions to 'aktiv' if both signatures present,
 * else stays at current. On clear (submitted_at=null): status falls back to
 * 'unterzeichnet' (if both signatures) or 'wartet_unterschriften'.
 */
define('API_ACCESS', true);
require_once '../config.php';

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

$vollmachtId = (int)($input['vollmacht_id'] ?? 0);
$submittedAt = $input['submitted_at'] ?? null;
$method      = $input['method'] ?? null;
$reference   = trim((string)($input['reference'] ?? ''));
$notes       = trim((string)($input['notes'] ?? ''));

if ($vollmachtId <= 0) jsonResponse(false, [], 'vollmacht_id required');
if ($submittedAt !== null && $submittedAt !== '') {
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $submittedAt)) {
        jsonResponse(false, [], 'submitted_at must be YYYY-MM-DD or null');
    }
    if (!in_array($method, ['online', 'fax', 'persoenlich', 'post'], true)) {
        jsonResponse(false, [], 'method must be online|fax|persoenlich|post');
    }
} else {
    $submittedAt = null;
    $method      = null;
    // keep reference/notes as-is if provided, allow clearing
}

try {
    $pdo = getDBConnection();

    $stmt = $pdo->prepare('SELECT id, status FROM member_vollmachten WHERE id = ?');
    $stmt->execute([$vollmachtId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) jsonResponse(false, [], 'Vollmacht not found');

    $upd = $pdo->prepare('
        UPDATE member_vollmachten
        SET submitted_at = ?, submitted_method = ?, submitted_reference = ?, submitted_notes = ?
        WHERE id = ?
    ');
    $upd->execute([
        $submittedAt,
        $method,
        $reference !== '' ? $reference : null,
        $notes !== ''     ? $notes     : null,
        $vollmachtId,
    ]);

    // Recompute status
    $check = $pdo->prepare('
        SELECT signature_member_filename AS sm, signature_vorstand_filename AS sv,
               submitted_at AS sa, status
        FROM member_vollmachten WHERE id = ?
    ');
    $check->execute([$vollmachtId]);
    $r = $check->fetch(PDO::FETCH_ASSOC);
    if (!in_array($r['status'], ['revoked', 'expired'], true)) {
        $hasBoth = !empty($r['sm']) && !empty($r['sv']);
        $hasAny  = !empty($r['sm']) || !empty($r['sv']);
        if ($hasBoth && !empty($r['sa']))      $new = 'aktiv';
        elseif ($hasBoth)                      $new = 'unterzeichnet';
        elseif ($hasAny)                       $new = 'wartet_unterschriften';
        else                                    $new = 'draft';
        if ($new !== $r['status']) {
            $pdo->prepare('UPDATE member_vollmachten SET status=? WHERE id=?')->execute([$new, $vollmachtId]);
        }
        $r['status'] = $new;
    }

    jsonResponse(true, [
        'id' => $vollmachtId, 'status' => $r['status'], 'submitted_at' => $submittedAt,
        'method' => $method, 'reference' => $reference, 'notes' => $notes,
    ]);
} catch (Throwable $e) {
    error_log('vollmacht_submit error: ' . $e->getMessage());
    jsonResponse(false, [], 'Server error');
}
