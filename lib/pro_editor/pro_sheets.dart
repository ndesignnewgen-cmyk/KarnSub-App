import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';
import '../timeline/layer_render.dart';
import '../timeline/timeline_model.dart';
import 'pro_editor_controller.dart';

/// Bottom sheets of the Pro Editor (design screens 04–07). Every change is
/// applied live through the controller (and undoable there).

const _palette = [
  0xFFFFFFFF, 0xFF111111, 0xFFFFB300, 0xFFFF6B6B, 0xFF34D399, 0xFF7C6BFF, 0xFF2DD4BF,
];

Widget _sheetFrame(BuildContext ctx, String title, List<Widget> children, {Widget? action}) =>
    SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 14 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              ?action,
              const SizedBox(width: 8),
              InkWell(
                key: const Key('pe_sheet_done'),
                onTap: () => Navigator.pop(ctx),
                child: const CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primaryDark,
                  child: Icon(Icons.check, color: Colors.white, size: 20),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );

Future<void> _show(BuildContext context, Widget Function(BuildContext) builder) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black26,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: builder,
    );

Widget _colorRow(int? current, ValueChanged<int?> onPick, {bool allowNone = false}) => Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (allowNone)
          _swatch(null, current == null, () => onPick(null)),
        for (final c in _palette) _swatch(c, current == c, () => onPick(c)),
      ],
    );

Widget _swatch(int? c, bool on, VoidCallback tap) => GestureDetector(
      key: Key('pe_color_${c ?? 'none'}'),
      onTap: tap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c == null ? Colors.transparent : Color(c),
          shape: BoxShape.circle,
          border: Border.all(color: on ? AppColors.primary : AppColors.border, width: on ? 3 : 1.5),
        ),
        child: c == null ? const Icon(Icons.block, size: 16, color: AppColors.textHint) : null,
      ),
    );

Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(t, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
    );

// ── Text (design 05) ───────────────────────────────────────────────────────

Future<void> showTextSheet(BuildContext context, ProEditorController c, String id) {
  if (c.timeline.find(id)?.$2 is! TextElement) return Future.value();
  return _show(context, (_) => _TextSheet(c: c, id: id));
}

/// Owns its text controller (disposed only after the sheet has fully closed).
class _TextSheet extends StatefulWidget {
  final ProEditorController c;
  final String id;
  const _TextSheet({required this.c, required this.id});
  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final TextEditingController ctl = TextEditingController(
      text: (widget.c.timeline.find(widget.id)?.$2 as TextElement?)?.text ?? '');

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    final c = widget.c;
    final id = widget.id;
    void set(VoidCallback f) => setState(f);
      final e = c.timeline.find(id)?.$2;
      if (e is! TextElement) return const SizedBox.shrink();
      final s = e.style;
      void style(Map<String, dynamic> m) {
        c.updateText(id, style: m);
        set(() {});
      }

