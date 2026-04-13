<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('password_history', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('hash');
            $table->timestamp('created_at');
            $table->index(['user_id', 'created_at']);
        });

        Schema::create('tags', function (Blueprint $table) {
            $table->id();
            $table->string('name', 64)->unique();
            $table->timestamps();
        });

        Schema::create('zegel_file_tag', function (Blueprint $table) {
            $table->id();
            $table->foreignId('zegel_file_id')->constrained()->cascadeOnDelete();
            $table->foreignId('tag_id')->constrained()->cascadeOnDelete();
            $table->unique(['zegel_file_id', 'tag_id']);
        });

        Schema::create('webhooks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('url');
            $table->string('secret', 64);
            $table->boolean('active')->default(true);
            $table->timestamps();
        });

        Schema::table('zegel_files', function (Blueprint $table) {
            $table->boolean('featured')->default(false)->index();
            $table->timestamp('last_verified_at')->nullable();
        });

    }

    public function down(): void
    {
        Schema::dropIfExists('password_history');
        Schema::dropIfExists('zegel_file_tag');
        Schema::dropIfExists('tags');
        Schema::dropIfExists('webhooks');
        Schema::table('zegel_files', function (Blueprint $table) {
            $table->dropColumn(['featured', 'last_verified_at']);
        });
    }
};
