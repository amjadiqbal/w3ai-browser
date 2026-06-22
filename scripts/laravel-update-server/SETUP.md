# TMRW Update Server — Laravel Setup

Self-hosted update distribution server. Replaces Vercel Blob + Vercel API.

## Files in this directory

| File | Where it goes in Laravel |
|------|--------------------------|
| `migration.php` | `database/migrations/xxxx_create_browser_updates_table.php` |
| `BrowserUpdate.php` | `app/Models/BrowserUpdate.php` |
| `UpdateController.php` | `app/Http/Controllers/UpdateController.php` |
| `VerifyPublishRequest.php` | `app/Http/Middleware/VerifyPublishRequest.php` |
| `routes.php` | merge into `routes/web.php` |
| `filesystem_config.php` | follow inline comments to patch `config/filesystems.php` + `config/app.php` |

## Cloudways server setup

### 1. PHP settings (Application > PHP-FPM Settings)

```
upload_max_filesize = 300M
post_max_size       = 320M
max_execution_time  = 300
memory_limit        = 512M
```

### 2. Nginx custom rules (Application > Nginx Settings)

```nginx
client_max_body_size 320M;
```

### 3. Storage directory

```bash
mkdir -p storage/app/updates
chmod 775 storage/app/updates
chown www-data:www-data storage/app/updates
```

### 4. Laravel .env additions

```env
UPDATE_BASE_URL=https://tmrw-update.w3ai.io
PUBLISH_SECRET=ff6d14a8fdff62cf80ce899206aea46583ab58c4878d96f0d4e5a83360c9523d
PUBLISH_HMAC_SECRET=<generate: openssl rand -hex 32>
```

### 5. Register middleware

In `bootstrap/app.php` (Laravel 11+):

```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->alias([
        'verify.publish' => \App\Http\Middleware\VerifyPublishRequest::class,
    ]);
})
```

Or in `app/Http/Kernel.php` (Laravel 10):

```php
protected $routeMiddleware = [
    // ...
    'verify.publish' => \App\Http\Middleware\VerifyPublishRequest::class,
];
```

### 6. Run migration

```bash
php artisan migrate
```

### 7. Test the endpoints

```bash
# Should return <updates/> (empty, no build published yet)
curl https://tmrw-update.w3ai.io/updates/update.xml

# Should return {"version":null}
curl https://tmrw-update.w3ai.io/api/status
```

## Browser repo .env additions

```env
PUBLISH_HMAC_SECRET=<same value as Laravel server>
UPDATE_SERVER_URL=https://tmrw-update.w3ai.io
```

Generate the HMAC secret once and put the same value in BOTH places:

```bash
openssl rand -hex 32
```

## Security model

Every private request (`POST /api/upload/*` and `POST /api/publish`) requires:

1. **Bearer token** — `Authorization: Bearer $PUBLISH_SECRET`
2. **HMAC signature** — `X-Signature: sha256=HMAC-SHA256($body, $PUBLISH_HMAC_SECRET)`
   (only enforced on JSON requests; multipart file uploads rely on the Bearer token)

Public endpoints (update.xml, download, status) have no auth.
Download endpoints are rate-limited to 120 req/min per IP.
