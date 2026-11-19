import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'block_model.dart';
import 'database_block.dart';

abstract final class ChartType {
  static const bar = 'bar';
  static const line = 'line';
  static const all = <String>[bar, line];
  static String label(String v) => v == line ? 'Line' : 'Bar';
}

class ChartConfig {
  ChartConfig({
    this.source,
    this.group,
    this.value,
    this.aggregate = DbAggregate.count,
    this.type = ChartType.bar,
  });

  String? source;
  String? group;
  String? value;
  String aggregate;
  String type;

  static ChartConfig fromProps(Map<String, Object?> props) => ChartConfig(
    source: props['source'] as String?,
    group: props['group'] as String?,
    value: props['value'] as String?,
    aggregate: (props['aggregate'] as String?) ?? DbAggregate.count,
    type: (props['type'] as String?) ?? ChartType.bar,
  );

  void writeTo(Map<String, Object?> props) {
    props['source'] = source;
    props['group'] = group;
    props['value'] = value;
    props['aggregate'] = aggregate;
    props['type'] = type;
  }
}

class ChartPoint {
  const ChartPoint(this.label, this.value);
  final String label;
  final double value;
}

/// A chart bound to one inline database in the page: group rows by a column,
/// aggregate a numeric column, draw bars or a line. No external chart package.
class ChartBlock extends StatefulWidget {
  const ChartBlock({
    super.key,
    required this.block,
    required this.doc,
    required this.onEdit,
    required this.onBeforeEdit,
  });

  final NoteBlock block;
  final BlockDoc doc;
  final VoidCallback onEdit;
  final VoidCallback onBeforeEdit;

  @override
  State<ChartBlock> createState() => _ChartBlockState();
}

class _ChartBlockState extends State<ChartBlock> {
  late ChartConfig _config;

  @override
  void initState() {
    super.initState();
    _config = ChartConfig.fromProps(widget.block.props);
  }

