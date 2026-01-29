import 'package:flutter/material.dart';
import 'package:instant_messenger/services/user_bootstrap.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';

import 'package:instant_messenger/services/app_bootstrap.dart';
import 'package:instant_messenger/app_router/router_notifier.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final result = context.watch<AppBootstrapResult?>();
    final router = context.read<RouterNotifier>();

    debugPrint('🟡 SPLASH BUILD -----------------------------');
    debugPrint('🟡 result == null → ${result == null}');
    debugPrint('🟡 router.bootstrapped → ${router.bootstrapped}');
    debugPrint('🟡 router.isAuthed → ${router.isAuthed}');
    debugPrint('🟡 router.requiresName → ${router.requiresName}');

    if (result != null) {
      debugPrint('🟡 result.nextRoute → ${result.nextRoute}');
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
