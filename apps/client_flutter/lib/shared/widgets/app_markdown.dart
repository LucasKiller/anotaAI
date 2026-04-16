import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class AppMarkdown extends StatelessWidget {
  const AppMarkdown({
    super.key,
    required this.data,
    this.dark = false,
  });

  final String data;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final baseTextColor =
        dark ? const Color(0xFFF3F6FB) : const Color(0xFF1B1F26);
    final mutedTextColor =
        dark ? const Color(0xFFA8B1BF) : const Color(0xFF5F6673);
    final accentColor =
        dark ? const Color(0xFF7DB0FF) : const Color(0xFF1B67F8);

    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
          color: baseTextColor,
          fontSize: 15,
          height: 1.6,
        ) ??
        TextStyle(
          color: baseTextColor,
          fontSize: 15,
          height: 1.6,
        );

    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        a: baseStyle.copyWith(
          color: accentColor,
          decoration: TextDecoration.underline,
          decorationColor: accentColor.withValues(alpha: 0.7),
        ),
        strong: baseStyle.copyWith(
          fontWeight: FontWeight.w700,
          color: baseTextColor,
        ),
        em: baseStyle.copyWith(
          fontStyle: FontStyle.italic,
        ),
        h1: theme.textTheme.headlineSmall?.copyWith(
              color: baseTextColor,
              fontWeight: FontWeight.w700,
            ) ??
            baseStyle.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
        h2: theme.textTheme.titleLarge?.copyWith(
              color: baseTextColor,
              fontWeight: FontWeight.w700,
            ) ??
            baseStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
        h3: theme.textTheme.titleMedium?.copyWith(
              color: baseTextColor,
              fontWeight: FontWeight.w700,
            ) ??
            baseStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        listBullet: baseStyle.copyWith(
          color: baseTextColor,
          fontWeight: FontWeight.w700,
        ),
        blockquote: baseStyle.copyWith(
          color: mutedTextColor,
          fontStyle: FontStyle.italic,
          height: 1.7,
        ),
        blockquoteDecoration: BoxDecoration(
          color:
              dark ? const Color(0xFF1E232C) : const Color(0xFFF4F7FB),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: accentColor,
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        code: baseStyle.copyWith(
          fontFamily: 'monospace',
          fontSize: 13.5,
          height: 1.5,
          color: dark ? const Color(0xFFF8E39A) : const Color(0xFF5F3E00),
        ),
        codeblockDecoration: BoxDecoration(
          color:
              dark ? const Color(0xFF0F1319) : const Color(0xFFF6F8FC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: dark ? const Color(0xFF272D38) : const Color(0xFFD9E0EC),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(14),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: dark ? const Color(0xFF2B313A) : const Color(0xFFDCE3EF),
            ),
          ),
        ),
      ),
    );
  }
}
