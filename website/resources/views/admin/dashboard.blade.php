@extends('layouts.app')

@section('content')
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200" rel="stylesheet">
<!-- Dashboard Canvas -->
<div class="p-8 max-w-[1440px] mx-auto space-y-8">
<!-- Header Section -->
<div class="flex items-end justify-between">
<div>
<h2 class="font-h1 text-h1 text-on-surface">Dashboard Overview</h2>
<p class="font-body-md text-body-md text-on-surface-variant">Welcome back. Here's what's happening with your system today.</p>
</div>
<button class="bg-primary text-on-primary px-6 py-2.5 rounded-lg font-medium text-sm flex items-center gap-2 shadow-sm hover:opacity-90 transition-all">
<span class="material-symbols-outlined text-sm" data-icon="download">download</span>
                    Export Report
                </button>
</div>
<!-- Stats Grid -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-gutter">
<!-- Card 1 -->
<div class="bg-white dark:bg-slate-900 p-6 rounded-xl border border-slate-200 dark:border-slate-800 shadow-sm">
<div class="flex justify-between items-start mb-4">
<div class="p-2 bg-primary-fixed text-primary rounded-lg">
<span class="material-symbols-outlined" data-icon="group">group</span>
</div>
<span class="flex items-center text-xs font-semibold text-green-600 bg-green-50 px-2 py-1 rounded-full">
                            +12% <span class="material-symbols-outlined text-[14px] ml-0.5" data-icon="trending_up">trending_up</span>
</span>
</div>
<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Total Users</p>
<h3 class="font-h2 text-h2">{{ number_format((int) ($totals["users"] ?? 0)) }}</h3>
</div>
<!-- Card 2 -->
<div class="bg-white dark:bg-slate-900 p-6 rounded-xl border border-slate-200 dark:border-slate-800 shadow-sm">
<div class="flex justify-between items-start mb-4">
<div class="p-2 bg-tertiary-fixed text-tertiary rounded-lg">
<span class="material-symbols-outlined" data-icon="payments">payments</span>
</div>
<span class="flex items-center text-xs font-semibold text-green-600 bg-green-50 px-2 py-1 rounded-full">
                            +5% <span class="material-symbols-outlined text-[14px] ml-0.5" data-icon="trending_up">trending_up</span>
</span>
</div>
<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Zegel Files</p>
<h3 class="font-h2 text-h2">{{ number_format((int) ($totals["zegel_files"] ?? 0)) }}</h3>
</div>
<!-- Card 3 -->
<div class="bg-white dark:bg-slate-900 p-6 rounded-xl border border-slate-200 dark:border-slate-800 shadow-sm">
<div class="flex justify-between items-start mb-4">
<div class="p-2 bg-secondary-fixed text-secondary rounded-lg">
<span class="material-symbols-outlined" data-icon="timer">timer</span>
</div>
<span class="flex items-center text-xs font-semibold text-red-600 bg-red-50 px-2 py-1 rounded-full">
                            -2% <span class="material-symbols-outlined text-[14px] ml-0.5" data-icon="trending_down">trending_down</span>
</span>
</div>
<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Downloads</p>
<h3 class="font-h2 text-h2">{{ number_format((int) ($totals["downloads"] ?? 0)) }}</h3>
</div>
<!-- Card 4 -->
<div class="bg-white dark:bg-slate-900 p-6 rounded-xl border border-slate-200 dark:border-slate-800 shadow-sm">
<div class="flex justify-between items-start mb-4">
<div class="p-2 bg-primary-container text-on-primary-container rounded-lg">
<span class="material-symbols-outlined" data-icon="shield_check">shield</span>
</div>
<span class="flex items-center text-xs font-semibold text-blue-600 bg-blue-50 px-2 py-1 rounded-full">
                            Stable
                        </span>