      Widget fontTile(String font, String name) {
        final on = (s['font'] ?? 'NotoSansLao') == font;
        return Expanded(
          child: GestureDetector(
            onTap: () => style({'font': font}),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? AppColors.primary : Colors.transparent, width: 2),
              ),
              child: Column(children: [
                Text('ກຂຄ', style: TextStyle(fontFamily: font, color: AppColors.textPrimary, fontSize: 18)),
                Text(name, style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
              ]),
            ),
          ),
        );
      }

      Widget toggle(IconData icon, bool on, VoidCallback tap, {Key? key}) => InkWell(
            key: key,
            onTap: tap,
            child: Container(
              width: 44,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: on ? AppColors.primaryDark.withValues(alpha: 0.6) : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: AppColors.textPrimary, size: 20),
            ),
          );

      return DefaultTabController(
        length: 4,
        child: _sheetFrame(ctx, tr('pe.text.title'), [
          TextField(
            key: const Key('pe_text_field'),
            controller: ctl,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (v) => c.updateText(id, text: v),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textHint,
            tabs: [
              Tab(text: tr('pe.text.tabStyle')),
              Tab(text: tr('pe.text.tabBg')),
              Tab(text: tr('pe.text.tabShadow')),
              Tab(text: tr('pe.text.tabShape')),
            ],
          ),
          SizedBox(
            height: 190,
            child: TabBarView(children: [
              // Style
              ListView(padding: EdgeInsets.zero, children: [
                const SizedBox(height: 8),
                Row(children: [
                  fontTile('NotoSansLao', 'Sans Lao'),
                  fontTile('NotoSerifLao', 'Serif Lao'),
                  fontTile('NotoSansLaoLooped', 'Looped'),
                ]),
                const SizedBox(height: 10),
                _colorRow((s['color'] as num?)?.toInt() ?? 0xFFFFFFFF, (v) => style({'color': v})),
                const SizedBox(height: 10),
                Row(children: [
                  toggle(Icons.format_align_left, s['align'] == 'left', () => style({'align': 'left'})),
                  toggle(Icons.format_align_center, (s['align'] ?? 'center') == 'center',
                      () => style({'align': 'center'})),
                  toggle(Icons.format_align_right, s['align'] == 'right', () => style({'align': 'right'})),
                  toggle(Icons.format_bold, s['bold'] == true, () => style({'bold': s['bold'] != true}),
                      key: const Key('pe_text_bold')),
                  toggle(Icons.format_italic, s['italic'] == true,
                      () => style({'italic': s['italic'] != true})),
                ]),
                Row(children: [
                  Text(tr('pe.text.spacing'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: ((s['spacing'] as num?)?.toDouble() ?? 0).clamp(0.0, 0.3),
                      max: 0.3,
                      onChanged: (v) => style({'spacing': v}),
                    ),
                  ),
                ]),
              ]),
              // Background
              ListView(padding: const EdgeInsets.only(top: 12), children: [
                _colorRow((s['bg'] as num?)?.toInt(), (v) => style({'bg': v}), allowNone: true),
              ]),
              // Shadow + outline
              ListView(padding: EdgeInsets.zero, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: s['shadow'] == true,
                  title: Text(tr('pe.text.shadow'), style: const TextStyle(color: AppColors.textPrimary)),
                  onChanged: (v) => style({'shadow': v}),
                ),
                _label(tr('pe.text.stroke')),
                _colorRow((s['stroke'] as num?)?.toInt(), (v) => style({'stroke': v}), allowNone: true),
              ]),
              // Add a shape
              ListView(padding: const EdgeInsets.only(top: 12), children: [
                Wrap(spacing: 10, children: [
                  for (final k in shapeKinds)
                    InkWell(
                      key: Key('pe_shape_$k'),
                      onTap: () {
                        c.addShape(k);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 56,
                        height: 48,
                        decoration: BoxDecoration(
                            color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
                        child: CustomPaint(
                          painter: _MiniShape(k),
                        ),
                      ),
                    ),
                ]),
              ]),
            ]),
          ),
        ]),
      );
  }
}

class _MiniShape extends CustomPainter {
  final String kind;
  _MiniShape(this.kind);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCenter(center: size.center(Offset.zero), width: 26, height: 26);
    canvas.drawPath(
        shapePath(kind, r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.textPrimary);
  }

  @override
  bool shouldRepaint(_MiniShape o) => false;
}

// ── Shape colours ──────────────────────────────────────────────────────────

Future<void> showShapeSheet(BuildContext context, ProEditorController c, String id) =>
    _show(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final e = c.timeline.find(id)?.$2;
          if (e is! ShapeElement) return const SizedBox.shrink();
          return _sheetFrame(ctx, tr('pe.shape.title'), [
            _label(tr('pe.shape.fill')),
            _colorRow(e.fillColor, (v) {
              c.updateShape(id, fill: v);
              set(() {});
            }),
            _label(tr('pe.shape.stroke')),
            _colorRow(e.strokeWidth > 0 ? e.strokeColor : null, (v) {
              c.updateShape(id, stroke: v ?? 0, strokeWidth: v == null ? 0 : math.max(3, e.strokeWidth));
              set(() {});
            }, allowNone: true),
          ]);
        }));

// ── Mask (design 04) ───────────────────────────────────────────────────────

