<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class BrowserUpdate extends Model
{
    protected $fillable = [
        'version',
        'build_id',
        'mar_filename',
        'mar_hash',
        'mar_size',
        'dmg_filename',
        'dmg_hash',
        'dmg_size',
        'notes',
        'active',
    ];

    protected $casts = [
        'active' => 'boolean',
        'mar_size' => 'integer',
        'dmg_size' => 'integer',
    ];

    public static function current(): ?self
    {
        return static::where('active', true)->latest()->first();
    }

    public function marUrl(): string
    {
        return config('app.update_base_url') . '/download/' . $this->mar_filename;
    }

    public function dmgUrl(): ?string
    {
        return $this->dmg_filename
            ? config('app.update_base_url') . '/download/' . $this->dmg_filename
            : null;
    }
}