  @override
  void didUpdateWidget(covariant ChartBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id) {
      _config = ChartConfig.fromProps(widget.block.props);
    }
  }

  List<NoteBlock> get _databases =>
      widget.doc.raw.where((b) => b.type == BType.database).toList();

  NoteBlock? get _source {
    for (final b in _databases) {
      if (b.id == _config.source) return b;
    }
    return null;
  }

  void _update(ChartConfig next) {
    widget.onBeforeEdit();
    setState(() => _config = next);
    _config.writeTo(widget.block.props);
    widget.block.updatedAt = DateTime.now();
    widget.onEdit();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final source = _source;

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8, right: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(MRadius.md),
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 14, color: c.inkMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title(source),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MType.small.copyWith(
                    fontSize: 11,
                    color: c.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                tooltip: 'Chart settings',
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (source == null || _config.group == null)
            _emptyState(context)
          else
            SizedBox(height: 170, child: _chart(context, source)),
        ],
      ),
    );
  }

  String _title(NoteBlock? source) {
    final dbName = source == null ? 'No database' : _dbTitle(source);
    if (_config.group == null) return dbName;
    final agg = DbAggregate.label(_config.aggregate);
    return '$agg by ${_columnName(source!, _config.group!)} — $dbName';
  }

  String _dbTitle(NoteBlock block) {
    final raw = block.props['title'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return 'Database';
  }

  String _columnName(NoteBlock source, String columnId) {
    final data = DbData.fromProps(source.props);
    return data.column(columnId)?.name ?? 'column';
  }

  Widget _emptyState(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _databases.isEmpty
                  ? 'Add a database block with /database, then bind this chart to it.'
                  : 'Choose the database and the column to chart.',
              style: MType.small.copyWith(fontSize: 11, color: c.inkMuted),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _openSettings(context),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: c.ink,
            ),
            child: const Text('Set up'),
          ),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context, NoteBlock source) {
    final data = DbData.fromProps(source.props);
    final points = _points(data);
    if (points.isEmpty) {
      return Center(
        child: Text(
          'No rows to chart yet',
          style: MType.small.copyWith(fontSize: 11, color: context.c.inkMuted),
        ),
      );
    }
    return CustomPaint(
      painter: _ChartPainter(
        points: points,
        type: _config.type,
        color: context.c.ink,
        muted: context.c.inkMuted,
        line: context.c.line,
        grid: context.c.line.withValues(alpha: 0.6),
      ),
      child: const SizedBox.expand(),
    );
  }

  List<ChartPoint> _points(DbData data) {
    final groupColumn = data.column(_config.group ?? '');
    final valueColumn = data.column(_config.value ?? '');
    if (groupColumn == null) return const [];

    final buckets = <String, List<double>>{};
    for (final row in data.rows) {
      final key = data.cell(row, groupColumn).trim();
      final label = key.isEmpty ? '(empty)' : key;
      final bucket = buckets.putIfAbsent(label, () => <double>[]);
      if (_config.aggregate == DbAggregate.count) {
        bucket.add(1);
      } else if (valueColumn != null) {
        final v = data.number(row, valueColumn);
        if (v != null) bucket.add(v);
      }
    }

    final points = <ChartPoint>[];
    final keys = buckets.keys.toList()..sort();
    for (final key in keys) {
      final values = buckets[key]!;
      if (values.isEmpty && _config.aggregate != DbAggregate.count) continue;
      final point = switch (_config.aggregate) {
        DbAggregate.sum => values.fold<double>(0, (a, b) => a + b),
        DbAggregate.average =>
          values.isEmpty
              ? 0.0
              : values.fold<double>(0, (a, b) => a + b) / values.length,
        DbAggregate.max => values.isEmpty ? 0.0 : values.reduce(math.max),
        DbAggregate.min => values.isEmpty ? 0.0 : values.reduce(math.min),
        _ => values.length.toDouble(),
      };
      points.add(ChartPoint(key, point));
    }
    return points;
  }

  Future<void> _openSettings(BuildContext context) async {
    final c = context.c;
    final databases = _databases;
    if (databases.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Add a /database block first')),
      );
      return;
    }

    var config = ChartConfig.fromProps(widget.block.props);
    if (config.source == null || !databases.any((b) => b.id == config.source)) {
      config.source = databases.first.id;
    }
    var data = DbData.fromProps(
      databases.firstWhere((b) => b.id == config.source).props,
    );
    config.group ??= data.columns.isEmpty ? null : data.columns.first.id;
    final numeric = data.columns
        .where((col) => col.type == DbType.number)
        .toList();
    config.value ??= numeric.isEmpty ? null : numeric.first.id;

    final result = await showDialog<ChartConfig>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          final columns = data.columns;
          final numericColumns = columns
              .where((col) => col.type == DbType.number)
              .toList();
          return AlertDialog(
            backgroundColor: c.surface,
            title: Text('Chart', style: MType.h3.copyWith(color: c.ink)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(context, 'Database'),
                  DropdownButton<String>(
                    value: config.source,
                    isExpanded: true,
                    items: [
                      for (final db in databases)
                        DropdownMenuItem(
                          value: db.id,
                          child: Text(_dbTitle(db)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setDialog(() {
                        config.source = v;
                        data = DbData.fromProps(
                          databases.firstWhere((b) => b.id == v).props,
                        );
                        config.group = data.columns.isEmpty
                            ? null
                            : data.columns.first.id;
                        final nums = data.columns
                            .where((col) => col.type == DbType.number)
                            .toList();
                        config.value = nums.isEmpty ? null : nums.first.id;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _label(context, 'Group by'),
                  DropdownButton<String>(
                    value: columns.any((col) => col.id == config.group)
                        ? config.group
                        : null,
                    isExpanded: true,
                    items: [
                      for (final col in columns)
                        DropdownMenuItem(value: col.id, child: Text(col.name)),
                    ],
                    onChanged: (v) => setDialog(() => config.group = v),
                  ),
                  const SizedBox(height: 10),
                  _label(context, 'Aggregate'),
                  DropdownButton<String>(
                    value: config.aggregate,
                    isExpanded: true,
                    items: [
                      for (final agg in DbAggregate.all)
                        DropdownMenuItem(
                          value: agg,
                          child: Text(DbAggregate.label(agg)),
                        ),
                    ],
                    onChanged: (v) => setDialog(
                      () => config.aggregate = v ?? DbAggregate.count,
                    ),
                  ),
                  if (config.aggregate != DbAggregate.count) ...[
                    const SizedBox(height: 10),
                    _label(context, 'Value column'),
                    DropdownButton<String>(
                      value: numericColumns.any((col) => col.id == config.value)
                          ? config.value
                          : null,
                      isExpanded: true,
                      hint: const Text('Numeric property'),
                      items: [
                        for (final col in numericColumns)
                          DropdownMenuItem(
                            value: col.id,
                            child: Text(col.name),
                          ),
                      ],
                      onChanged: (v) => setDialog(() => config.value = v),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _label(context, 'Type'),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: ChartType.bar, label: Text('Bar')),
                      ButtonSegment(value: ChartType.line, label: Text('Line')),
                    ],
                    selected: {config.type},
                    onSelectionChanged: (s) =>
                        setDialog(() => config.type = s.first),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, config),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    _update(result);
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: MType.small.copyWith(fontSize: 10.5, color: context.c.inkMuted),
    ),
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.type,
    required this.color,
    required this.muted,
    required this.line,
    required this.grid,
  });

  final List<ChartPoint> points;
  final String type;
  final Color color;
  final Color muted;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    const bottom = 22.0;
    const top = 10.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - 6,
      size.height - bottom,
    );

    var maxValue = 0.0;
    for (final p in points) {
      if (p.value > maxValue) maxValue = p.value;
    }
    if (maxValue <= 0) maxValue = 1;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final textStyle = TextStyle(fontSize: 8.5, color: muted);
    for (var i = 0; i <= 3; i++) {
      final y = chart.bottom - chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final value = maxValue * i / 3;
      _text(
        canvas,
        _short(value),
        Offset(0, y - 5),
        textStyle,
        maxWidth: left - 4,
        align: TextAlign.right,
      );
    }

    if (type == ChartType.line) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final dx =
            chart.left +
            chart.width * (points.length == 1 ? 0.5 : i / (points.length - 1));
        final dy = chart.bottom - chart.height * (points[i].value / maxValue);
        if (i == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }
      canvas.drawPath(path, paint);
      final dot = Paint()..color = color;
      for (var i = 0; i < points.length; i++) {
        final dx =
            chart.left +
            chart.width * (points.length == 1 ? 0.5 : i / (points.length - 1));
        final dy = chart.bottom - chart.height * (points[i].value / maxValue);
        canvas.drawCircle(Offset(dx, dy), 2.6, dot);
      }
    } else {
      final slot = chart.width / points.length;
      final barWidth = math.min(34.0, slot * 0.6);
      final paint = Paint()..color = color;
      for (var i = 0; i < points.length; i++) {
        final cx = chart.left + slot * i + slot / 2;
        final height = chart.height * (points[i].value / maxValue);
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            cx - barWidth / 2,
            chart.bottom - height,
            barWidth,
            height,
          ),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rect, paint);
      }
    }

    canvas.drawLine(
      Offset(chart.left, chart.bottom),
      Offset(chart.right, chart.bottom),
      Paint()
        ..color = line
        ..strokeWidth = 1,
    );

    final slot = chart.width / points.length;
    for (var i = 0; i < points.length; i++) {
      final cx = chart.left + slot * i + slot / 2;
      _text(
        canvas,
        points[i].label,
        Offset(cx - slot / 2, chart.bottom + 5),
        textStyle,
        maxWidth: slot,
        align: TextAlign.center,
      );
    }
  }

  String _short(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(10, maxWidth));
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_ChartPainter old) {
    if (old.type != type ||
        old.color != color ||
        old.muted != muted ||
        old.line != line ||
        old.grid != grid ||
        old.points.length != points.length) {
      return true;
    }
    for (var i = 0; i < points.length; i++) {
      if (old.points[i].label != points[i].label ||
          old.points[i].value != points[i].value) {
        return true;
      }
    }
    return false;
  }
}
