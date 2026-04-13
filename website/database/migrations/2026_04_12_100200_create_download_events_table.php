<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('download_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('zegel_file_id')->constrained()->cascadeOnDelete();

            // Hash of (ip + user_agent + salt) — never store raw PII.
            $table->string('fingerprint', 64)->index();

            // Day bucket (YYYY-MM-DD) used with the unique index below to dedupe.
            $table->date('day_bucket')->index();

            // Coarse country code (if resolvable) — optional.
            $table->string('country', 2)->nullable();

            // Classification: verified|soft|rejected. Rejected events still get
            // logged for abuse monitoring but do not increment counters.
            $table->string('classification', 16)->default('verified');

            // Anti-fraud scores and signal metadata (JSON).
            $table->unsignedTinyInteger('trust_score')->default(100);
            $table->json('signals')->nullable();

            $table->timestamps();

            // One counted download per (file, fingerprint, day).
            $table->unique(['zegel_file_id', 'fingerprint', 'day_bucket'], 'download_events_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('download_events');
    }
};