</div>
<p class="font-label-caps text-label-caps text-on-surface-variant uppercase mb-1">Public Files</p>
<h3 class="font-h2 text-h2">{{ number_format((int) ($totals["public_files"] ?? 0)) }}</h3>
</div>
</div>
<!-- Bento Chart Section -->
<div class="bg-white dark:bg-slate-900 p-8 rounded-xl border border-slate-200 dark:border-slate-800 shadow-sm">
<div class="flex items-center justify-between mb-8">
<div>
<h3 class="font-h3 text-h3">User Engagement</h3>
<p class="text-sm text-on-surface-variant">Consolidated metrics for the last 30 days</p>
</div>
<div class="flex gap-2 p-1 bg-surface-container-low rounded-lg">
<button class="px-4 py-1.5 text-xs font-semibold bg-white dark:bg-slate-800 shadow-sm rounded-md">Daily</button>
<button class="px-4 py-1.5 text-xs font-semibold text-outline hover:text-on-surface">Weekly</button>
<button class="px-4 py-1.5 text-xs font-semibold text-outline hover:text-on-surface">Monthly</button>
</div>
</div>
<!-- SVG Chart Placeholder -->
<div class="w-full h-[320px] relative">
<svg class="w-full h-full overflow-visible" viewbox="0 0 1000 300">
<!-- Grid Lines -->
<line class="text-slate-100 dark:text-slate-800" stroke="currentColor" stroke-width="1" x1="0" x2="1000" y1="50" y2="50"></line>
<line class="text-slate-100 dark:text-slate-800" stroke="currentColor" stroke-width="1" x1="0" x2="1000" y1="150" y2="150"></line>
<line class="text-slate-100 dark:text-slate-800" stroke="currentColor" stroke-width="1" x1="0" x2="1000" y1="250" y2="250"></line>
<!-- Area Gradient -->
<defs>
<lineargradient id="chartGradient" x1="0" x2="0" y1="0" y2="1">
<stop offset="0%" stop-color="#3B82F6" stop-opacity="0.2"></stop>
<stop offset="100%" stop-color="#3B82F6" stop-opacity="0"></stop>
</lineargradient>
</defs>
<!-- The Curve -->
<path d="M0,250 L0,200 C100,180 200,240 300,150 C400,60 500,120 600,100 C700,80 800,40 900,120 L1000,80 L1000,300 L0,300 Z" fill="url(#chartGradient)"></path>
<path d="M0,200 C100,180 200,240 300,150 C400,60 500,120 600,100 C700,80 800,40 900,120 L1000,80" fill="none" stroke="#3B82F6" stroke-linecap="round" stroke-width="3"></path>
<!-- Points -->
<circle cx="300" cy="150" fill="#3B82F6" r="5"></circle>
<circle cx="600" cy="100" fill="#3B82F6" r="5"></circle>
<circle cx="900" cy="120" fill="#3B82F6" r="5"></circle>
</svg>
<!-- Chart Tooltip Placeholder -->
<div class="absolute top-[80px] left-[610px] bg-slate-900 text-white px-3 py-2 rounded-lg text-xs shadow-xl animate-pulse">
<p class="font-bold">Oct 14</p>
<p class="opacity-80">842 Sessions</p>
</div>
</div>
</div>
<!-- Recent Activity Table -->
<div class="bg-white dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-800 shadow-sm overflow-hidden">
<div class="px-8 py-6 border-b border-slate-200 dark:border-slate-800 flex items-center justify-between">
<h3 class="font-h3 text-h3">Recent System Activity</h3>
<button class="text-primary font-medium text-sm hover:underline">View All Activity</button>
</div>
<div class="overflow-x-auto">
<table class="w-full text-left border-collapse">
<thead class="bg-slate-50 dark:bg-slate-800/50">
<tr>
<th class="px-8 py-4 font-label-caps text-label-caps text-outline uppercase">Entity</th>
<th class="px-8 py-4 font-label-caps text-label-caps text-outline uppercase">Action</th>
<th class="px-8 py-4 font-label-caps text-label-caps text-outline uppercase">Status</th>
<th class="px-8 py-4 font-label-caps text-label-caps text-outline uppercase">Timestamp</th>
<th class="px-8 py-4 font-label-caps text-label-caps text-outline uppercase text-right">Reference</th>
</tr>
</thead>
<tbody class="divide-y divide-slate-100 dark:divide-slate-800">
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
</tbody>
</table>
</div>
</div>
</div>
@endsection
