import 'package:flutter/material.dart';
import '../models/subtitle_style_model.dart';
import '../theme/app_theme.dart';

class StylePreviewCard extends StatelessWidget {
  final SubtitlePreset preset;
  final bool isSelected;
  final VoidCallback onTap;
  final bool locked;

  const StylePreviewCard({
    super.key,
    required this.preset,
    required this.isSelected,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 8)]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                children: [
                  Center(child: _buildPreviewText()),
                  if (locked)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock,
                            color: Color(0xFFFFD700), size: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            preset.name,
            style: TextStyle(
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewText() {
    const previewText = 'ຕົວຢ່າງ';

    // Retro 3D extrude
    if (preset.has3dShadow) {
      return Text(
        previewText,
        style: TextStyle(
          color: preset.textColor,
          fontSize: 13,
          fontWeight: preset.fontWeight,
          shadows: const [
            Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 0),
            Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
            Shadow(color: Colors.black, offset: Offset(3, 3), blurRadius: 0),
            Shadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
          ],
        ),
      );
    }

    // Gradient fill
    if (preset.gradientColors != null && preset.gradientColors!.length >= 2) {
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: preset.gradientColors!,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(r),
        child: Text(
          previewText,
          style: TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: preset.fontWeight),
        ),
      );
    }

    // Hard outline (stroke + fill)
    if (preset.hasOutline) {
      TextStyle base(Paint? fg, Color? col) => TextStyle(
            foreground: fg,
            color: col,
            fontSize: 13,
            fontWeight: preset.fontWeight,
          );
      return Stack(
        alignment: Alignment.center,
        children: [
          Text(previewText,
              style: base(
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2.2
                  ..strokeJoin = StrokeJoin.round
                  ..color = preset.outlineColor ?? Colors.black,
                null,
              )),
          Text(previewText, style: base(null, preset.textColor)),
        ],
      );
    }

    // Neon glow effect
    if (preset.hasNeonGlow) {
      return Text(
        previewText,
        style: TextStyle(
          color: preset.textColor,
          fontSize: 13,
          fontWeight: preset.fontWeight,
          shadows: [
            Shadow(color: preset.glowColor ?? preset.textColor, blurRadius: 10),
            Shadow(color: preset.glowColor ?? preset.textColor, blurRadius: 20),
          ],
        ),
      );
    }

    // Underline effect
    if (preset.hasUnderline) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            previewText,
            style: TextStyle(
              color: preset.textColor,
              fontSize: 13,
              fontWeight: preset.fontWeight,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 46,
            height: 2.5,
            decoration: BoxDecoration(
              color: preset.underlineColor ?? AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      );
    }

    final textWidget = Text(
      previewText,
      style: TextStyle(
        color: preset.textColor,
        fontSize: 13,
        fontWeight: preset.fontWeight,
        shadows: preset.hasShadow
            ? [const Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(1, 2))]
            : null,
      ),
    );

    // Background color
    if (preset.backgroundColor != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: preset.backgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: textWidget,
      );
    }

    return textWidget;
  }
}
