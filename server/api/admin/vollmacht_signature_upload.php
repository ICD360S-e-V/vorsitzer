<?php
/**
 * API Endpoint: Upload a signature (or delete) for a Vollmacht.
 *
 * URL:    /api/admin/vollmacht_signature_upload.php
 * Method: POST  (multipart/form-data for upload, application/json for delete)
 *
 * Upload (multipart):
 *   - vollmacht_id (int)
 *   - signer       ('member' | 'vorstand' | 'receipt')
 *   - file         (PDF / JPG / PNG, max 10 MB)
 *
 * Delete (application/json):
 *   { "vollmacht_id": <int>, "signer": "member|vorstand|receipt", "delete": true }
 *
 * Updates status to:
 *   - wartet_unterschriften  → if any signature missing
 *   - unterzeichnet          → if both member + vorstand signatures present
 *                              AND submitted_at IS NULL
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

$contentType = $_SERVER['CONTENT_TYPE'] ?? '';
$isJson = str_contains(strtolower($contentType), 'application/json');

if ($isJson) {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) jsonResponse(false, [], 'Invalid JSON');
    $vollmachtId = (int)($input['vollmacht_id'] ?? 0);
    $signer      = (string)($input['signer'] ?? '');
    $isDelete    = ($input['delete'] ?? false) === true;
} else {
    $vollmachtId = (int)($_POST['vollmacht_id'] ?? 0);
    $signer      = (string)($_POST['signer'] ?? '');
    $isDelete    = false;
}

if ($vollmachtId <= 0) jsonResponse(false, [], 'vollmacht_id required');
if (!in_array($signer, ['member', 'vorstand', 'receipt'], true)) {
    jsonResponse(false, [], 'signer must be member|vorstand|receipt');
}

$colFile = $signer === 'receipt' ? 'submitted_receipt_filename' : "signature_{$signer}_filename";
$colAt   = $signer === 'receipt' ? null                          : "signature_{$signer}_uploaded_at";
$colBy   = $signer === 'receipt' ? null                          : "signature_{$signer}_uploaded_by";

try {
    $pdo = getDBConnection();

    // Verify ownership / existence
    $stmt = $pdo->prepare("SELECT id, user_id, $colFile AS current_file FROM member_vollmachten WHERE id = ?");
    $stmt->execute([$vollmachtId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) jsonResponse(false, [], 'Vollmacht not found');

    $storageDir = __DIR__ . '/../../uploads/vollmachten/signatures';
    if (!is_dir($storageDir)) mkdir($storageDir, 0750, true);

    if ($isDelete) {
        if (!empty($row['current_file'])) {
            $absPath = $storageDir . '/' . $row['current_file'];
            if (is_file($absPath)) @unlink($absPath);
        }
        if ($colAt) {
            $pdo->prepare("UPDATE member_vollmachten SET $colFile=NULL, $colAt=NULL, $colBy=NULL WHERE id=?")
                ->execute([$vollmachtId]);
        } else {
            $pdo->prepare("UPDATE member_vollmachten SET $colFile=NULL WHERE id=?")->execute([$vollmachtId]);
        }
        recomputeStatus($pdo, $vollmachtId);
        jsonResponse(true, ['deleted' => true]);
    }

    // Upload path
    if (!isset($_FILES['file']) || $_FILES['file']['error'] !== UPLOAD_ERR_OK) {
        jsonResponse(false, [], 'No valid file uploaded');
    }
    $file = $_FILES['file'];
    if ($file['size'] > 10 * 1024 * 1024) jsonResponse(false, [], 'File too large (max 10 MB)');

    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $mime  = $finfo->file($file['tmp_name']);
    $allowed = ['application/pdf', 'image/jpeg', 'image/png'];
    if (!in_array($mime, $allowed, true)) {
        jsonResponse(false, [], 'Only PDF, JPG, PNG allowed');
    }
    $ext = match ($mime) { 'application/pdf' => 'pdf', 'image/jpeg' => 'jpg', 'image/png' => 'png' };

    $filename = sprintf('vollmacht%d_%s_%s.%s', $vollmachtId, $signer, date('Ymd_His'), $ext);
    $absPath  = $storageDir . '/' . $filename;
    if (!move_uploaded_file($file['tmp_name'], $absPath)) {
        jsonResponse(false, [], 'Failed to save file');
    }

    // Delete previous file if any
    if (!empty($row['current_file'])) {
        $prev = $storageDir . '/' . $row['current_file'];
        if (is_file($prev) && $prev !== $absPath) @unlink($prev);
    }

    if ($colAt) {
        $pdo->prepare("UPDATE member_vollmachten SET $colFile=?, $colAt=NOW(), $colBy=? WHERE id=?")
            ->execute([$filename, $callerId, $vollmachtId]);
    } else {
        $pdo->prepare("UPDATE member_vollmachten SET $colFile=? WHERE id=?")
            ->execute([$filename, $vollmachtId]);
    }
    recomputeStatus($pdo, $vollmachtId);

    jsonResponse(true, [
        'filename' => $filename,
        'size'     => $file['size'],
        'mime'     => $mime,
    ]);
} catch (Throwable $e) {
    error_log('vollmacht_signature_upload error: ' . $e->getMessage());
    jsonResponse(false, [], 'Server error');
}

/**
 * Derive status from current state:
 *   - revoked / expired: keep as-is
 *   - both signatures present + submitted_at set: 'aktiv'
 *   - both signatures present, not submitted: 'unterzeichnet'
 *   - any signature missing, generated: 'wartet_unterschriften'
 *   - no signatures: 'draft'
 */
function recomputeStatus(PDO $pdo, int $id): void {
    $stmt = $pdo->prepare('
        SELECT signature_member_filename AS sm, signature_vorstand_filename AS sv,
               submitted_at AS sa, status
        FROM member_vollmachten WHERE id = ?
    ');
    $stmt->execute([$id]);
    $r = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$r) return;
    if (in_array($r['status'], ['revoked', 'expired'], true)) return;

    $hasBoth = !empty($r['sm']) && !empty($r['sv']);
    $hasAny  = !empty($r['sm']) || !empty($r['sv']);
    if ($hasBoth && !empty($r['sa'])) $new = 'aktiv';
    elseif ($hasBoth)                  $new = 'unterzeichnet';
    elseif ($hasAny)                   $new = 'wartet_unterschriften';
    else                               $new = 'draft';

    if ($new !== $r['status']) {
        $pdo->prepare('UPDATE member_vollmachten SET status=? WHERE id=?')->execute([$new, $id]);
    }
}
