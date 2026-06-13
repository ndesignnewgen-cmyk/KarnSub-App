import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../i18n/i18n.dart';
import 'settings_screen.dart';

/// First-launch walkthrough (3 slides). Shown once; sets [prefsKey] when done.
class OnboardingScreen extends StatefulWidget {
  static const prefsKey = 'onboarding_done';
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  Future<void> _finish({bool openSettings = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen.prefsKey, true);
    if (!mounted) return;
    widget.onDone();
    if (openSettings) {
      // Land on Home first (onDone swapped the root), then push Settings on top.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = Navigator.maybeOf(context, rootNavigator: true);
        nav?.push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      });
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = [
      (Icons.subtitles_rounded, tr('ob.t1'), tr('ob.d1')),
      (Icons.movie_filter_rounded, tr('ob.t2'), tr('ob.d2')),
      (Icons.vpn_key_rounded, tr('ob.t3'), tr('ob.d3')),
    ];
    final last = _index == slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _finish(),
                child: Text(
                  tr('ob.skip'),
                  style: const TextStyle(
                      color: AppColors.textHint, fontSize: 13),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final s = slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            gradient: AppGradients.primary,
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child:
                              Icon(s.$1, color: Colors.white, size: 52),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          s.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          s.$3,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14.5,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppColors.primary
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: last
                  ? Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _finish(openSettings: true),
                          icon: const Icon(Icons.vpn_key_rounded, size: 18),
                          label: Text(tr('ob.addKey')),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => _finish(),
                          child: Text(
                            tr('ob.start'),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ),
                      ],
                    )
                  : ElevatedButton(
                      onPressed: () => _page.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      ),
                      child: Text(tr('ob.next')),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
