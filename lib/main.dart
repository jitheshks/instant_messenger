import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/controller/chats_tab_controller.dart';
import 'package:instant_messenger/controller/contacts_data_controller.dart';
import 'package:instant_messenger/controller/profile_controller.dart';
import 'package:instant_messenger/services/app_bootstrap.dart';
import 'package:instant_messenger/services/app_info_service.dart';
import 'package:instant_messenger/services/app_lifecycle_service.dart';
import 'package:instant_messenger/services/background_upload_executor.dart';
import 'package:instant_messenger/services/chats_repository.dart';
import 'package:instant_messenger/services/contact_repository.dart';
import 'package:instant_messenger/services/first_launch_service.dart';
import 'package:instant_messenger/services/hive_init.dart';
import 'package:instant_messenger/services/message_cache.dart';
import 'package:instant_messenger/services/permission_service.dart';
import 'package:instant_messenger/services/uploads/cloudinary_foreground_service.dart';
import 'package:instant_messenger/services/uploads/upload_orchestrator.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'app_router/app_router.dart';
import 'app_router/router_notifier.dart';
import 'controller/auth_controller.dart';
import 'controller/login_screen_controller.dart';
import 'controller/notification_controller.dart';
import 'controller/push_controller.dart';
import 'controller/settings_controller.dart';
import 'firebase_options.dart';
import 'services/user_bootstrap.dart';
import 'services/outbox_service.dart';
import 'services/chat_repository.dart';
import 'services/notification_service.dart';
import 'services/onesignal_service.dart';
import 'services/user_service.dart';
import 'services/auth_service.dart';
import 'services/firebase_auth_service.dart';
import 'theme/theme.dart';

// Keep global navigator key used by notification tap routing
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

