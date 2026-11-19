import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import 'block_model.dart';

/// Column kinds supported by the inline database block.
abstract final class DbType {
  static const text = 'text';
  static const number = 'number';
  static const select = 'select';
  static const date = 'date';
  static const checkbox = 'checkbox';

  static const all = <String>[text, number, select, date, checkbox];

  static String label(String type) => switch (type) {
    number => 'Number',
    select => 'Select',
    date => 'Date',
    checkbox => 'Checkbox',
    _ => 'Text',
  };

  static IconData icon(String type) => switch (type) {
    number => Icons.tag_rounded,
    select => Icons.sell_outlined,
    date => Icons.event_outlined,
    checkbox => Icons.check_box_outlined,
    _ => Icons.notes_rounded,
  };
}

class DbColumn {
  DbColumn({
    required this.id,
    required this.name,
    this.type = DbType.text,
    List<String>? options,
  }) : options = options ?? <String>[];

  final String id;
  String name;
  String type;
  final List<String> options;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    if (options.isNotEmpty) 'options': options,
  };

  static DbColumn fromJson(Map<String, Object?> j) => DbColumn(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? 'Column',
    type: (j['type'] as String?) ?? DbType.text,
    options: ((j['options'] as List?) ?? const []).map((e) => '$e').toList(),
  );
}

class DbRow {
  DbRow({required this.id, Map<String, String>? cells})
    : cells = cells ?? <String, String>{};

  final String id;
  final Map<String, String> cells;

  Map<String, Object?> toJson() => {'id': id, 'cells': cells};

  static DbRow fromJson(Map<String, Object?> j) => DbRow(
    id: j['id'] as String,
    cells: ((j['cells'] as Map?) ?? const {}).map(
      (k, v) => MapEntry('$k', v == null ? '' : '$v'),
    ),
  );
}

/// The whole table lives in the block props as JSON, so persistence, undo and
/// export need no extra tables or queries.
class DbData {
  DbData({
    required this.columns,
    required this.rows,
    this.view = 'table',
    this.groupBy,
    this.sortColumn,
    this.sortDesc = false,
    this.filterColumn,
    this.filterValue = '',
  });

  final List<DbColumn> columns;
  final List<DbRow> rows;

  /// "table" or "board".
  String view;

  /// Column used to group cards in the board view.
  String? groupBy;

  /// Optional sort column and direction, shared by both views.
  String? sortColumn;
  bool sortDesc;

  /// One simple filter: a column and a case-insensitive contains match.
  String? filterColumn;
  String filterValue;

  static int _seq = 0;
  static String newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  static DbData blank() => DbData(
    columns: [
      DbColumn(id: newId('c'), name: 'Name'),
      DbColumn(
        id: newId('c'),
        name: 'Status',
        type: DbType.select,
        options: ['To do', 'Doing', 'Done'],
      ),
      DbColumn(id: newId('c'), name: 'Score', type: DbType.number),
    ],
    rows: [
      DbRow(id: newId('r'), cells: {}),
      DbRow(id: newId('r'), cells: {}),
    ],
  );

  static DbData fromProps(Map<String, Object?> props) {
    try {
      final rawColumns = props['columns'];
      final rawRows = props['rows'];
      if (rawColumns is String && rawRows is String) {
        final cols = (jsonDecode(rawColumns) as List)
            .map((e) => DbColumn.fromJson((e as Map).cast<String, Object?>()))
            .toList();
        final rowList = (jsonDecode(rawRows) as List)
            .map((e) => DbRow.fromJson((e as Map).cast<String, Object?>()))
            .toList();
        if (cols.isNotEmpty) {
          return DbData(
            columns: cols,
            rows: rowList,
            view: (props['view'] as String?) ?? 'table',
            groupBy: props['groupBy'] as String?,
            sortColumn: props['sortColumn'] as String?,
            sortDesc: props['sortDesc'] == true,
            filterColumn: props['filterColumn'] as String?,
            filterValue: (props['filterValue'] as String?) ?? '',
          );
        }
      }
    } catch (_) {}
    return blank();
  }

