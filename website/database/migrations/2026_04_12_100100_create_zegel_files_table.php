<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('zegel_files', function (Blueprint $table) {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('title');
            $table->string('slug')->nullable()->index();
            $table->text('description')->nullable();
            $table->string('original_filename');
            $table->string('stored_path');           // relative to private disk
            $table->string('content_type', 128)->nullable();
            $table->string('merkle_root_hex', 64)->index();
            $table->unsignedInteger('flags')->default(0);
            $table->unsignedInteger('block_count')->default(0);
            $table->unsignedBigInteger('size_bytes')->default(0);
            $table->string('sha256_hex', 64)->nullable()->index(); // hash of sealed file
            $table->string('visibility', 16)->default('private');   // public|private|unlisted
            $table->timestamp('published_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->string('certificate_serial', 32)->unique();
            $table->string('issuer_cn')->nullable();
            $table->string('subject_cn')->nullable();
            $table->json('certificate_data')->nullable();
            $table->unsignedBigInteger('view_count')->default(0);
            $table->unsignedBigInteger('download_count')->default(0);
            $table->unsignedBigInteger('unique_download_count')->default(0);
            $table->boolean('locked')->default(false);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['visibility', 'published_at']);
            $table->index(['user_id', 'visibility']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('zegel_files');
    }
};
