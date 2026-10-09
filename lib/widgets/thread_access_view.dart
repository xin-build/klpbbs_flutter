import 'package:flutter/material.dart';

import '../core/discuz_thread_access.dart';

/// A server restriction is a page state, with no author or post actions.
class ThreadAccessView extends StatelessWidget {
  final DiscuzThreadAccessException access;
  final VoidCallback onRetry;
  final VoidCallback? onBackToForum;
  final VoidCallback? onLogin;

  const ThreadAccessView({
    super.key,
    required this.access,
    required this.onRetry,
    this.onBackToForum,
    this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = switch (access.kind) {
      DiscuzThreadAccessKind.authorOnly => Icons.lock_person_outlined,
      DiscuzThreadAccessKind.loginRequired => Icons.login_rounded,
      DiscuzThreadAccessKind.passwordRequired => Icons.lock_outline_rounded,
      DiscuzThreadAccessKind.underReview => Icons.hourglass_top_rounded,
      DiscuzThreadAccessKind.notFound => Icons.article_outlined,
      _ => Icons.visibility_off_outlined,
    };
    return Center(
      key: const ValueKey('thread-access-state'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child:
                      Icon(icon, size: 40, color: scheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(height: 24),
              Text(access.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              SelectableText(access.message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.6)),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (onBackToForum != null)
                    OutlinedButton.icon(
                        onPressed: onBackToForum,
                        icon: const Icon(Icons.forum_outlined, size: 18),
                        label: const Text('返回板块')),
                  if (onLogin != null)
                    FilledButton.icon(
                        onPressed: onLogin,
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('登录')),
                  FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重新检查')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
