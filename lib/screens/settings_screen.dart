import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../i18n/i18n.dart';
import '../services/api_config.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../config/build_config.dart';
import '../services/free_quota_service.dart';
import '../services/license_service.dart';
import '../services/subscription_service.dart';
import '../services/payment_config.dart';
import '../services/slip_verify_service.dart';
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
  final _tenorKeyCtrl = TextEditingController();
  final _freesoundKeyCtrl = TextEditingController();
  bool _obscure = true;
  bool _groqObscure = true;
  bool _openAiObscure = true;
  bool _tenorObscure = true;
  bool _freesoundObscure = true;
  bool _groqSaved = false;
  bool _isSaved = false;
  bool _openAiSaved = false;
  bool _tenorSaved = false;
  bool _freesoundSaved = false;
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
    final tenorKey = await ApiConfig.getTenorKey();
    final freesoundKey = await ApiConfig.getFreesoundKey();
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
    if (tenorKey != null) _tenorKeyCtrl.text = tenorKey;
    if (freesoundKey != null) _freesoundKeyCtrl.text = freesoundKey;
    setState(() {
      _user = AuthService.currentUser;
      _isPro = pro;
      _proExpiry = expiry;
      _isLoading = false;
      _tenorSaved = tenorKey != null && tenorKey.isNotEmpty;
      _freesoundSaved = freesoundKey != null && freesoundKey.isNotEmpty;
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
      _showSuccess(tr('set.signedIn'));
    } else if (result == SignInResult.cancelled) {
      // user backed out — say nothing
    } else if (result == SignInResult.notConfigured) {
      _showError(tr('set.firebaseNotSet'));
    } else {
      _showError(tr('set.signInFailed'));
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
    _showSuccess(tr('set.signedOut'));
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.accent, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('set.deleteAccount'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
        ]),
        content: Text(tr('set.deleteConfirm'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('common.cancel'),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            child: Text(tr('set.deleteConfirmYes')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSyncing = true);
    var res = await AuthService.deleteAccount();
    // Firebase may require a fresh login before deletion — re-auth and retry once.
    if (res == DeleteResult.needsReauth) {
      final si = await AuthService.signInWithGoogle();
      if (si == SignInResult.success) {
        res = await AuthService.deleteAccount();
      }
    }
    if (!mounted) return;
    if (res == DeleteResult.success) {
      await FreeQuotaService.clearCloud();
      await _refreshPro();
      if (!mounted) return;
      setState(() {
        _user = null;
        _isSyncing = false;
      });
      _showSuccess(tr('set.accountDeleted'));
    } else {
      setState(() => _isSyncing = false);
      _showError(tr('set.deleteFailed'));
    }
  }

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);
    await SubscriptionService.refresh();
    await _refreshPro();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    _showSuccess(
      _isPro
          ? tr('set.updatedProUntil', {'date': _proExpiry != null ? _fmtDate(_proExpiry!) : ''})
          : tr('set.updatedNoPro'),
    );
  }

  Future<void> _save() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      _showError(tr('set.enterKeyFirst'));
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

  Future<void> _clearGroq() async {
    await ApiConfig.clearGroqKey();
    _groqKeyCtrl.clear();
    setState(() {});
  }

  Future<void> _saveTenor() async {
    final key = _tenorKeyCtrl.text.trim();
    if (key.isEmpty) {
      await ApiConfig.clearTenorKey();
    } else {
      await ApiConfig.saveTenorKey(key);
    }
    setState(() => _tenorSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _tenorSaved = false);
    });
  }

  Future<void> _clearTenor() async {
    await ApiConfig.clearTenorKey();
    _tenorKeyCtrl.clear();
    setState(() {});
  }

  Future<void> _saveFreesound() async {
    final key = _freesoundKeyCtrl.text.trim();
    if (key.isEmpty) {
      await ApiConfig.clearFreesoundKey();
    } else {
      await ApiConfig.saveFreesoundKey(key);
    }
    setState(() => _freesoundSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _freesoundSaved = false);
    });
  }

  Future<void> _clearFreesound() async {
    await ApiConfig.clearFreesoundKey();
    _freesoundKeyCtrl.clear();
    setState(() {});
  }

  // PRO pricing + seller contact.
  static String get proPrice => tr('set.priceMonth');
  // WhatsApp: 020 9552 4699 → international format 856 20 9552 4699.
  static const String _whatsappNumber = '8562095524699';

  Future<void> _openWhatsApp() async {
    final uid = _user?.uid ?? '';
    final msg = Uri.encodeComponent(
      '${tr('set.waMsg')}'
      '${uid.isNotEmpty ? '\nAccount ID: $uid' : ''}',
    );
    final uri = Uri.parse('https://wa.me/$_whatsappNumber?text=$msg');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _showError(tr('set.waFail'));
      }
    } catch (_) {
      if (mounted) _showError(tr('set.waFail'));
    }
  }

  /// Auto PRO top-up: show QR + price, let the user upload a paid slip, verify
  /// it with Gemini, then redeem (anti-reuse) and unlock PRO instantly.
  Future<void> _openAutoTopUp() async {
    // Must be signed in (we key payments by uid).
    if (AuthService.currentUser == null) {
      _showError(tr('set.signInFirst'));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool busy = false;
        String? status;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> uploadSlip() async {
              final picked = await FilePicker.platform
                  .pickFiles(type: FileType.image);
              if (picked == null || picked.files.single.path == null) return;
              setSheet(() {
                busy = true;
                status = tr('set.checkingSlip');
              });
              final res =
                  await SlipVerifyService.verifySlip(File(picked.files.single.path!));
              if (!res.ok) {
                setSheet(() {
                  busy = false;
                  status = '❌ ${res.error}';
                });
                return;
              }
              setSheet(() => status = tr('set.openingPro'));
              final redeem = await SubscriptionService.redeemBySlip(
                refId: res.refId,
                amountKip: res.amountKip,
                bank: res.bank,
              );
              switch (redeem) {
                case RedeemResult.success:
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadAll();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(tr('set.proSuccess')),
                      backgroundColor: const Color(0xFF2E7D32),
                    ));
                  }
                  break;
                case RedeemResult.alreadyUsed:
                  setSheet(() {
                    busy = false;
                    status = tr('set.slipUsed');
                  });
                  break;
                case RedeemResult.notLoggedIn:
                  setSheet(() {
                    busy = false;
                    status = tr('set.signInFirst2');
                  });
                  break;
                case RedeemResult.error:
                  setSheet(() {
                    busy = false;
                    final d = SubscriptionService.lastError;
                    status = d == null
                        ? tr('set.errorRetry')
                        : '❌ ${d.contains('PERMISSION_DENIED') ? tr('set.firestoreDenied') : d}';
                  });
                  break;
              }
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('set.autoTopupTitle'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(tr('set.priceMonth'),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    // QR — fills the framed box (white card behind it).
                    Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        PaymentConfig.qrAssetPath,
                        fit: BoxFit.fitWidth,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 200,
                          child: Center(
                            child: Icon(Icons.qr_code_2,
                                size: 120, color: Colors.black54),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${tr('set.transferTo', {'name': PaymentConfig.merchantName})}\n'
                      '${tr('set.account', {'acc': PaymentConfig.merchantAccount})}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(status!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: status!.startsWith('❌')
                                    ? Colors.redAccent
                                    : AppColors.primary,
                                fontSize: 12.5)),
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: busy ? null : uploadSlip,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.surfaceLight,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.upload_file, size: 18),
                        label: Text(
                          busy ? tr('set.checking') : tr('set.paidUpload'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('set.slipHint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
    _tenorKeyCtrl.dispose();
    _freesoundKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(tr('set.title'))),
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
                  const SizedBox(height: 26),
                  _buildApiKeysSection(),
                  const SizedBox(height: 26),
                  _buildLanguageSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── AI Keys (consolidated, collapsible) ──────────────────────────────────

  Widget _sectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildApiKeysSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(tr('set.aiKeys'), tr('set.aiKeysDesc')),
        _keyTile(
          icon: Icons.auto_awesome,
          accent: AppColors.primary,
          title: 'Gemini',
          subtitle: tr('set.geminiSub'),
          badge: tr('set.required'),
          badgeColor: AppColors.accent,
          controller: _apiKeyCtrl,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          saved: _isSaved,
          hint: 'AIzaSy...',
          onSave: _save,
          onClear: _clear,
          from: tr('set.fromAistudio'),
          steps: [
            tr('set.howGemini1'),
            tr('set.howGemini2'),
            tr('set.howGemini3'),
            tr('set.howGemini4'),
          ],
          info: tr('set.geminiInfo'),
        ),
        const SizedBox(height: 10),
        _keyTile(
          icon: Icons.bolt,
          accent: const Color(0xFF00BFA5),
          title: 'Groq',
          subtitle: tr('set.groqSub'),
          badge: tr('set.recommended'),
          badgeColor: const Color(0xFF00BFA5),
          controller: _groqKeyCtrl,
          obscure: _groqObscure,
          onToggleObscure: () => setState(() => _groqObscure = !_groqObscure),
          saved: _groqSaved,
          hint: 'gsk_...',
          onSave: _saveGroq,
          onClear: _clearGroq,
          from: 'console.groq.com',
          steps: [
            tr('set.howGroq1'),
            tr('set.howGroq2'),
            tr('set.howGroq3'),
            tr('set.howGroq4'),
          ],
          info: tr('set.groqInfo2'),
        ),
        const SizedBox(height: 10),
        _keyTile(
          icon: Icons.graphic_eq,
          accent: const Color(0xFF10A37F),
          title: 'OpenAI',
          subtitle: tr('set.openaiSub'),
          badge: tr('set.optional'),
          badgeColor: AppColors.textSecondary,
          controller: _openAiKeyCtrl,
          obscure: _openAiObscure,
          onToggleObscure: () => setState(() => _openAiObscure = !_openAiObscure),
          saved: _openAiSaved,
          hint: 'sk-...',
          onSave: _saveOpenAi,
          onClear: _clearOpenAi,
          from: tr('set.fromOpenai'),
          steps: [
            tr('set.howOpenai1'),
            tr('set.howOpenai2'),
            tr('set.howOpenai3'),
            tr('set.howOpenai4'),
          ],
          info: tr('set.openaiInfo'),
        ),
        const SizedBox(height: 10),
        _keyTile(
          icon: Icons.gif_box_outlined,
          accent: const Color(0xFFEA4C89),
          title: 'Tenor',
          subtitle: tr('set.tenorSub'),
          badge: tr('set.optional'),
          badgeColor: AppColors.textSecondary,
          controller: _tenorKeyCtrl,
          obscure: _tenorObscure,
          onToggleObscure: () => setState(() => _tenorObscure = !_tenorObscure),
          saved: _tenorSaved,
          hint: 'AIza... / tenor key',
          onSave: _saveTenor,
          onClear: _clearTenor,
          from: tr('set.fromTenor'),
          steps: [
            tr('set.howTenor1'),
            tr('set.howTenor2'),
            tr('set.howTenor3'),
            tr('set.howTenor4'),
          ],
          info: tr('set.tenorInfo'),
        ),
        _keyTile(
          icon: Icons.library_music,
          accent: const Color(0xFF00BFA5),
          title: 'Freesound',
          subtitle: tr('set.freesoundSub'),
          badge: tr('set.optional'),
          badgeColor: AppColors.textSecondary,
          controller: _freesoundKeyCtrl,
          obscure: _freesoundObscure,
          onToggleObscure: () =>
              setState(() => _freesoundObscure = !_freesoundObscure),
          saved: _freesoundSaved,
          hint: 'freesound token',
          onSave: _saveFreesound,
          onClear: _clearFreesound,
          from: tr('set.fromFreesound'),
          steps: [
            tr('set.howFs1'),
            tr('set.howFs2'),
            tr('set.howFs3'),
          ],
          info: tr('set.freesoundInfo'),
        ),
      ],
    );
  }

  Widget _keyTile({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required bool saved,
    required String hint,
    required Future<void> Function() onSave,
    required Future<void> Function() onClear,
    required String from,
    required List<String> steps,
    required String info,
  }) {
    final isSet = controller.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isSet ? accent.withValues(alpha: 0.45) : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent, splashColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: !isSet && title == 'Gemini',
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          iconColor: AppColors.textHint,
          collapsedIconColor: AppColors.textHint,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          title: Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge,
                    style: TextStyle(
                        color: badgeColor, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: [
                Icon(isSet ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 13, color: isSet ? AppColors.success : AppColors.textHint),
                const SizedBox(width: 5),
                Text(isSet ? tr('set.keySet') : tr('set.keyNotSet'),
                    style: TextStyle(
                        color: isSet ? AppColors.success : AppColors.textHint,
                        fontSize: 11.5)),
                Expanded(
                  child: Text('  ·  $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11.5)),
                ),
              ],
            ),
          ),
          children: [
            // Key input
            TextField(
              controller: controller,
              obscureText: obscure,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                  color: AppColors.textPrimary, fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: accent, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textHint, size: 19),
                    onPressed: onToggleObscure,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AppColors.textHint, size: 17),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: controller.text));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr('set.copied')),
                          duration: const Duration(seconds: 1)));
                    },
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () async => onSave(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: saved ? AppColors.success : accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(saved ? Icons.check : Icons.save_outlined, size: 17),
                    label: Text(saved ? tr('set.saved') : tr('set.save'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              if (isSet) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () async => onClear(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Text(tr('set.delete')),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            // How-to (compact)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(from,
                      style: TextStyle(
                          color: accent, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (int i = 0; i < steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i + 1}. ',
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(steps[i],
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                    height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(info,
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 11, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App language (Lao / Thai) ────────────────────────────────────────────

  Widget _buildLanguageSection() {
    Widget chip(String code, String label) {
      final selected = I18n.lang.value == code;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (!selected) {
              I18n.set(code);
              setState(() {}); // refresh this screen immediately
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.8 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('lang.section'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            chip('lo', '🇱🇦 ${tr('lang.lo')}'),
            chip('th', '🇹🇭 ${tr('lang.th')}'),
          ],
        ),
      ],
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
                      signedIn ? tr('set.account.section') : tr('set.linkPro'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      signedIn
                          ? (_user!.email ?? tr('set.loggedIn'))
                          : tr('set.loginBenefit'),
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
                    label: Text(tr('set.updatePro')),
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
                  child: Text(tr('set.signOut')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isSyncing ? null : _deleteAccount,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 16),
                label: Text(tr('set.deleteAccount'),
                    style: const TextStyle(fontSize: 12)),
              ),
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
                label: Text(
                  tr('set.signInGoogle'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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

  // ── Shared PRO building blocks ────────────────────────────────────────────

  /// Card header: icon + title + subtitle + status pill.
  Widget _proHeader({
    required IconData icon,
    required Color color,
    required String subtitle,
    required String pill,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('KarnSub PRO',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              Text(subtitle,
                  style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(pill,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  /// Feature chips shown in a compact wrap (no long sentences).
  Widget _proFeatureChips() {
    Widget chip(IconData i, String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700).withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, color: const Color(0xFFFFD700), size: 14),
            const SizedBox(width: 6),
            Text(t,
                style: const TextStyle(
                    color: Color(0xFFFFD700), fontSize: 11.5)),
          ]),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      chip(Icons.block, tr('set.feat.noWatermark')),
      chip(Icons.highlight, 'Karaoke'),
      chip(Icons.translate, tr('set.feat.bilingual')),
      chip(Icons.record_voice_over, tr('set.feat.aiVoice')),
    ]);
  }

  /// Primary "pay with QR" button (big, the main CTA).
  Widget _payQrButton(String label) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _openAutoTopUp,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.qr_code_2_rounded, size: 20),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  /// Small secondary "other ways" link (WhatsApp / manual).
  Widget _otherWaysLink() {
    return Center(
      child: TextButton(
        onPressed: _showBuyInfo,
        child: Text(tr('set.otherChannels'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
    );
  }

  /// "Enter license key" button — the ONLY unlock path on the Play Store build
  /// (where selling in-app is not allowed), but also offered everywhere else.
  Widget _redeemKeyButton({bool primary = false}) {
    final child = primary
        ? SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _showRedeemKey,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.vpn_key_rounded, size: 20),
              label: Text(tr('set.redeemKey'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          )
        : Center(
            child: TextButton.icon(
              onPressed: _showRedeemKey,
              icon: const Icon(Icons.vpn_key_rounded,
                  size: 16, color: AppColors.textSecondary),
              label: Text(tr('set.haveKey'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
          );
    return child;
  }

  /// Dialog: paste a PRO key → validate + claim (single-use) → unlock.
  Future<void> _showRedeemKey() async {
    final ctrl = TextEditingController();
    bool busy = false;
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.vpn_key_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(tr('set.redeemKey'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('set.redeemKeyHint'),
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    letterSpacing: 1.5),
                decoration: InputDecoration(
                  hintText: 'KARN-XXXX-XXXX-XXXX',
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  errorText: err,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text(tr('common.close'),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      final res =
                          await LicenseService.activateWithKey(ctrl.text);
                      if (res == ActivationResult.success) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _loadAll();
                        _showSuccess(tr('set.keyOk'));
                        return;
                      }
                      setD(() {
                        busy = false;
                        err = switch (res) {
                          ActivationResult.invalid => tr('set.keyInvalid'),
                          ActivationResult.expired => tr('set.keyExpired'),
                          ActivationResult.alreadyUsed => tr('set.keyUsed'),
                          ActivationResult.needsInternet =>
                            tr('set.keyNeedNet'),
                          _ => tr('set.keyInvalid'),
                        };
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(tr('set.activate')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProActive() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _proHeader(
          icon: Icons.star_rounded,
          color: const Color(0xFFFFD700),
          subtitle: _proExpiry != null
              ? tr('set.proUntil', {'date': _fmtDate(_proExpiry!)})
              : tr('set.proFull'),
          pill: 'PRO ✓',
        ),
        const SizedBox(height: 16),
        _proFeatureChips(),
        const SizedBox(height: 16),
        if (!kPlayStoreBuild)
          _payQrButton(tr('set.renewPro'))
        else
          _redeemKeyButton(primary: true),
      ],
    );
  }

  Widget _buildProExpired() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _proHeader(
          icon: Icons.star_rounded,
          color: const Color(0xFFCC4444),
          subtitle: tr('set.expiredOn', {'date': _proExpiry != null ? _fmtDate(_proExpiry!) : ''}),
          pill: tr('set.expired'),
        ),
        const SizedBox(height: 16),
        _proFeatureChips(),
        const SizedBox(height: 16),
        if (!kPlayStoreBuild) ...[
          _payQrButton(tr('set.renewProPrice', {'price': proPrice})),
          const SizedBox(height: 6),
          _otherWaysLink(),
          const SizedBox(height: 2),
          _redeemKeyButton(),
        ] else
          _redeemKeyButton(primary: true),
      ],
    );
  }

  Widget _buildProUnlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _proHeader(
          icon: Icons.star_border_rounded,
          color: AppColors.textSecondary,
          subtitle: tr('set.upgradeFull'),
          pill: 'FREE',
        ),
        const SizedBox(height: 8),
        Text(
          tr('set.unlockAll', {'price': proPrice}),
          style: const TextStyle(
              color: Color(0xFFFFD700),
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
        const SizedBox(height: 14),
        _proFeatureChips(),
        const SizedBox(height: 18),
        if (!kPlayStoreBuild) ...[
          _payQrButton(tr('set.subscribeQr')),
          const SizedBox(height: 6),
          _otherWaysLink(),
          const SizedBox(height: 2),
          _redeemKeyButton(),
        ] else
          _redeemKeyButton(primary: true),
      ],
    );
  }

  void _showBuyInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          tr('set.buyPro'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buyStep('1', tr('set.buyFast')),
            _buyStep('2', tr('set.buyWa', {'price': proPrice})),
            _buyStep('3', tr('set.loginRequired')),
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
                      tr('set.proNote', {'price': proPrice}),
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
            child: Text(
              tr('common.close'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openAutoTopUp();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.qr_code_2_rounded, size: 16),
            label: Text(tr('set.payQrAuto')),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('set.groqKeyLabel'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      tr('set.groqKeyDesc'),
                      style: const TextStyle(
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
              hintText: tr('set.groqHint2'),
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
              label: Text(_groqSaved ? tr('set.saved') : tr('set.saveGroqKey')),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr('set.groqInfo'),
            style: const TextStyle(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gemini API Key',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    tr('set.fromAistudio'),
                    style: const TextStyle(
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
                        SnackBar(
                          content: Text(tr('set.copied')),
                          duration: const Duration(seconds: 1),
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
                  label: _isSaved ? tr('set.saved') : tr('set.save'),
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
                child: Text(tr('set.delete')),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OpenAI API Key',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    tr('set.fromOpenai'),
                    style: const TextStyle(
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
                         SnackBar(
                           content: Text(tr('set.copied')),
                           duration: const Duration(seconds: 1),
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
                  label: _openAiSaved ? tr('set.saved') : tr('set.save'),
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
                child: Text(tr('set.delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowToGetGeminiKey() {
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
          Text(
            tr('set.howGemini'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _buildStep('1', tr('set.howGemini1')),
          _buildStep('2', tr('set.howGemini2')),
          _buildStep('3', tr('set.howGemini3')),
          _buildStep('4', tr('set.howGemini4')),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('set.geminiInfo'),
                    style: const TextStyle(color: AppColors.primary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowToGetOpenAiKey() {
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
          Text(
            tr('set.howOpenai'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _buildStep('1', tr('set.howOpenai1')),
          _buildStep('2', tr('set.howOpenai2')),
          _buildStep('3', tr('set.howOpenai3')),
          _buildStep('4', tr('set.howOpenai4')),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10A37F).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF10A37F).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF10A37F), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('set.openaiInfo'),
                    style: const TextStyle(color: Color(0xFF10A37F), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowToGetGroqKey() {
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
          Text(
            tr('set.howGroq'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _buildStep('1', tr('set.howGroq1')),
          _buildStep('2', tr('set.howGroq2')),
          _buildStep('3', tr('set.howGroq3')),
          _buildStep('4', tr('set.howGroq4')),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00BFA5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00BFA5).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF00BFA5), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('set.groqInfo2'),
                    style: const TextStyle(color: Color(0xFF00BFA5), fontSize: 12),
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

}
