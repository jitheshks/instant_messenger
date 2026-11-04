// lib/features/settings/presentation/providers/settings_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/settings/presentation/controllers/settings_notifier.dart';

final settingsControllerProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
