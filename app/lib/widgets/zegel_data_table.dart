import 'package:flutter/services.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A generic, reusable data table component with sorting, filtering,
/// and JSON export capabilities.
///
/// Used consistently across the app for displaying tabular data like
/// block listings, audit trails, key inventories, and batch results.
///
/// Features:
/// - Column sorting (ascending/descending)
/// - Text search filtering
/// - "Copy as JSON" export (item 18 from SUGGESTED_IMPROVEMENTS)
/// - Consistent styling
/// - Empty state handling
///
/// Implements items 92 and 18 from SUGGESTED_IMPROVEMENTS.md:
/// "Create a generic Data Table component" and "Add a Copy as JSON button."
class ZegelDataTable extends StatefulWidget {
  /// Column definitions.
  final List<ZegelColumn> columns;

  /// Row data. Each row is a map of column key -> cell value.
  final List<Map<String, dynamic>> rows;

  /// Title displayed above the table.
  final String? title;

  /// Whether to show the search/filter bar.
  final bool showSearch;

  /// Whether to show the "Copy as JSON" button.
  final bool showJsonExport;

  /// Callback when a row is tapped.
  final void Function(Map<String, dynamic> row)? onRowTap;

  /// Empty state message.
  final String emptyMessage;

  const ZegelDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.title,
    this.showSearch = true,
    this.showJsonExport = true,
    this.onRowTap,
    this.emptyMessage = 'No data to display',
  });

  @override
  State<ZegelDataTable> createState() => _ZegelDataTableState();
}

class _ZegelDataTableState extends State<ZegelDataTable> {
  String _searchQuery = '';
  String? _sortColumn;
  bool _sortAscending = true;

  List<Map<String, dynamic>> get _filteredRows {
    var rows = List<Map<String, dynamic>>.from(widget.rows);

    // Apply search filter.
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      rows = rows.where((row) {
        return row.values.any(
          (v) => v.toString().toLowerCase().contains(query),
        );
      }).toList();
    }

    // Apply sorting.
    if (_sortColumn != null) {
      rows.sort((a, b) {
        final aVal = a[_sortColumn] ?? '';
        final bVal = b[_sortColumn] ?? '';
        int cmp;
        if (aVal is num && bVal is num) {
          cmp = aVal.compareTo(bVal);
        } else {
          cmp = aVal.toString().compareTo(bVal.toString());
        }
        return _sortAscending ? cmp : -cmp;
      });
    }

    return rows;
  }

  void _onSort(String columnKey) {
    setState(() {
      if (_sortColumn == columnKey) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = columnKey;
        _sortAscending = true;
      }
    });
  }

  void _copyAsJson() {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_filteredRows);
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied ${_filteredRows.length} rows as JSON to clipboard',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row with title, search, and actions.
        if (widget.title != null || widget.showSearch || widget.showJsonExport)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                if (widget.title != null)
                  Expanded(
                    child: Text(
                      widget.title!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (widget.showSearch)
                  SizedBox(
                    width: 200,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Filter...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                if (widget.showJsonExport) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy_all, size: 20),
                    tooltip: 'Copy as JSON',
                    onPressed: _copyAsJson,
                  ),
                ],
              ],
            ),
          ),

        // Table
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                widget.emptyMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: _sortColumn != null
                  ? widget.columns.indexWhere((c) => c.key == _sortColumn)
                  : null,
              sortAscending: _sortAscending,
              columns: widget.columns.map((col) {
                return DataColumn(
                  label: Text(
                    col.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  numeric: col.numeric,
                  onSort: (_, __) => _onSort(col.key),
                );
              }).toList(),
              rows: filtered.map((row) {
                return DataRow(
                  onSelectChanged: widget.onRowTap != null
                      ? (_) => widget.onRowTap!(row)
                      : null,
                  cells: widget.columns.map((col) {
                    final value = row[col.key];
                    final display = col.formatter != null
                        ? col.formatter!(value)
                        : value?.toString() ?? '';
                    return DataCell(Text(display));
                  }).toList(),
                );
              }).toList(),
            ),
          ),

        // Footer with count.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${filtered.length} of ${widget.rows.length} rows',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Definition of a column in [ZegelDataTable].
class ZegelColumn {
  /// Key used to look up values in row maps.
  final String key;

  /// Display label for the column header.
  final String label;

  /// Whether the column contains numeric data (affects alignment).
  final bool numeric;

  /// Optional formatter to convert raw values to display strings.
  final String Function(dynamic value)? formatter;

  const ZegelColumn({
    required this.key,
    required this.label,
    this.numeric = false,
    this.formatter,
  });
}
