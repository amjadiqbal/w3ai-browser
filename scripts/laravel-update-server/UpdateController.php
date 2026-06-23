<?php

namespace App\Http\Controllers;

use App\Models\BrowserUpdate;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Storage;

class UpdateController extends Controller
{
    private const STORAGE_DISK = 'updates';
    private const PLATFORM_VERSION = '151.0a1';

    public function xml(): Response
    {
        $update = BrowserUpdate::current();

        if (!$update) {
            return response('<updates/>', 200)
                ->header('Content-Type', 'text/xml; charset=UTF-8')
                ->header('Cache-Control', 'no-store');
        }

        $xml = sprintf(
            '<?xml version="1.0" encoding="UTF-8"?>' . "\n" .
            '<updates>' . "\n" .
            '  <update type="minor" displayVersion="%s" appVersion="%s" platformVersion="%s" buildID="%s">' . "\n" .
            '    <patch type="complete" URL="%s" hashFunction="sha512" hashValue="%s" size="%d"/>' . "\n" .
            '  </update>' . "\n" .
            '</updates>',
            e($update->version),
            e($update->version),
            self::PLATFORM_VERSION,
            e($update->build_id),
            e($update->marUrl()),
            e($update->mar_hash),
            $update->mar_size
        );

        return response($xml, 200)
            ->header('Content-Type', 'text/xml; charset=UTF-8')
            ->header('Cache-Control', 'no-store, no-cache, must-revalidate');
    }

    public function download(string $filename): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        $filename = basename($filename);

        if (!Storage::disk(self::STORAGE_DISK)->exists($filename)) {
            abort(404, 'File not found');
        }

        $mimeType = str_ends_with($filename, '.dmg') ? 'application/x-apple-diskimage' : 'application/octet-stream';

        return Storage::disk(self::STORAGE_DISK)->download($filename, $filename, [
            'Content-Type'        => $mimeType,
            'Content-Disposition' => 'attachment; filename="' . $filename . '"',
            'Cache-Control'       => 'public, max-age=31536000, immutable',
        ]);
    }

    /**
     * Upload a DMG or MAR file.
     * POST /api/upload/{type}   type = dmg | mar
     * Multipart: file, version
     */
    public function upload(Request $request, string $type): \Illuminate\Http\JsonResponse
    {
        abort_unless(in_array($type, ['dmg', 'mar'], true), 400, 'type must be dmg or mar');

        $request->validate([
            'file'    => 'required|file|max:512000',
            'version' => 'required|string|regex:/^\d+\.\d+\.\d+$/',
        ]);

        $version  = $request->input('version');
        $ext      = $type === 'dmg' ? 'dmg' : 'complete.mar';
        $filename = "TMRW-Browser-v{$version}.{$ext}";

        $request->file('file')->storeAs('/', $filename, self::STORAGE_DISK);

        return response()->json([
            'ok'       => true,
            'filename' => $filename,
            'url'      => config('app.update_base_url') . '/download/' . $filename,
        ]);
    }

    /**
     * Register the build as the current active update.
     * POST /api/publish   Content-Type: application/json
     * Body: { version, buildID, marHash, marSize, dmgHash?, dmgSize?, notes? }
     */
    public function publish(Request $request): \Illuminate\Http\JsonResponse
    {
        $data = $request->validate([
            'version' => 'required|string|regex:/^\d+\.\d+\.\d+$/',
            'buildID' => 'required|string',
            'marHash' => 'required|string|size:128',
            'marSize' => 'required|integer|min:1',
            'dmgHash' => 'nullable|string|size:128',
            'dmgSize' => 'nullable|integer|min:1',
            'notes'   => 'nullable|string|max:4000',
        ]);

        $version     = $data['version'];
        $marFilename = "TMRW-Browser-v{$version}.complete.mar";
        $dmgFilename = "TMRW-Browser-v{$version}.dmg";

        if (!Storage::disk(self::STORAGE_DISK)->exists($marFilename)) {
            return response()->json(['error' => "MAR file not found on server: {$marFilename}. Upload it first via POST /api/upload/mar"], 422);
        }

        BrowserUpdate::where('active', true)->update(['active' => false]);

        $update = BrowserUpdate::create([
            'version'      => $version,
            'build_id'     => $data['buildID'],
            'mar_filename' => $marFilename,
            'mar_hash'     => $data['marHash'],
            'mar_size'     => $data['marSize'],
            'dmg_filename' => Storage::disk(self::STORAGE_DISK)->exists($dmgFilename) ? $dmgFilename : null,
            'dmg_hash'     => $data['dmgHash'] ?? null,
            'dmg_size'     => $data['dmgSize'] ?? null,
            'notes'        => $data['notes'] ?? null,
            'active'       => true,
        ]);

        return response()->json([
            'ok'          => true,
            'publishedAt' => $update->created_at,
            'marUrl'      => $update->marUrl(),
            'dmgUrl'      => $update->dmgUrl(),
        ]);
    }

    public function status(): \Illuminate\Http\JsonResponse
    {
        $update = BrowserUpdate::current();

        return response()->json($update ? [
            'version'  => $update->version,
            'buildID'  => $update->build_id,
            'marUrl'   => $update->marUrl(),
            'dmgUrl'   => $update->dmgUrl(),
            'notes'    => $update->notes,
            'activeAt' => $update->created_at,
        ] : ['version' => null]);
    }
}
