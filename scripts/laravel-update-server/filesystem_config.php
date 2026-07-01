<?php

// ─────────────────────────────────────────────────────────────────────────────
// Add the 'updates' disk to config/filesystems.php inside the 'disks' array:
// ─────────────────────────────────────────────────────────────────────────────

return [
    // ... your existing disks ...

    'updates' => [
        'driver'     => 'local',
        'root'       => storage_path('app/updates'),
        'visibility' => 'private',          // served via controller, not direct URL
    ],
];

// ─────────────────────────────────────────────────────────────────────────────
// Add to config/app.php:
// ─────────────────────────────────────────────────────────────────────────────

//  'update_base_url'      => env('UPDATE_BASE_URL', 'https://tmrw-update.w3ai.io'),
//  'publish_secret'       => env('PUBLISH_SECRET'),
//  'publish_hmac_secret'  => env('PUBLISH_HMAC_SECRET'),

// ─────────────────────────────────────────────────────────────────────────────
// Add to your Laravel .env:
// ─────────────────────────────────────────────────────────────────────────────

// UPDATE_BASE_URL=https://tmrw-update.w3ai.io
// PUBLISH_SECRET=<same value as in the browser repo .env>
// PUBLISH_HMAC_SECRET=<generate with: openssl rand -hex 32>
