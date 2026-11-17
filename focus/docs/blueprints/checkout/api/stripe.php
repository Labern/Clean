<?php
// /api/stripe/*: Focus payments, through Stripe Checkout Sessions with our own page (ui_mode "elements").
//
//   POST /api/stripe/session   {"plan":"monthly"|"yearly"|"once"}         -> {"clientSecret":"..."}
//   GET  /api/stripe/status?session_id=cs_...                              -> {"status","paid","plan","email"}
//   POST /api/stripe/webhook   (Stripe only; signature checked)            -> 200
//
// Prices are Stripe Prices found by lookup key (focus_pro_monthly / _yearly / _once), so the amounts live in Stripe and
// in focus/pricing.json, never here. The early adopter gift is the promotion code EARLY, applied on the page.
// Card details never reach this server: the Payment Element sends them straight to Stripe.
//
// Secrets live beside htdocs, never served: ~/stripe/secret.key (sk_...) and ~/stripe/webhook.secret (whsec_...).
// Purchases are appended to ~/stripe/purchases.jsonl from the webhook (the record of who bought what).
// Installed over SSH by bin/api-install (bin/ship refuses .php by design).

const STRIPE_VERSION = '2026-10-28.endive';
const PLANS = ['monthly' => ['focus_pro_monthly', 'subscription'],
               'yearly'  => ['focus_pro_yearly',  'subscription'],
               'once'    => ['focus_pro_once',    'payment']];

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if (preg_match('#^https?://(www\.)?paradoxica\.(uk|co\.uk)$#', $origin) || getenv('STRIPE_DEV_ORIGIN') === $origin) {
    header("Access-Control-Allow-Origin: $origin");
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');
    header('Vary: Origin');
}
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'OPTIONS') { http_response_code(204); exit; }

function out($code, $data) { http_response_code($code); echo json_encode($data, JSON_UNESCAPED_SLASHES), "\n"; exit; }
function fail($code, $msg) { out($code, ['error' => $msg]); }

$home = dirname(__DIR__, 2);                             // htdocs/api -> the account's home
$dir = getenv('STRIPE_DIR') ?: "$home/stripe";           // STRIPE_DIR: local tests only
function secret($dir, $name) { $v = trim((string)@file_get_contents("$dir/$name")); return $v; }

// Stripe's API: form-encoded in, JSON out. Our only dependency is curl.
function stripe($dir, $verb, $path, $params = []) {
    $key = secret($dir, 'secret.key');
    if ($key === '') fail(503, 'payments are not set up yet');
    $url = 'https://api.stripe.com/v1/' . $path;
    $q = http_build_query($params);
    $ch = curl_init($verb === 'GET' && $q ? "$url?$q" : $url);
    curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 20, CURLOPT_USERPWD => "$key:",
        CURLOPT_HTTPHEADER => ['Stripe-Version: ' . STRIPE_VERSION]]);
    if ($verb === 'POST') { curl_setopt($ch, CURLOPT_POST, true); curl_setopt($ch, CURLOPT_POSTFIELDS, $q); }
    if (getenv('STRIPE_DEV_PROXY')) { curl_setopt($ch, CURLOPT_PROXY, getenv('STRIPE_DEV_PROXY')); curl_setopt($ch, CURLOPT_CAINFO, getenv('STRIPE_DEV_CA')); }
    $res = curl_exec($ch); $code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE); curl_close($ch);
    $data = json_decode((string)$res, true);
    if (!is_array($data)) fail(502, 'Stripe did not answer');
    if ($code >= 400) { error_log('stripe ' . $path . ': ' . ($data['error']['message'] ?? $code)); fail(502, $data['error']['message'] ?? 'Stripe refused the request'); }
    return $data;
}

$route = trim(preg_replace('#^/?api/stripe/?#', '', parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH)), '/');
if ($route === '' && isset($_GET['r'])) $route = $_GET['r'];

