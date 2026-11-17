<?php
// /api/feedback: feedback sent from inside a PARADOX app (first: Focus).
//
//   POST https://paradoxica.uk/api/feedback        JSON (or a form post)
//     app      required  the app's slug: "focus"
//     message  required  what the person wrote, 1 to 5000 characters
//     kind     optional  "bug" | "idea" | "other"
//     email    optional  if they want a reply
//     version  optional  app version, e.g. "0.16"
//     os       optional  e.g. "macOS 15.1" ("macOS" is accepted as the name too)
//   -> 200 {"ok":true,"id":"..."}     400 bad input · 405 not POST · 413 too big · 429 slow down
//
// Each message is appended to ~/feedback/<app>.jsonl (beside htdocs, never served) and emailed to the
// address in ~/feedback/to (default below). No key: the app is public, so the limits are the protection:
// 16 KB a request, 5 per 10 minutes and 30 a day per address, 500 a day in all.
// Installed over SSH by bin/api-install (bin/ship refuses .php by design).

const TO_DEFAULT = 'help@paradoxica.co.uk';   // the brand rule (16 Nov 2026): every app's feedback goes to help@
const MAX_BODY = 16384;

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

// A feedback form on our own pages may call this too. Apps need no CORS.
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if (preg_match('#^https?://(www\.)?(paradoxica\.(uk|co\.uk)|slowdownforcats\.org)$#', $origin)) {
    header("Access-Control-Allow-Origin: $origin");
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');
    header('Access-Control-Max-Age: 86400');
    header('Vary: Origin');
}
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'OPTIONS') { http_response_code(204); exit; }

function done($code, $msg, $extra = []) {
    http_response_code($code);
    echo json_encode(['ok' => $code === 200, 'msg' => $msg] + $extra), "\n";
    exit;
}
if ($method !== 'POST') { header('Allow: POST, OPTIONS'); done(405, 'POST only'); }

$body = file_get_contents('php://input', false, null, 0, MAX_BODY + 1);
if ($body === false) done(400, 'no body');
if (strlen($body) > MAX_BODY) done(413, 'too big: 16 KB at most');

$in = null;
if (stripos($_SERVER['CONTENT_TYPE'] ?? '', 'json') !== false || ($body !== '' && $body[0] === '{')) $in = json_decode($body, true);
else parse_str($body, $in);
if (!is_array($in)) done(400, 'send JSON or a form post');

// text: valid UTF-8, no control characters except new lines and tabs, trimmed, capped
function clean($v, $max, $oneLine = false) {
    if (!is_string($v) && !is_int($v) && !is_float($v)) return '';
    $s = (string)$v;
    if (!mb_check_encoding($s, 'UTF-8')) $s = mb_convert_encoding($s, 'UTF-8', 'UTF-8');
    $s = str_replace(["\r\n", "\r"], "\n", $s);
    $s = preg_replace($oneLine ? '/[\x00-\x1F\x7F]+/u' : '/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]+/u', ' ', $s) ?? '';
    return mb_substr(trim($s), 0, $max);
}
$app = strtolower(clean($in['app'] ?? '', 32, true));
if (!preg_match('/^[a-z0-9][a-z0-9-]{0,31}$/', $app)) done(400, 'app is required: the app\'s name, e.g. "focus"');
$message = clean($in['message'] ?? '', 5000);
if ($message === '') done(400, 'message is required');
$kind = strtolower(clean($in['kind'] ?? '', 16, true));
if (!in_array($kind, ['bug', 'idea', 'other'], true)) $kind = 'other';
$email = clean($in['email'] ?? '', 254, true);
// the account's email, sent by the app when there is one (never asked for again); empty until sign-in exists
if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) done(400, 'email is not a valid address');
$version = clean($in['version'] ?? '', 40, true);
$os = clean($in['os'] ?? $in['macOS'] ?? '', 80, true);   // Focus sends it as "macOS"

$home = dirname(__DIR__, 2);                        // htdocs/api -> the account's home
$dir = getenv('FEEDBACK_DIR') ?: "$home/feedback";  // FEEDBACK_DIR: tests only
if (!is_dir($dir) && !@mkdir($dir, 0700, true)) done(500, 'cannot store feedback');

// limits: per address (kept as a hash, never the address itself) and in all
$ip = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? ($_SERVER['REMOTE_ADDR'] ?? '');
$ip = trim(explode(',', $ip)[0]);
$who = substr(hash('sha256', "feedback|$ip"), 0, 16);
$now = time();
$fh = @fopen("$dir/.rate.json", 'c+');
if (!$fh || !flock($fh, LOCK_EX)) done(500, 'cannot store feedback');
$rate = json_decode(stream_get_contents($fh) ?: '[]', true);
if (!is_array($rate)) $rate = [];
$rate = array_values(array_filter($rate, fn($r) => is_array($r) && ($r[0] ?? 0) > $now - 86400));
$mine = array_filter($rate, fn($r) => $r[1] === $who);
$recent = array_filter($mine, fn($r) => $r[0] > $now - 600);
$limit = count($recent) >= 5 || count($mine) >= 30 || count($rate) >= 500;
if (!$limit) $rate[] = [$now, $who];
ftruncate($fh, 0); rewind($fh); fwrite($fh, json_encode($rate)); fflush($fh); flock($fh, LOCK_UN); fclose($fh);
if ($limit) { header('Retry-After: 600'); done(429, 'too many messages: try again later'); }

$id = gmdate('Ymd-His', $now) . '-' . bin2hex(random_bytes(3));
$row = ['id' => $id, 'at' => gmdate('c', $now), 'app' => $app, 'kind' => $kind, 'message' => $message,
        'email' => $email, 'version' => $version, 'os' => $os, 'who' => $who];
$line = json_encode($row, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
if (@file_put_contents("$dir/$app.jsonl", $line, FILE_APPEND | LOCK_EX) === false) done(500, 'cannot store feedback');
@chmod("$dir/$app.jsonl", 0600);

// the email is a convenience: the file is the record, so a failed send still answers ok
$to = trim((string)@file_get_contents("$dir/to")) ?: TO_DEFAULT;
if (filter_var($to, FILTER_VALIDATE_EMAIL) && !getenv('FEEDBACK_NO_MAIL')) {
    // subject: APP NAME IN CAPITALS + space + the rest (brand rule). An app may send its own subject in that form; the
    // recipient is never taken from the request (a client-supplied "to" is ignored, so this can't be used to send mail anywhere).
    $name = strtoupper(explode('-', $app)[0]);
    $given = clean($in['subject'] ?? '', 120, true);
    $first = mb_substr(strtok($message, "\n"), 0, 60);
    $subj = ($given !== '' && str_starts_with($given, "$name ")) ? $given : "$name $first";
    $subject = '=?UTF-8?B?' . base64_encode($subj) . '?=';
    $text = $message . "\n\n--\nApp: $app" . ($version ? " $version" : '') . ($os ? "\nSystem: $os" : '')
          . "\nReply to: " . ($email ?: 'no address given') . "\nRef: $id\n";
    $host = preg_replace('/^www\./', '', strtolower($_SERVER['SERVER_NAME'] ?? 'paradoxica.uk'));
    if (!preg_match('/^[a-z0-9.-]+$/', $host)) $host = 'paradoxica.uk';
    $headers = "From: PARADOX feedback <feedback@$host>\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit";
    if ($email) $headers .= "\r\nReply-To: $email";
    @mail($to, $subject, $text, $headers);
}
done(200, 'thank you', ['id' => $id]);
