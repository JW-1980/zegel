<?php

declare(strict_types=1);

use App\Http\Controllers\Admin\AuditController as AdminAuditController;
use App\Http\Controllers\Admin\DashboardController as AdminDashboardController;
use App\Http\Controllers\Admin\SettingsController as AdminSettingsController;
use App\Http\Controllers\Admin\UsersController as AdminUsersController;
use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\Auth\PasswordResetController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\BadgeController;
use App\Http\Controllers\DownloadsController;
use App\Http\Controllers\GdprController;
use App\Http\Controllers\HealthController;
use App\Http\Controllers\HomeController;
use App\Http\Controllers\Installer\InstallerController;
use App\Http\Controllers\MetricsController;
use App\Http\Controllers\PublicFileController;
use App\Http\Controllers\PublicMetaController;
use App\Http\Controllers\QrController;
use App\Http\Controllers\SearchController;
use App\Http\Controllers\User\AccountController;
use App\Http\Controllers\User\DashboardController as UserDashboardController;
use App\Http\Controllers\User\ZegelFileController;
use App\Http\Controllers\VerifyController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Public pages
|--------------------------------------------------------------------------
*/

Route::get('/', [HomeController::class, 'index'])->name('home');
Route::get('/downloads', [DownloadsController::class, 'index'])->name('downloads.index');
Route::get('/search',    [SearchController::class, 'index'])->middleware('throttle:60,1')->name('search');
Route::get('/verify',    [VerifyController::class, 'show'])->name('verify.show');
Route::post('/verify',   [VerifyController::class, 'verify'])->middleware('throttle:15,1')->name('verify.run');

Route::get('/healthz',   [HealthController::class, 'readiness'])->name('healthz');
Route::get('/livez',     [HealthController::class, 'liveness'])->name('livez');
Route::get('/metrics',   [MetricsController::class, 'index'])->name('metrics');

Route::get('/badge/{file}.svg', [BadgeController::class, 'forFile'])->name('badge.file');
Route::get('/qr.svg', [QrController::class, 'show'])->middleware('throttle:120,1')->name('qr');

Route::get('/robots.txt',               [PublicMetaController::class, 'robots']);
Route::get('/.well-known/security.txt', [PublicMetaController::class, 'security']);
Route::get('/humans.txt',               [PublicMetaController::class, 'humans']);
Route::get('/sitemap.xml',              [PublicMetaController::class, 'sitemap']);
Route::get('/manifest.webmanifest',     [PublicMetaController::class, 'manifest']);
Route::get('/api/openapi.json',         [PublicMetaController::class, 'openapi']);
Route::get('/sample.zgl',               [PublicMetaController::class, 'sample']);

Route::prefix('legal')->name('legal.')->group(function (): void {
    Route::get('/privacy', [GdprController::class, 'privacy'])->name('privacy');
    Route::get('/terms',   [GdprController::class, 'terms'])->name('terms');
    Route::get('/cookies', [GdprController::class, 'cookies'])->name('cookies');
    Route::get('/imprint', [GdprController::class, 'imprint'])->name('imprint');
    Route::get('/dpa',     [GdprController::class, 'dpa'])->name('dpa');
});

Route::post('/consent', [GdprController::class, 'recordConsent'])
    ->middleware('throttle:60,1')
    ->name('gdpr.consent');

/*
|--------------------------------------------------------------------------
| Installation wizard
|--------------------------------------------------------------------------
*/

Route::prefix('install')->name('installer.')->middleware('throttle:30,1')->group(function (): void {
    Route::get('/',             [InstallerController::class, 'welcome'])->name('welcome');
    Route::get('/requirements', [InstallerController::class, 'requirements'])->name('requirements');
    Route::get('/database',     [InstallerController::class, 'databaseForm'])->name('database');
    Route::post('/database',    [InstallerController::class, 'runMigrations'])->name('database.store');
    Route::get('/admin',        [InstallerController::class, 'adminForm'])->name('admin');
    Route::post('/admin',       [InstallerController::class, 'storeAdmin'])->name('admin.store');
});