// ---- create a Checkout Session for one plan --------------------------------------------------------------------
if ($route === 'session') {
    if ($method !== 'POST') fail(405, 'POST only');
    $in = json_decode(file_get_contents('php://input', false, null, 0, 4096), true);
    $plan = is_array($in) ? ($in['plan'] ?? '') : '';
    if (!isset(PLANS[$plan])) fail(400, 'plan must be monthly, yearly or once');
    [$lookup, $mode] = PLANS[$plan];
    $prices = stripe($dir, 'GET', 'prices', ['lookup_keys' => [$lookup], 'active' => 'true']);
    $price = $prices['data'][0]['id'] ?? null;
    if (!$price) fail(503, 'that plan is not on sale yet');
    $host = preg_replace('/^www\./', '', strtolower($_SERVER['HTTP_HOST'] ?? 'paradoxica.uk'));
    if (!preg_match('/^(paradoxica\.(uk|co\.uk)|localhost(:\d+)?|127\.0\.0\.1(:\d+)?)$/', $host)) $host = 'paradoxica.uk';
    $scheme = str_starts_with($host, 'localhost') || str_starts_with($host, '127.') ? 'http' : 'https';
    $p = [
        'ui_mode' => 'elements',
        'mode' => $mode,
        'line_items' => [['price' => $price, 'quantity' => 1]],
        'return_url' => "$scheme://$host/focus/checkout/done/?session_id={CHECKOUT_SESSION_ID}",
        'allow_promotion_codes' => 'true',
        'billing_address_collection' => 'auto',
        'metadata' => ['product' => 'focus', 'tier' => 'pro', 'plan' => $plan],
    ];
    if ($mode === 'payment') {                         // a one-off: keep a customer and send a proper invoice
        $p['customer_creation'] = 'always';
        $p['invoice_creation'] = ['enabled' => 'true', 'invoice_data' => ['metadata' => ['product' => 'focus', 'plan' => $plan]]];
    } else {
        $p['subscription_data'] = ['metadata' => ['product' => 'focus', 'tier' => 'pro', 'plan' => $plan]];
    }
    if (is_file("$dir/tax.on")) $p['automatic_tax'] = ['enabled' => 'true'];   // switched on once Stripe Tax is set up
    $s = stripe($dir, 'POST', 'checkout/sessions', $p);
    out(200, ['clientSecret' => $s['client_secret']]);
}

// ---- what happened to a session (the thank-you page asks) ------------------------------------------------------
if ($route === 'status') {
    $id = $_GET['session_id'] ?? '';
    if (!preg_match('/^cs_(test|live)_[A-Za-z0-9]+$/', $id)) fail(400, 'session_id is missing');
    $s = stripe($dir, 'GET', "checkout/sessions/$id", []);
    out(200, ['status' => $s['status'], 'paid' => $s['payment_status'] === 'paid' || $s['payment_status'] === 'no_payment_required',
              'plan' => $s['metadata']['plan'] ?? '', 'email' => $s['customer_details']['email'] ?? '',
              'total' => $s['amount_total'] ?? null, 'currency' => $s['currency'] ?? 'gbp']);
}

// ---- Stripe tells us about payments (signature checked) --------------------------------------------------------
if ($route === 'webhook') {
    if ($method !== 'POST') fail(405, 'POST only');
    $payload = file_get_contents('php://input', false, null, 0, 262144);
    $whsec = secret($dir, 'webhook.secret');
    if ($whsec === '') fail(503, 'webhook is not set up');
    $sig = $_SERVER['HTTP_STRIPE_SIGNATURE'] ?? '';
    $t = null; $v1 = [];
    foreach (explode(',', $sig) as $part) { [$k, $v] = array_pad(explode('=', trim($part), 2), 2, ''); if ($k === 't') $t = $v; if ($k === 'v1') $v1[] = $v; }
    if (!$t || !$v1 || abs(time() - (int)$t) > 300) fail(400, 'bad signature');
    $expect = hash_hmac('sha256', "$t.$payload", $whsec);
    $ok = false; foreach ($v1 as $v) if (hash_equals($expect, $v)) $ok = true;
    if (!$ok) fail(400, 'bad signature');
    $e = json_decode($payload, true);
    if (!is_array($e)) fail(400, 'bad payload');
    if (!is_dir($dir)) @mkdir($dir, 0700, true);
    $o = $e['data']['object'] ?? [];
    $keep = ['checkout.session.completed', 'checkout.session.async_payment_succeeded', 'checkout.session.async_payment_failed',
             'customer.subscription.updated', 'customer.subscription.deleted', 'invoice.paid', 'invoice.payment_failed', 'charge.refunded'];
    if (in_array($e['type'] ?? '', $keep, true)) {
        $row = ['at' => gmdate('c'), 'event' => $e['id'] ?? '', 'type' => $e['type'], 'livemode' => $e['livemode'] ?? false,
                'object' => $o['id'] ?? '', 'customer' => $o['customer'] ?? '', 'email' => $o['customer_details']['email'] ?? ($o['customer_email'] ?? ''),
                'plan' => $o['metadata']['plan'] ?? '', 'status' => $o['payment_status'] ?? ($o['status'] ?? ''), 'subscription' => $o['subscription'] ?? ''];
        // idempotent: the same event delivered twice is recorded once
        $seen = "$dir/seen-events.txt";
        $already = is_file($seen) && str_contains((string)file_get_contents($seen), $row['event'] . "\n");
        if (!$already) {
            file_put_contents("$dir/purchases.jsonl", json_encode($row, JSON_UNESCAPED_SLASHES) . "\n", FILE_APPEND | LOCK_EX);
            file_put_contents($seen, $row['event'] . "\n", FILE_APPEND | LOCK_EX);
            @chmod("$dir/purchases.jsonl", 0600);
        }
    }
    out(200, ['received' => true]);
}

fail(404, 'unknown');
