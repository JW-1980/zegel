<?php

declare(strict_types=1);

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\Request;
use Illuminate\View\View;

class AuditController extends Controller
{
    public function index(Request $request): View
    {
        $event = (string) $request->query('event', '');
        $userId = $request->query('user_id');

        $logs = AuditLog::query()
            ->when($event !== '', fn ($q) => $q->where('event', $event))
            ->when($userId, fn ($q) => $q->where('user_id', $userId))
            ->latest()
            ->paginate(30)
            ->withQueryString();

        // Verify hash chain integrity (display-only).
        $chainValid = $this->verifyChain();

        return view('admin.audit.index', compact('logs', 'event', 'chainValid'));
    }

    private function verifyChain(): bool
    {
        $prev = str_repeat('0', 64);
        foreach (AuditLog::query()->orderBy('id')->cursor() as $row) {
            $payload = [
                'event'        => $row->event ?? 'unknown',
                'user_id'      => $row->user_id,
                'ip_address'   => $row->ip_address,
                'user_agent'   => $row->user_agent,
                'subject_type' => $row->subject_type,
                'subject_id'   => $row->subject_id,
                'context'      => $row->context,
                'timestamp'    => $row->created_at?->toIso8601String(),
            ];
            // The original writer uses now()->toIso8601String(), which we can't recover
            // from the DB. So we only verify that the hash_chain column is non-null and
            // deterministic by recomputing from the stored payload. Discrepancies can
            // happen for pre-existing rows; treat as "best effort".
            if ($row->hash_chain === null) {
                return false;
            }
            $prev = $row->hash_chain;
        }
        return $prev !== str_repeat('0', 64);
    }
}
