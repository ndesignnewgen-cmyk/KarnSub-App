import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/api_config.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/free_quota_service.dart';
import '../services/license_service.dart';
import '../services/subscription_service.dart';
import '../widgets/gradient_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyCtrl = TextEditingController();
  final _groqKeyCtrl = TextEditingController();
  final _openAiKeyCtrl = TextEditingController();
  final _elevenLabsKeyCtrl = TextEditingController();
  bool _obscure = true;
  bool _groqObscure = true;
  bool _openAiObscure = true;
  bool _elevenLabsObscure = true;
  bool _groqSaved = false;
  bool _isSaved = false;
  bool _openAiSaved = false;
  bool _elevenLabsSaved = false;
  bool _isLoading = true;
  bool _isPro = false;
  DateTime? _proExpiry;

  // Firebase account state
  User? _user;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _user = AuthService.currentUser;
    _loadAll();
  }

  Future<void> _loadAll() async {
    final key = await ApiConfig.getApiKey();
    final groqKey = await ApiConfig.getGroqKey();
    final openAiKey = await ApiConfig.getOpenAiKey();
    final elevenLabsKey = await ApiConfig.getElevenLabsKey();
    // If signed in, pull the latest PRO state from the cloud first.
    if (AuthService.currentUser != null) {
      await SubscriptionService.refresh();
    }
    final pro = await LicenseService.isPro();
    final expiry = await LicenseService.proExpiry();
    if (!mounted) return;
    if (key != null) _apiKeyCtrl.text = key;
    if (groqKey != null) _groqKeyCtrl.text = groqKey;
    if (openAiKey != null) _openAiKeyCtrl.text = openAiKey;
    if (elevenLabsKey != null) _elevenLabsKeyCtrl.text = elevenLabsKey;
    setState(() {
      _user = AuthService.currentUser;
      _isPro = pro;
      _proExpiry = expiry;
      _isLoading = false;
    });
  }

  Future<void> _refreshPro() async {
    setState(() {
      _isPro = false;
      _isLoading = false;
    });
    final pro = await LicenseService.isPro();
    final expiry = await LicenseService.proExpiry();
    if (!mounted) return;
    setState(() {
      _isPro = pro;
      _proExpiry = expiry;
    });
  }

  Future<void> _signIn() async {
    setState(() => _isSyncing = true);
    final result = await AuthService.signInWithGoogle();
    if (!mounted) return;
    if (result == SignInResult.success) {
      await SubscriptionService.refresh();
      await _refreshPro();
      if (!mounted) return;
      setState(() => _user = AuthService.currentUser);
      _showSuccess('ເຂົ້າສູ່ລະບົບສຳເລັດ — PRO ຈະຕິດຕາມບັນຊີນີ້');
    } else if (result == SignInResult.cancelled) {
      // user backed out — say nothing
    } else if (result == SignInResult.notConfigured) {
      _showError('ຍັງບໍ່ໄດ້ຕັ້ງຄ່າ Firebase — ຕິດຕໍ່ຜູ້ພັດທະນາ');
    } else {
      _showError('ເຂົ້າສູ່ລະບົບບໍ່ສຳເລັດ — ລອງໃໝ່');
    }
    if (mounted) setState(() => _isSyncing = false);
  }

  Future<void> _signOut() async {
    setState(() => _isSyncing = true);
    await AuthService.signOut();
    await FreeQuotaService.clearCloud();
    await _refreshPro();
    if (!mounted) return;
    setState(() {
      _user = null;
      _isSyncing = false;
    });
    _showSuccess('ອອກຈາກລະບົບແລ້ວ');
  }

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);
    await SubscriptionService.refresh();
    await _refreshPro();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    _showSuccess(
      _isPro
          ? 'ອັບເດດແລ້ວ — PRO ໃຊ້ໄດ້ຮອດ ${_proExpiry != null ? _fmtDate(_proExpiry!) : ''}'
          : 'ອັບເດດແລ້ວ — ຍັງບໍ່ມີ PRO ໃນບັນຊີນີ້',
    );
  }

  Future<void> _save() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      _showError('ກາລຸນາໃສ່ API Key ກ່ອນ');
      return;
    }
    await ApiConfig.saveApiKey(key);
    setState(() => _isSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isSaved = false);
    });
  }

  Future<void> _clear() async {
    await ApiConfig.clearApiKey();
    _apiKeyCtrl.clear();
    setState(() {});
  }

  Future<void> _saveOpenAi() async {
    final key = _openAiKeyCtrl.text.trim();
    if (key.isEmpty) {
      await ApiConfig.clearOpenAiKey();
    } else {
      await ApiConfig.saveOpenAiKey(key);
    }
    setState(() => _openAiSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _openAiSaved = false);
    });
  }

  Future<void> _clearOpenAi() async {
    await ApiConfig.clearOpenAiKey();
    _openAiKeyCtrl.clear();
    setState(() {});
  }

  Future<void> _saveGroq() async {
    final key = _groqKeyCtrl.text.trim();
    if (key.isEmpty) {
      await ApiConfig.clearGroqKey();
    } else {
      await ApiConfig.saveGroqKey(key);
    }
    setState(() => _groqSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _groqSaved = false);
    });
  }

  Future<void> _saveElevenLabs() async {
    final key = _elevenLabsKeyCtrl.text.trim();
    if (key.isEmpty) {
      await ApiConfig.clearElevenLabsKey();
    } else {
      await ApiConfig.saveElevenLabsKey(key);
    }
    setState(() => _elevenLabsSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _elevenLabsSaved = false);
    });
  }

  Future<void> _clearElevenLabs() async {
    await ApiConfig.clearElevenLabsKey();
    _elevenLabsKeyCtrl.clear();
    setState(() {});
  }

  // PRO pricing + seller contact.
  static const String proPrice = '39,000 ກີບ/ເດືອນ';
  // WhatsApp: 020 9552 4699 → international format 856 20 9552 4699.
  static const String _whatsappNumber = '8562095524699';

  Future<void> _openWhatsApp() async {
    final uid = _user?.uid ?? '';
    final msg = Uri.encodeComponent(
      'ສະບາຍດີ ຢາກສະມັກ KarnSub PRO (39,000 ກີບ/ເດືອນ).'
      '${uid.isNotEmpty ? '\nAccount ID: $uid' : ''}',
    );
    final uri = Uri.parse('https://wa.me/$_whatsappNumber?text=$msg');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _showError('ເປີດ WhatsApp ບໍ່ໄດ້ — ໂທ/add: 020 9552 4699');
      }
    } catch (_) {
      if (mounted) _showError('ເປີດ WhatsApp ບໍ່ໄດ້ — ໂທ/add: 020 9552 4699');
    }
  }

  /// Format DateTime as DD/MM/YYYY.
  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.accent),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _groqKeyCtrl.dispose();
    _openAiKeyCtrl.dispose();
    _elevenLabsKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('ຕັ້ງຄ່າ')),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProSection(),
                  if (FirebaseService.available) ...[
                    const SizedBox(height: 16),
                    _buildAccountSection(),
                  ],
                  const SizedBox(height: 24),
                  _buildApiKeySection(),
                  const SizedBox(height: 24),
                  _buildOpenAiKeySection(),
                  const SizedBox(height: 24),
                  _buildElevenLabsKeySection(),
                  const SizedBox(height: 24),
                  _buildGroqKeySection(),
                  const SizedBox(height: 24),
                  _buildHowToGetKey(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  // ── Account (Firebase) Section ───────────────────────────────────────────

  Widget _buildAccountSection() {
    final signedIn = _user != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  signedIn
                      ? Icons.account_circle_rounded
                      : Icons.cloud_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signedIn ? 'ບັນຊີ' : 'ເຊື່ອມ PRO ກັບບັນຊີ',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      signedIn
                          ? (_user!.email ?? 'ເຂົ້າສູ່ລະບົບແລ້ວ')
                          : 'ລ໋ອກອິນ → PRO ຕິດຕາມບັນຊີ ແມ້ປ່ຽນເຄື່ອງ',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (signedIn) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSyncing ? null : _manualSync,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size(0, 44),
                    ),
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('ອັບເດດ PRO'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _isSyncing ? null : _signOut,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('ອອກ'),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _signIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : const Icon(Icons.login_rounded, size: 18),
                label: const Text(
                  'ເຂົ້າສູ່ລະບົບ ດ້ວຍ Google',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── PRO Status / Unlock Section ──────────────────────────────────────────

  Widget _buildProSection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: _isPro
            ? const LinearGradient(
                colors: [Color(0xFF1A1200), Color(0xFF2C1F00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : (_proExpiry != null
                  ? const LinearGradient(
                      colors: [Color(0xFF1A0A0A), Color(0xFF2A1010)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null),
        color: (_isPro || _proExpiry != null) ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isPro
              ? const Color(0xFFFFD700)
              : (_proExpiry != null
                    ? const Color(0xFFCC4444)
                    : AppColors.border),
          width: (_isPro || _proExpiry != null) ? 1.5 : 1,
        ),
      ),
      child: _isPro
          ? _buildProActive()
          : (_proExpiry != null ? _buildProExpired() : _buildProUnlock()),
    );
  }

  Widget _buildProActive() {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.star_rounded,
                color: Color(0xFFFFD700),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'KarnSub PRO',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    _proExpiry != null
                        ? 'ໃຊ້ໄດ້ຮອດ ${_fmtDate(_proExpiry!)}'
                        : 'Activated — ທຸກ features ໃຊ້ໄດ້ເຕັມ',
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.5),
                ),
              ),
              child: const Text(
                'PRO ✓',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: Color(0xFF3D2E00), height: 1),
        const SizedBox(height: 14),
        _proFeatureRow(
          Icons.all_inclusive_rounded,
          'Export ບໍ່ຈຳກັດ — ບໍ່ຕິດ watermark',
        ),
        const SizedBox(height: 8),
        _proFeatureRow(Icons.highlight, 'Karaoke Highlight'),
        const SizedBox(height: 8),
        _proFeatureRow(Icons.translate, 'ຊັບສອງພາສາ (Bilingual)'),
      ],
    );
  }

  Widget _proFeatureRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFD700), size: 16),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFFFB300), fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _buildProExpired() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFCC4444).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.star_rounded,
                color: Color(0xFFCC4444),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'KarnSub PRO',
                    style: TextStyle(
                      color: Color(0xFFCC4444),
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    'ໝົດອາຍຸ ${_proExpiry != null ? _fmtDate(_proExpiry!) : ''}',
                    style: const TextStyle(
                      color: Color(0xFFAA3333),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFCC4444).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFCC4444).withOpacity(0.5),
                ),
              ),
              child: const Text(
                'ໝົດ',
                style: TextStyle(
                  color: Color(0xFFCC4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(color: Color(0xFF3D1010), height: 1),
        const SizedBox(height: 14),
        const Text(
          'ຕໍ່ອາຍຸ PRO:',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'ຈ່າຍຕໍ່ເດືອນ ($proPrice) ທາງ WhatsApp → ແລ້ວກົດ "ອັບເດດ PRO" ໃນກາດບັນຊີດ້ານລຸ່ມ',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: _showBuyInfo,
            child: const Text(
              'ວິທີຊື້ PRO →',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProUnlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with FREE badge
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.star_border_rounded,
                color: AppColors.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KarnSub PRO',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Upgrade ເພື່ອໃຊ້ງານເຕັມ',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'FREE',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Free tier limits
        _limitRow(
          Icons.branding_watermark_outlined,
          'Export video → ຕິດ watermark (ຟຣີ)',
        ),
        const SizedBox(height: 6),
        _limitRow(Icons.hd_rounded, 'Export ບໍ່ຕິດ watermark → 1 ຄັ້ງ/ມື້'),
        const SizedBox(height: 6),
        _limitRow(Icons.lock_rounded, 'Karaoke + Bilingual → PRO only'),

        const SizedBox(height: 16),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 16),

        // PRO features teaser
        const Text(
          'PRO ໄດ້ຫຍັງ?',
          style: TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        _proTeaseRow(
          Icons.all_inclusive_rounded,
          'Export ບໍ່ຈຳກັດ — ບໍ່ຕິດ watermark',
        ),
        const SizedBox(height: 6),
        _proTeaseRow(Icons.highlight, 'Karaoke Highlight'),
        const SizedBox(height: 6),
        _proTeaseRow(Icons.translate, 'ຊັບສອງພາສາ (Bilingual)'),
        const SizedBox(height: 10),
        Text(
          'ພຽງ $proPrice',
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 16),
        // Subscribe via WhatsApp (one-tap deep link)
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: _openWhatsApp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366), // WhatsApp green
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text(
              'ສະມັກ PRO ທາງ WhatsApp',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 16),

        // How to get PRO (cloud subscription model)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700).withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFFFD700).withOpacity(0.25),
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFFFD700),
                size: 18,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ຂັ້ນຕອນ: login Google → ສະມັກທາງ WhatsApp → ກົດ "ອັບເດດ PRO"',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: _showBuyInfo,
            child: const Text(
              'ວິທີຊື້ PRO →',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _limitRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textHint, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _proTeaseRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFD700), size: 14),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
        ),
      ],
    );
  }

  void _showBuyInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ຊື້ KarnSub PRO',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buyStep('1', 'ເຂົ້າສູ່ລະບົບ ດ້ວຍ Google ໃນແອັບກ່ອນ'),
            _buyStep('2', 'ກົດ "ສະມັກ PRO ທາງ WhatsApp" → ໂອນ $proPrice'),
            _buyStep('3', 'ສົ່ງ screenshot ການໂອນ (ບອກ Gmail/Account ID ນຳ)'),
            _buyStep('4', 'ລໍຖ້າເປີດ PRO → ກົດ "ອັບເດດ PRO" ໃນ Settings'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFFFD700),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PRO $proPrice — ໝົດເດືອນ ກັບຄືນ FREE ເອງ',
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'ປິດ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openWhatsApp();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.chat_rounded, size: 16),
            label: const Text('WhatsApp'),
          ),
        ],
      ),
    );
  }

  Widget _buyStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Groq (Whisper) API Key — optional, for precise word timing ───────────

  Widget _buildGroqKeySection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF00BFa5).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.graphic_eq,
                    color: Color(0xFF00BFA5), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Groq Key (ໃຫ້ຕົງສຽງ)',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'ທາງເລືອກ — Whisper ຈັບເວລາທຸກຄຳໃຫ້ຕົງສຽງ (console.groq.com)',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _groqKeyCtrl,
            obscureText: _groqObscure,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'gsk_xxxxxxxxxxxxxxxxxxxx (ໃສ່ ຫຼື ບໍ່ໃສ່ກໍ່ໄດ້)',
              hintStyle: const TextStyle(color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF00BFA5), width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              suffixIcon: IconButton(
                icon: Icon(
                  _groqObscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textHint,
                  size: 20,
                ),
                onPressed: () => setState(() => _groqObscure = !_groqObscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saveGroq,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _groqSaved ? AppColors.success : const Color(0xFF00BFA5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(_groqSaved ? Icons.check : Icons.save_outlined,
                  size: 18),
              label: Text(_groqSaved ? 'ບັນທຶກແລ້ວ!' : 'ບັນທຶກ Groq Key'),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '💡 ໃສ່ Groq key ແລ້ວ ການຖອດສຽງ/Auto Sync ຈະໃຊ້ Whisper ຈັບເວລາ '
            'ໃຫ້ຕົງສຽງທຸກຄຳ (ຂໍຟຣີໄດ້ທີ່ console.groq.com). ບໍ່ໃສ່ກໍ່ໄດ້ — '
            'ຈະໃຊ້ການ sync ແບບປົກກະຕິ.',
            style: TextStyle(
                color: AppColors.textHint, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── Gemini API Key Section ───────────────────────────────────────────────

  Widget _buildApiKeySection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.key,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gemini API Key',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'ຈາກ aistudio.google.com',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscure,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
              hintStyle: const TextStyle(color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy,
                      color: AppColors.textHint,
                      size: 18,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _apiKeyCtrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('ຄັດລອກແລ້ວ'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: _isSaved ? 'ບັນທຶກແລ້ວ!' : 'ບັນທຶກ',
                  icon: _isSaved ? Icons.check : Icons.save_outlined,
                  height: 48,
                  solidColor: _isSaved ? AppColors.success : null,
                  onTap: _save,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _clear,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('ລຶບ'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── OpenAI API Key Section ───────────────────────────────────────────────

  Widget _buildOpenAiKeySection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.key,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OpenAI API Key',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'ຈາກ platform.openai.com',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _openAiKeyCtrl,
            obscureText: _openAiObscure,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'sk-proj-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
              hintStyle: const TextStyle(color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _openAiObscure ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _openAiObscure = !_openAiObscure),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy,
                      color: AppColors.textHint,
                      size: 18,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _openAiKeyCtrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(
                           content: Text('ຄັດລອກແລ້ວ'),
                           duration: Duration(seconds: 1),
                         ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: _openAiSaved ? 'ບັນທຶກແລ້ວ!' : 'ບັນທຶກ',
                  icon: _openAiSaved ? Icons.check : Icons.save_outlined,
                  height: 48,
                  solidColor: _openAiSaved ? AppColors.success : null,
                  onTap: _saveOpenAi,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _clearOpenAi,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('ລຶບ'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowToGetKey() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ວິທີຂໍ Gemini API Key',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _buildStep('1', 'ໄປ aistudio.google.com → ລ໋ອກອິນ Gmail'),
          _buildStep('2', 'ກົດ "Get API key" → "Create API key"'),
          _buildStep('3', 'ຄັດລອກ Key (ຂຶ້ນຕົ້ນ AIzaSy...)'),
          _buildStep('4', 'ວາງ key ໃສ່ຊ່ອງດ້ານເທິງ → ກົດ ບັນທຶກ'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Gemini 2.5 Flash — ຖອດສຽງລາວໄດ້ດີທີ່ສຸດ\nມີຊັ້ນຟຣີ (Free tier) ໃຫ້ໃຊ້ໄດ້',
                    style: TextStyle(color: AppColors.primary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ElevenLabs TTS (Premium Online) Key Section ───────────────────────

  Widget _buildElevenLabsKeySection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.record_voice_over,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ElevenLabs API Key',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'ສຽງພາກລະດັບ Premium (elevenlabs.io)',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _elevenLabsKeyCtrl,
            obscureText: _elevenLabsObscure,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
              hintStyle: const TextStyle(color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _elevenLabsObscure ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _elevenLabsObscure = !_elevenLabsObscure),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy,
                      color: AppColors.textHint,
                      size: 18,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _elevenLabsKeyCtrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(
                           content: Text('ຄັດລອກແລ້ວ'),
                           duration: Duration(seconds: 1),
                         ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: _elevenLabsSaved ? '...ບັນທຶກແລ້ວ!' : 'ບັນທຶກ',
                  icon: _elevenLabsSaved ? Icons.check : Icons.save_outlined,
                  height: 48,
                  solidColor: _elevenLabsSaved ? AppColors.success : null,
                  onTap: _saveElevenLabs,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _clearElevenLabs,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('ລຶບ'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '💡 ວິທີຂໍ Key: ໄປທີ່ elevenlabs.io → ລ໋ອກອິນບັນຊີຂອງທ່ານ '
            '→ ກົດທີ່ໂປຣໄຟລ໌ (Profile) ດ້ານຂວາລຸ່ມ → ເລືອກ My Account → '
            'ຄັດລອກ API Key ແລ້ວນຳມາວາງໃສ່ບ່ອນນີ້.',
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
