import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Shows a compact single-date picker dialog. Returns the selected [DateTime]
/// or null if cancelled.
Future<DateTime?> showWahaDatePicker(
  BuildContext context, {
  DateTime? initial,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _SingleDatePickerDialog(initial: initial),
  );
}

/// Shows a compact two-month side-by-side range picker dialog. Returns the
/// selected [DateTimeRange] or null if cancelled.
Future<DateTimeRange?> showWahaDateRangePicker(
  BuildContext context, {
  DateTimeRange? initial,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => _RangeDatePickerDialog(initial: initial),
  );
}

// ── Single date dialog ────────────────────────────────────────────────────────

class _SingleDatePickerDialog extends StatefulWidget {
  final DateTime? initial;
  const _SingleDatePickerDialog({this.initial});

  @override
  State<_SingleDatePickerDialog> createState() =>
      _SingleDatePickerDialogState();
}

class _SingleDatePickerDialogState extends State<_SingleDatePickerDialog> {
  late DateTime _selected;
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    _selected  = widget.initial ?? DateTime.now();
    _viewMonth = DateTime(_selected.year, _selected.month);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selected date chip
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: WahaDateChip(
                label: 'Date',
                date: _selected,
                selected: true,
                onTap: () {},
              ),
            ),
            // Month nav
            _MonthNav(
              month: _viewMonth,
              onPrev: () => setState(() =>
                  _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1)),
              onNext: () => setState(() =>
                  _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1)),
            ),
            // Calendar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: WahaCalendarGrid(
                month: _viewMonth,
                start: _selected,
                end: _selected,
                onSelect: (d) => setState(() => _selected = d),
              ),
            ),
            const SizedBox(height: 8),
            _Actions(
              onCancel: () => Navigator.pop(context),
              onApply:  () => Navigator.pop(context, _selected),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Range date dialog (two months side by side) ───────────────────────────────

class _RangeDatePickerDialog extends StatefulWidget {
  final DateTimeRange? initial;
  const _RangeDatePickerDialog({this.initial});

  @override
  State<_RangeDatePickerDialog> createState() =>
      _RangeDatePickerDialogState();
}

class _RangeDatePickerDialogState extends State<_RangeDatePickerDialog> {
  late DateTime _start;
  late DateTime _end;
  bool _pickingEnd = false;
  // Left month; right month is always leftMonth + 1
  late DateTime _leftMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start     = widget.initial?.start ?? DateTime(now.year, now.month, 1);
    _end       = widget.initial?.end   ?? now;
    // Show start month on the left, end month on the right (or prev month if same)
    _leftMonth = DateTime(_start.year, _start.month);
    final rightMonth = DateTime(_leftMonth.year, _leftMonth.month + 1);
    if (_end.isAfter(rightMonth) ||
        (_end.month != _leftMonth.month && _end.year != _leftMonth.year)) {
      // keep left at start month — no-op, leftMonth already set
    }
  }

  DateTime get _rightMonth => DateTime(_leftMonth.year, _leftMonth.month + 1);

  void _onSelect(DateTime d) {
    setState(() {
      if (!_pickingEnd) {
        _start     = d;
        if (_end.isBefore(_start)) _end = _start;
        _pickingEnd = true;
      } else {
        if (d.isBefore(_start)) {
          _end   = _start;
          _start = d;
        } else {
          _end = d;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 660,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // From / To chips
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: WahaDateChip(
                      label: 'From',
                      date: _start,
                      selected: !_pickingEnd,
                      onTap: () => setState(() => _pickingEnd = false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.arrow_forward, size: 16, color: scheme.outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WahaDateChip(
                      label: 'To',
                      date: _end,
                      selected: _pickingEnd,
                      onTap: () => setState(() => _pickingEnd = true),
                    ),
                  ),
                ],
              ),
            ),
            // Two calendar months side by side
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left month
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MonthNav(
                        month: _leftMonth,
                        onPrev: () => setState(() => _leftMonth =
                            DateTime(_leftMonth.year, _leftMonth.month - 1)),
                        onNext: null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: WahaCalendarGrid(
                          month: _leftMonth,
                          start: _start,
                          end: _end,
                          onSelect: _onSelect,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 300,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                // Right month
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MonthNav(
                        month: _rightMonth,
                        onPrev: null,
                        onNext: () => setState(() => _leftMonth =
                            DateTime(_leftMonth.year, _leftMonth.month + 1)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: WahaCalendarGrid(
                          month: _rightMonth,
                          start: _start,
                          end: _end,
                          onSelect: _onSelect,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Actions(
              onCancel: () => Navigator.pop(context),
              onApply:  () => Navigator.pop(
                  context, DateTimeRange(start: _start, end: _end)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class WahaDateChip extends StatelessWidget {
  final String label;
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;
  static final _fmt = DateFormat('MMM d, yyyy');

  const WahaDateChip({
    super.key,
    required this.label,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.primary : scheme.outline)),
            Text(_fmt.format(date),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class WahaCalendarGrid extends StatelessWidget {
  final DateTime month;
  final DateTime start;
  final DateTime end;
  final ValueChanged<DateTime> onSelect;

  const WahaCalendarGrid({
    super.key,
    required this.month,
    required this.start,
    required this.end,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final firstDay    = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // Sun=0

    final cells = <Widget>[
      ...['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => Center(
            child: Text(d,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.outline)))),
      ...List.generate(startWeekday, (_) => const SizedBox.shrink()),
      ...List.generate(daysInMonth, (i) {
        final d      = DateTime(month.year, month.month, i + 1);
        final isStart = _same(d, start);
        final isEnd   = _same(d, end);
        final inRange = d.isAfter(start) && d.isBefore(end);
        final future  = d.isAfter(DateTime.now());

        Color? bg;
        if (isStart || isEnd) bg = scheme.primary;
        else if (inRange)     bg = scheme.primaryContainer;

        return GestureDetector(
          onTap: future ? null : () => onSelect(d),
          child: Container(
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('${i + 1}',
                style: TextStyle(
                    fontSize: 12,
                    color: (isStart || isEnd)
                        ? scheme.onPrimary
                        : future
                            ? scheme.outline.withValues(alpha: 0.35)
                            : scheme.onSurface)),
          ),
        );
      }),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.1,
      children: cells,
    );
  }

  static bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MonthNav extends StatelessWidget {
  final DateTime month;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  static final _hdr = DateFormat('MMMM yyyy');

  const _MonthNav({
    required this.month,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          onPrev != null
              ? IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: onPrev)
              : const SizedBox(width: 48),
          Text(_hdr.format(month),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          onNext != null
              ? IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onNext)
              : const SizedBox(width: 48),
        ],
      );
}

class _Actions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onApply;
  const _Actions({required this.onCancel, required this.onApply});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: onApply, child: const Text('Apply')),
          ],
        ),
      );
}
