<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Schema;

abstract class TestCase extends BaseTestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        try {
            if (Schema::hasTable('site_settings')) {
                \App\Models\SiteSetting::setValue('installed_at', now()->toIso8601String(), 'string', 'Timestamp of wizard completion');
            }
        } catch (\Throwable $e) {}
    }
}
