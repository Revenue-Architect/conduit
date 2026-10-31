import 'dart:async';

import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'package:conduit/core/services/native_sheet_bridge.dart';
import 'package:conduit/l10n/app_localizations.dart';

import '../theme/conduit_input_styles.dart';
import '../theme/theme_extensions.dart';
import 'conduit_components.dart';
import '../../features/hermes/motion/hermez_card_route.dart';
import '../../features/hermes/motion/hermez_card_stack.dart';
import '../../features/hermes/motion/hermez_dialog_card.dart';

/// Centralized helper for building themed dialogs consistently.
///
/// On iOS: delegates to [AdaptiveAlertDialog] for native Cupertino /
/// Liquid Glass chrome.
/// On Android: renders a [AlertDialog] explicitly themed with conduit
/// tokens so button colors, backgrounds, and text match the app palette.
class ThemedDialogs {
  ThemedDialogs._();

  /// Build a base themed dialog body: the one card's content on Android
  /// (shown by [showCustom]), an [AlertDialog] elsewhere.
  static Widget buildBase({
    required BuildContext context,
    required String title,
    Widget? content,
    List<Widget>? actions,
    bool scrollable = false,
  }) {
    final theme = context.conduitTheme;
    return HermezDialogBody(
      backgroundColor: theme.surfaces.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.dialog),
      ),
      titleTextStyle: AppTypography.titleMediumStyle.copyWith(
        color: theme.textPrimary,
      ),
      contentTextStyle: AppTypography.bodyMediumStyle.copyWith(
        color: theme.textSecondary,
      ),
      title: Text(title),
      content: content,
      actions: actions,
      scrollable: scrollable,
    );
  }

  /// Show a simple confirmation dialog with Cancel/Confirm actions.
  ///
  /// On iOS uses [AdaptiveAlertDialog] for native chrome.
  /// On Android renders a fully themed [AlertDialog].
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
    bool isDestructive = false,
    bool barrierDismissible = true,
  }) async {
    final l10n = AppLocalizations.of(context);
    final effectiveConfirmText = confirmText ?? l10n?.confirm ?? 'Confirm';
    final effectiveCancelText = cancelText ?? l10n?.cancel ?? 'Cancel';

    if (PlatformUiCapabilities.usesNativeIOS26 && barrierDismissible) {
      try {
        final result = await NativeSheetBridge.instance.presentSheet(
          rethrowErrors: true,
          root: NativeSheetDetailConfig(
            id: 'confirmation-dialog',
            title: title,
            subtitle: message,
            items: [
              NativeSheetItemConfig(
                id: 'cancel',
                title: effectiveCancelText,
                sfSymbol: 'xmark',
                dismissOnSelect: true,
                actionId: 'cancel',
              ),
              NativeSheetItemConfig(
                id: 'confirm',
                title: effectiveConfirmText,
                sfSymbol: isDestructive ? 'trash' : 'checkmark',
                destructive: isDestructive,
                dismissOnSelect: true,
                actionId: 'confirm',
              ),
            ],
          ),
        );
        return result?.actionId == 'confirm';
      } catch (_) {
        // Fall through to the Flutter Cupertino dialog when the bridge fails.
      }
      if (!context.mounted) return false;
    }

    if (PlatformUiCapabilities.isIOS) {
      final completer = Completer<bool>();
      await AdaptiveAlertDialog.show(
        context: context,
        title: title,
        message: message,
        actions: [
          AlertAction(
            title: effectiveCancelText,
            onPressed: () {
              if (!completer.isCompleted) completer.complete(false);
            },
            style: AlertActionStyle.cancel,
          ),
          AlertAction(
            title: effectiveConfirmText,
            onPressed: () {
              if (!completer.isCompleted) completer.complete(true);
            },
            style: isDestructive
                ? AlertActionStyle.destructive
                : AlertActionStyle.primary,
          ),
        ],
      );
      if (!completer.isCompleted) completer.complete(false);
      return completer.future;
    }

    // Android: one card grown out of the control that asked
    // (docs/app-design-2026-10-30, "One card"). Closing never confirms.
    // barrierDismissible false is the must-answer card, through showCustom.
    if (barrierDismissible) {
      return confirmHermezCard(
        context,
        title: title,
        body: message,
        confirmLabel: effectiveConfirmText,
        cancelLabel: effectiveCancelText,
        destructive: isDestructive,
        fromIsControl: false,
      );
    }
    final result = await showCustom<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = ctx.conduitTheme;
        return buildBase(
          context: ctx,
          title: title,
          content: Text(
            message,
            style: AppTypography.bodyMediumStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
          actions: [
            ConduitTextButton(
              text: effectiveCancelText,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            ConduitTextButton(
              text: effectiveConfirmText,
              onPressed: () => Navigator.of(ctx).pop(true),
              isDestructive: isDestructive,
              isPrimary: !isDestructive,
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  /// Show a generic themed dialog with arbitrary widget content.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    // Android: the same title, content and actions as one card.
    if (!PlatformUiCapabilities.isIOS && barrierDismissible) {
      return pushHermezCard<T>(
        context,
        semanticLabel: title,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
          child: HermezCardStack(
            root: HermezCardView(
              title: title,
              builder: (_) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    content,
                    if (actions != null && actions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        children: actions,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return showCustom<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => buildBase(
        context: ctx,
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }

  /// Show custom dialog content through the shared dialog route defaults.
  static Future<T?> showCustom<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    return showHermezDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  /// Text input dialog used for rename/create flows.
  ///
  /// On iOS uses [AdaptiveAlertDialog.inputShow] for native chrome.
  /// On Android renders a fully themed [AlertDialog] with [TextField].
  static Future<String?> promptTextInput(
    BuildContext context, {
    required String title,
    required String hintText,
    String? initialValue,
    String? confirmText,
    String? cancelText,
    bool barrierDismissible = true,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    int? maxLength,
  }) async {
    final l10n = AppLocalizations.of(context);
    final effectiveConfirmText = confirmText ?? l10n?.save ?? 'Save';
    final effectiveCancelText = cancelText ?? l10n?.cancel ?? 'Cancel';

    final nativeEditorPreservesInputConfiguration =
        keyboardType == null &&
        textCapitalization == TextCapitalization.sentences &&
        (maxLength == null || maxLength == TextField.noMaxLength);
    if (PlatformUiCapabilities.usesNativeIOS26 &&
        nativeEditorPreservesInputConfiguration) {
      try {
        final result = await NativeSheetBridge.instance.presentTextEditor(
          title: title,
          value: initialValue ?? '',
          placeholder: hintText,
          sendLabel: effectiveConfirmText,
          valueId: 'text',
          sendActionId: 'confirm',
          closeActionId: 'cancel',
          rethrowErrors: true,
        );
        if (result?.actionId != 'confirm') return null;
        final value = result?.values['text'];
        if (value is! String) return null;
        final bounded = maxLength == null || maxLength == TextField.noMaxLength
            ? value
            : value.characters.take(maxLength).toString();
        final trimmed = bounded.trim();
        if (trimmed.isEmpty) return null;
        if (initialValue != null && trimmed == initialValue.trim()) return null;
        return trimmed;
      } catch (_) {
        // Fall through to the Flutter Cupertino dialog when the bridge fails.
      }
      if (!context.mounted) return null;
    }

    if (PlatformUiCapabilities.isIOS) {
      final result = await AdaptiveAlertDialog.inputShow(
        context: context,
        title: title,
        actions: [
          AlertAction(
            title: effectiveCancelText,
            onPressed: () {},
            style: AlertActionStyle.cancel,
          ),
          AlertAction(
            title: effectiveConfirmText,
            onPressed: () {},
            style: AlertActionStyle.primary,
          ),
        ],
        input: AdaptiveAlertDialogInput(
          placeholder: hintText,
          initialValue: initialValue,
          keyboardType: keyboardType,
          maxLength: maxLength,
        ),
      );
      if (result == null) return null;
      final trimmed = result.trim();
      if (trimmed.isEmpty) return null;
      if (initialValue != null && trimmed == initialValue.trim()) return null;
      return trimmed;
    }

    // Android: a one-card prompt (it trims and drops unchanged text itself).
    if (barrierDismissible) {
      return promptHermezCard(
        context,
        title: title,
        hintText: hintText,
        initialValue: initialValue,
        confirmLabel: effectiveConfirmText,
        cancelLabel: effectiveCancelText,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        maxLength: maxLength,
      );
    }
    final result = await showCustom<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TextInputDialogContent(
        title: title,
        hintText: hintText,
        initialValue: initialValue,
        confirmText: effectiveConfirmText,
        cancelText: effectiveCancelText,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        maxLength: maxLength,
      ),
    );
    if (result == null) return null;
    final trimmed = result.trim();
    if (trimmed.isEmpty) return null;
    if (initialValue != null && trimmed == initialValue.trim()) return null;
    return trimmed;
  }
}

/// Material text-input dialog that owns its own [TextEditingController].
///
/// This prevents the "used after being disposed" error that occurs when a
/// controller is disposed while the dialog dismiss animation is still running.
class _TextInputDialogContent extends StatefulWidget {
  const _TextInputDialogContent({
    required this.title,
    required this.hintText,
    required this.confirmText,
    required this.cancelText,
    this.initialValue,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLength,
  });

  final String title;
  final String hintText;
  final String confirmText;
  final String cancelText;
  final String? initialValue;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;

  @override
  State<_TextInputDialogContent> createState() =>
      _TextInputDialogContentState();
}

class _TextInputDialogContentState extends State<_TextInputDialogContent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    return ThemedDialogs.buildBase(
      context: context,
      title: widget.title,
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.textCapitalization,
        maxLength: widget.maxLength,
        style: AppTypography.bodyMediumStyle.copyWith(color: theme.textPrimary),
        decoration: context.conduitInputStyles
            .underline(hint: widget.hintText)
            .copyWith(
              counterStyle: AppTypography.labelSmallStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
      ),
      actions: [
        ConduitTextButton(
          text: widget.cancelText,
          onPressed: () => Navigator.of(context).pop(null),
        ),
        ConduitTextButton(
          text: widget.confirmText,
          onPressed: () => Navigator.of(context).pop(_controller.text),
          isPrimary: true,
        ),
      ],
    );
  }
}