// Run-once guard for NotificationController.configure
bool _notificationConfigured = false;

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> testDns() async {
  try {
    final result = await InternetAddress.lookup('api.cloudinary.com');
    print('DNS OK: $result');
  } catch (e) {
    print('DNS FAIL: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  
await dotenv.load(fileName: '.env');

// 🔐 SAFETY ASSERTS (fail fast in dev)
assert(
  dotenv.env['CLOUDINARY_CLOUD_NAME']?.isNotEmpty == true,
  'Missing CLOUDINARY_CLOUD_NAME in .env',
);

assert(
  dotenv.env['CLOUDINARY_UPLOAD_PRESET']?.isNotEmpty == true,
  'Missing CLOUDINARY_UPLOAD_PRESET in .env',
);

// ✅ Read once, pass everywhere
final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME']!;
final uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET']!;
  debugPrint('Cloudinary TEST → cloud=$cloudName preset=$uploadPreset');

  final savedMode = await AdaptiveTheme.getThemeMode();

  // 🔍 TEMP DNS TEST
  await testDns();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  // Initialize Hive, register adapters, open boxes (with recovery)
  await HiveInit.initAndOpenBoxes(
    boxesToOpen: ['profile', 'contacts', 'chats_meta'],
    suspectBoxesToDelete: ['chats_meta'], // tune to your app
  );



  AppLifecycleService().register();

  await Workmanager().initialize(callbackDispatcher);

  runApp(
    MyApp(
      savedMode: savedMode,
      cloudName: cloudName,
      uploadPreset: uploadPreset,
    ),
  );
}

class MyApp extends StatelessWidget {
  final AdaptiveThemeMode? savedMode;

  final String cloudName;
  final String uploadPreset;
  const MyApp({
    super.key,
    this.savedMode,
    required this.cloudName,
    required this.uploadPreset,
  });

  @override
  Widget build(BuildContext context) {
    // 🔥 TEMP HARD-CODED (NO ENV)
    const kOneSignalAppId = '70142ddd-32be-40e0-b1ce-97a1b958e3f4';
    const kPushSenderSecret =
        'os_v2_app_oakc3xjsxzaobmoos6q3swhd6qxlfedjwjuebqejybd5ybdmbhxhmpzc2m27sjjosnieywtxwusxkt34qufnlebc2pucmhtq6yp7wbi';

    debugPrint('OneSignal TEST → appId=$kOneSignalAppId');
    debugPrint('Push secret length=${kPushSenderSecret.length}');

    final pair = themedPair(Colors.teal);

    return MultiProvider(
      providers: [
        // 1) RouterNotifier first
       ChangeNotifierProvider<RouterNotifier>(
  create: (_) {
    final g = RouterNotifier();

    FirebaseAuth.instance.authStateChanges().listen((user) {
      g.setAuthed(user != null);

      if (user == null) {
        g.reset(); // 🔥 CRITICAL
      }
    });

    return g;
  },
),

//  User bootstrap (SINGLE INSTANCE FOR WHOLE APP)
Provider<UserBootstrap>(
  create: (_) => UserBootstrap(),
),


        //  Build GoRouter from RouterNotifier; reuse previous instance to avoid churn
        ProxyProvider<RouterNotifier, GoRouter>(
          lazy: false,
          update: (ctx, guard, previous) => previous ?? buildRouter(guard),
        ),

        // 3) App services
        Provider<UserService>(create: (_) => UserService()),

        Provider<AppInfoService>(create: (_) => AppInfoService()),

       
        ChangeNotifierProvider<SettingsController>(
          create: (ctx) =>
              SettingsController(userService: ctx.read<UserService>()),
        ),

        ChangeNotifierProvider<PushController>(
          create: (ctx) => PushController(
            oneSignal: OneSignalService(
              FirebaseFirestore.instance,
              ctx.read<AppInfoService>(), // app info injected here
            ),
            oneSignalAppId: kOneSignalAppId,
            oneSignalRestApiKey: kPushSenderSecret.isEmpty
                ? null
                : kPushSenderSecret,
          ),
        ),
        Provider<AuthService>(
          create: (_) => FirebaseAuthService(FirebaseAuth.instance),
        ),

        ChangeNotifierProvider(
          create: (ctx) => AuthController(ctx.read<RouterNotifier>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => LoginController(
            ctx.read<AuthService>(),
            ctx.read<RouterNotifier>(),
          ),
        ),

        //  Contacts (GLOBAL – required for chat names)
        Provider<ContactsRepository>(create: (_) => ContactsRepository()),

       ChangeNotifierProvider<ContactsDataController>(
  create: (ctx) {
    final c = ContactsDataController(ctx.read<ContactsRepository>());
    c.loadMatchedContacts(); // 🔥 REQUIRED ONE-LINER
    return c;
  },
),



FutureProvider<AppBootstrapResult?>(
  initialData: null,
  create: (ctx) async {
    final router = ctx.read<RouterNotifier>();

    //  Not logged in → nothing to bootstrap
    if (!router.isAuthed) {
      router.setBootstrapped(true);
      return null;
    }

    final user = FirebaseAuth.instance.currentUser!;
    debugPrint('[BOOTSTRAP] start uid=${user.uid}');

    // 1️⃣ Decide route (ONLY PLACE)
final bootstrap = ctx.read<UserBootstrap>();
    final nextRoute = await bootstrap.bootstrap();

    // 2️⃣ READ USER PROFILE ONCE 
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final displayName =
        (userDoc.data()?['display_name'] as String?)?.trim() ?? '';

    debugPrint(
      '[BOOTSTRAP] nextRoute=$nextRoute displayName="$displayName"',
    );

    // 3️⃣ App-level services
    final result = await bootstrapAppServices(
      uid: user.uid,
      cloudName: cloudName,
      uploadPreset: uploadPreset,
      nextRoute: nextRoute,
      displayName: displayName,
    );

    AppLifecycleService().attachOutbox(result.outbox);

    // 4️⃣ First-launch permissions (once)
    final alreadyAsked = await FirstLaunchService.isDone();
    if (!alreadyAsked) {
      await PermissionService.requestFirstLoginPermissions(
        includeMicrophone: true,
        includeContacts: true,
      );
      await PermissionService.ensureNotifications();
      await ctx.read<ContactsDataController>().refreshIfPermitted();
      await FirstLaunchService.markDone();
    }

    // 5️⃣ Unlock router
    router
      ..setRequiresName(nextRoute == NextRoute.editName)
      ..setBootstrapped(true);

    debugPrint('[BOOTSTRAP] completed');

    return result; // ✅ SINGLE SOURCE OF TRUTH
  },
),



        ProxyProvider<AppBootstrapResult?, OutboxService?>(
          update: (_, boot, _) => boot?.outbox,
        ),

// -------------------------
// CLOUDINARY FOREGROUND (UI uploads)
// -------------------------
Provider<CloudinaryForegroundService>(
  create: (_) => CloudinaryForegroundService(
    cloudName: cloudName,
    uploadPreset: uploadPreset,
  ),
),


// UploadOrchestrator 
ProxyProvider<OutboxService?, UploadOrchestrator?>(
  update: (ctx, outbox, previous) {
    if (outbox == null) return null;

    return previous ??
        UploadOrchestrator(
          foreground: ctx.read<CloudinaryForegroundService>(),
          outbox: outbox,
        );
  },
),


//  ProfileController (depends on orchestrator)

ChangeNotifierProxyProvider2<
  AppBootstrapResult?,
  UploadOrchestrator?,
  ProfileController?>(
  create: (_) => null,
  update: (ctx, boot, orchestrator, previous) {
    if (boot == null || orchestrator == null) return null;

    return previous ??
        ProfileController(
          settings: ctx.read<SettingsController>(),
          uploadOrchestrator: orchestrator,
        );
  },
),


        //  Per-user service wiring
        ProxyProvider<AppBootstrapResult?, ChatRepository?>(
          update: (_, boot, _) => boot?.repo,
        ),

       // 🔥 GLOBAL ChatsRepository
Provider<ChatsRepository>(
  create: (_) => ChatsRepository(),
),

// 🔥 GLOBAL MessageCache (from bootstrap)
ProxyProvider<AppBootstrapResult?, MessageCache?>(
  update: (_, boot, _) => boot?.cache,
),

// 🔥 GLOBAL ChatsTabController (SINGLE INSTANCE)
ChangeNotifierProxyProvider2<
  ChatsRepository?,
  MessageCache?,
  ChatsTabController?
>(
  create: (_) => null,
  update: (_, repo, cache, previous) {
    if (repo == null || cache == null) return previous;
    return previous ?? ChatsTabController(repo, cache);
  },
),

      ],

      child: AdaptiveTheme(
        light: pair.light,
        dark: pair.dark,
        initial: savedMode ?? AdaptiveThemeMode.system,
        builder: (theme, darkTheme) => Builder(
          builder: (context) {

            if (!_notificationConfigured) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                NotificationController.configure((chatId) {
                  final nav = rootNavKey.currentState;
                  if (nav == null) return;
                  GoRouter.of(nav.context).push('/chat/$chatId');
                });

                //  SINGLE SOURCE OF PUSH INIT
                context.read<RouterNotifier>().attachPushInit(context);

                _notificationConfigured = true;
              });
            }

            return MaterialApp.router(
              title: 'Instant Messenger',
              debugShowCheckedModeBanner: false,
              theme: theme,
              darkTheme: darkTheme,
              routerConfig: context.read<GoRouter>(),
              localizationsDelegates: const [
                CountryLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
            );
          },
        ),
      ),
    );
  }
}
