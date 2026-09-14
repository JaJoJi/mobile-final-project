import 'package:flutter/material.dart';

/// The shared text input — design spec §3.3.
///
/// * Floating `labelText` always (**[MUST]** a placeholder is not a label).
/// * Validate on submit / blur — not per keystroke (see [validator] +
///   [AutovalidateMode.onUserInteraction] is deliberately NOT the default).
/// * Password fields ship a visibility toggle when [obscureText] is set.
/// * **[MUST]** callers pass `keyboardType` / `textInputAction` /
///   `autofillHints`.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.helperText,
    this.errorText,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onFieldSubmitted,
    this.onChanged,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final String? helperText;
  final String? errorText;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    Widget? suffix = widget.suffixIcon;
    if (widget.obscureText) {
      suffix = IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(_obscured ? Icons.visibility_off : Icons.visibility),
        tooltip: _obscured ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }

    return TextFormField(
      controller: widget.controller,
      obscureText: _obscured,
      enabled: widget.enabled,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        errorText: widget.errorText,
        prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
        suffixIcon: suffix,
      ),
    );
  }
}
