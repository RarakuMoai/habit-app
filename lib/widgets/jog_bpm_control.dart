import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import 'hold_repeat_button.dart';

/// Called from the stable ExerciseTimer state, which survives header/summary
/// layout changes when a native keyboard reduces the available panel height.
Future<int?> showJogBpmEditor(
  BuildContext context, {
  required int value,
  required Color color,
}) => showDialog<int>(
  context: context,
  builder: (_) => _BpmEditor(value: value, color: color),
);

/// Uses the timer's existing header row; no extra row in the action column.
/// Values remain owned by ExerciseTimer, including live playback and persistence.
class JogBpmControl extends StatelessWidget {
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  final VoidCallback onEdit;

  const JogBpmControl({
    super.key,
    required this.value,
    required this.color,
    required this.onChanged,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget step(String id, IconData icon, String label, VoidCallback? onTap) =>
        Semantics(
          label: label,
          button: true,
          enabled: onTap != null,
          onTap: onTap,
          child: HoldRepeatButton(
            key: ValueKey('jog-bpm-$id'),
            onTrigger: onTap,
            child: SizedBox.square(
              dimension: 44,
              child: Icon(
                icon,
                size: 18,
                color: onTap == null ? AppInk.faint : color,
              ),
            ),
          ),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 196),
      child: SizedBox(
        key: const ValueKey('jog-bpm-control'),
        height: 44,
        child: Material(
          color: color.withValues(alpha: 0.06),
          shape: StadiumBorder(
            side: BorderSide(color: color.withValues(alpha: 0.18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                step(
                  'slower',
                  Icons.remove_rounded,
                  l10n.metroSlower,
                  value > 30 ? () => onChanged(value - 1) : null,
                ),
                Expanded(
                  child: Semantics(
                    label: l10n.bpmLabel,
                    value: '$value BPM',
                    button: true,
                    child: InkWell(
                      key: const ValueKey('jog-bpm-edit'),
                      onTap: onEdit,
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: ExcludeSemantics(
                            child: box.maxWidth < 176
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$value',
                                        style: TextStyle(
                                          fontSize: 16,
                                          height: 1.1,
                                          fontWeight: FontWeight.w800,
                                          color: color,
                                        ),
                                      ),
                                      Text(
                                        'BPM',
                                        style: TextStyle(
                                          fontSize: 9,
                                          height: 1.1,
                                          fontWeight: FontWeight.w700,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text.rich(
                                    TextSpan(
                                      text: '$value',
                                      children: const [
                                        TextSpan(
                                          text: ' BPM',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 16,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800,
                                      color: color,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                step(
                  'faster',
                  Icons.add_rounded,
                  l10n.metroFaster,
                  value < 240 ? () => onChanged(value + 1) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BpmEditor extends StatefulWidget {
  final int value;
  final Color color;
  const _BpmEditor({required this.value, required this.color});
  @override
  State<_BpmEditor> createState() => _BpmEditorState();
}

class _BpmEditorState extends State<_BpmEditor> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: '${widget.value}')
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: '${widget.value}'.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, int.parse(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.bpmLabel),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.bpmSub, style: const TextStyle(color: AppInk.soft)),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('jog-bpm-input'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: widget.color,
              ),
              decoration: const InputDecoration(
                suffixText: 'BPM',
                helperText: '30–240 BPM',
              ),
              validator: (text) {
                final value = int.tryParse(text ?? '');
                return value == null || value < 30 || value > 240
                    ? l10n.valRangeWithUnit(30, 240, 'BPM')
                    : null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('jog-bpm-save'),
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: widget.color),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
