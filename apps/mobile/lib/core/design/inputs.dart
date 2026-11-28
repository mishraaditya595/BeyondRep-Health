import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'beyondrep_theme.dart';

/// The only text input for BeyondRep screens, dialogs and sheets. Look comes
/// from `BeyondRepTheme` (filled, rounded, accent focus ring); do not restyle
/// per screen and do not use a raw `TextField`/`TextFormField` in features.
class NsTextField extends StatelessWidget {
  const NsTextField({
    this.controller,
    this.label,
    this.hint,
    this.initialValue,
    this.enabled = true,
    this.autofocus = false,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.prefixIcon,
    this.dense = false,
    this.textAlign = TextAlign.start,
    this.autofillHints,
    this.autocorrect = true,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextAlign textAlign;

  /// Tighter padding for fields sharing a row (e.g. reps / weight / unit).
  final bool dense;
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? initialValue;
  final bool enabled;
  final bool autofocus;
  final int? maxLength;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final Iterable<String>? autofillHints;
  final bool autocorrect;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
          : null,
    );
    if (initialValue != null && controller == null) {
      return TextFormField(
        initialValue: initialValue,
        enabled: enabled,
        autofocus: autofocus,
        maxLength: maxLength,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        textAlign: textAlign,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        autocorrect: autocorrect,
        decoration: decoration,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
      );
    }
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textAlign: textAlign,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      autocorrect: autocorrect,
      decoration: decoration,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// A choice in an [NsDropdown].
class NsOption<T> {
  const NsOption(this.value, this.label);
  final T value;
  final String label;
}

/// The only single-choice select. Same field look as [NsTextField].
class NsDropdown<T> extends StatelessWidget {
  const NsDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.dense = false,
    super.key,
  });

  /// Tighter padding for fields sharing a row.
  final bool dense;
  final T value;
  final List<NsOption<T>> options;

  /// Null disables the control.
  final ValueChanged<T>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
      dropdownColor: scheme.surface,
      icon: const Icon(Icons.expand_more),
      decoration: InputDecoration(
        labelText: label,
        contentPadding: dense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
            : null,
      ),
      items: [
        for (final option in options)
          DropdownMenuItem<T>(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (next) {
              if (next != null) onChanged!(next);
            },
    );
  }
}

/// Selectable pill (period filters, unit toggles, "custom only"). Styling is
/// the theme's `chipTheme`.
class NsChip extends StatelessWidget {
  const NsChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: onSelected,
  );
}

/// Square check control for logging a row (set done, task done). Filled when
/// [checked]; always the same size so rows line up.
class NsCheckButton extends StatelessWidget {
  const NsCheckButton({
    required this.checked,
    required this.onPressed,
    required this.tooltip,
    super.key,
  });

  final bool checked;

  /// Null disables the control.
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        checked: checked,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: Material(
          color: checked
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.check,
                color: checked
                    ? scheme.onPrimary
                    : scheme.onSurface.withValues(
                        alpha: onPressed == null ? .25 : .55,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label (with optional subtitle) and a switch, the only on/off setting row
/// for features: the whole row is the touch target (at least 48 dp) and reads
/// as one switch to screen readers. Look comes from the theme's
/// `switchTheme`; a null [onChanged] disables it.
class NsSwitchRow extends StatelessWidget {
  const NsSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted =
        theme.extension<BeyondRepColors>()?.muted ??
        theme.colorScheme.onSurfaceVariant;
    final enabled = onChanged != null;
    return Semantics(
      container: true,
      toggled: value,
      enabled: enabled,
      label: [label, ?subtitle].join('. '),
      onTap: enabled ? () => onChanged!(!value) : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Switch(value: value, onChanged: onChanged),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
