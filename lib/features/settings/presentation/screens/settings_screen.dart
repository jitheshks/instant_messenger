import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/features/settings/presentation/providers/settings_providers.dart';
import 'package:instant_messenger/shared/widgets/tiles/header_tile.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/account_picker_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsControllerProvider.notifier).start();
    });

    final c = ref.watch(settingsControllerProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Profile Header Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? cs.surfaceContainer : cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? cs.outlineVariant : cs.outlineVariant.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: HeaderTile(
                      displayName: c.displayName,
                      bio: c.bio,
                      avatarUrl: c.avatarUrl,
                      useListTile: false,
                      radius: 28,
                      onTap: () => context.push('/profile'),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: cs.primary,
                    ),
                    tooltip: 'Add account',
                    onPressed: () async {
                      await showModalBottomSheet<String>(
                        context: context,
                        useSafeArea: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        builder: (_) => AccountPickerSheet(
                          currentName: c.displayName,
                          currentPhone: c.phoneE164.isNotEmpty
                              ? c.phoneE164
                              : 'No phone number',
                          currentAvatarUrl: c.avatarUrl,
                          onAddAccount: () {},
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          _sectionHeader(context, 'Personal & Security'),
          _settingsTile(
            context,
            icon: Icons.shield_outlined,
            title: 'Account & Security',
            subtitle: 'Security notifications, two-step verification',
          ),
          _settingsTile(
            context,
            icon: Icons.lock_outline,
            title: 'Privacy',
            subtitle: 'Block contacts, read receipts, disappearing messages',
          ),

          const SizedBox(height: 16),
          _sectionHeader(context, 'Preferences'),
          _settingsTile(
            context,
            icon: Icons.palette_outlined,
            title: 'Appearance & Theme',
            subtitle: 'Theme mode, chat wallpaper, font scaling',
            onTap: () => _showThemeDialog(context),
          ),
          _settingsTile(
            context,
            icon: Icons.notifications_none_outlined,
            title: 'Notifications',
            subtitle: 'Message tones, group alerts, call rings',
          ),
          _settingsTile(
            context,
            icon: Icons.language_outlined,
            title: 'App Language',
            subtitle: c.appLanguage,
          ),

          const SizedBox(height: 16),
          _sectionHeader(context, 'Data & Storage'),
          _settingsTile(
            context,
            icon: Icons.cloud_outlined,
            title: 'Storage and Data',
            subtitle: 'Network usage, auto-download preferences',
          ),
          _settingsTile(
            context,
            icon: Icons.accessibility_new_outlined,
            title: 'Accessibility',
            subtitle: 'High contrast, reduced animations',
          ),

          const SizedBox(height: 16),
          _sectionHeader(context, 'Support & About'),
          _settingsTile(
            context,
            icon: Icons.help_outline,
            title: 'Help Center',
            subtitle: 'FAQ, contact support, privacy policy',
          ),
          _settingsTile(
            context,
            icon: Icons.share_outlined,
            title: 'Invite Friends',
            subtitle: 'Share Instant Messenger with colleagues',
          ),
          _settingsTile(
            context,
            icon: Icons.info_outline,
            title: 'About Instant Messenger',
            subtitle: 'Version 2.0.0 • Modern Secure Messaging',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _showThemeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final currentMode = AdaptiveTheme.of(context).mode;
        return AlertDialog(
          title: const Text('Appearance'),
          content: RadioGroup<AdaptiveThemeMode>(
            groupValue: currentMode,
            onChanged: (mode) {
              if (mode == AdaptiveThemeMode.system) {
                AdaptiveTheme.of(context).setSystem();
              } else if (mode == AdaptiveThemeMode.light) {
                AdaptiveTheme.of(context).setLight();
              } else if (mode == AdaptiveThemeMode.dark) {
                AdaptiveTheme.of(context).setDark();
              }
              Navigator.pop(ctx);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<AdaptiveThemeMode>(
                  title: const Text('System default'),
                  subtitle: const Text('Match system brightness'),
                  value: AdaptiveThemeMode.system,
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
                RadioListTile<AdaptiveThemeMode>(
                  title: const Text('Light mode'),
                  subtitle: const Text('Crisp Alabaster & Royal Iris'),
                  value: AdaptiveThemeMode.light,
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
                RadioListTile<AdaptiveThemeMode>(
                  title: const Text('Dark mode'),
                  subtitle: const Text('Midnight Obsidian & Radiant Iris'),
                  value: AdaptiveThemeMode.dark,
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _settingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cs.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
      onTap: onTap,
      visualDensity: const VisualDensity(vertical: 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}
