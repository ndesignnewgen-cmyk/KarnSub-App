part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Image/video/sticker overlays, web sheets, SFX picking.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorOverlays on _EditorScreenState {
  /// Pick an image from the device and add it as an overlay at the playhead.
  Future<void> _pickImageOverlay(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;
    _pauseForEdit();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;
    final srcPath = result.files.single.path!;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'overlays'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = p.extension(srcPath);
      final dest = p.join(
          dir.path, 'img_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(srcPath).copy(dest);

      final startMs = _position.inMilliseconds;
      final endMs = (startMs + 3000).clamp(0, _duration.inMilliseconds);
      final overlay = ImageOverlay(
        id: const Uuid().v4(),
        path: dest,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs == startMs ? startMs + 3000 : endMs),
      );
      provider.addImageOverlay(overlay);
      setState(() => _selectedImageId = overlay.id);
      _toast(tr('ed.imageAdded'));
    } catch (e) {
      _showErrorBanner(tr('ed.imageAddFail', {'e': e.toString()}));
    }
  }

  /// Pick a VIDEO clip from the device and add it as a B-roll overlay at the
  /// playhead — full-width, muted, plays in-place (preview + native export).
  Future<void> _pickVideoOverlay(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;
    if (!_isPro) {
      _showProFeatureDialog(tr('ed.brollPro'));
      return;
    }
    _pauseForEdit();
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) return;
    final srcPath = result.files.single.path!;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'overlays'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = p.extension(srcPath);
      final dest = p.join(
          dir.path, 'vid_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(srcPath).copy(dest);

      // Probe the clip length for a sensible default duration (cap 6s).
      int clipMs = 4000;
      try {
        final probe = VideoPlayerController.file(File(dest));
        await probe.initialize();
        clipMs = probe.value.duration.inMilliseconds;
        await probe.dispose();
      } catch (_) {}

      final startMs = _position.inMilliseconds;
      final span = clipMs.clamp(1000, 6000);
      var endMs = startMs + span;
      if (_duration.inMilliseconds > 0 && endMs > _duration.inMilliseconds) {
        endMs = _duration.inMilliseconds;
      }
      if (endMs <= startMs) endMs = startMs + span;
      final overlay = ImageOverlay(
        id: const Uuid().v4(),
        path: dest,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
        x: 0.5,
        y: 0.40, // (used only if cover is turned off)
        scale: 1.0,
        isVideo: true,
        cover: true, // full-screen B-roll by default
      );
      provider.addImageOverlay(overlay);
      _ensureBrollControllers(provider.currentProject);
      setState(() => _selectedImageId = overlay.id);
      _toast(tr('ed.brollAdded'));
    } catch (e) {
      _showErrorBanner(tr('ed.imageAddFail', {'e': e.toString()}));
    }
  }

  /// Web image search → insert as an overlay at the playhead (Openverse, free).
  void _showWebImageSheet(ProjectProvider provider) {
    _pauseForEdit();
    // Pre-fill the query from the subtitle near the playhead.
    final segs = provider.currentProject?.segments ?? [];
    String seed = '';
    for (final s in segs) {
      if (_position >= s.startTime && _position <= s.endTime) {
        seed = s.text;
        break;
      }
    }
    final queryCtrl = TextEditingController(text: seed);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        List<WebImage> results = [];
        bool loading = false;
        bool inserting = false;
        int source = 0; // 0 = images (Openverse), 1 = meme GIF (Tenor)
        bool needTenorKey = false;
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> runSearch() async {
            FocusScope.of(ctx).unfocus();
            setSheet(() {
              loading = true;
              needTenorKey = false;
            });
            List<WebImage> r;
            if (source == 1) {
              // Meme GIF: works with no key (Tenor v1) — uses the user's own
              // Tenor v2 key if they added one (better quota).
              final tk = await ApiConfig.getTenorKey();
              r = await ImageSearchService.searchMeme(queryCtrl.text, userKey: tk);
            } else {
              r = await ImageSearchService.search(queryCtrl.text);
            }
            setSheet(() {
              results = r;
              loading = false;
            });
          }

          Future<void> aiKeyword() async {
            final apiKey = await ApiConfig.getApiKey();
            if (apiKey == null || apiKey.isEmpty || queryCtrl.text.trim().isEmpty) {
              return;
            }
            setSheet(() => loading = true);
            try {
              final en = await GeminiSpeechService(apiKey: apiKey)
                  .translateTexts([queryCtrl.text.trim()], 'en');
              if (en.isNotEmpty && en.first.trim().isNotEmpty) {
                queryCtrl.text = en.first.trim();
              }
            } catch (_) {}
            await runSearch();
          }

          Future<void> insert(WebImage img) async {
            if (inserting) return;
            setSheet(() => inserting = true);
            final path =
                await ImageSearchService.download(img.full, fallbackUrl: img.thumb);
            setSheet(() => inserting = false);
            if (path == null) {
              _toast(tr('ed.webImageFail'));
              return;
            }
            final startMs = _position.inMilliseconds;
            final endMs = (startMs + 3000).clamp(0, _duration.inMilliseconds);
            final overlay = ImageOverlay(
              id: const Uuid().v4(),
              path: path,
              startTime: Duration(milliseconds: startMs),
              endTime:
                  Duration(milliseconds: endMs <= startMs ? startMs + 3000 : endMs),
            );
            provider.addImageOverlay(overlay);
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              setState(() => _selectedImageId = overlay.id);
              _toast(tr('ed.imageAdded'));
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.image_search, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(tr('ed.webImage'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(source == 1 ? tr('ed.gifNote') : tr('ed.webImageHelp'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                  const SizedBox(height: 10),
                  // Source toggle: Image (Openverse) vs Meme GIF (Tenor).
                  Row(children: [
                    for (int sIdx = 0; sIdx < 2; sIdx++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(sIdx == 0 ? tr('ed.srcImage') : tr('ed.srcMeme')),
                          selected: source == sIdx,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                              color: source == sIdx ? Colors.white : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surfaceLight,
                          onSelected: (_) => setSheet(() {
                            source = sIdx;
                            results = [];
                            needTenorKey = false;
                          }),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: queryCtrl,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(),
                        decoration: InputDecoration(
                          hintText: tr('ed.webImageHint'),
                          hintStyle: const TextStyle(color: AppColors.textHint),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: loading ? null : runSearch,
                      icon: const Icon(Icons.search, color: AppColors.primary),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: loading ? null : aiKeyword,
                      icon: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFFFB703)),
                      label: Text(tr('ed.webImageAi'),
                          style: const TextStyle(color: Color(0xFFFFB703), fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 300,
                    child: loading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : needTenorKey
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(tr('ed.needTenorKey'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppColors.textHint)),
                                    const SizedBox(height: 10),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => const SettingsScreen()));
                                      },
                                      icon: const Icon(Icons.settings, size: 16),
                                      label: Text(tr('ed.goToSettings')),
                                    ),
                                  ],
                                ),
                              )
                            : results.isEmpty
                            ? Center(
                                child: Text(tr('ed.webImageEmpty'),
                                    style: const TextStyle(color: AppColors.textHint)))
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                                itemCount: results.length,
                                itemBuilder: (_, i) => GestureDetector(
                                  onTap: inserting ? null : () => insert(results[i]),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      results[i].thumb,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                          color: AppColors.surfaceLight,
                                          child: const Icon(Icons.broken_image,
                                              color: AppColors.textHint)),
                                    ),
                                  ),
                                ),
                              ),
                  ),
                  if (inserting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                        Text(tr('ed.webImageInserting'),
                            style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                      ]),
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  /// Sticker picker — browse Twemoji emoji (colourful) or search any free icon
  /// (Iconify). The chosen SVG is rasterised to PNG and dropped in as an
  /// [ImageOverlay] at the playhead, so drag/scale/keyframe/export all reuse the
  /// existing overlay pipeline.
  void _showStickerSheet(ProjectProvider provider) {
    if (provider.currentProject == null) return;
    _pauseForEdit();
    HapticFeedback.selectionClick();
    const cats = ['faces', 'gestures', 'hot', 'symbols', 'objects'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        int tab = 0; // 0 = emoji, 1 = icon search
        String cat = cats.first;
        final queryCtrl = TextEditingController();
        List<String> iconResults = [];
        bool loading = false;
        bool inserting = false;

        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> insert(String svgUrl, {required bool tinted}) async {
            if (inserting) return;
            setSheet(() => inserting = true);
            final path = await StickerService.downloadAsPng(svgUrl,
                size: 384, prefix: tinted ? 'icon' : 'emoji');
            if (path == null) {
              setSheet(() => inserting = false);
              _toast(tr('ed.stickerFail'));
              return;
            }
            final startMs = _position.inMilliseconds;
            final endMs = (startMs + 3000).clamp(0, _duration.inMilliseconds);
            final overlay = ImageOverlay(
              id: const Uuid().v4(),
              path: path,
              startTime: Duration(milliseconds: startMs),
              endTime: Duration(
                  milliseconds: endMs <= startMs ? startMs + 3000 : endMs),
              scale: 0.3,
            );
            provider.addImageOverlay(overlay);
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              setState(() => _selectedImageId = overlay.id);
              _toast(tr('ed.stickerAdded'));
            }
          }

          Future<void> runSearch() async {
            FocusScope.of(ctx).unfocus();
            if (queryCtrl.text.trim().isEmpty) return;
            setSheet(() => loading = true);
            final r = await StickerService.searchIcons(queryCtrl.text.trim());
            setSheet(() {
              iconResults = r;
              loading = false;
            });
          }

          Widget tile(Widget child, VoidCallback onTap) => GestureDetector(
                onTap: inserting ? null : onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: child,
                ),
              );

          final emojiNames = StickerService.emojiCategories[cat] ?? const [];

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.emoji_emotions,
                        color: Color(0xFFFFCA28)),
                    const SizedBox(width: 8),
                    Text(tr('ed.stickerTitle'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(tr('ed.stickerHelp'),
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 11)),
                  const SizedBox(height: 10),
                  // Emoji vs Icon-search toggle.
                  Row(children: [
                    for (int t = 0; t < 2; t++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                              t == 0 ? tr('ed.stickerEmoji') : tr('ed.stickerIcon')),
                          selected: tab == t,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                              color: tab == t
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surfaceLight,
                          onSelected: (_) => setSheet(() => tab = t),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  if (tab == 0) ...[
                    // Category chips.
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final c in cats)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(tr('ed.cat_$c')),
                                selected: cat == c,
                                showCheckmark: false,
                                labelStyle: TextStyle(
                                    color: cat == c
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                                selectedColor: const Color(0xFFFFCA28),
                                backgroundColor: AppColors.surfaceLight,
                                onSelected: (_) => setSheet(() => cat = c),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 300,
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: emojiNames.length,
                        itemBuilder: (_, i) {
                          final url =
                              StickerService.twemojiSvgUrl(emojiNames[i]);
                          return tile(
                            SvgPicture.network(url,
                                placeholderBuilder: (_) => const Center(
                                    child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)))),
                            () => insert(url, tinted: false),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: queryCtrl,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 14),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => runSearch(),
                          decoration: InputDecoration(
                            hintText: tr('ed.stickerSearchHint'),
                            hintStyle: const TextStyle(color: AppColors.textHint),
                            filled: true,
                            fillColor: AppColors.surfaceLight,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: loading ? null : runSearch,
                        icon: const Icon(Icons.search, color: AppColors.primary),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 280,
                      child: loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary))
                          : iconResults.isEmpty
                              ? Center(
                                  child: Text(tr('ed.stickerSearchEmpty'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: AppColors.textHint)))
                              : GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 5,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                                  itemCount: iconResults.length,
                                  itemBuilder: (_, i) {
                                    final url = StickerService.iconifySvgUrl(
                                        iconResults[i],
                                        color: 'white');
                                    return tile(
                                      SvgPicture.network(url,
                                          placeholderBuilder: (_) => const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))),
                                      () => insert(url, tinted: true),
                                    );
                                  },
                                ),
                    ),
                  ],
                  if (inserting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text(tr('ed.stickerInserting'),
                                style: const TextStyle(
                                    color: AppColors.textHint, fontSize: 12)),
                          ]),
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  /// Search B-roll VIDEO clips from the web (Pixabay) and drop a chosen one in
  /// as a full-screen video overlay at the playhead.
  void _showWebBrollSheet(ProjectProvider provider) {
    if (!_isPro) {
      _showProFeatureDialog(tr('ed.brollPro'));
      return;
    }
    _pauseForEdit();
    final segs = provider.currentProject?.segments ?? [];
    String seed = '';
    for (final s in segs) {
      if (_position >= s.startTime && _position <= s.endTime) {
        seed = s.text;
        break;
      }
    }
    final queryCtrl = TextEditingController(text: seed);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        List<WebVideo> results = [];
        bool loading = false;
        bool inserting = false;
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> runSearch() async {
            FocusScope.of(ctx).unfocus();
            setSheet(() => loading = true);
            final r = await ImageSearchService.searchVideoDetailed(queryCtrl.text);
            setSheet(() {
              results = r;
              loading = false;
            });
          }

          Future<void> aiKeyword() async {
            final apiKey = await ApiConfig.getApiKey();
            if (apiKey == null || apiKey.isEmpty || queryCtrl.text.trim().isEmpty) {
              return;
            }
            setSheet(() => loading = true);
            try {
              final en = await GeminiSpeechService(apiKey: apiKey)
                  .translateTexts([queryCtrl.text.trim()], 'en');
              if (en.isNotEmpty && en.first.trim().isNotEmpty) {
                queryCtrl.text = en.first.trim();
              }
            } catch (_) {}
            await runSearch();
          }

          Future<void> insert(WebVideo vid) async {
            if (inserting) return;
            setSheet(() => inserting = true);
            final path = await ImageSearchService.downloadVideo(vid.url);
            if (path == null) {
              setSheet(() => inserting = false);
              _toast(tr('ed.webImageFail'));
              return;
            }
            int clipMs = 4000;
            try {
              final probe = VideoPlayerController.file(File(path));
              await probe.initialize();
              clipMs = probe.value.duration.inMilliseconds;
              await probe.dispose();
            } catch (_) {}
            final startMs = _position.inMilliseconds;
            final span = clipMs.clamp(1000, 6000);
            var endMs = startMs + span;
            if (_duration.inMilliseconds > 0 && endMs > _duration.inMilliseconds) {
              endMs = _duration.inMilliseconds;
            }
            if (endMs <= startMs) endMs = startMs + span;
            final overlay = ImageOverlay(
              id: const Uuid().v4(),
              path: path,
              startTime: Duration(milliseconds: startMs),
              endTime: Duration(milliseconds: endMs),
              x: 0.5,
              y: 0.40,
              scale: 1.0,
              isVideo: true,
              cover: true,
            );
            provider.addImageOverlay(overlay);
            _ensureBrollControllers(provider.currentProject);
            setSheet(() => inserting = false);
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              setState(() => _selectedImageId = overlay.id);
              _toast(tr('ed.brollAdded'));
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.ondemand_video, color: Color(0xFF7C4DFF)),
                    const SizedBox(width: 8),
                    Text(tr('ed.webBroll'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(tr('ed.webBrollHelp'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: queryCtrl,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(),
                        decoration: InputDecoration(
                          hintText: tr('ed.webImageHint'),
                          hintStyle: const TextStyle(color: AppColors.textHint),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: loading ? null : runSearch,
                      icon: const Icon(Icons.search, color: Color(0xFF7C4DFF)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: loading ? null : aiKeyword,
                      icon: const Icon(Icons.auto_awesome,
                          size: 16, color: Color(0xFFFFB703)),
                      label: Text(tr('ed.webImageAi'),
                          style: const TextStyle(
                              color: Color(0xFFFFB703), fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 300,
                    child: loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF7C4DFF)))
                        : results.isEmpty
                            ? Center(
                                child: Text(tr('ed.webBrollEmpty'),
                                    style: const TextStyle(
                                        color: AppColors.textHint)))
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 16 / 9,
                                ),
                                itemCount: results.length,
                                itemBuilder: (_, i) => GestureDetector(
                                  onTap:
                                      inserting ? null : () => insert(results[i]),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          results[i].thumb,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                              color: AppColors.surfaceLight,
                                              child: const Icon(Icons.movie,
                                                  color: AppColors.textHint)),
                                        ),
                                        const Center(
                                          child: Icon(Icons.play_circle_fill,
                                              color: Colors.white70, size: 34),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                  ),
                  if (inserting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text(tr('ed.webBrollInserting'),
                                style: const TextStyle(
                                    color: AppColors.textHint, fontSize: 12)),
                          ]),
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  /// Search the BBC Sound Effects archive (keyless) and drop a chosen sound in
  /// as a custom SFX block at the playhead. Downloads WAV so export works.
  void _showWebSfxSheet(ProjectProvider provider) {
    _pauseForEdit();
    final segs = provider.currentProject?.segments ?? [];
    String seed = '';
    for (final s in segs) {
      if (_position >= s.startTime && _position <= s.endTime) {
        seed = s.text;
        break;
      }
    }
    final queryCtrl = TextEditingController(text: seed);
    final previewPlayer = AudioPlayer();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        List<WebSfx> results = [];
        bool loading = false;
        bool inserting = false;
        String? playingId;
        int sfxSource = 0; // 0 = Freesound (meme/UI, needs token), 1 = BBC (realistic, keyless)
        bool needFreesoundKey = false;
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> runSearch() async {
            FocusScope.of(ctx).unfocus();
            setSheet(() {
              loading = true;
              needFreesoundKey = false;
            });
            List<WebSfx> r;
            if (sfxSource == 0) {
              final token = await ApiConfig.getFreesoundKey();
              if (token == null || token.trim().isEmpty) {
                setSheet(() {
                  loading = false;
                  needFreesoundKey = true;
                  results = [];
                });
                return;
              }
              r = await SfxSearchService.searchFreesound(queryCtrl.text, token);
            } else {
              r = await SfxSearchService.search(queryCtrl.text);
            }
            setSheet(() {
              results = r;
              loading = false;
            });
          }

          Future<void> aiKeyword() async {
            final apiKey = await ApiConfig.getApiKey();
            if (apiKey == null ||
                apiKey.isEmpty ||
                queryCtrl.text.trim().isEmpty) {
              return;
            }
            setSheet(() => loading = true);
            try {
              final en = await GeminiSpeechService(apiKey: apiKey)
                  .translateTexts([queryCtrl.text.trim()], 'en');
              if (en.isNotEmpty && en.first.trim().isNotEmpty) {
                queryCtrl.text = en.first.trim();
              }
            } catch (_) {}
            await runSearch();
          }

          Future<void> preview(WebSfx s) async {
            try {
              if (playingId == s.id) {
                await previewPlayer.stop();
                setSheet(() => playingId = null);
                return;
              }
              await previewPlayer.stop();
              await previewPlayer.play(UrlSource(s.mp3Url));
              setSheet(() => playingId = s.id);
              previewPlayer.onPlayerComplete.first.then((_) {
                if (ctx.mounted) setSheet(() => playingId = null);
              });
            } catch (_) {}
          }

          Future<void> insert(WebSfx s) async {
            if (inserting) return;
            setSheet(() => inserting = true);
            var path = await SfxSearchService.download(s);
            // Freesound previews are mp3 → decode to WAV so export can read it.
            if (path != null && s.needsDecode) {
              try {
                const ch = MethodChannel('com.anniekaydee.subtitle_app/audio');
                final wavPath = path.replaceAll(RegExp(r'\.mp3$'), '.wav');
                await ch.invokeMethod('extractAudio',
                    {'videoPath': path, 'outputPath': wavPath});
                final wf = File(wavPath);
                if (wf.existsSync() && wf.lengthSync() > 44) {
                  try { File(path).deleteSync(); } catch (_) {}
                  path = wavPath;
                }
              } catch (_) {/* keep mp3 — preview works, export best-effort */}
            }
            setSheet(() => inserting = false);
            if (path == null) {
              _toast(tr('ed.webSfxFail'));
              return;
            }
            final durMs = s.durationMs > 0 ? s.durationMs : 1500;
            provider.addSfxBlock(SfxBlock(
              id: const Uuid().v4(),
              type: SfxType.pop, // placeholder; isCustom drives behaviour
              startTime: _position,
              duration: Duration(milliseconds: durMs),
              isCustom: true,
              customPath: path,
              customName: s.title,
            ));
            await previewPlayer.stop();
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              setState(() {});
              _toast(tr('ed.webSfxAdded'));
            }
          }

          String fmtDur(int ms) {
            final sec = (ms / 1000);
            return '${sec.toStringAsFixed(sec < 10 ? 1 : 0)}s';
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.library_music, color: Color(0xFF00BFA5)),
                    const SizedBox(width: 8),
                    Text(tr('ed.webSfx'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(tr('ed.webSfxHelp'),
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 11)),
                  const SizedBox(height: 10),
                  // Source toggle: Freesound (meme/UI) vs BBC (realistic).
                  Row(children: [
                    for (int sIdx = 0; sIdx < 2; sIdx++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(sIdx == 0 ? tr('ed.srcMeme2') : tr('ed.srcReal')),
                          selected: sfxSource == sIdx,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                              color: sfxSource == sIdx ? Colors.white : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          selectedColor: const Color(0xFF00BFA5),
                          backgroundColor: AppColors.surfaceLight,
                          onSelected: (_) => setSheet(() {
                            sfxSource = sIdx;
                            results = [];
                            needFreesoundKey = false;
                          }),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: queryCtrl,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(),
                        decoration: InputDecoration(
                          hintText: tr('ed.webSfxHint'),
                          hintStyle: const TextStyle(color: AppColors.textHint),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: loading ? null : runSearch,
                      icon: const Icon(Icons.search, color: Color(0xFF00BFA5)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: loading ? null : aiKeyword,
                      icon: const Icon(Icons.auto_awesome,
                          size: 16, color: Color(0xFFFFB703)),
                      label: Text(tr('ed.webImageAi'),
                          style: const TextStyle(
                              color: Color(0xFFFFB703), fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 320,
                    child: loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF00BFA5)))
                        : needFreesoundKey
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(tr('ed.needFreesound'),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: AppColors.textHint)),
                                        const SizedBox(height: 10),
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        const SettingsScreen()));
                                          },
                                          icon: const Icon(Icons.settings, size: 16),
                                          label: Text(tr('ed.goToSettings')),
                                        ),
                                      ]),
                                ),
                              )
                            : results.isEmpty
                            ? Center(
                                child: Text(tr('ed.webSfxEmpty'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: AppColors.textHint)))
                            : ListView.separated(
                                itemCount: results.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, color: AppColors.border),
                                itemBuilder: (_, i) {
                                  final s = results[i];
                                  final isPlaying = playingId == s.id;
                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 4),
                                    leading: IconButton(
                                      onPressed: () => preview(s),
                                      icon: Icon(
                                          isPlaying
                                              ? Icons.stop_circle
                                              : Icons.play_circle_fill,
                                          color: const Color(0xFF00BFA5),
                                          size: 30),
                                    ),
                                    title: Text(s.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13)),
                                    subtitle: Text(fmtDur(s.durationMs),
                                        style: const TextStyle(
                                            color: AppColors.textHint,
                                            fontSize: 11)),
                                    trailing: inserting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : TextButton.icon(
                                            onPressed: () => insert(s),
                                            icon: const Icon(Icons.add,
                                                size: 16,
                                                color: Color(0xFF00BFA5)),
                                            label: Text(tr('ed.webSfxInsert'),
                                                style: const TextStyle(
                                                    color: Color(0xFF00BFA5),
                                                    fontSize: 12)),
                                          ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    ).whenComplete(() => previewPlayer.dispose());
  }

  void _deleteImageOverlay(ProjectProvider provider, String id) {
    final project = provider.currentProject;
    final o = project?.imageOverlays.where((e) => e.id == id).firstOrNull;
    provider.removeImageOverlay(id);
    try { if (o != null) File(o.path).deleteSync(); } catch (_) {}
    setState(() => _selectedImageId = null);
    _toast(tr('ed.imageDeleted'));
  }

  void _rotateImageOverlay(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    provider.pushHistory();
    o.rotation = (o.rotation + 90) % 360;
    provider.commit();
    setState(() {});
  }

  void _flipImageOverlay(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    provider.pushHistory();
    o.flipH = !o.flipH;
    provider.commit();
    setState(() {});
  }

  /// Toggle an overlay between full-screen (cover) and normal (band) placement.
  void _toggleCover(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    provider.pushHistory();
    o.cover = !o.cover;
    provider.commit();
    setState(() {});
    _toast(tr(o.cover ? 'ed.coverOnDone' : 'ed.coverOffDone'));
  }

  /// Overlay keyframe at the playhead (within tolerance), or null.
  OverlayKeyframe? _overlayKfAtPlayhead(ImageOverlay o, {int tolMs = 120}) {
    final ms = _position.inMilliseconds;
    for (final k in o.keyframes) {
      if ((k.timeMs - ms).abs() <= tolMs) return k;
    }
    return null;
  }

  /// CapCut-style toggle: if a keyframe sits at the playhead → delete it;
  /// otherwise add one capturing the current state.
  void _toggleOverlayKeyframe(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    final hit = _overlayKfAtPlayhead(o);
    provider.pushHistory();
    if (hit != null) {
      o.keyframes.remove(hit);
      provider.commit();
      setState(() {});
      _toast(tr('ed.kfDeleted'));
    } else {
      _overlayKeyframeAtPlayhead(o);
      provider.commit();
      setState(() {});
      _toast(tr('ed.kfCaptured'));
    }
  }

  /// Zoom keyframe (on the selected clip) at the playhead, or null.
  ZoomKeyframe? _clipZoomKfAtPlayhead(SubtitleProject project, {int tolMs = 120}) {
    if (_selectedClipIndex == null) return null;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) return null;
    final clip = clips[_selectedClipIndex!];
    final ms = _position.inMilliseconds;
    for (final z in project.zoomEffects) {
      if (clip.start < z.endTime.inMilliseconds &&
          z.startTime.inMilliseconds < clip.end) {
        for (final k in z.keyframes) {
          if ((k.timeMs - ms).abs() <= tolMs) return k;
        }
      }
    }
    return null;
  }

  /// CapCut-style toggle for the selected clip's zoom keyframe at the playhead.
  void _toggleClipKeyframe(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || _selectedClipIndex == null) return;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) return;
    final clip = clips[_selectedClipIndex!];
    final ms = _position.inMilliseconds;
    ZoomEffect? z;
    for (final e in project.zoomEffects) {
      if (clip.start < e.endTime.inMilliseconds &&
          e.startTime.inMilliseconds < clip.end) {
        z = e;
        break;
      }
    }
    ZoomKeyframe? hit;
    if (z != null) {
      for (final k in z.keyframes) {
        if ((k.timeMs - ms).abs() <= 120) {
          hit = k;
          break;
        }
      }
    }
    provider.pushHistory();
    if (hit != null && z != null) {
      z.keyframes.remove(hit);
      if (z.keyframes.isEmpty) project.zoomEffects.remove(z);
      provider.commit();
      setState(() {});
      _toast(tr('ed.kfDeleted'));
    } else {
      final zz = z ?? _ensureZoomForSelectedClip(provider);
      if (zz == null) return;
      _keyframeAtPlayhead(zz);
      provider.commit();
      setState(() {});
      _toast(tr('ed.kfCaptured'));
    }
  }

  /// Curve (easing) picker for the keyframe at the playhead. [current] = current
  /// easing index; [onPick] receives the chosen one (0..5).
  void _showEasingSheet(int current, void Function(int) onPick) {
    _pauseForEdit();
    final items = <(int, IconData, String)>[
      (0, Icons.trending_flat, 'ed.easeLinear'),
      (1, Icons.north_east, 'ed.easeIn'),
      (2, Icons.south_east, 'ed.easeOut'),
      (3, Icons.waves, 'ed.easeInOut'),
      (4, Icons.keyboard_double_arrow_up, 'ed.easeCubicIn'),
      (5, Icons.keyboard_double_arrow_down, 'ed.easeCubicOut'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.show_chart, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(tr('ed.easeTitle'),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 6),
                ...items.map((it) {
                  final sel = current == it.$1;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(it.$2,
                        color: sel ? AppColors.primary : AppColors.textSecondary),
                    title: Text(tr(it.$3),
                        style: TextStyle(
                            color: sel
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                    trailing: sel
                        ? const Icon(Icons.check, color: AppColors.primary, size: 18)
                        : null,
                    onTap: () {
                      onPick(it.$1);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Opacity slider for the selected overlay. In keyframe mode it writes to the
  /// keyframe at the playhead; otherwise it sets the static opacity.
  void _showOverlayOpacitySheet(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    _pauseForEdit();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        double val = _overlayStateAt(o, _position.inMilliseconds).opacity;
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.opacity, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(tr('ed.opacity'),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${(val * 100).round()}%',
                      style: const TextStyle(color: AppColors.textHint)),
                ]),
                Slider(
                  value: val,
                  min: 0.0,
                  max: 1.0,
                  activeColor: AppColors.primary,
                  onChangeStart: (_) => provider.pushHistory(),
                  onChanged: (v) {
                    setSheet(() => val = v);
                    if (o.keyframes.isNotEmpty) {
                      _overlayKeyframeAtPlayhead(o).opacity = v;
                    } else {
                      o.opacity = v;
                    }
                    provider.liveUpdate();
                    setState(() {});
                  },
                  onChangeEnd: (_) => provider.commit(),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  void _showImageScaleSheet(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('ed.imageSize'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: o.scale.clamp(0.1, 3.0),
                        min: 0.1,
                        max: 3.0,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.border,
                        onChanged: (v) {
                          setSheet(() => o.scale = v);
                          provider.liveUpdate();
                          setState(() {});
                        },
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${(o.scale * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => provider.commit());
  }

  Future<void> _pickCustomAudio(ProjectProvider provider) async {
    Navigator.pop(context); // Close sheet
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );
    if (result == null || result.files.single.path == null) return;
    final srcPath = result.files.single.path!;
    final name = result.files.single.name;

    // Show a quick progress toast while decoding (MP3/M4A → WAV).
    _toast(tr('ed.addingAudio'));
    try {
      // Decode ANY audio format (MP3/M4A/WAV) into a 44.1kHz mono WAV via the
      // native MediaCodec extractor, so both preview AND export can read it.
      final supportDir = await getApplicationSupportDirectory();
      final sfxDir = Directory(p.join(supportDir.path, 'custom_sfx'));
      if (!sfxDir.existsSync()) sfxDir.createSync(recursive: true);
      final wavPath = p.join(
          sfxDir.path, 'sfx_${DateTime.now().millisecondsSinceEpoch}.wav');

      const channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
      await channel.invokeMethod('extractAudio', {
        'videoPath': srcPath,
        'outputPath': wavPath,
      });

      // Read the decoded WAV header to get the true duration.
      final f = File(wavPath);
      if (!f.existsSync() || f.lengthSync() <= 44) {
        _showErrorBanner(tr('ed.cantReadAudio'));
        return;
      }
      final raf = await f.open();
      final hdr = await raf.read(44);
      await raf.close();
      final wavLen = f.lengthSync();
      final bd = ByteData.sublistView(hdr);
      final chs = bd.getInt16(22, Endian.little);
      final sr = bd.getInt32(24, Endian.little);
      final bps = bd.getInt16(34, Endian.little) ~/ 8;
      final durMs = (sr * chs * bps) > 0
          ? ((wavLen - 44) / (sr * chs * bps) * 1000).round()
          : 1000;

      provider.addSfxBlock(SfxBlock(
        id: const Uuid().v4(),
        type: SfxType.pop, // placeholder; isCustom drives behaviour
        startTime: _position,
        duration: Duration(milliseconds: durMs),
        isCustom: true,
        customPath: wavPath,
        customName: name,
      ));
      _toast(tr('ed.audioAdded', {'name': name}));
    } catch (e) {
      _showErrorBanner(tr('ed.audioAddFail', {'e': e.toString()}));
    }
  }

  void _showAddSfxSheet(ProjectProvider provider) {
    _pauseForEdit();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DefaultTabController(
          length: 4,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Add SFX',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TabBar(
                      isScrollable: true,
                      indicatorColor: AppColors.primary,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.white54,
                      tabs: [
                        Tab(text: tr('ed.sfxTab.funny')),
                        Tab(text: tr('ed.sfxTab.motion')),
                        Tab(text: tr('ed.sfxTab.general')),
                        Tab(text: tr('ed.sfxTab.mine')),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Tab 1: ຕະຫຼົກ/ຕີ (Funny/Hits)
                          ListView(
                            children: [
                              _buildSfxTile(context, provider, SfxType.pop, '🔥', 'ສຽງ Pop', 'ຍອດນິຍົມ'),
                              _buildSfxTile(context, provider, SfxType.pop2, '🔥', 'ສຽງ Pop 2', 'ຍອດນິຍົມ 2'),
                              _buildSfxTile(context, provider, SfxType.punch, '👊', 'ສຽງ Punch', 'ສຽງຕີ/ຊົກ'),
                              _buildSfxTile(context, provider, SfxType.punch2, '👊', 'ສຽງ Punch 2', 'ສຽງຕີ/ຊົກ 2'),
                              _buildSfxTile(context, provider, SfxType.slap, '🖐️', 'ສຽງ Slap', 'ສຽງຕົບໜ້າ'),
                              _buildSfxTile(context, provider, SfxType.wow, '😲', 'ສຽງ Wow', 'ສຽງວ້າວ'),
                              _buildSfxTile(context, provider, SfxType.cricket, '🦗', 'ສຽງ Cricket', 'ສຽງຈີ່ຫຼໍ່ (ງຽບ/ຈືດ)'),
                              _buildSfxTile(context, provider, SfxType.vineBoom, '💥', 'ສຽງ Vine Boom', 'ສຽງຕຸ້ມແບບມີມດັງໆ'),
                              _buildSfxTile(context, provider, SfxType.laugh, '😂', 'ສຽງ Laugh', 'ສຽງຫົວເລາະ'),
                              _buildSfxTile(context, provider, SfxType.boing, '🪀', 'ສຽງ Boing', 'ສຽງເດັ້ງດຶ໋ງ'),
                              _buildSfxTile(context, provider, SfxType.thud, '📦', 'ສຽງ Thud', 'ສຽງຂອງຕົກໜັກໆ'),
                              _buildSfxTile(context, provider, SfxType.squeak, '🐭', 'ສຽງ Squeak', 'ສຽງບີບໜູ'),
                              _buildSfxTile(context, provider, SfxType.quack, '🦆', 'ສຽງ Quack', 'ສຽງເປັດ'),
                              _buildSfxTile(context, provider, SfxType.pop3, '🔥', 'ສຽງ Pop 3', 'ຍອດນິຍົມ 3'),
                              _buildSfxTile(context, provider, SfxType.pop4, '🔥', 'ສຽງ Pop 4', 'ຍອດນິຍົມ 4'),
                              _buildSfxTile(context, provider, SfxType.pop5, '🔥', 'ສຽງ Pop 5', 'ຍອດນິຍົມ 5'),
                              _buildSfxTile(context, provider, SfxType.punch3, '👊', 'ສຽງ Punch 3', 'ສຽງຕີ/ຊົກ 3'),
                              _buildSfxTile(context, provider, SfxType.punch4, '👊', 'ສຽງ Punch 4', 'ສຽງຕີ/ຊົກ 4'),
                              _buildSfxTile(context, provider, SfxType.punch5, '👊', 'ສຽງ Punch 5', 'ສຽງຕີ/ຊົກ 5'),
                              _buildSfxTile(context, provider, SfxType.slap2, '🖐️', 'ສຽງ Slap 2', 'ສຽງຕົບໜ້າ 2'),
                              _buildSfxTile(context, provider, SfxType.wow2, '😲', 'ສຽງ Wow 2', 'ສຽງວ້າວ 2'),
                              _buildSfxTile(context, provider, SfxType.squeak2, '🐭', 'ສຽງ Squeak 2', 'ສຽງບີບໜູ 2'),
                              _buildSfxTile(context, provider, SfxType.squeak3, '🐭', 'ສຽງ Squeak 3', 'ສຽງບີບໜູ 3'),
                              _buildSfxTile(context, provider, SfxType.squeak4, '🐭', 'ສຽງ Squeak 4', 'ສຽງບີບໜູ 4'),
                              _buildSfxTile(context, provider, SfxType.squeek, '🐭', 'ສຽງ Squeek', 'ສຽງບີບໜູ (ອື່ນ)'),
                            ],
                          ),
                          // Tab 2: ການເຄື່ອນໄຫວ (Movement)
                          ListView(
                            children: [
                              _buildSfxTile(context, provider, SfxType.swoosh, '💨', 'ສຽງ Swoosh', 'ສຽງປາດ'),
                              _buildSfxTile(context, provider, SfxType.swoosh2, '💨', 'ສຽງ Swoosh 2', 'ສຽງປາດ 2'),
                              _buildSfxTile(context, provider, SfxType.whoosh, '🌬️', 'ສຽງ Whoosh', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່'),
                              _buildSfxTile(context, provider, SfxType.whoosh2, '🌬️', 'ສຽງ Whoosh 2', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 2'),
                              _buildSfxTile(context, provider, SfxType.whoosh3, '🌬️', 'ສຽງ Whoosh 3', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 3'),
                              _buildSfxTile(context, provider, SfxType.whoosh4, '🌬️', 'ສຽງ Whoosh 4', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 4'),
                              _buildSfxTile(context, provider, SfxType.whoosh5, '🌬️', 'ສຽງ Whoosh 5', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 5'),
                              _buildSfxTile(context, provider, SfxType.whoosh6, '🌬️', 'ສຽງ Whoosh 6', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 6'),
                              _buildSfxTile(context, provider, SfxType.whoosh7, '🌬️', 'ສຽງ Whoosh 7', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 7'),
                              _buildSfxTile(context, provider, SfxType.whoosh8, '🌬️', 'ສຽງ Whoosh 8', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 8'),
                              _buildSfxTile(context, provider, SfxType.whoosh9, '🌬️', 'ສຽງ Whoosh 9', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 9'),
                              _buildSfxTile(context, provider, SfxType.whoosh10, '🌬️', 'ສຽງ Whoosh 10', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 10'),
                            ],
                          ),
                          // Tab 3: ທົ່ວໄປ (Misc)
                          ListView(
                            children: [
                              _buildSfxTile(context, provider, SfxType.ding, '🔔', 'ສຽງ Ding', 'ສຽງກະດິ່ງ/ແຈ້ງເຕືອນ'),
                              _buildSfxTile(context, provider, SfxType.ding2, '🔔', 'ສຽງ Ding 2', 'ສຽງກະດິ່ງ/ແຈ້ງເຕືອນ 2'),
                              _buildSfxTile(context, provider, SfxType.applause, '👏', 'ສຽງ Applause', 'ສຽງຕົບມື'),
                              _buildSfxTile(context, provider, SfxType.cameraShutter, '📸', 'ສຽງ Camera Shutter', 'ສຽງກົດຊັດເຕີກ້ອງ'),
                              _buildSfxTile(context, provider, SfxType.cashRegister, '💰', 'ສຽງ Cash Register', 'ສຽງເຄື່ອງຄິດເງິນ'),
                              _buildSfxTile(context, provider, SfxType.recordScratch, '💿', 'ສຽງ Record Scratch', 'ສຽງແຜ່ນສຽງສະດຸດ'),
                              _buildSfxTile(context, provider, SfxType.badumtss, '🥁', 'ສຽງ Ba Dum Tss', 'ສຽງກອງຮັບມຸກຕະລົກ'),
                              _buildSfxTile(context, provider, SfxType.beep, '🤖', 'ສຽງ Beep', 'ສຽງບີບ'),
                              _buildSfxTile(context, provider, SfxType.correct, '✅', 'ສຽງ Correct', 'ສຽງຖືກຕ້ອງ'),
                              _buildSfxTile(context, provider, SfxType.buzzer, '❌', 'ສຽງ Buzzer', 'ສຽງຜິດພາດ/ໝົດເວລາ'),
                              _buildSfxTile(context, provider, SfxType.magic, '🪄', 'ສຽງ Magic', 'ສຽງເວດມົນ'),
                              _buildSfxTile(context, provider, SfxType.typing, '⌨️', 'ສຽງ Typing', 'ສຽງພິມຄີບອດ'),
                              _buildSfxTile(context, provider, SfxType.glitch, '📺', 'ສຽງ Glitch', 'ສຽງໂທລະທັດຊ໋ອດ'),
                              _buildSfxTile(context, provider, SfxType.airhorn, '📯', 'ສຽງ Airhorn', 'ສຽງແກລົມ'),
                              _buildSfxTile(context, provider, SfxType.cameraShutter2, '📸', 'ສຽງ Camera Shutter 2', 'ສຽງກົດຊັດເຕີກ້ອງ 2'),
                              _buildSfxTile(context, provider, SfxType.cameraShutter3, '📸', 'ສຽງ Camera Shutter 3', 'ສຽງກົດຊັດເຕີກ້ອງ 3'),
                              _buildSfxTile(context, provider, SfxType.cashRegister2, '💰', 'ສຽງ Cash Register 2', 'ສຽງເຄື່ອງຄິດເງິນ 2'),
                              _buildSfxTile(context, provider, SfxType.recordScratch2, '💿', 'ສຽງ Record Scratch 2', 'ສຽງແຜ່ນສຽງສະດຸດ 2'),
                              _buildSfxTile(context, provider, SfxType.badumtss2, '🥁', 'ສຽງ Ba Dum Tss 2', 'ສຽງກອງຮັບມຸກຕະລົກ 2'),
                            ],
                          ),
                          // Tab 4: ສຽງຂອງຂ້ອຍ (My Audio)
                          ListView(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.audio_file, color: AppColors.primary, size: 32),
                                title: Text(tr('ed.pickFromDevice'), style: const TextStyle(color: Colors.white)),
                                subtitle: Text(tr('ed.supportFormats'), style: const TextStyle(color: Colors.white54)),
                                trailing: const Icon(Icons.add_circle, color: AppColors.primary),
                                onTap: () => _pickCustomAudio(provider),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Thin a set of auto-SFX candidates so they don't spam the ear: enforce a
  /// minimum gap between sounds, never the same sound twice in a row, and cap the
  /// total. Returns ready-to-add blocks (sorted by time).
  List<SfxBlock> _thinAutoSfx(
    List<({int ms, SfxType type})> cands, {
    int minGapMs = 2500,
    int cap = 12,
  }) {
    cands.sort((a, b) => a.ms.compareTo(b.ms));
    final out = <SfxBlock>[];
    int lastMs = -1 << 30;
    SfxType? lastType;
    for (final c in cands) {
      if (out.length >= cap) break;
      if (c.ms - lastMs < minGapMs) continue; // too close → skip
      if (c.type == lastType) continue; // no identical sound back-to-back
      out.add(SfxBlock(
          id: const Uuid().v4(),
          type: c.type,
          startTime: Duration(milliseconds: c.ms)));
      lastMs = c.ms;
      lastType = c.type;
    }
    return out;
  }

  void _applyAutoSfx(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;

    _pauseForEdit();

    // Collect candidates, then thin them (gap + variety + cap) so the result
    // isn't a wall of Pop. Emoji first (strict = no generic-Pop fallback),
    // otherwise one word match per segment.
    final cands = <({int ms, SfxType type})>[];
    for (final seg in project.segments) {
      final emoji = seg.emoji;
      if (emoji != null && emoji.isNotEmpty) {
        final esfx = SfxMapper.getSfxForEmoji(emoji, strict: true);
        if (esfx != null) {
          cands.add((ms: seg.startTime.inMilliseconds, type: esfx));
          continue; // one per segment
        }
      }
      // Word match (specific sounds only — getSfxForWord has no generic fallback).
      if (seg.words != null && seg.wordTimings != null) {
        var currentMs = seg.startTime.inMilliseconds;
        for (int i = 0; i < seg.words!.length; i++) {
          final sfx = SfxMapper.getSfxForWord(seg.words![i]);
          if (sfx != null) cands.add((ms: currentMs, type: sfx));
          if (i < seg.wordTimings!.length) {
            currentMs += seg.wordTimings![i].inMilliseconds;
          }
        }
      } else {
        for (final word in seg.text.split(RegExp(r'\s+'))) {
          final sfx = SfxMapper.getSfxForWord(word);
          if (sfx != null) {
            cands.add((ms: seg.startTime.inMilliseconds, type: sfx));
            break; // one per segment without word timings
          }
        }
      }
    }

    final newBlocks = _thinAutoSfx(cands);
    if (newBlocks.isEmpty) {
      _toast(tr('ed.noAutoSfx'));
      return;
    }

    // Confirm dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(tr('ed.autoSfxTitle'), style: const TextStyle(color: Colors.white)),
        content: Text(tr('ed.autoSfxBody', {'n': newBlocks.length}), style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.pushHistory();
              // Keep old blocks, add new
              for (final b in newBlocks) {
                provider.addSfxBlock(b);
              }
              _toast(tr('ed.sfxAddedN', {'n': newBlocks.length}));
            },
            child: Text(tr('ed.mergeWithOld'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              provider.pushHistory();
              // Remove old blocks
              for (final old in List.from(project.sfxBlocks)) {
                provider.removeSfxBlock(old.id);
              }
              for (final b in newBlocks) {
                provider.addSfxBlock(b);
              }
              _toast(tr('ed.autoSfxPlaced', {'n': newBlocks.length}));
            },
            child: Text(tr('ed.replaceAll'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
