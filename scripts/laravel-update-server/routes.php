<?php

use App\Http\Controllers\UpdateController;
use Illuminate\Support\Facades\Route;

// ─────────────────────────────────────────────────────────────────────────────
// FILE: routes/web.php  — add these GET routes to your existing web.php
// GET requests are never subject to CSRF, so they are safe here.
// ─────────────────────────────────────────────────────────────────────────────

// Public: Firefox polls this every 6 hours
Route::get('/updates/update.xml', [UpdateController::class, 'xml'])
    ->middleware('throttle:120,1');

// Public: streams MAR / DMG files from private storage
Route::get('/download/{filename}', [UpdateController::class, 'download'])
    ->middleware('throttle:120,1')
    ->where('filename', '[A-Za-z0-9\-\.\_]+');

// ─────────────────────────────────────────────────────────────────────────────
// FILE: routes/api.php  — add these to your existing api.php
//
// Laravel automatically prefixes api.php with /api and uses the 'api'
// middleware group which has NO CSRF protection.
// POST /upload/{type} → /api/upload/{type}
// POST /publish       → /api/publish
// GET  /status        → /api/status
// ─────────────────────────────────────────────────────────────────────────────

// Public status check
Route::get('/status', [UpdateController::class, 'status']);

// Private: Bearer token + HMAC-SHA256 signature required
Route::middleware(['verify.publish', 'throttle:30,1'])->group(function () {
    Route::post('/upload/{type}', [UpdateController::class, 'upload'])
        ->where('type', 'mar|dmg');

    Route::post('/publish', [UpdateController::class, 'publish']);

    Route::post('/clear', [UpdateController::class, 'clear']);
});
