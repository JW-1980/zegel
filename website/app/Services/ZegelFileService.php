<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\AuditLog;
use App\Models\User;
use App\Models\ZegelFile;
use App\Zegel\ZegelInspection;
use App\Zegel\ZegelReader;
use App\Zegel\ZegelFormatException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

/**
 * Accepts an uploaded .zgl file, inspects the header, stores it under a
 * private disk, and records a database entry with certificate metadata.
 */
class ZegelFileService
{
    public function __construct(
        private readonly ZegelReader $reader,
        private readonly CertificateService $certs,
    ) {}

    /**
     * @throws ZegelFormatException
     */
    public function ingest(
        UploadedFile $file,
        User $owner,
        string $title,
        ?string $description,
        string $visibility,
    ): ZegelFile {
        $this->guardFilename($file->getClientOriginalName());

        $bytes = file_get_contents($file->getRealPath());
        if ($bytes === false) {
            throw new ZegelFormatException('Could not read uploaded file');
        }

        // Fast magic-bytes check — reject non-Zegel binaries BEFORE full parse.
        if (strlen($bytes) < 8 || substr($bytes, 0, 5) !== "ZEGEL") {
            throw new ZegelFormatException('File does not start with the ZEGEL magic bytes');
        }

        // Structural inspection — does NOT require the master key.
        $inspection = $this->reader->inspect($bytes);

        $sha256 = hash('sha256', $bytes);
        $disk   = Storage::disk('private');
        $path   = 'zegel/' . substr($sha256, 0, 2) . '/' . $sha256 . '.zgl';
        $disk->put($path, $bytes);

        $zegelFile = ZegelFile::create([
            'user_id'           => $owner->id,
            'title'             => $title,
            'description'       => $description,
            'original_filename' => $file->getClientOriginalName(),
            'stored_path'       => $path,
            'content_type'      => $inspection->contentType,
            'merkle_root_hex'   => $inspection->merkleRootHex,
            'flags'             => $inspection->flags,
            'block_count'       => $inspection->blockCount,
            'size_bytes'        => strlen($bytes),
            'sha256_hex'        => $sha256,
            'visibility'        => $visibility,
            'published_at'      => $visibility === ZegelFile::VISIBILITY_PUBLIC ? now() : null,
            'expires_at'        => $inspection->expirationTimestamp
                ? \Carbon\Carbon::createFromTimestamp($inspection->expirationTimestamp)
                : null,
            'subject_cn'        => $this->subjectFromInspection($inspection, $file, $owner),
            'issuer_cn'         => \App\Models\SiteSetting::getValue('certificate_issuer_cn', 'Zegel Certificate Authority'),
        ]);

        $cert = $this->certs->buildCertificate($zegelFile, $inspection, $owner);
        $zegelFile->forceFill(['certificate_data' => $cert])->save();

        AuditLog::writeEntry([
            'user_id'      => $owner->id,
            'event'        => 'zegel.upload',
            'ip_address'   => request()->ip(),
            'user_agent'   => (string) request()->userAgent(),
            'subject_type' => ZegelFile::class,
            'subject_id'   => $zegelFile->id,
            'context'      => [
                'filename'  => $zegelFile->original_filename,
                'visibility'=> $visibility,
                'size'      => $zegelFile->size_bytes,
                'merkle'    => $zegelFile->merkle_root_hex,
            ],
        ]);

        return $zegelFile;
    }

    public function readBytes(ZegelFile $file): string
    {
        $bytes = Storage::disk('private')->get($file->stored_path);
        if ($bytes === null) {
            throw new \RuntimeException('Stored file missing on disk');
        }
        return $bytes;
    }

    private function guardFilename(string $name): void
    {
        $deny = ['exe', 'bat', 'cmd', 'msi', 'dmg', 'scr', 'com', 'vbs', 'ps1'];
        $ext  = strtolower(pathinfo($name, PATHINFO_EXTENSION));
        if (in_array($ext, $deny, true)) {
            throw new ZegelFormatException('Filename uses a deny-listed extension: .' . $ext);
        }
        if (strlen($name) > 255) {
            throw new ZegelFormatException('Filename is too long');
        }
    }

    private function subjectFromInspection(ZegelInspection $ins, UploadedFile $file, User $owner): string
    {
        if ($ins->publicMetadata && isset($ins->publicMetadata['subject_cn'])) {
            return (string) $ins->publicMetadata['subject_cn'];
        }
        $filename = $ins->filename ?: $file->getClientOriginalName();
        return 'CN=' . $filename . ', O=' . $owner->name;
    }
}
