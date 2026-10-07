import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A write-only input for an API key or other secret (R21, KTD8).
///
/// - The text is hidden by default, with a toggle to show it while the owner
///   checks what they typed or pasted.
/// - Whitespace is dropped as it arrives, so a pasted key with a trailing
///   newline or a stray space is stored as the key it was meant to be.
/// - The keyboard is told not to suggest, autocorrect, auto-fill or learn from
///   what is typed (Android and iOS keyboards otherwise keep a dictionary of
///   it).
///
/// The page owns [controller] and clears it once the key is saved. The field
/// itself never keeps, logs or echoes the value.
class HermesSecretField extends StatefulWidget {
  const HermesSecretField({
    super.key,
    required this.controller,
    this.label = 'API key',
    this.hintText,
    this.enabled = true,
    this.errorText,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool enabled;
  final String? errorText;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// [raw] as it should be stored: no whitespace anywhere.
  static String normalize(String raw) => raw.replaceAll(_whitespace, '');

  static final RegExp _whitespace = RegExp(r'\s');

  @override
  State<HermesSecretField> createState() => _HermesSecretFieldState();
}

class _HermesSecretFieldState extends State<HermesSecretField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: !_visible,
      obscuringCharacter: '•',
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      maxLines: 1,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      // Nothing about what is typed here is suggested, corrected, filled in
      // or learnt by the keyboard.
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      autofillHints: null,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        errorText: widget.errorText,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          key: const ValueKey('secret-field-toggle'),
          tooltip: _visible ? 'Hide key' : 'Show key',
          onPressed: widget.enabled
              ? () => setState(() => _visible = !_visible)
              : null,
          icon: Icon(
            _visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }
}
