<?php
/**
 * API Endpoint: Stream a Vollmacht-related file (PDF, signature, receipt).
 *
 * URL:    /api/admin/vollmacht_pdf.php?id=<int>[&type=pdf|signature_member|signature_vorstand|receipt]
 * Method: GET
 *
 * type defaults to 'pdf' (the generated procura). For the main PDF we also
 * verify SHA256. Signature/receipt uploads are streamed without integrity
 * check (they're user uploads, no canonical hash recorded yet).
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

$id   = (int)($_GET['id'] ?? 0);
$type = $_GET['type'] ?? 'pdf';
if ($id <= 0) jsonResponse(false, [], 'id required');
$allowed = ['pdf', 'signature_member', 'signature_vorstand', 'receipt'];
if (!in_array($type, $allowed, true)) jsonResponse(false, [], 'Invalid type');

try {
    $pdo = getDBConnection();
    $stmt = $pdo->prepare('
        SELECT pdf_filename, pdf_sha256,
               signature_member_filename, signature_vorstand_filename,
               submitted_receipt_filename
        FROM member_vollmachten
        WHERE id = ?
    ');
    $stmt->execute([$id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) jsonResponse(false, [], 'Not found');

    $baseDir = __DIR__ . '/../../uploads/vollmachten';
    $relPath = null;
    $expectedSha = null;
    switch ($type) {
        case 'pdf':
            $relPath = $row['pdf_filename'] ? $row['pdf_filename'] : null;
            $expectedSha = $row['pdf_sha256'] ?: null;
            $subDir = '';
            break;
        case 'signature_member':
            $relPath = $row['signature_member_filename'];
            $subDir = '/signatures';
            break;
        case 'signature_vorstand':
            $relPath = $row['signature_vorstand_filename'];
            $subDir = '/signatures';
            break;
        case 'receipt':
            $relPath = $row['submitted_receipt_filename'];
            $subDir = '/signatures';
            break;
    }

    if (empty($relPath)) jsonResponse(false, [], 'File not uploaded yet');
    $absPath = $baseDir . $subDir . '/' . $relPath;
    if (!is_file($absPath) || !is_readable($absPath)) {
        jsonResponse(false, [], 'File missing on disk');
    }
    if ($expectedSha) {
        $actual = hash_file('sha256', $absPath);
        if (!hash_equals($expectedSha, $actual)) {
            error_log("vollmacht_pdf: SHA256 mismatch for id=$id type=$type");
            jsonResponse(false, [], 'Integrity check failed');
        }
    }

    $mime = match (strtolower(pathinfo($absPath, PATHINFO_EXTENSION))) {
        'pdf'        => 'application/pdf',
        'jpg', 'jpeg'=> 'image/jpeg',
        'png'        => 'image/png',
        default      => 'application/octet-stream',
    };
    header('Content-Type: ' . $mime);
    header('Content-Disposition: inline; filename="' . basename($absPath) . '"');
    header('Content-Length: ' . filesize($absPath));
    header('Cache-Control: private, no-cache, no-store, must-revalidate');
    readfile($absPath);
    exit;
} catch (Throwable $e) {
    error_log('vollmacht_pdf error: ' . $e->getMessage());
    jsonResponse(false, [], 'Server error');
}
