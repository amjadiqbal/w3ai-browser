<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('browser_updates', function (Blueprint $table) {
            $table->id();
            $table->string('version');
            $table->string('build_id');
            $table->string('mar_filename');
            $table->string('mar_hash');
            $table->unsignedBigInteger('mar_size');
            $table->string('dmg_filename')->nullable();
            $table->string('dmg_hash')->nullable();
            $table->unsignedBigInteger('dmg_size')->nullable();
            $table->text('notes')->nullable();
            $table->boolean('active')->default(true);
            $table->timestamps();

            $table->index(['active', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('browser_updates');
    }
};
