// lib/view/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../controller/settings_controller.dart';
import '../../widgets/header_tile.dart';
import '../../widgets/account_picker_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {


  // ✅ SAFE: run AFTER first frame
  WidgetsBinding.instance.addPostFrameCallback((_) {
    context.read<SettingsController>().start();
  });

    final c = context.watch<SettingsController>();
    final dividerPad = const SizedBox(height: 8);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: const [Icon(Icons.search)],
      ),
      body: ListView(
        children: [
        // In SettingsScreen, change the HeaderTile call to:
Row(
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
      icon: const Icon(Icons.add_circle_outline, color: Color(0xFF25D366)),
      tooltip: 'Add',
      onPressed: () async {
        await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          clipBehavior: Clip.antiAlias,
          builder: (_) => AccountPickerSheet(
            currentName: c.displayName,
            currentPhone: '+91 96459 05577',
            currentAvatarUrl: c.avatarUrl,
            onAddAccount: () {},
          ),
        );
      },
    ),
    const SizedBox(width: 12), // right edge padding
  ],
),


          const Divider(height: 0),
          _settingsTile(context, icon: Icons.vpn_key_outlined, title: 'Account', subtitle: 'Security notifications, change number'),
          _settingsTile(context, icon: Icons.lock_outline, title: 'Privacy', subtitle: 'Block contacts, disappearing messages'),
          dividerPad,
          _settingsTile(context, icon: Icons.account_circle_outlined, title: 'Avatar', subtitle: 'Create, edit, profile photo'),
          _settingsTile(context, icon: Icons.list_alt_outlined, title: 'Lists', subtitle: 'Manage people and groups'),
          _settingsTile(context, icon: Icons.chat_bubble_outline, title: 'Chats', subtitle: 'Theme, wallpapers, chat history'),
          _settingsTile(context, icon: Icons.notifications_none, title: 'Notifications', subtitle: 'Message, group & call tones'),
          _settingsTile(context, icon: Icons.cloud_outlined, title: 'Storage and data', subtitle: 'Network usage, auto-download'),
          _settingsTile(context, icon: Icons.accessibility_new, title: 'Accessibility', subtitle: 'Increase contrast, animation'),
          _settingsTile(context, icon: Icons.language, title: 'App language', subtitle: c.appLanguage),
          _settingsTile(context, icon: Icons.help_outline, title: 'Help', subtitle: 'Help centre, contact us, privacy policy'),
          _settingsTile(context, icon: Icons.person_add_alt, title: 'Invite a friend'),
          _settingsTile(context, icon: Icons.system_update_alt, title: 'App updates'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Also from Meta', style: Theme.of(context).textTheme.labelSmall),
          ),
          _settingsTile(context, icon: Icons.bubble_chart_outlined, title: 'Meta AI app'),
          _settingsTile(context, icon: Icons.camera_alt_outlined, title: 'Instagram'),
          _settingsTile(context, icon: Icons.facebook, title: 'Facebook'),
          _settingsTile(context, icon: Icons.message_outlined, title: 'Threads'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _settingsTile(BuildContext context, {required IconData icon, required String title, String? subtitle, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