/*
|--------------------------------------------------------------------------
| Auth (guest)
|--------------------------------------------------------------------------
*/

Route::middleware('guest')->group(function (): void {
    Route::get('/login',     [LoginController::class, 'show'])->name('login');
    Route::post('/login',    [LoginController::class, 'store'])->middleware('throttle:10,1');
    Route::get('/register',  [RegisterController::class, 'show'])->name('register');
    Route::post('/register', [RegisterController::class, 'store'])->middleware('throttle:5,1');

    Route::get('/forgot-password',     [PasswordResetController::class, 'requestForm'])->name('password.request');
    Route::post('/forgot-password',    [PasswordResetController::class, 'sendResetLink'])->middleware('throttle:5,1')->name('password.email');
    Route::get('/reset-password/{token}', [PasswordResetController::class, 'resetForm'])->name('password.reset');
    Route::post('/reset-password',     [PasswordResetController::class, 'reset'])->middleware('throttle:5,1')->name('password.update');
});

Route::post('/logout', [LoginController::class, 'destroy'])
    ->middleware('auth')
    ->name('logout');

/*
|--------------------------------------------------------------------------
| Authenticated user routes
|--------------------------------------------------------------------------
*/

Route::middleware('auth')->group(function (): void {
    Route::get('/dashboard', [UserDashboardController::class, 'index'])->name('user.dashboard');

    Route::prefix('files')->name('user.files.')->group(function (): void {
        Route::get('/',          [ZegelFileController::class, 'index'])->name('index');
        Route::get('/new',       [ZegelFileController::class, 'create'])->name('create');
        Route::post('/',         [ZegelFileController::class, 'store'])->middleware('throttle:30,1')->name('store');
        Route::delete('/{file}', [ZegelFileController::class, 'destroy'])->name('destroy');
        Route::patch('/{file}/visibility', [ZegelFileController::class, 'updateVisibility'])->name('visibility');
    });

    Route::prefix('gdpr')->name('gdpr.')->group(function (): void {
        Route::get('/export', [GdprController::class, 'export'])->name('export');
        Route::post('/erase', [GdprController::class, 'erase'])->middleware('throttle:3,60')->name('erase');
    });

    Route::prefix('account')->name('account.')->group(function (): void {
        Route::get('/',           [AccountController::class, 'edit'])->name('edit');
        Route::put('/profile',    [AccountController::class, 'updateProfile'])->name('profile.update');
        Route::put('/password',   [AccountController::class, 'updatePassword'])->name('password.update');
        Route::post('/logout-everywhere', [AccountController::class, 'logoutEverywhere'])->name('logout_everywhere');
    });
});

/*
|--------------------------------------------------------------------------
| Admin area
|--------------------------------------------------------------------------
*/

Route::middleware(['auth', 'admin'])->prefix('admin')->name('admin.')->group(function (): void {
    Route::get('/',                   [AdminDashboardController::class, 'index'])->name('dashboard');
    Route::get('/users',              [AdminUsersController::class, 'index'])->name('users.index');
    Route::patch('/users/{user}/active', [AdminUsersController::class, 'toggleActive'])->name('users.active');
    Route::patch('/users/{user}/admin',  [AdminUsersController::class, 'toggleAdmin'])->name('users.admin');
    Route::get('/settings',  [AdminSettingsController::class, 'edit'])->name('settings.edit');
    Route::put('/settings',  [AdminSettingsController::class, 'update'])->name('settings.update');
    Route::get('/audit',     [AdminAuditController::class, 'index'])->name('audit.index');
});

/*
|--------------------------------------------------------------------------
| Public (or unlisted) Zegel file pages — UUID route binding
|--------------------------------------------------------------------------
*/

Route::prefix('f')->group(function (): void {
    Route::get('/{file}',          [PublicFileController::class, 'show'])->name('files.show');
    Route::get('/{file}/raw',      [PublicFileController::class, 'raw'])->name('files.raw');
    Route::get('/{file}/download', [PublicFileController::class, 'download'])
        ->middleware('throttle:120,1')
        ->name('files.download');
});
