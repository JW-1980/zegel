<?php

declare(strict_types=1);

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class HomePageTest extends TestCase
{
    use RefreshDatabase;

    public function test_home_renders_for_guest(): void
    {
        $response = $this->get('/');
        $response->assertStatus(200);
        $response->assertSee('Seal any file', false);
    }

    public function test_robots_txt_is_served(): void
    {
        $this->get('/robots.txt')->assertStatus(200)->assertSee('Sitemap');
    }

    public function test_security_txt_is_served(): void
    {
        $this->get('/.well-known/security.txt')->assertStatus(200)->assertSee('Contact');
    }

    public function test_healthz_returns_status(): void
    {
        $response = $this->get('/healthz');
        $response->assertStatus(200);
        $response->assertJsonStructure(['status', 'checks']);
    }

    public function test_metrics_exposes_counters(): void
    {
        $response = $this->get('/metrics');
        $response->assertStatus(200);
        $this->assertStringContainsString('text/plain', (string) $response->headers->get('Content-Type'));
        $response->assertSee('zegel_users_total');
    }
}
