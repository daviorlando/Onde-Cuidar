import 'package:flutter/material.dart';

enum Tone { info, attention, error }

/// Cartão com fundo `*Container` e todo o conteúdo em `on*Container`, para
/// manter contraste nos temas claro e escuro.
class ToneCard extends StatelessWidget {
  const ToneCard({
    required this.tone,
    required this.child,
    this.margin,
    super.key,
  });

  final Tone tone;
  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      Tone.info => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      Tone.attention => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      Tone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Card(
      color: background,
      margin: margin,
      child: Theme(
        data: theme.copyWith(
          iconTheme: theme.iconTheme.copyWith(color: foreground),
          listTileTheme: theme.listTileTheme.copyWith(
            textColor: foreground,
            iconColor: foreground,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: foreground,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: child,
          ),
        ),
      ),
    );
  }
}
