<?php
// ship.php: receives a signed site bundle from bin/ship and writes it into htdocs.
//
// Auth: HMAC-SHA256 with the key in ../ship.key (outside htdocs, never served).
//   X-Ship-Time  unix seconds, must be within 300 s of the server clock
//   X-Ship-Sig   hex hmac(key, time . "\n" . sha256(body))
// A signature is accepted once (../ship.seen), so a captured request can't be replayed.
// Body: JSON {"stamp": "...", "files": {"path/in/htdocs": "<base64>", ...}}
// Static files only: anything that could execute (.php, .htaccess, ...) is refused,
// so a leaked key can deface the site but never run code on the server.
// Overwrites, never deletes. Never touches itself.

header('Content-Type: application/json');
header('Cache-Control: no-store');

function done($code, $msg, $extra = []) {
    http_response_code($code);
    echo json_encode(['ok' => $code === 200, 'msg' => $msg] + $extra), "\n";
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') done(405, 'POST only');

$home = dirname(__DIR__);
$key = @file_get_contents("$home/ship.key");
$key = $key === false ? '' : trim($key);
if (strlen($key) < 32) done(500, 'ship.key missing beside htdocs');

$body = file_get_contents('php://input', false, null, 0, 20 * 1024 * 1024 + 1);
if ($body === false || strlen($body) > 20 * 1024 * 1024) done(413, 'bundle over 20 MB');

$t = $_SERVER['HTTP_X_SHIP_TIME'] ?? '';
$sig = strtolower($_SERVER['HTTP_X_SHIP_SIG'] ?? '');
if (!ctype_digit($t) || abs(time() - (int)$t) > 300) done(401, 'stale or missing X-Ship-Time', ['server_time' => time()]);
$want = hash_hmac('sha256', $t . "\n" . hash('sha256', $body), $key);
if (!hash_equals($want, $sig)) done(401, 'bad signature');

$seenFile = "$home/ship.seen";
$seen = @file($seenFile, FILE_IGNORE_NEW_LINES) ?: [];
if (in_array($sig, $seen, true)) done(409, 'replayed request');
$seen[] = $sig;
file_put_contents($seenFile, implode("\n", array_slice($seen, -200)) . "\n", LOCK_EX);

$req = json_decode($body, true);
if (!is_array($req) || !isset($req['files']) || !is_array($req['files'])) done(400, 'bad bundle');

$deny = '/\.(php\d?|phtml|phar|pht|cgi|pl|py|sh|htaccess|htpasswd|user\.ini)$|(^|\/)\.ht|(^|\/)\.user\.ini$/i';
$files = [];
foreach ($req['files'] as $path => $b64) {
    $path = (string)$path;
    if ($path === '' || $path[0] === '/' || strpos($path, "\0") !== false || strpos($path, '\\') !== false) done(400, "bad path: $path");
    foreach (explode('/', $path) as $seg) if ($seg === '' || $seg === '.' || $seg === '..') done(400, "bad path: $path");
    if (preg_match($deny, $path) || $path === 'ship.php') done(403, "refused: $path");
    $data = base64_decode((string)$b64, true);
    if ($data === false) done(400, "bad base64: $path");
    $files[$path] = $data;
}
if (!$files) done(400, 'empty bundle');

$root = __DIR__;
$written = 0;
foreach ($files as $path => $data) {
    $dest = "$root/$path";
    $dir = dirname($dest);
    if (!is_dir($dir) && !mkdir($dir, 0755, true)) done(500, "mkdir failed: $path");
    $tmp = "$dest.ship-" . bin2hex(random_bytes(4));
    if (file_put_contents($tmp, $data) === false || !rename($tmp, $dest)) { @unlink($tmp); done(500, "write failed: $path"); }
    @chmod($dest, 0644);
    $written++;
}

$stamp = preg_replace('/[^A-Za-z0-9._-]/', '', (string)($req['stamp'] ?? '')) ?: (string)time();
file_put_contents("$root/deploy.txt", "$stamp\n");
done(200, 'shipped', ['files' => $written, 'stamp' => $stamp]);
