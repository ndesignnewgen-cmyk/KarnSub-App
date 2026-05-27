import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/project_provider.dart';
import 'screens/home_screen.dart';
import 'services/custom_font_service.dart';
import 'services/firebase_service.dart';
import 'services/subscription_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bring up Firebase (no-op / local-only if not configured yet).
  await FirebaseService.init();
  // If a user is already signed in, refresh their PRO status from the cloud.
  await SubscriptionService.syncOnLaunch();
  // Register user-imported fonts so they're ready for the editor preview.
  await CustomFontService.init();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const SubtitleApp());
}

class SubtitleApp extends StatelessWidget {
  const SubtitleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
      ],
      child: MaterialApp(
        title: 'KarnSub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        // Lock the UI text size so it looks identical on every device,
        // regardless of the user's system font-size setting (which is what
        // makes the layout look oversized / overflow on some phones).
        // We pin textScaler to 1.0 (ignore the OS font scale) like CapCut/TikTok.
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: child!,
          );
        },
        home: const AppLoader(),
      ),
    );
  }
}

class AppLoader extends StatefulWidget {
  const AppLoader({super.key});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  // Keep the logo splash on screen for at least this long so it doesn't just
  // flash by — like other apps that briefly show their logo on launch.
  bool _minElapsed = false;

  @override
  void initState() {
    super.initState();
    _load();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _minElapsed = true);
    });
  }

  Future<void> _load() async {
    await context.read<ProjectProvider>().loadFromStorage();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final ready = provider.isLoaded && _minElapsed;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: ready ? const HomeScreen() : const _SplashScreen(),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                child: child,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/icon/icon.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.subtitles_rounded,
                    color: AppColors.primary,
                    size: 96,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'KarnSub',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'ສ້າງຊັບພາສາລາວ ອັດຕະໂນມັດ',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
