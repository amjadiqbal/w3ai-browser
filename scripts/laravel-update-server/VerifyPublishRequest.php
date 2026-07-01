<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class VerifyPublishRequest
{
    public function handle(Request $request, Closure $next): Response
    {
        $token = $request->bearerToken();
        if (!$token || !hash_equals(config('app.publish_secret'), $token)) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        // For JSON requests, verify HMAC signature of the request body.
        // For multipart file uploads the body is binary — skip HMAC, rely on Bearer token.
        if ($request->isJson()) {
            $signature = $request->header('X-Signature');
            $expected  = 'sha256=' . hash_hmac('sha256', $request->getContent(), config('app.publish_hmac_secret'));

            if (!$signature || !hash_equals($expected, $signature)) {
                return response()->json(['error' => 'Invalid signature'], 401);
            }
        }

        return $next($request);
    }
}