  /// Rows in display order, honouring the optional sort.
  List<DbRow> get sortedRows {
    final list = List<DbRow>.from(rows);
    final sortCol = sortColumn == null ? null : column(sortColumn!);
    if (sortCol == null) return list;
    list.sort((a, b) {
      final av = a.cells[sortCol.id] ?? '';
      final bv = b.cells[sortCol.id] ?? '';
      int result;
      if (sortCol.type == DbType.number) {
        result = (double.tryParse(av.replaceAll(',', '.')) ?? 0).compareTo(
          double.tryParse(bv.replaceAll(',', '.')) ?? 0,
        );
      } else if (sortCol.type == DbType.checkbox) {
        result = (av == 'true' ? 1 : 0).compareTo(bv == 'true' ? 1 : 0);
      } else {
        result = av.toLowerCase().compareTo(bv.toLowerCase());
      }
      return sortDesc ? -result : result;
    });
    return list;
  }

  void writeTo(Map<String, Object?> props) {
    props['columns'] = jsonEncode(columns.map((c) => c.toJson()).toList());
    props['rows'] = jsonEncode(rows.map((r) => r.toJson()).toList());
    props['view'] = view;
    props['groupBy'] = groupBy;
    props['sortColumn'] = sortColumn;
    props['sortDesc'] = sortDesc;
    props['filterColumn'] = filterColumn;
    props['filterValue'] = filterValue;
  }

  /// Rows after sorting and the optional filter.
  List<DbRow> get visibleRows {
    final rows = sortedRows;
    final filterCol = filterColumn == null ? null : column(filterColumn!);
    final needle = filterValue.trim().toLowerCase();
    if (filterCol == null || needle.isEmpty) return rows;
    return rows.where((r) {
      final value = (r.cells[filterCol.id] ?? '').toLowerCase();
      if (filterCol.type == DbType.checkbox) {
        return value ==
            (needle == 'true' || needle == 'yes' ? 'true' : 'false');
      }
      return value.contains(needle);
    }).toList();
  }

  /// Distinct values of [columnId] in row order, with a label for empty cells.
  List<String> groupValues(String columnId) {
    final seen = <String>[];
    for (final row in visibleRows) {
      final value = (row.cells[columnId] ?? '').trim();
      final label = value.isEmpty ? '' : value;
      if (!seen.contains(label)) seen.add(label);
    }
    return seen;
  }

  DbColumn? column(String id) {
    for (final c in columns) {
      if (c.id == id) return c;
    }
    return null;
  }

  DbRow? row(String id) {
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  }

  void addRow({Map<String, String>? cells}) {
    rows.add(DbRow(id: newId('r'), cells: cells));
  }

  void insertRowAfter(String rowId) {
    final index = rows.indexWhere((r) => r.id == rowId);
    final row = DbRow(id: newId('r'));
    if (index < 0) {
      rows.add(row);
    } else {
      rows.insert(index + 1, row);
    }
  }

  void removeRow(String rowId) => rows.removeWhere((r) => r.id == rowId);

  void addColumn({String name = 'Column', String type = DbType.text}) {
    columns.add(DbColumn(id: newId('c'), name: name, type: type));
  }

  void removeColumn(String columnId) {
    columns.removeWhere((c) => c.id == columnId);
    for (final r in rows) {
      r.cells.remove(columnId);
    }
  }

  String cell(DbRow row, DbColumn column) => row.cells[column.id] ?? '';

  void setCell(String rowId, String columnId, String value) {
    final row = this.row(rowId);
    if (row == null) return;
    if (value.isEmpty) {
      row.cells.remove(columnId);
    } else {
      row.cells[columnId] = value;
    }
  }

  double? number(DbRow row, DbColumn column) =>
      double.tryParse((row.cells[column.id] ?? '').replaceAll(',', '.'));

  double sum(DbColumn column) {
    var total = 0.0;
    for (final r in rows) {
      total += number(r, column) ?? 0;
    }
    return total;
  }

  int filled(DbColumn column) =>
      rows.where((r) => (r.cells[column.id] ?? '').isNotEmpty).length;
}

/// Inline database rendered in the page. Every mutation calls [onEdit] so the
/// host can take an undo snapshot and schedule the save.
class DatabaseBlock extends StatefulWidget {
  const DatabaseBlock({
    super.key,
    required this.block,
    required this.onEdit,
    required this.onBeforeEdit,
  });

