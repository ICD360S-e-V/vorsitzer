<?php
/**
 * API Endpoint: Stream a generated Vollmacht PDF.
 *
 * URL:    /api/admin/vollmacht_pdf.php?id=<int>
 * Method: GET
 *
 * Streams the PDF from disk. Verifies the SHA256 matches the stored value
 * before sending — protects against on-disk tampering.
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

$id = (int)($_GET['id'] ?? 0);
if ($id <= 0) jsonResponse(false, [], 'id required');

try {
    $pdo = getDBConnection();
    $stmt = $pdo->prepare('
        SELECT pdf_filename, pdf_sha256, user_id
        FROM member_vollmachten
        WHERE id = ?
    ');
    $stmt->execute([$id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row || empty($row['pdf_filename'])) jsonResponse(false, [], 'Not found');

    $absPath = __DIR__ . '/../../uploads/vollmachten/' . $row['pdf_filename'];
    if (!is_file($absPath) || !is_readable($absPath)) {
        jsonResponse(false, [], 'PDF file missing on disk');
    }
    if (!empty($row['pdf_sha256'])) {
        $actual = hash_file('sha256', $absPath);
        if (!hash_equals($row['pdf_sha256'], $actual)) {
            error_log("vollmacht_pdf: SHA256 mismatch for id=$id");
            jsonResponse(false, [], 'PDF integrity check failed');
        }
    }

    header('Content-Type: application/pdf');
    header('Content-Disposition: inline; filename="' . basename($row['pdf_filename']) . '"');
    header('Content-Length: ' . filesize($absPath));
    header('Cache-Control: private, no-cache, no-store, must-revalidate');
    readfile($absPath);
    exit;
} catch (Throwable $e) {
    error_log('vollmacht_pdf error: ' . $e->getMessage());
    jsonResponse(false, [], 'Server error');
}
