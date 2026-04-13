<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Zegel\ZegelException;
use App\Zegel\ZegelReader;
use App\Zegel\ZegelTamperedException;
use Illuminate\Http\Request;
use Illuminate\View\View;

/**
 * Allows a visitor to upload a .zgl file and optionally a master key
 * (as hex) so it can be verified server-side. The content of the uploaded
 * file is discarded immediately after verification to respect privacy.
 */
class VerifyController extends Controller
{
    public function show(): View
    {
        return view('verify.show');
    }

    public function verify(Request $request): View
    {
        $request->validate([
            'zegel_file' => ['required', 'file', 'max:32768'],
            'master_key' => ['nullable', 'string', 'regex:/^[0-9a-fA-F]{64}$/'],
        ]);

        $bytes = @file_get_contents($request->file('zegel_file')->getRealPath());
        if ($bytes === false) {
            abort(500, 'Failed to read upload');
        }

        $reader = new ZegelReader();
        $result = ['valid' => null, 'error' => null, 'inspection' => null];

        try {
            $ins = $reader->inspect($bytes);
            $result['inspection'] = $ins;
        } catch (ZegelException $e) {
            $result['error'] = 'Structural error: ' . $e->getMessage();
            return view('verify.show', compact('result'));
        }

        if ($request->filled('master_key')) {
            $key = hex2bin((string) $request->input('master_key'));
            try {
                $r = $reader->verify($bytes, $key);
                $result['valid']   = $r->valid;
                $result['content'] = strlen($r->content);
            } catch (ZegelTamperedException $e) {
                $result['valid'] = false;
                $result['error'] = 'Tamper detected: ' . $e->getMessage();
            } catch (ZegelException $e) {
                $result['error'] = 'Verification error: ' . $e->getMessage();
            }
        }

        // Be explicit: discard the uploaded bytes.
        unset($bytes);
        return view('verify.show', compact('result'));
    }
}