  final NoteBlock block;

  /// Called after a change, to schedule the save.
  final VoidCallback onEdit;

  /// Called before a change, so the host can take an undo snapshot.
  final VoidCallback onBeforeEdit;

  @override
  State<DatabaseBlock> createState() => _DatabaseBlockState();
}

class _DatabaseBlockState extends State<DatabaseBlock> {
  late DbData _data;
  String? _editingColumn;
  final TextEditingController _renameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _data = DbData.fromProps(widget.block.props);
    _data.writeTo(widget.block.props);
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  void _begin() => widget.onBeforeEdit();

  void _commit() {
    _data.writeTo(widget.block.props);
    widget.block.updatedAt = DateTime.now();
    widget.onEdit();
    setState(() {});
  }

  /// Writes the value without rebuilding the table, so typing in a cell does
  /// not recreate its field or move the caret.
  void _touch() {
    _data.writeTo(widget.block.props);
    widget.block.updatedAt = DateTime.now();
    widget.onEdit();
  }

  static const double _rowHeight = 36;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8, right: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MRadius.md),
        border: Border.all(color: c.line),
        color: c.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
            child: Row(
              children: [
                Icon(Icons.table_chart_outlined, size: 14, color: c.inkMuted),
                const SizedBox(width: 8),
                Text(
                  '${_data.rows.length} row${_data.rows.length == 1 ? '' : 's'}',
                  style: MType.small.copyWith(
                    fontSize: 10.5,
                    color: c.inkMuted,
                  ),
                ),
                const Spacer(),
                if (_data.view == 'board') ...[
                  TextButton.icon(
                    onPressed: () => _pickGroupColumn(context),
                    icon: const Icon(Icons.workspaces_outline, size: 13),
                    label: Text(
                      'Group: ${_groupColumn?.name ?? '—'}',
                      style: MType.small.copyWith(
                        fontSize: 10.5,
                        color: c.inkMuted,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: c.ink,
                    ),
                  ),
                ],
                _viewToggle(context),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  tooltip: 'Filter',
                  onPressed: () => _filterSheet(context),
                  icon: Icon(
                    _data.filterColumn != null &&
                            _data.filterValue.trim().isNotEmpty
                        ? Icons.filter_alt
                        : Icons.filter_alt_outlined,
                    color: c.inkMuted,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _addColumnSheet(context),
                  icon: const Icon(Icons.add, size: 14),
                  label: Text(
                    'Property',
                    style: MType.small.copyWith(fontSize: 11, color: c.ink),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: c.ink,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          if (_data.view == 'board')
            _board(context)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final colCount = _data.columns.isEmpty
                    ? 1
                    : _data.columns.length;
                final avail =
                    (constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : 640.0) -
                    68.0;
                final colWidth = (avail / colCount).clamp(160.0, 420.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _headerRow(context, colWidth),
                        Divider(height: 1, color: c.line),
                        for (var i = 0; i < _data.visibleRows.length; i++)
                          _dataRow(context, _data.visibleRows[i], i, colWidth),
                        _addRowButton(context),
                        if (_data.columns.isNotEmpty)
                          _footerRow(context, colWidth),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  DbColumn? get _groupColumn {
    final explicit = _data.groupBy == null
        ? null
        : _data.column(_data.groupBy!);
    if (explicit != null) return explicit;
    for (final c in _data.columns) {
      if (c.type == DbType.select) return c;
    }
    return _data.columns.isEmpty ? null : _data.columns.first;
  }

  Widget _viewToggle(BuildContext context) {
    final c = context.c;
    Widget button(String view, IconData icon) {
      final active = _data.view == view;
      return InkWell(
        onTap: () {
          if (active) return;
          _begin();
          _data.view = view;
          if (view == 'board' && _data.groupBy == null) {
            _data.groupBy = _groupColumn?.id;
          }
          _commit();
        },
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: 26,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon, size: 14, color: active ? c.ink : c.inkFaint),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('table', Icons.view_list_rounded),
        button('board', Icons.view_kanban_outlined),
      ],
    );
  }

  Future<void> _pickGroupColumn(BuildContext context) async {
    final c = context.c;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Offset(60, 120)
        : box.localToGlobal(Offset.zero);
    final rect = overlay == null
        ? const RelativeRect.fromLTRB(60, 120, 60, 60)
        : RelativeRect.fromRect(
            Rect.fromLTWH(origin.dx, origin.dy, 1, 1),
            Offset.zero & overlay.size,
          );
    final chosen = await showMenu<String>(
      context: context,
      position: rect,
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        side: BorderSide(color: c.line),
      ),
      items: [
        for (final column in _data.columns)
          PopupMenuItem<String>(
            value: column.id,
            height: 32,
            child: Row(
              children: [
                Icon(DbType.icon(column.type), size: 13, color: c.inkMuted),
                const SizedBox(width: 8),
                Text(
                  column.name,
                  style: MType.small.copyWith(fontSize: 11.5, color: c.ink),
                ),
                if (_data.groupBy == column.id) ...[
                  const Spacer(),
                  Icon(Icons.check_rounded, size: 13, color: c.ink),
                ],
              ],
            ),
          ),
      ],
    );
    if (!mounted || chosen == null) return;
    _begin();
    _data.groupBy = chosen;
    _commit();
  }

  Widget _board(BuildContext context) {
    final groupColumn = _groupColumn;
    if (groupColumn == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Add a property to group by',
          style: MType.small.copyWith(fontSize: 11, color: context.c.inkMuted),
        ),
      );
    }
    final groups = _data.groupValues(groupColumn.id);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups) _boardColumn(context, groupColumn, group),
          _boardColumn(context, groupColumn, '', isAddColumn: true),
        ],
      ),
    );
  }

  Widget _boardColumn(
    BuildContext context,
    DbColumn groupColumn,
    String value, {
    bool isAddColumn = false,
  }) {
    final c = context.c;
    final rows = isAddColumn
        ? const <DbRow>[]
        : _data.visibleRows
              .where((r) => (r.cells[groupColumn.id] ?? '').trim() == value)
              .toList();
    final label = isAddColumn
        ? 'Add group'
        : value.isEmpty
        ? 'No ${groupColumn.name}'
        : value;

    final body = Container(
      width: 224,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.small.copyWith(
                      fontSize: 10.5,
                      color: c.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!isAddColumn)
                  Text(
                    '${rows.length}',
                    style: MType.small.copyWith(
                      fontSize: 10,
                      color: c.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
          if (!isAddColumn)
            for (final row in rows) _boardCard(context, row, groupColumn),
          InkWell(
            onTap: () {
              if (isAddColumn) {
                _addGroup(context, groupColumn);
              } else {
                _begin();
                final row = DbRow(
                  id: DbData.newId('r'),
                  cells: {groupColumn.id: value},
                );
                _data.rows.add(row);
                _commit();
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Icon(
                    isAddColumn ? Icons.add_circle_outline : Icons.add,
                    size: 13,
                    color: c.inkMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isAddColumn ? 'New group' : 'New card',
                    style: MType.small.copyWith(
                      fontSize: 10.5,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isAddColumn) return body;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final row = _data.row(details.data);
        return row != null && (row.cells[groupColumn.id] ?? '').trim() != value;
      },
      onAcceptWithDetails: (details) {
        _begin();
        _data.setCell(details.data, groupColumn.id, value);
        _commit();
      },
      builder: (context, candidate, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: candidate.isEmpty ? Colors.transparent : c.ink,
            width: 1.5,
          ),
        ),
        child: body,
      ),
    );
  }

  Widget _boardCard(BuildContext context, DbRow row, DbColumn groupColumn) {
    final c = context.c;
    final titleColumn = _data.columns.firstWhere(
      (col) => col.type == DbType.text,
      orElse: () => _data.columns.first,
    );
    final title = _data.cell(row, titleColumn).trim();
    final extras = <String>[];
    for (final col in _data.columns) {
      if (col.id == titleColumn.id || col.id == groupColumn.id) continue;
      final value = _data.cell(row, col).trim();
      if (value.isEmpty) continue;
      extras.add(
        col.type == DbType.checkbox
            ? (value == 'true' ? '☑ ${col.name}' : '☐ ${col.name}')
            : '${col.name}: $value',
      );
      if (extras.length >= 2) break;
    }

    final card = Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(color: c.shadow, blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'Untitled' : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MType.small.copyWith(
              fontSize: 11.5,
              color: c.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
          for (final extra in extras)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                extra,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MType.small.copyWith(fontSize: 9.5, color: c.inkMuted),
              ),
            ),
        ],
      ),
    );

    return Draggable<String>(
      data: row.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 208, child: card),
      ),
      child: card,
    );
  }

  Future<void> _addGroup(BuildContext context, DbColumn groupColumn) async {
    final controller = TextEditingController();
    final c = context.c;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('New group', style: MType.h3.copyWith(color: c.ink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    final text = value.trim();
    if (text.isEmpty) return;
    _begin();
    if (groupColumn.type == DbType.select &&
        !groupColumn.options.contains(text)) {
      groupColumn.options.add(text);
    }
    _data.rows.add(DbRow(id: DbData.newId('r'), cells: {groupColumn.id: text}));
    _commit();
  }

  Future<void> _filterSheet(BuildContext context) async {
    final c = context.c;
    final controller = TextEditingController(text: _data.filterValue);
    String? columnId = _data.filterColumn;
    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: c.surface,
          title: Text('Filter', style: MType.h3.copyWith(color: c.ink)),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButton<String>(
                  value: _data.columns.any((col) => col.id == columnId)
                      ? columnId
                      : null,
                  isExpanded: true,
                  hint: const Text('Property'),
                  items: [
                    for (final col in _data.columns)
                      DropdownMenuItem(value: col.id, child: Text(col.name)),
                  ],
                  onChanged: (v) => setDialog(() => columnId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Contains value',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _begin();
                _data.filterColumn = null;
                _data.filterValue = '';
                _commit();
                Navigator.pop(context, false);
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || applied != true) return;
    if (columnId == null) return;
    _begin();
    _data.filterColumn = columnId;
    _data.filterValue = controller.text;
    _commit();
  }

  Widget _headerRow(BuildContext context, double colWidth) {
    final c = context.c;
    return Container(
      color: c.surfaceAlt,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: c.line)),
            ),
            child: Text(
              '#',
              style: MType.small.copyWith(fontSize: 10, color: c.inkFaint),
            ),
          ),
          for (final column in _data.columns)
            Container(
              width: colWidth,
              height: 34,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: c.line)),
              ),
              child: InkWell(
                onTap: () => _columnMenu(context, column),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        DbType.icon(column.type),
                        size: 13,
                        color: c.inkMuted,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _editingColumn == column.id
                            ? TextField(
                                autofocus: true,
                                controller: _renameController,
                                style: MType.small.copyWith(
                                  fontSize: 11.5,
                                  color: c.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: 'Name',
                                ),
                                onSubmitted: (v) {
                                  _begin();
                                  column.name = v.trim().isEmpty
                                      ? 'Column'
                                      : v.trim();
                                  _editingColumn = null;
                                  _commit();
                                },
                                onTapOutside: (_) {
                                  _editingColumn = null;
                                  setState(() {});
                                },
                              )
                            : Text(
                                column.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MType.small.copyWith(
                                  fontSize: 11.5,
                                  color: c.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      if (_data.sortColumn == column.id)
                        Icon(
                          _data.sortDesc
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 12,
                          color: c.inkMuted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 15,
              tooltip: 'Add property',
              onPressed: () => _addColumnSheet(context),
              icon: Icon(Icons.add, color: c.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, DbRow row, int index, double colWidth) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line.withValues(alpha: 0.75))),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: _rowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: c.line)),
            ),
            child: Text(
              '${index + 1}',
              style: MType.small.copyWith(fontSize: 10, color: c.inkFaint),
            ),
          ),
          for (final column in _data.columns)
            Container(
              width: colWidth,
              height: _rowHeight,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: c.line)),
              ),
              child: _cell(context, row, column),
            ),
          SizedBox(
            width: 34,
            height: _rowHeight,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 13,
              tooltip: 'Delete row',
              onPressed: () {
                _begin();
                _data.removeRow(row.id);
                _commit();
              },
              icon: Icon(Icons.close_rounded, color: c.inkFaint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, DbRow row, DbColumn column) {
    final c = context.c;
    final value = _data.cell(row, column);
    switch (column.type) {
      case DbType.checkbox:
        final on = value == 'true';
        return Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: on,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: c.lineStrong),
              onChanged: (v) {
                _begin();
                _data.setCell(row.id, column.id, (v ?? false) ? 'true' : '');
                _commit();
              },
            ),
          ),
        );
      case DbType.select:
        final (pillBg, pillFg) = _selectColors(value, c, context.isDark);
        return PopupMenuButton<String>(
          tooltip: 'Set value',
          color: c.surface,
          onSelected: (v) {
            _begin();
            _data.setCell(row.id, column.id, v == '__clear' ? '' : v);
            _commit();
          },
          itemBuilder: (_) => [
            for (final option in column.options)
              PopupMenuItem(value: option, height: 32, child: Text(option)),
            if (column.options.isNotEmpty) const PopupMenuDivider(),
            const PopupMenuItem(
              value: '__clear',
              height: 32,
              child: Text('Clear'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: value.isEmpty
                  ? Text(
                      'Select…',
                      style: MType.small.copyWith(
                        fontSize: 11,
                        color: c.inkFaint.withValues(alpha: 0.45),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MType.small.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: pillFg,
                        ),
                      ),
                    ),
            ),
          ),
        );
      case DbType.date:
        return InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(value) ?? now,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            _begin();
            _data.setCell(
              row.id,
              column.id,
              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
            );
            _commit();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value.isEmpty ? 'Pick date…' : value,
                style: MType.small.copyWith(
                  fontSize: 11,
                  color: value.isEmpty
                      ? c.inkFaint.withValues(alpha: 0.45)
                      : c.ink,
                ),
              ),
            ),
          ),
        );
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextFormField(
              key: ValueKey('${row.id}:${column.id}'),
              initialValue: value,
              textAlign: column.type == DbType.number
                  ? TextAlign.right
                  : TextAlign.left,
              style: MType.small.copyWith(fontSize: 12, color: c.ink),
              keyboardType: column.type == DbType.number
                  ? TextInputType.number
                  : TextInputType.text,
              inputFormatters: column.type == DbType.number
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
                  : null,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                hoverColor: Colors.transparent,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: column.type == DbType.number ? '0' : 'Empty',
                hintStyle: MType.small.copyWith(
                  fontSize: 11,
                  color: c.inkFaint.withValues(alpha: 0.35),
                ),
              ),
              onChanged: (v) {
                _begin();
                _data.setCell(row.id, column.id, v);
                _touch();
              },
            ),
          ),
        );
    }
  }

  (Color, Color) _selectColors(String value, MColors c, bool dark) {
    final lower = value.toLowerCase();
    if (lower.contains('done') || lower.contains('complete')) {
      return dark
          ? (
              Color.alphaBlend(c.success.withValues(alpha: 0.14), c.surface),
              c.success,
            )
          : (const Color(0xFFEDF3EC), const Color(0xFF2F6F4E));
    }
    if (lower.contains('doing') || lower.contains('progress')) {
      return dark
          ? (const Color(0xFF173043), const Color(0xFF89C9EC))
          : (const Color(0xFFE7F3F8), const Color(0xFF2B6C94));
    }
    if (lower.contains('todo') || lower.contains('to do')) {
      return (c.surfaceSunken, c.inkMuted);
    }
    return (c.accentSoft, c.ink);
  }

  Widget _addRowButton(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: () {
        _begin();
        _data.addRow();
        _commit();
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: c.line.withValues(alpha: 0.75)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: c.inkMuted),
            const SizedBox(width: 6),
            Text(
              'New row',
              style: MType.small.copyWith(fontSize: 11, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footerRow(BuildContext context, double colWidth) {
    final c = context.c;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 34),
          for (final column in _data.columns)
            SizedBox(
              width: colWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: column.type == DbType.number
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Text(
                    column.type == DbType.number
                        ? 'SUM ${_formatNumber(_data.sum(column))}'
                        : column.type == DbType.checkbox
                        ? '${_data.rows.where((r) => r.cells[column.id] == 'true').length} checked'
                        : '${_data.filled(column)} filled',
                    style: MType.small.copyWith(
                      fontSize: 10,
                      color: c.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 34),
        ],
      ),
    );
  }

  String _formatNumber(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  Future<void> _columnMenu(BuildContext context, DbColumn column) async {
    final c = context.c;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Offset(60, 120)
        : box.localToGlobal(Offset.zero);
    final rect = overlay == null
        ? const RelativeRect.fromLTRB(60, 120, 60, 60)
        : RelativeRect.fromRect(
            Rect.fromLTWH(origin.dx, origin.dy, 1, 1),
            Offset.zero & overlay.size,
          );
    final action = await showMenu<String>(
      context: context,
      position: rect,
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        side: BorderSide(color: c.line),
      ),
      items: [
        _tile('rename', Icons.edit_outlined, 'Rename', c),
        _typeTile(DbType.text, column, c),
        _typeTile(DbType.number, column, c),
        _typeTile(DbType.select, column, c),
        _typeTile(DbType.date, column, c),
        _typeTile(DbType.checkbox, column, c),
        const PopupMenuDivider(),
        _tile('sortAsc', Icons.arrow_upward_rounded, 'Sort ascending', c),
        _tile('sortDesc', Icons.arrow_downward_rounded, 'Sort descending', c),
        if (_data.sortColumn == column.id)
          _tile('sortClear', Icons.clear_rounded, 'Clear sort', c),
        const PopupMenuDivider(),
        _tile('delete', Icons.delete_outline_rounded, 'Delete property', c),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      _renameController.text = column.name;
      _renameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: column.name.length,
      );
      _editingColumn = column.id;
      setState(() {});
      return;
    }
    if (action == 'sortAsc' || action == 'sortDesc') {
      _begin();
      _data.sortColumn = column.id;
      _data.sortDesc = action == 'sortDesc';
      _commit();
      return;
    }
    if (action == 'sortClear') {
      _begin();
      _data.sortColumn = null;
      _data.sortDesc = false;
      _commit();
      return;
    }
    if (action == 'delete') {
      _begin();
      _data.removeColumn(column.id);
      _commit();
      return;
    }
    if (action.startsWith('type:')) {
      _begin();
      column.type = action.substring(5);
      if (column.type == DbType.select && column.options.isEmpty) {
        column.options.addAll(['To do', 'Doing', 'Done']);
      }
      _commit();
    }
  }

  PopupMenuItem<String> _tile(
    String value,
    IconData icon,
    String label,
    MColors c,
  ) => PopupMenuItem<String>(
    value: value,
    height: 34,
    child: Row(
      children: [
        Icon(icon, size: 14, color: c.inkMuted),
        const SizedBox(width: 9),
        Text(label, style: MType.small.copyWith(fontSize: 12, color: c.ink)),
      ],
    ),
  );

  PopupMenuItem<String> _typeTile(String type, DbColumn column, MColors c) =>
      PopupMenuItem<String>(
        value: 'type:$type',
        height: 32,
        child: Row(
          children: [
            Icon(DbType.icon(type), size: 13, color: c.inkMuted),
            const SizedBox(width: 9),
            Text(
              DbType.label(type),
              style: MType.small.copyWith(fontSize: 11.5, color: c.ink),
            ),
            if (column.type == type) ...[
              const Spacer(),
              Icon(Icons.check_rounded, size: 13, color: c.ink),
            ],
          ],
        ),
      );

  Future<void> _addColumnSheet(BuildContext context) async {
    final c = context.c;
    final nameController = TextEditingController();
    var type = DbType.text;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: c.surface,
          title: Text('New property', style: MType.h3.copyWith(color: c.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Property name'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in DbType.all)
                    ChoiceChip(
                      label: Text(DbType.label(t)),
                      selected: type == t,
                      onSelected: (_) => setDialog(() => type = t),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || created != true) return;
    _begin();
    _data.addColumn(
      name: nameController.text.trim().isEmpty
          ? 'Column'
          : nameController.text.trim(),
      type: type,
    );
    _commit();
  }
}

/// Aggregates used by the chart block.
abstract final class DbAggregate {
  static const count = 'count';
  static const sum = 'sum';
  static const average = 'average';
  static const max = 'max';
  static const min = 'min';

  static const all = <String>[count, sum, average, max, min];

  static String label(String value) => switch (value) {
    sum => 'Sum',
    average => 'Average',
    max => 'Max',
    min => 'Min',
    _ => 'Count',
  };
}
