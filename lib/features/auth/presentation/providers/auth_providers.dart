// lib/features/auth/presentation/providers/auth_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/features/notifications/presentation/providers/notification_providers.dart';
import 'package:instant_messenger/features/auth/data/auth_service.dart';
import 'package:instant_messenger/features/auth/data/supabase_auth_service.dart';
import 'package:instant_messenger/features/auth/presentation/controllers/auth_controller.dart';
import 'package:instant_messenger/features/auth/presentation/controllers/login_notifier.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return SupabaseAuthService();
});

final authStateStreamProvider = StreamProvider<bool>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth.authStateChanges();
});

final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateStreamProvider);
  final auth = ref.watch(authServiceProvider);
  return auth.currentUserId ?? SupabaseConfig.currentUserId;
});

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(
    ref.watch(routerNotifierProvider),
    authService: ref.watch(authServiceProvider),
    pushController: ref.watch(pushControllerProvider),
  );
});

final loginControllerProvider = NotifierProvider<LoginNotifier, LoginState>(
  LoginNotifier.new,
);
