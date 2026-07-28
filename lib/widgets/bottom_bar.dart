import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state.dart';
import '../services/fs_service.dart';

/// IDE status bar displaying real-time metrics for the generated context prompt with smooth fade transitions.
class BottomBar extends ConsumerWidget {
  const BottomBar({super.key});

  /// Formats byte count into human-readable memory units (B, KB, MB)
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Formats estimated token count (standard ~4 characters per token heuristic)
  String _formatTokenCount(int charCount) {
    final estimatedTokens = (charCount / 4).round();
    if (estimatedTokens >= 1000) {
      return '~${(estimatedTokens / 1000).toStringAsFixed(1)}k tokens';
    }
    return '~$estimatedTokens tokens';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(promptStatsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(180),
        border: Border(
          top: BorderSide(color: theme.dividerColor.withAlpha(40), width: 1),
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeOut,
        child: statsAsync.when(
          skipLoadingOnReload: true,
          data: (PromptBuildResult? result) {
            if (result == null || result.fileCount == 0) {
              return Row(
                key: const ValueKey('bottom_bar_empty'),
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'No files selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '0 files | 0 lines | 0 B | ~0 tokens',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            }

            final charCount = result.promptText.length;
            final tokenStr = _formatTokenCount(charCount);
            final sizeStr = _formatFileSize(charCount);
            final lineStr = '${result.totalLines} lines';

            return Row(
              key: ValueKey(
                'bottom_bar_stats_${result.fileCount}_${result.skillCount}_${result.totalLines}_$charCount',
              ),
              children: [
                _StatItem(
                  icon: Icons.insert_drive_file_outlined,
                  label: '${result.fileCount} files selected',
                  color: Colors.teal.shade300,
                ),
                const SizedBox(width: 16),
                if (result.skillCount > 0) ...[
                  _StatItem(
                    icon: Icons.psychology_outlined,
                    label: '${result.skillCount} skills',
                    color: Colors.purple.shade300,
                  ),
                  const SizedBox(width: 16),
                ],
                _StatItem(
                  icon: Icons.notes,
                  label: lineStr,
                  color: Colors.blue.shade300,
                ),
                const SizedBox(width: 16),
                _StatItem(
                  icon: Icons.data_usage,
                  label: sizeStr,
                  color: Colors.grey.shade300,
                ),
                const Spacer(),
                _StatItem(
                  icon: Icons.auto_awesome,
                  label: tokenStr,
                  color: Colors.amber.shade300,
                  isBold: true,
                ),
              ],
            );
          },
          loading: () => Row(
            key: const ValueKey('bottom_bar_loading'),
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Calculating prompt metrics...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          error: (error, stack) => Row(
            key: const ValueKey('bottom_bar_error'),
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: colorScheme.error,
              ),
              const SizedBox(width: 6),
              Text(
                'Error calculating metrics',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper component rendering individual metric icons and labels inside the status bar
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.color,
    this.isBold = false,
  });

  final Color color;
  final IconData icon;
  final bool isBold;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
