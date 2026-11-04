import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:lottie/lottie.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrapAsync = ref.watch(appBootstrapResultProvider);
    final result = bootstrapAsync.value;
    final router = ref.read(routerNotifierProvider);

    debugPrint('🟡 SPLASH BUILD -----------------------------');
    debugPrint('🟡 result == null → ${result == null}');
    debugPrint('🟡 router.bootstrapped → ${router.bootstrapped}');
    debugPrint('🟡 router.isAuthed → ${router.isAuthed}');
    debugPrint('🟡 router.requiresName → ${router.requiresName}');

    if (result != null) {
      debugPrint('🟡 result.nextRoute → ${result.nextRoute}');
    }

    if (bootstrapAsync.hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'Initialization Notice',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not connect to services. Check your connection or retry.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.refresh(appBootstrapResultProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ⛔ Still bootstrapping
    if (result == null) {
      debugPrint('⏳ SPLASH: waiting for AppBootstrapResult');
      return _SplashUI();
    }

    // ✅ Unlock router ONCE (idempotent)
    if (!router.bootstrapped) {
      debugPrint('🔓 SPLASH: unlocking router');

      Future.microtask(() {
        debugPrint('🔓 SPLASH MICROTASK: setBootstrapped(true)');
        router.setBootstrapped(true);

        final needName = result.nextRoute == NextRoute.editName;
        debugPrint('🔓 SPLASH MICROTASK: setRequiresName($needName)');
        router.setRequiresName(needName);
      });
    } else {
      debugPrint('✅ SPLASH: router already bootstrapped');
    }

    return _SplashUI();
  }
}

/// 🎨 PURE UI — NO LOGIC
class _SplashUI extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🔥 Lottie logo
            Lottie.asset(
              'assets/lottie/splash_logo.json',
              width: 160,
              height: 160,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 24),

            // Optional app name / tagline
            Text(
              'Instant Messenger',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 12),

            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
