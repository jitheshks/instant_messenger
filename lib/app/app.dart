import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/presentation/providers/notification_providers.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:instant_messenger/app/theme/app_theme.dart';

// Keep global navigator key used by notification tap routing
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

// Run-once guard for NotificationController.configure
bool _notificationConfigured = false;
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class MyApp extends ConsumerWidget {
  final AdaptiveThemeMode? savedMode;

  const MyApp({super.key, this.savedMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    // Eagerly trigger bootstrap observation:
    ref.watch(appBootstrapResultProvider);

    return AdaptiveTheme(
      light: AppTheme.muiLight,
      dark: AppTheme.muiDark,
      initial: savedMode ?? AdaptiveThemeMode.system,
      builder: (theme, darkTheme) => Builder(
        builder: (context) {
          if (!_notificationConfigured) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final coordinator =
                  ref.read(notificationNavigationCoordinatorProvider);
              NotificationController.configureCoordinator(coordinator);

              OneSignalService.resolveContactDelegate = (phone) {
                final contacts =
                    ref.read(contactsDataControllerProvider).cachedMatched;
                return ContactIdentityResolver.resolveIdentity(
                  phoneE164: phone,
                  contacts: contacts,
                  fallback: phone ?? 'New message',
                );
              };

              // SINGLE SOURCE OF PUSH INIT
              ref
                  .read(routerNotifierProvider)
                  .attachPushInit(ref.read(pushControllerProvider));

              _notificationConfigured = true;
            });
          }

          final isDark = theme.brightness == Brightness.dark;

          return mui.Theme(
            data: isDark ? darkTheme : theme,
            child: MaterialApp.router(
              title: 'Instant Messenger',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
              routerConfig: router,
              localizationsDelegates: const [
                CountryLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
            ),
          );
        },
      ),
    );
  }
}
