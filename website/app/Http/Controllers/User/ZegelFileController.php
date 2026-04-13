<?php

declare(strict_types=1);

namespace App\Http\Controllers\User;

use App\Http\Controllers\Controller;
use App\Models\ZegelFile;
use App\Services\ZegelFileService;
use App\Zegel\ZegelFormatException;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;

class ZegelFileController extends Controller
{
    public function __construct(private readonly ZegelFileService $service)
    {
    }

    public function index(): View
    {
        $files = ZegelFile::query()
            ->where('user_id', Auth::id())
            ->latest()
            ->paginate(20);

        return view('user.files.index', compact('files'));
    }

    public function create(): View
    {
        return view('user.files.create');
    }

    public function store(Request $request): RedirectResponse
    {
        $maxMb = (int) \App\Models\SiteSetting::getValue('max_upload_mb', 25);
        $data = $request->validate([
            'title'       => ['required', 'string', 'max:200'],
            'description' => ['nullable', 'string', 'max:2000'],
            'visibility'  => ['required', 'in:public,private,unlisted'],
            'zegel_file'  => [
                'required',
                'file',
                'max:' . ($maxMb * 1024),
                'mimetypes:application/octet-stream,application/x-zgl,text/plain',
            ],
        ]);

        try {
            $file = $this->service->ingest(
                $request->file('zegel_file'),
                $request->user(),
                (string) $data['title'],
                $data['description'] ?? null,
                (string) $data['visibility'],
            );
        } catch (ZegelFormatException $e) {
            return back()->withErrors([
                'zegel_file' => __('The uploaded file is not a valid Zegel (.zgl) container.')
                    . ' ' . $e->getMessage(),
            ])->withInput();
        }

        return redirect()
            ->route('files.show', $file->public_id)
            ->with('status', __('Your Zegel file was uploaded.'));
    }

    public function destroy(ZegelFile $file): RedirectResponse
    {
        $this->authorizeOwnership($file);
        $file->delete();
        return redirect()->route('user.files.index')->with('status', __('File deleted.'));
    }

    public function updateVisibility(Request $request, ZegelFile $file): RedirectResponse
    {
        $this->authorizeOwnership($file);
        $data = $request->validate([
            'visibility' => ['required', 'in:public,private,unlisted'],
        ]);
        $file->visibility = $data['visibility'];
        if ($data['visibility'] === ZegelFile::VISIBILITY_PUBLIC && $file->published_at === null) {
            $file->published_at = now();
        }
        $file->save();
        return back()->with('status', __('Visibility updated.'));
    }

    private function authorizeOwnership(ZegelFile $file): void
    {
        $user = Auth::user();
        abort_unless(
            $user && ($file->user_id === $user->getKey() || $user->isAdmin()),
            403,
        );
    }
}
