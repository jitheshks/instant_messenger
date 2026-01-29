import 'package:flutter/material.dart';

class AccountPickerSheet extends StatelessWidget {
  const AccountPickerSheet({
    super.key,
    required this.currentName,
    required this.currentPhone,
    this.currentAvatarUrl,
    this.onAddAccount,
  });

  final String currentName;
  final String currentPhone;
  final String? currentAvatarUrl;
  final VoidCallback? onAddAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              height: 4, width: 44, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // current account
            ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                backgroundImage: (currentAvatarUrl != null && currentAvatarUrl!.isNotEmpty)
                    ? NetworkImage(currentAvatarUrl!)
                    : null,
                child: (currentAvatarUrl == null || currentAvatarUrl!.isEmpty)
                    ? Icon(Icons.person, color: theme.colorScheme.outline)
                    : null,
              ),
              title: Text(currentName, style: theme.textTheme.titleMedium),
              subtitle: Text(currentPhone, style: theme.textTheme.bodySmall),
              trailing: const Icon(Icons.check_circle, color: Color(0xFF22C55E)),
              onTap: () => Navigator.pop(context, 'current'),
            ),
            const SizedBox(height: 8),
            // add account
            ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.add),
              ),
              title: const Text('Add account'),
              onTap: () {
                Navigator.pop(context, 'add');
                onAddAccount?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}
