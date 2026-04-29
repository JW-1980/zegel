import re

with open("admin_panel.html", "r") as f:
    content = f.read()

# find dashboard content
match = re.search(r'(<!-- Dashboard Canvas -->\s*<div class="p-8 max-w-\[1440px\] mx-auto space-y-8">.*</div>)\s*</main>', content, re.DOTALL)
if match:
    dashboard_content = match.group(1)

    # replace hardcoded values

    # "Export Report" to maybe nothing or keep it

    # Cards: Total Users, Revenue, Active Sessions, System Health
    # Total Users:
    dashboard_content = re.sub(
        r'<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Total Users</p>\s*<h3 class="font-h2 text-h2">12,584</h3>',
        '<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Total Users</p>\n<h3 class="font-h2 text-h2">{{ number_format((int) ($totals["users"] ?? 0)) }}</h3>',
        dashboard_content
    )

    # Total Revenue -> Zegel Files
    dashboard_content = re.sub(
        r'<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Total Revenue</p>\s*<h3 class="font-h2 text-h2">\$45,200.00</h3>',
        '<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Zegel Files</p>\n<h3 class="font-h2 text-h2">{{ number_format((int) ($totals["zegel_files"] ?? 0)) }}</h3>',
        dashboard_content
    )

    # Active Sessions -> Downloads
    dashboard_content = re.sub(
        r'<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Active Sessions</p>\s*<h3 class="font-h2 text-h2">1,200</h3>',
        '<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Downloads</p>\n<h3 class="font-h2 text-h2">{{ number_format((int) ($totals["downloads"] ?? 0)) }}</h3>',
        dashboard_content
    )

    # System Health -> Public Files
    dashboard_content = re.sub(
        r'<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">System Health</p>\s*<h3 class="font-h2 text-h2">99.9%</h3>',
        '<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Public Files</p>\n<h3 class="font-h2 text-h2">{{ number_format((int) ($totals["public_files"] ?? 0)) }}</h3>',
        dashboard_content
    )

    # Recent Activity Table replacement
    # We will replace the static table rows with foreach loop over $recentAudits

    table_body_pattern = r'<tbody class="divide-y divide-slate-100 dark:divide-slate-800">.*?</tbody>'

    table_body_replacement = """<tbody class="divide-y divide-slate-100 dark:divide-slate-800">
@foreach($recentAudits as $a)
<tr class="hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors group">
<td class="px-8 py-4">
<div class="flex items-center gap-3">
<div class="h-8 w-8 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-blue-600">
<span class="material-symbols-outlined text-sm" data-icon="event">event</span>
</div>
<span class="text-sm font-medium">{{ $a->event }}</span>
</div>
</td>
<td class="px-8 py-4 text-sm text-on-surface-variant">{{ $a->ip_address }}</td>
<td class="px-8 py-4">
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400">
    Success
</span>
</td>
<td class="px-8 py-4 text-sm text-on-surface-variant">{{ $a->created_at->diffForHumans() }}</td>
<td class="px-8 py-4 text-right">
<span class="text-xs font-mono text-outline">{{ $a->id }}</span>
</td>
</tr>
@endforeach
</tbody>"""

    dashboard_content = re.sub(table_body_pattern, table_body_replacement, dashboard_content, flags=re.DOTALL)

    # Now wrap it in blade directives

    final_blade = f"""@extends('layouts.app')

@section('content')
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200" rel="stylesheet">
{dashboard_content}
@endsection
"""

    with open("website/resources/views/admin/dashboard.blade.php", "w") as out:
        out.write(final_blade)

    print("Dashboard blade file generated")
