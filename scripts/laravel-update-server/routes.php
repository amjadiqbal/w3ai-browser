<?php

// ─────────────────────────────────────────────────────────────────────────────
// Add these to your Laravel routes/web.php (or routes/api.php — see note below)
// ─────────────────────────────────────────────────────────────────────────────
//
// NOTE: Put the public routes in routes/web.php (no CSRF).
//       Put the private API routes in routes/api.php so they use the
//       api middleware group (stateless, throttled).
//
// In routes/web.php:
// ─────────────────────────────────────────────────────────────────────────────

use App\Http\Controllers\UpdateController;
use Illuminate\Support\Facades\Route;

// Public — browser polls this to check for updates
Route::get('/updates/update.xml', [UpdateController::class, 'xml'])
    ->name('update.xml');

// Public — browser/user downloads MAR patch or DMG installer
Route::get('/download/{filename}', [UpdateController::class, 'download'])
    ->where('filename', '[A-Za-z0-9\-\.\_]+')
    ->name('update.download')
    ->middleware('throttle:120,1');

// Public status check (useful for monitoring)
Route::get('/api/status', [UpdateController::class, 'status'])
    ->name('update.status');

// ─────────────────────────────────────────────────────────────────────────────
// In routes/api.php  (or add to web.php inside a middleware group):
// ─────────────────────────────────────────────────────────────────────────────

Route::middleware(['throttle:30,1', \App\Http\Middleware\VerifyPublishRequest::class])
    ->prefix('api')
    ->group(function () {
        // Step 1: Upload the MAR (and optionally DMG) file
        // POST /api/upload/mar   multipart: file, version
        // POST /api/upload/dmg   multipart: file, version
        Route::post('/upload/{type}', [UpdateController::class, 'upload'])
            ->where('type', 'dmg|mar')
            ->name('update.upload');

        // Step 2: Register the build as the live update
        // POST /api/publish   JSON: { version, buildID, marHash, marSize, dmgHash?, dmgSize?, notes? }
        Route::post('/publish', [UpdateController::class, 'publish'])
            ->name('update.publish');
    });
