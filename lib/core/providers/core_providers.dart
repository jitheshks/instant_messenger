import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:instant_messenger/core/utils/app_info_service.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';

/// Global singleton [SupabaseClient] provider.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  try {
    return Supabase.instance.client;
  } catch (_) {
    final client = SupabaseClient(
      'http://localhost:54321',
      'anon-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    ref.onDispose(() => client.dispose());
    return client;
  }
});

/// Global singleton [AppInfoService] provider.
final appInfoServiceProvider = Provider<AppInfoService>((ref) {
  return AppInfoService();
});

/// Global singleton [ConnectivityService] provider.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});
