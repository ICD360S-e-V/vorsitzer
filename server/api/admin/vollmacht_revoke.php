<?php
/**
 * API Endpoint: Revoke a Vollmacht.
 *
 * URL:    /api/admin/vollmacht_revoke.php
 * Method: POST  (application/json)
 * Body:   { "id": <int>, "reason": "..." }
 *
 * Marks the Vollmacht as 'revoked'. Per the legal note in the PDF, after
 * revocation, account credential changes are the member's responsibility —
 * this endpoint only records the revocation; it does NOT delete the member's
 * BA-account credentials (the member must do that personally).
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

$id     = (int)($input['id'] ?? 0);
$reason = trim((string)($input['reason'] ?? ''));
if ($id <= 0) jsonResponse(false, [], 'id required');

try {
    $pdo = getDBConnection();

    $stmt = $pdo->prepare('SELECT id, status FROM member_vollmachten WHERE id = ?');
    $stmt->execute([$id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) jsonResponse(false, [], 'Vollmacht not found');
    if ($row['status'] === 'revoked') jsonResponse(false, [], 'Already revoked');

    $upd = $pdo->prepare('
        UPDATE member_vollmachten
        SET status = "revoked", revoked_at = NOW(), revoked_reason = ?
        WHERE id = ?
    ');
    $upd->execute([$reason !== '' ? $reason : null, $id]);

    jsonResponse(true, ['id' => $id, 'status' => 'revoked', 'revoked_at' => date('c')]);
} catch (Throwable $e) {
    error_log('vollmacht_revoke error: ' . $e->getMessage());
    jsonResponse(false, [], 'Server error');
}