Future<void> showMaskSheet(BuildContext context, ProEditorController c, String id) {
  IconData icon(String k) => switch (k) {
        'none' => Icons.block,
        'rect' => Icons.crop_square,
        'ellipse' => Icons.circle_outlined,
        'heart' => Icons.favorite,
        'star' => Icons.star_border,
        'diamond' => Icons.diamond_outlined,
        'split' => Icons.vertical_split_outlined,
        _ => Icons.view_day_outlined,
      };
  return _show(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final e = c.timeline.find(id)?.$2;
        if (e is! ImageElement) return const SizedBox.shrink();
        final m = e.mask ?? const MaskSpec();
        void put(MaskSpec n) {
          c.setMask(id, n);
          set(() {});
        }

        Widget slider(String label, double v, ValueChanged<double> f, {double max = 1}) => Row(children: [
              SizedBox(
                  width: 64,
                  child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
              Expanded(child: Slider(value: v.clamp(0, max), max: max, onChanged: f)),
              SizedBox(
                  width: 34,
                  child: Text(v.round().toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12))),
            ]);

        return _sheetFrame(
          ctx,
          'Mask',
          [
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final k in maskKinds)
                InkWell(
                  key: Key('pe_mask_$k'),
                  onTap: () => put(MaskSpec(
                      shape: k, feather: m.feather, size: m.size, rotation: m.rotation, inverted: m.inverted)),
                  child: Container(
                    width: 58,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: (e.mask?.shape ?? 'none') == k ? AppColors.primary : Colors.transparent,
                          width: 2),
                    ),
                    child: Icon(icon(k), color: AppColors.textPrimary),
                  ),
                ),
            ]),
            if (e.mask != null) ...[
              const SizedBox(height: 8),
              slider(tr('pe.mask.feather'), m.feather * 100, (v) => put(_mask(m, feather: v / 100)), max: 100),
              slider(tr('pe.mask.size'), m.size * 100, (v) => put(_mask(m, size: v / 100)), max: 100),
              slider(tr('pe.mask.rotate'), m.rotation, (v) => put(_mask(m, rotation: v)), max: 360),
            ],
            const SizedBox(height: 6),
            Text(tr('pe.mask.blendSoon'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
          ],
          action: e.mask == null
              ? null
              : TextButton.icon(
                  onPressed: () => put(_mask(m, inverted: !m.inverted)),
                  icon: const Icon(Icons.flip, size: 16),
                  label: Text(tr('pe.mask.invert')),
                ),
        );
      }));
}

MaskSpec _mask(MaskSpec m, {double? feather, double? size, double? rotation, bool? inverted}) => MaskSpec(
      shape: m.shape,
      feather: feather ?? m.feather,
      size: size ?? m.size,
      rotation: rotation ?? m.rotation,
      inverted: inverted ?? m.inverted,
    );

// ── Keyframe curve (design 06) ─────────────────────────────────────────────

Future<void> showKeyframeSheet(BuildContext context, ProEditorController c, String id) {
  const presets = [
    (0, 'Linear', null),
    (1, 'Ease in', null),
    (2, 'Ease out', null),
    (3, 'Ease in-out', null),
    (6, 'Bounce', [0.34, 1.56, 0.64, 1.0]),
  ];
  return _show(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final e = c.timeline.find(id)?.$2;
        if (e == null || e is! VisualElement) return const SizedBox.shrink();
        final kfs = (e as VisualElement).keyframes;
        final rel = c.playhead.value - e.startMs;
        final i = ProEditorController.easingIndex(kfs, rel);
        final cur = kfs.isEmpty ? null : kfs[i];
        final now = c.transformNow(id)!;
        return _sheetFrame(
          ctx,
          tr('pe.kf.title'),
          [
            if (kfs.isEmpty)
              Text(tr('pe.kf.empty'), style: const TextStyle(color: AppColors.textHint, fontSize: 12.5))
            else ...[
              Container(
                height: 120,
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                child: CustomPaint(
                    size: Size.infinite, painter: _CurvePainter(cur?.easing ?? 0, cur?.bezier)),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (ez, name, bz) in presets)
                  ChoiceChip(
                    key: Key('pe_ease_$ez'),
                    label: Text(name),
                    selected: cur?.easing == ez,
                    onSelected: (_) {
                      c.setEasing(id, ez, bezier: bz);
                      set(() {});
                    },
                  ),
              ]),
            ],
            const SizedBox(height: 10),
            for (final (label, value) in [
              (tr('pe.kf.pos'), 'X ${(now.x * 100).round()} · Y ${(now.y * 100).round()}'),
              (tr('pe.kf.size'), '${(now.scale * 100).round()}%'),
              (tr('pe.kf.rotate'), '${now.rotation.round()}°'),
              (tr('pe.kf.opacity'), '${(now.opacity * 100).round()}%'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(c.hasKeyframeNow(id) ? Icons.diamond : Icons.diamond_outlined,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: const TextStyle(color: AppColors.textPrimary))),
                  Text(value, style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'monospace')),
                ]),
              ),
          ],
          action: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: tr('pe.kf.copy'),
              onPressed: kfs.isEmpty
                  ? null
                  : () {
                      c.copyKeyframes(id);
                      set(() {});
                    },
              icon: const Icon(Icons.copy, size: 18),
            ),
            IconButton(
              tooltip: tr('pe.kf.paste'),
              onPressed: c.hasKeyframeClipboard
                  ? () {
                      c.pasteKeyframes(id);
                      set(() {});
                    }
                  : null,
              icon: const Icon(Icons.content_paste, size: 18),
            ),
          ]),
        );
      }));
}

