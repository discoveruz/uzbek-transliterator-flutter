import 'package:flutter/material.dart';
import 'package:yangi_alifbo/engine.dart';
import 'package:yangi_alifbo/limit.dart';

/// What the converter does with the files it is given: which scripts convert, and whether a workbook converts only some
/// of its sheets and columns. Each file is converted with the choices made when its turn comes.
class ConvertOptions extends StatefulWidget {
  const ConvertOptions({
    super.key,
    required this.options,
    required this.limit,
    required this.onOptions,
    required this.onLimit,
  });

  final Options options;
  final WorkbookLimit limit;
  final ValueChanged<Options> onOptions;

  /// Called with each limit the fields read as; columns that are not letters are not passed on.
  final ValueChanged<WorkbookLimit> onLimit;

  @override
  State<ConvertOptions> createState() => _ConvertOptionsState();
}

class _ConvertOptionsState extends State<ConvertOptions> {
  // The fields start from the kept limit and then hold what is typed, which is kept only once it reads as a limit.
  late final _columns = TextEditingController(text: formatColumns(widget.limit.columns));
  late final _sheets = TextEditingController(text: formatSheets(widget.limit.sheets));
  bool _columnsInvalid = false;

  @override
  void dispose() {
    _columns.dispose();
    _sheets.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final options = widget.options;
    final limit = widget.limit;
    final label = text.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final columns = TextField(
      controller: _columns,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: 'Columns',
        hintText: 'Every column',
        helperText: 'Letters, such as B, D-E',
        errorText: _columnsInvalid ? 'Write columns as letters, such as B, D-E' : null,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (typed) {
        final runs = parseColumns(typed);
        setState(() => _columnsInvalid = runs == null);
        if (runs != null) widget.onLimit(limit.copyWith(columns: runs));
      },
    );
    final sheets = TextField(
      controller: _sheets,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(
        labelText: 'Sheets',
        hintText: 'Every sheet',
        helperText: 'Names, separated by commas',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (typed) => widget.onLimit(limit.copyWith(sheets: parseSheets(typed))),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Convert', style: label),
            const SizedBox(height: 10),
            // The script that is on alone cannot be turned off, or nothing would convert.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ScriptChip(
                  name: 'Old Latin',
                  letters: 'Oʻ Gʻ Sh Ch',
                  selected: options.oldLatin,
                  onSelected: options.oldLatin && !options.cyrillic
                      ? null
                      : (on) => widget.onOptions(Options(oldLatin: on, cyrillic: options.cyrillic)),
                ),
                _ScriptChip(
                  name: 'Cyrillic',
                  letters: 'Ў Ғ Ш Ч',
                  selected: options.cyrillic,
                  onSelected: options.cyrillic && !options.oldLatin
                      ? null
                      : (on) => widget.onOptions(Options(oldLatin: options.oldLatin, cyrillic: on)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Excel workbooks', style: label),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only some sheets and columns'),
              value: limit.on,
              onChanged: (on) => widget.onLimit(limit.copyWith(on: on)),
            ),
            if (limit.on) ...[
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 480
                    ? Column(children: [columns, const SizedBox(height: 16), sheets])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: columns),
                          const SizedBox(width: 12),
                          Expanded(child: sheets),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                'Only .xlsx workbooks can be limited. Word files always convert whole.',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// A script and its old letters, on or off.
class _ScriptChip extends StatelessWidget {
  const _ScriptChip({required this.name, required this.letters, required this.selected, required this.onSelected});

  final String name;
  final String letters;
  final bool selected;

  /// Null while it is the only script on, which keeps it on.
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text.rich(
        TextSpan(
          text: name,
          children: [
            TextSpan(
              text: '   $letters',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      selected: selected,
      onSelected: onSelected,
    );
  }
}
