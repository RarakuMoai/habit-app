import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/audio_settings_service.dart';
import '../utils/bgm_service.dart';
import '../utils/sfx_service.dart';

enum AudioControlStyle { appBar, onboarding }

class AudioControlButton extends StatefulWidget {
  final AudioControlStyle style;
  final Color accent;
  final VoidCallback? onMusicEnabled;

  const AudioControlButton({
    super.key,
    required this.style,
    required this.accent,
    this.onMusicEnabled,
  });

  @override
  State<AudioControlButton> createState() => _AudioControlButtonState();
}

class _AudioControlButtonState extends State<AudioControlButton> {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hidePanel();
    super.dispose();
  }

  void _togglePanel() {
    if (_entry != null) {
      _hidePanel();
      return;
    }
    unawaited(SfxService.instance.play(SfxCue.tap));

    final buttonBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    if (buttonBox == null) return;

    final buttonTopLeft = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    final overlaySize = overlay.size;
    final panelWidth = overlaySize.width < 306 ? overlaySize.width - 20 : 286.0;
    const panelHeight = 184.0;
    final right = (overlaySize.width - buttonTopLeft.dx - buttonBox.size.width)
        .clamp(10.0, overlaySize.width - panelWidth - 10);
    final below = buttonTopLeft.dy + buttonBox.size.height + 8;
    final top = (below + panelHeight > overlaySize.height - 12)
        ? (buttonTopLeft.dy - panelHeight - 8).clamp(12.0, overlaySize.height)
        : below;

    _entry = OverlayEntry(
      builder: (_) => _AudioPanelOverlay(
        top: top,
        right: right,
        width: panelWidth,
        accent: widget.accent,
        onDismiss: _hidePanel,
        onMusicEnabled: widget.onMusicEnabled,
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hidePanel() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioSettingsService.musicMuted,
      builder: (_, musicMuted, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AudioSettingsService.sfxMuted,
          builder: (_, sfxMuted, _) {
            final allMuted = musicMuted && sfxMuted;
            final icon = allMuted
                ? Icons.volume_off_rounded
                : (musicMuted || sfxMuted
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded);
            final color = widget.style == AudioControlStyle.onboarding
                ? (allMuted ? Colors.grey.shade600 : widget.accent)
                : Colors.grey.shade800;
            return _AudioCircle(
              key: _buttonKey,
              style: widget.style,
              accent: widget.accent,
              child: IconButton(
                icon: Icon(icon, color: color),
                tooltip: '聲音設定',
                onPressed: _togglePanel,
              ),
            );
          },
        );
      },
    );
  }
}

class _AudioCircle extends StatelessWidget {
  final AudioControlStyle style;
  final Color accent;
  final Widget child;

  const _AudioCircle({
    super.key,
    required this.style,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final onboarding = style == AudioControlStyle.onboarding;
    return Padding(
      padding: onboarding
          ? const EdgeInsets.only(top: 6, right: 10)
          : const EdgeInsets.only(right: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: onboarding ? 0.82 : 0.88),
          shape: BoxShape.circle,
          border: onboarding
              ? Border.all(color: accent.withValues(alpha: 0.22))
              : null,
          boxShadow: [
            BoxShadow(
              color: (onboarding ? accent : Colors.black).withValues(
                alpha: onboarding ? 0.12 : 0.10,
              ),
              blurRadius: onboarding ? 14 : 10,
              offset: Offset(0, onboarding ? 5 : 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _AudioPanelOverlay extends StatelessWidget {
  final double top;
  final double right;
  final double width;
  final Color accent;
  final VoidCallback onDismiss;
  final VoidCallback? onMusicEnabled;

  const _AudioPanelOverlay({
    required this.top,
    required this.right,
    required this.width,
    required this.accent,
    required this.onDismiss,
    this.onMusicEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          top: top,
          right: right,
          width: width,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) {
              return Opacity(
                opacity: t,
                child: Transform.scale(
                  alignment: Alignment.topRight,
                  scale: 0.88 + t * 0.12,
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: _AudioSettingsPanel(
                accent: accent,
                onMusicEnabled: onMusicEnabled,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioSettingsPanel extends StatelessWidget {
  final Color accent;
  final VoidCallback? onMusicEnabled;

  const _AudioSettingsPanel({required this.accent, this.onMusicEnabled});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 14),
                transform: Matrix4.rotationZ(0.785398),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.97),
                  border: Border(
                    left: BorderSide(color: accent.withValues(alpha: 0.14)),
                    top: BorderSide(color: accent.withValues(alpha: 0.14)),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AudioRow(
                    icon: Icons.music_note_rounded,
                    title: '背景音樂',
                    subtitle: '兔咪陪伴的環境音',
                    accent: accent,
                    valueListenable: AudioSettingsService.musicMuted,
                    onChanged: (muted) async {
                      await BgmService.instance.setMuted(muted);
                      if (!muted) onMusicEnabled?.call();
                    },
                  ),
                  const SizedBox(height: 8),
                  _AudioRow(
                    icon: Icons.touch_app_rounded,
                    title: '操作音效',
                    subtitle: '完成、點擊與取消回饋',
                    accent: accent,
                    valueListenable: AudioSettingsService.sfxMuted,
                    onChanged: (muted) async {
                      await AudioSettingsService.instance.setSfxMuted(muted);
                      if (!muted) {
                        unawaited(SfxService.instance.play(SfxCue.success));
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final ValueNotifier<bool> valueListenable;
  final Future<void> Function(bool muted) onChanged;

  const _AudioRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.valueListenable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: valueListenable,
      builder: (_, muted, _) {
        final enabled = !muted;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: enabled
                ? accent.withValues(alpha: 0.08)
                : Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? accent.withValues(alpha: 0.22)
                  : Colors.grey.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: enabled ? accent : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: accent,
                onChanged: (value) => unawaited(onChanged(!value)),
              ),
            ],
          ),
        );
      },
    );
  }
}