class _CurvePainter extends CustomPainter {
  final int easing;
  final List<double>? bezier;
  _CurvePainter(this.easing, this.bezier);
  @override
  void paint(Canvas canvas, Size size) {
    final pad = 14.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    final grid = Paint()..color = AppColors.border;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(pad + w * i / 4, pad), Offset(pad + w * i / 4, pad + h), grid);
    }
    final path = Path();
    for (var i = 0; i <= 60; i++) {
      final x = i / 60;
      final y = applyEasing(easing, x, bezier);
      final o = Offset(pad + x * w, pad + h - y * h);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_CurvePainter o) => o.easing != easing || o.bezier != bezier;
}

// ── In/out animation (keyframe presets) ────────────────────────────────────

Future<void> showAnimationSheet(BuildContext context, ProEditorController c, String id) {
  var inKind = 'none', outKind = 'none';
  var ms = 400;
  String name(String k) => tr('pe.anim.$k');
  return _show(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        void apply() => c.applyAnimation(id, inKind: inKind, outKind: outKind, ms: ms);
        Widget row(String label, String cur, ValueChanged<String> pick, String keyPrefix) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(label),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final k in ProEditorController.animationKinds)
                    ChoiceChip(
                      key: Key('$keyPrefix$k'),
                      label: Text(name(k)),
                      selected: cur == k,
                      onSelected: (_) {
                        set(() => pick(k));
                        apply();
                      },
                    ),
                ]),
              ],
            );
        return _sheetFrame(ctx, 'Animation', [
          row(tr('pe.anim.in'), inKind, (k) => inKind = k, 'pe_anim_in_'),
          row(tr('pe.anim.out'), outKind, (k) => outKind = k, 'pe_anim_out_'),
          Row(children: [
            Text(tr('pe.tr.duration'), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Expanded(
              child: Slider(
                value: ms.toDouble(),
                min: 200,
                max: 1500,
                divisions: 13,
                onChanged: (v) => set(() => ms = v.round()),
                onChangeEnd: (_) => apply(),
              ),
            ),
            Text('${(ms / 1000).toStringAsFixed(1)}s',
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace')),
          ]),
          Text(tr('pe.anim.note'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
        ]);
      }));
}

// ── Transition (design 07) ─────────────────────────────────────────────────

/// Kinds offered (exportable ones first; the rest wait for the new engine).
const transitionChoices = [
  ('none', 'pe.tr.none', true),
  ('fade', 'pe.tr.fade', true),
  ('zoom', 'pe.tr.zoom', true),
  ('shake', 'pe.tr.shake', true),
  ('dissolve', 'pe.tr.dissolve', false),
  ('slide', 'pe.tr.slide', false),
  ('glitch', 'pe.tr.glitch', false),
  ('flash', 'pe.tr.flash', false),
];

Future<void> showTransitionSheet(
    BuildContext context, ProEditorController c, String fromId, String toId, void Function(String) toast) {
  var ms = c.transitionBetween(fromId, toId)?.durationMs ?? 500;
  return _show(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final cur = c.transitionBetween(fromId, toId)?.kind ?? 'none';
        return _sheetFrame(ctx, 'Transition', [
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (kind, label, ok) in transitionChoices)
                InkWell(
                  key: Key('pe_tr_$kind'),
                  onTap: () {
                    if (!ok) {
                      toast(tr('pe.soon', {'v': '1.8'}));
                      return;
                    }
                    c.setTransition(fromId, toId, kind, ms);
                    set(() {});
                  },
                  child: Opacity(
                    opacity: ok ? 1 : 0.4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cur == kind ? AppColors.primary : Colors.transparent, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(tr(label),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text(tr('pe.tr.duration'), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Expanded(
              child: Slider(
                value: ms.toDouble(),
                min: 200,
                max: 1500,
                divisions: 13,
                onChanged: (v) => set(() => ms = v.round()),
                onChangeEnd: (v) {
                  if (cur != 'none') c.setTransition(fromId, toId, cur, v.round());
                },
              ),
            ),
            Text('${(ms / 1000).toStringAsFixed(1)}s',
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace')),
          ]),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('pe_tr_all'),
              onPressed: () {
                c.setTransitionAll(cur, ms);
                toast(tr('pe.tr.allDone'));
              },
              child: Text(tr('pe.tr.all')),
            ),
          ),
        ]);
      }));
}
